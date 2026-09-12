-- Client preferences are user-scoped. Billing mutations are server-only.
create table public.ai_preferences (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  classification boolean not null default true,
  tagging boolean not null default true,
  search boolean not null default true,
  explore boolean not null default true,
  resurfacing boolean not null default false,
  photo_analysis boolean not null default false,
  monthly_budget_micros bigint not null default 1000000 check (monthly_budget_micros between 0 and 100000000),
  revision integer not null default 1,
  updated_at timestamptz not null default now()
);
create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  -- Retain anonymous accounting after account removal so the server cap cannot reset.
  owner_id uuid references auth.users(id) on delete set null,
  feature text not null check (feature in ('connection','classification','tagging','search','explore','resurfacing','photo_analysis')),
  provider text not null default 'anthropic' check (provider = 'anthropic'),
  model text not null,
  status text not null default 'reserved' check (status in ('reserved','completed','failed','uncertain')),
  reserved_micros bigint not null check (reserved_micros between 1 and 1000000),
  charged_micros bigint not null check (charged_micros >= 0),
  input_tokens integer,
  output_tokens integer,
  error_code text,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index ai_usage_owner_created on public.ai_usage(owner_id, created_at desc);
alter table public.ai_preferences enable row level security;
alter table public.ai_usage enable row level security;
create policy ai_preferences_owner_read on public.ai_preferences for select to authenticated using (owner_id = (select auth.uid()));
create policy ai_usage_owner_read on public.ai_usage for select to authenticated using (owner_id = (select auth.uid()));
revoke all on public.ai_preferences, public.ai_usage from anon, authenticated;
grant select on public.ai_preferences, public.ai_usage to authenticated;
grant all on public.ai_preferences, public.ai_usage to service_role;

create function public.ai_workspace() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  select to_jsonb(p) - 'owner_id' - 'updated_at' into result from public.ai_preferences p where p.owner_id = auth.uid();
  return jsonb_build_object(
    'preferences', coalesce(result, '{"enabled":false,"classification":true,"tagging":true,"search":true,"explore":true,"resurfacing":false,"photo_analysis":false,"monthly_budget_micros":1000000,"revision":0}'::jsonb),
    'month_charged_micros', (select coalesce(sum(charged_micros),0) from public.ai_usage where owner_id = auth.uid() and created_at >= date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'),
    'recent_usage', (select coalesce(jsonb_agg(to_jsonb(u) - 'owner_id' order by u.created_at desc),'[]'::jsonb) from
      (select * from public.ai_usage where owner_id = auth.uid() order by created_at desc limit 30) u)
  );
end;
$$;

create function public.save_ai_preferences(p_preferences jsonb, p_expected_revision integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare current_revision integer; key text;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  if jsonb_typeof(p_preferences) is distinct from 'object' or p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = '22023', message = 'invalid_ai_preferences';
  end if;
  foreach key in array array['enabled','classification','tagging','search','explore','resurfacing','photo_analysis'] loop
    if jsonb_typeof(p_preferences->key) is distinct from 'boolean' then
      raise exception using errcode = '22023', message = 'invalid_ai_preferences';
    end if;
  end loop;
  if jsonb_typeof(p_preferences->'monthly_budget_micros') is distinct from 'number'
    or (p_preferences->>'monthly_budget_micros')::numeric not between 0 and 100000000
    or trunc((p_preferences->>'monthly_budget_micros')::numeric) <> (p_preferences->>'monthly_budget_micros')::numeric then
    raise exception using errcode = '22023', message = 'invalid_ai_budget';
  end if;
  -- Serialize with reservation so disabling AI and lowering caps takes effect atomically.
  perform pg_advisory_xact_lock(741924);
  select revision into current_revision from public.ai_preferences where owner_id = auth.uid() for update;
  if coalesce(current_revision,0) <> p_expected_revision then return null; end if;
  insert into public.ai_preferences(owner_id,enabled,classification,tagging,search,explore,resurfacing,photo_analysis,monthly_budget_micros)
  values(auth.uid(),(p_preferences->>'enabled')::boolean,(p_preferences->>'classification')::boolean,
    (p_preferences->>'tagging')::boolean,(p_preferences->>'search')::boolean,(p_preferences->>'explore')::boolean,
    (p_preferences->>'resurfacing')::boolean,(p_preferences->>'photo_analysis')::boolean,(p_preferences->>'monthly_budget_micros')::bigint)
  on conflict(owner_id) do update set enabled=excluded.enabled,classification=excluded.classification,
    tagging=excluded.tagging,search=excluded.search,explore=excluded.explore,resurfacing=excluded.resurfacing,
    photo_analysis=excluded.photo_analysis,monthly_budget_micros=excluded.monthly_budget_micros,
    revision=ai_preferences.revision+1,updated_at=now();
  return public.ai_workspace();
end;
$$;

create function public.reserve_ai_usage(p_owner_id uuid, p_feature text, p_model text,
  p_reserved_micros bigint, p_global_budget_micros bigint) returns uuid
language plpgsql security definer set search_path = '' as $$
declare prefs public.ai_preferences; request_id uuid;
begin
  if p_feature is null or p_feature not in ('connection','classification','tagging','search','explore','resurfacing','photo_analysis')
    or p_model is distinct from 'claude-haiku-4-5-20251001'
    or p_reserved_micros is null or p_reserved_micros not between 1 and 1000000
    or p_global_budget_micros is null or p_global_budget_micros not between 1 and 100000000 then
    raise exception using errcode = '22023', message = 'invalid_ai_reservation';
  end if;
  perform pg_advisory_xact_lock(741924);
  select * into prefs from public.ai_preferences where owner_id=p_owner_id;
  if prefs.owner_id is null or not prefs.enabled or
    (p_feature <> 'connection' and not coalesce((to_jsonb(prefs)->>p_feature)::boolean,false)) then
    raise exception using errcode = '42501', message = 'ai_disabled';
  end if;
  if (select count(*) from public.ai_usage where owner_id=p_owner_id and created_at > now()-interval '1 hour') >= 60 then
    raise exception using errcode = 'P0001', message = 'ai_rate_limit';
  end if;
  if (select coalesce(sum(charged_micros),0) from public.ai_usage) + p_reserved_micros > p_global_budget_micros
    or (select coalesce(sum(charged_micros),0) from public.ai_usage where owner_id=p_owner_id and created_at >= date_trunc('month',now() at time zone 'UTC') at time zone 'UTC') + p_reserved_micros > prefs.monthly_budget_micros then
    raise exception using errcode = 'P0001', message = 'ai_budget_exceeded';
  end if;
  insert into public.ai_usage(owner_id,feature,model,reserved_micros,charged_micros)
  values(p_owner_id,p_feature,p_model,p_reserved_micros,p_reserved_micros) returning id into request_id;
  return request_id;
end;
$$;

create function public.finish_ai_usage(p_id uuid, p_status text, p_input_tokens integer,
  p_output_tokens integer, p_error_code text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare affected integer;
begin
  if p_status is null or p_status not in ('completed','failed','uncertain')
    or (p_status='completed' and (p_input_tokens is null or p_output_tokens is null or p_input_tokens < 0 or p_output_tokens < 0))
    or (p_error_code is not null and (length(p_error_code)>64 or p_error_code !~ '^[a-z0-9_]+$')) then
    raise exception using errcode = '22023', message = 'invalid_ai_completion';
  end if;
  perform pg_advisory_xact_lock(741924);
  update public.ai_usage set status=p_status,input_tokens=p_input_tokens,output_tokens=p_output_tokens,
    charged_micros=case when p_status='completed' then p_input_tokens::bigint + p_output_tokens::bigint*5
      when p_status='failed' then 0 else reserved_micros end,
    error_code=p_error_code,finished_at=now()
  where id=p_id and status='reserved';
  get diagnostics affected = row_count;
  return affected=1;
end;
$$;

revoke all on function public.ai_workspace(), public.save_ai_preferences(jsonb,integer),
  public.reserve_ai_usage(uuid,text,text,bigint,bigint), public.finish_ai_usage(uuid,text,integer,integer,text) from public, anon, authenticated;
grant execute on function public.ai_workspace(), public.save_ai_preferences(jsonb,integer) to authenticated;
grant execute on function public.reserve_ai_usage(uuid,text,text,bigint,bigint), public.finish_ai_usage(uuid,text,integer,integer,text) to service_role;
