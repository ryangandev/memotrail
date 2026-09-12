-- One persistent exploration thread per source Entry. Only trusted server code
-- creates model turns; reading and explicitly saving a conclusion use user auth.
create table public.ai_exploration_turns (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null,
  sequence bigint generated always as identity unique,
  question text not null check (length(btrim(question)) between 1 and 2000),
  source_revision integer not null check (source_revision > 0),
  source_snapshot jsonb not null,
  status text not null default 'generating' check (status in ('generating','completed','failed')),
  answer text check (length(answer) between 1 and 12000),
  model text,
  error_code text,
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (id,owner_id),
  foreign key (entry_id,owner_id) references public.entries(id,owner_id) on delete cascade,
  check ((status='completed' and answer is not null and model is not null) or (status<>'completed' and answer is null))
);
create index ai_exploration_entry_order on public.ai_exploration_turns(owner_id,entry_id,sequence desc);
create unique index ai_exploration_one_active on public.ai_exploration_turns(entry_id) where status='generating';

-- A deleted saved Entry leaves a request tombstone, so retrying a completed
-- Save cannot resurrect data the user deliberately removed.
create table public.ai_exploration_saves (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  turn_id uuid not null,
  saved_entry_id uuid references public.entries(id) on delete set null,
  input_digest text not null,
  created_at timestamptz not null default now(),
  foreign key (turn_id,owner_id) references public.ai_exploration_turns(id,owner_id) on delete cascade
);
create index ai_exploration_saves_turn on public.ai_exploration_saves(owner_id,turn_id);
alter table public.ai_exploration_turns enable row level security;
alter table public.ai_exploration_saves enable row level security;
create policy exploration_turns_owner_read on public.ai_exploration_turns for select to authenticated
  using(owner_id=(select auth.uid()) and exists(select 1 from public.entries e where e.id=entry_id and e.owner_id=(select auth.uid()) and e.deleted_at is null));
create policy exploration_saves_owner_read on public.ai_exploration_saves for select to authenticated
  using(owner_id=(select auth.uid()) and exists(select 1 from public.ai_exploration_turns t where t.id=turn_id));
revoke all on public.ai_exploration_turns,public.ai_exploration_saves from anon,authenticated;
grant select on public.ai_exploration_turns,public.ai_exploration_saves to authenticated;
grant all on public.ai_exploration_turns,public.ai_exploration_saves to service_role;
grant usage,select on sequence public.ai_exploration_turns_sequence_seq to service_role;

create function public.exploration_workspace(p_entry_id uuid,p_before_sequence bigint default null,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare source public.entries;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required';end if;
  if p_limit is null or p_limit not between 1 and 20 or (p_before_sequence is not null and p_before_sequence<1) then
    raise exception using errcode='22023',message='invalid_exploration_page';end if;
  select * into source from public.entries where id=p_entry_id and owner_id=auth.uid() and deleted_at is null;
  if not found then return null;end if;
  return jsonb_build_object(
    'source',jsonb_build_object('id',source.id,'title',source.title,'body',source.body,'revision',source.revision),
    'total_count',(select count(*) from public.ai_exploration_turns where entry_id=source.id and owner_id=auth.uid()),
    'turns',(select coalesce(jsonb_agg(to_jsonb(t)-'owner_id'||jsonb_build_object(
      'status',case when t.status='generating' and t.created_at<now()-interval '2 minutes' then 'failed' else t.status end,
      'saved_entries',(select coalesce(jsonb_agg(jsonb_build_object('request_id',s.id,'entry_id',s.saved_entry_id,'title',e.title,'deleted',e.deleted_at is not null or e.id is null) order by s.created_at),'[]') from public.ai_exploration_saves s left join public.entries e on e.id=s.saved_entry_id and e.owner_id=auth.uid() where s.turn_id=t.id and s.owner_id=auth.uid())
    ) order by t.sequence),'[]') from (select * from public.ai_exploration_turns where entry_id=source.id and owner_id=auth.uid() and (p_before_sequence is null or sequence<p_before_sequence) order by sequence desc limit p_limit) t)
  );
end;
$$;

create function public.claim_exploration_turn(p_owner_id uuid,p_entry_id uuid,p_request_id uuid,p_question text,p_source_revision integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.entries; existing public.ai_exploration_turns; question text:=btrim(p_question);
begin
  if p_owner_id is null or p_entry_id is null or p_request_id is null or p_source_revision is null or p_source_revision<1 or question is null or length(question) not between 1 and 2000 then
    raise exception using errcode='22023',message='invalid_exploration_request';end if;
  -- Same request ID serializes even if competing requests name different Entries.
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,741925));
  select * into source from public.entries where id=p_entry_id and owner_id=p_owner_id and deleted_at is null for update;
  if not found then raise exception using errcode='P0001',message='entry_unavailable';end if;
  select * into existing from public.ai_exploration_turns where id=p_request_id;
  if found then
    if existing.owner_id<>p_owner_id or existing.entry_id<>p_entry_id or existing.question<>question or existing.source_revision<>p_source_revision then
      raise exception using errcode='22023',message='request_id_conflict';end if;
    if existing.status='generating' and existing.created_at<now()-interval '2 minutes' then
      update public.ai_exploration_turns set status='failed',error_code='interrupted',finished_at=now() where id=existing.id returning * into existing;
    end if;
    return jsonb_build_object('claimed',false,'turn',to_jsonb(existing)-'owner_id');
  end if;
  if source.revision<>p_source_revision then raise exception using errcode='P0001',message='entry_changed';end if;
  if not exists(select 1 from public.ai_preferences where owner_id=p_owner_id and enabled and explore) then
    raise exception using errcode='42501',message='ai_disabled';end if;
  update public.ai_exploration_turns set status='failed',error_code='interrupted',finished_at=now()
    where entry_id=source.id and status='generating' and created_at<now()-interval '2 minutes';
  if exists(select 1 from public.ai_exploration_turns where entry_id=source.id and status='generating') then
    raise exception using errcode='P0001',message='exploration_busy';end if;
  insert into public.ai_exploration_turns(id,owner_id,entry_id,question,source_revision,source_snapshot)
  values(p_request_id,p_owner_id,source.id,question,source.revision,jsonb_build_object(
    'title',source.title,'body',left(source.body,12000),'body_truncated',length(source.body)>12000,
    'date_precision',source.date_precision,'occurred_start',source.occurred_start,'occurred_end',source.occurred_end,
    'occurred_label',source.occurred_label,'occurred_timezone',source.occurred_timezone)) returning * into existing;
  return jsonb_build_object('claimed',true,'turn',to_jsonb(existing)-'owner_id');
end;
$$;

create function public.finish_exploration_turn(p_owner_id uuid,p_request_id uuid,p_answer text,p_model text,p_error_code text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
  if p_owner_id is null or p_request_id is null or
    (p_error_code is null and (p_answer is null or length(btrim(p_answer)) not between 1 and 12000 or p_model is distinct from 'claude-haiku-4-5-20251001')) or
    (p_error_code is not null and (p_answer is not null or p_error_code not in ('provider_error','invalid_answer','budget_exceeded','disabled','interrupted'))) then
    raise exception using errcode='22023',message='invalid_exploration_completion';end if;
  update public.ai_exploration_turns set status=case when p_error_code is null then 'completed' else 'failed' end,
    answer=p_answer,model=case when p_error_code is null then p_model else null end,error_code=p_error_code,finished_at=now()
    where id=p_request_id and owner_id=p_owner_id and status='generating';
  get diagnostics changed=row_count;
  return changed=1;
end;
$$;

create function public.save_exploration_conclusion(p_request_id uuid,p_turn_id uuid,p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare turn public.ai_exploration_turns; source public.entries; saved public.ai_exploration_saves;
  title text:=nullif(btrim(p_title),''); body text:=btrim(p_body); digest text; new_id uuid;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required';end if;
  if p_request_id is null or p_turn_id is null or length(coalesce(title,''))>200 or body is null or length(body) not between 1 and 50000 then
    raise exception using errcode='22023',message='invalid_exploration_conclusion';end if;
  digest:=md5(jsonb_build_array(p_turn_id,title,body)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,741926));
  select * into saved from public.ai_exploration_saves where id=p_request_id;
  if found then
    if saved.owner_id<>auth.uid() or saved.turn_id<>p_turn_id or saved.input_digest<>digest then
      raise exception using errcode='22023',message='request_id_conflict';end if;
    return jsonb_build_object('entry_id',saved.saved_entry_id,'created',false);
  end if;
  select * into turn from public.ai_exploration_turns where id=p_turn_id and owner_id=auth.uid() and status='completed';
  if not found then raise exception using errcode='P0001',message='exploration_unavailable';end if;
  select * into source from public.entries where id=turn.entry_id and owner_id=auth.uid() and deleted_at is null for update;
  if not found then raise exception using errcode='P0001',message='entry_unavailable';end if;
  insert into public.entries(owner_id,title,body,date_precision,metadata)
  values(auth.uid(),title,body,'unknown',jsonb_build_object('origin','ai_exploration','exploration_turn_id',turn.id)) returning id into new_id;
  -- Archive the source's previous link state and advance its revision before
  -- adding relationships, so an old device cannot silently remove this link.
  update public.entries set updated_at=now() where id=source.id;
  insert into public.entry_links(owner_id,source_entry_id,target_entry_id,relationship) values
    (auth.uid(),source.id,new_id,'exploration_conclusion'),(auth.uid(),new_id,source.id,'exploration_source');
  insert into public.ai_exploration_saves(id,owner_id,turn_id,saved_entry_id,input_digest)
  values(p_request_id,auth.uid(),turn.id,new_id,digest);
  return jsonb_build_object('entry_id',new_id,'created',true);
end;
$$;

revoke all on function public.exploration_workspace(uuid,bigint,integer),public.claim_exploration_turn(uuid,uuid,uuid,text,integer),
  public.finish_exploration_turn(uuid,uuid,text,text,text),public.save_exploration_conclusion(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.exploration_workspace(uuid,bigint,integer),public.save_exploration_conclusion(uuid,uuid,text,text) to authenticated;
grant execute on function public.claim_exploration_turn(uuid,uuid,uuid,text,integer),public.finish_exploration_turn(uuid,uuid,text,text,text) to service_role;
