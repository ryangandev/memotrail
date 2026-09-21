-- A geographic snapshot records where its coordinates came from, without
-- becoming a reusable or named personal record.
alter table public.locations
  add column coordinate_source text not null default 'manual'
    check (coordinate_source in ('manual', 'geoapify', 'photo_gps')),
  add column source_attachment_id uuid
    references public.attachments(id) on delete set null,
  add constraint locations_photo_source_check
    check (source_attachment_id is null or coordinate_source = 'photo_gps');

update public.locations
set coordinate_source = 'geoapify'
where provider = 'geoapify';

create or replace function public.normalize_location_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.formatted_address := coalesce(
    nullif(btrim(new.formatted_address), ''),
    nullif(concat_ws(', ', new.address, new.city, new.region, new.country), '')
  );
  new.name := left(coalesce(new.formatted_address, 'Location not set'), 200);
  new.notes := null;
  if tg_op = 'INSERT' and new.provider = 'geoapify' then
    new.coordinate_source := 'geoapify';
  end if;
  return new;
end;
$$;

create function public.record_photo_location_source(
  p_location_id uuid,
  p_entry_id uuid,
  p_attachment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.attachments as attachment
    where attachment.id = p_attachment_id
      and attachment.owner_id = auth.uid()
      and attachment.entry_id = p_entry_id
      and attachment.deleted_at is null
      and attachment.variant = 'original'
  ) or not exists (
    select 1 from public.locations as location
    where location.id = p_location_id
      and location.owner_id = auth.uid()
      and location.bound_entry_id = p_entry_id
      and location.deleted_at is null
  ) then
    raise exception using errcode = '42501', message = 'invalid_photo_location_source';
  end if;

  update public.locations
  set coordinate_source = 'photo_gps', source_attachment_id = p_attachment_id
  where id = p_location_id and owner_id = auth.uid();
end;
$$;

revoke all on function public.record_photo_location_source(uuid,uuid,uuid)
  from public, anon;
grant execute on function public.record_photo_location_source(uuid,uuid,uuid)
  to authenticated;

-- Preserve the established review RPC signature and append provenance only
-- when the user explicitly adopts GPS from one of this Entry's photos.
do $migration$
declare
  definition text;
  old_fragment text := $old$
      ) as saved;
    elsif not exists (
$old$;
  new_fragment text := $new$
      ) as saved;
      perform public.record_photo_location_source(
        target_place_id, reviewed.entry_id, source_attachment_id
      );
    elsif not exists (
$new$;
begin
  select pg_get_functiondef(
    'public.review_wiki_item_with_photo_place_core(uuid,integer,text,text,text,text,timestamp with time zone,text,text[],text[],boolean,timestamp with time zone,text,text,jsonb,jsonb,boolean)'::regprocedure
  ) into definition;
  if position('from public.save_location(' in definition) = 0
    or position(old_fragment in definition) = 0
  then
    raise exception 'Photo Location writer changed unexpectedly';
  end if;
  execute replace(definition, old_fragment, new_fragment);
end;
$migration$;

-- One atomic, bounded hourly counter per owner and provider action. Its row
-- is reused each hour, so quota accounting does not grow without bound.
create table public.location_provider_usage (
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('search', 'preview', 'tiles')),
  window_started timestamptz not null,
  request_count integer not null check (request_count >= 1),
  primary key (owner_id, kind)
);

revoke all on public.location_provider_usage from public, anon, authenticated;

create function public.consume_location_provider_quota(p_kind text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_owner uuid := auth.uid();
  request_limit integer;
  current_window timestamptz := date_trunc('hour', now());
  saved_count integer;
begin
  if request_owner is null then return false; end if;
  request_limit := case p_kind
    when 'search' then 120
    when 'preview' then 300
    when 'tiles' then 3000
    else null
  end;
  if request_limit is null then
    raise exception using errcode = '22023', message = 'invalid_location_quota_kind';
  end if;

  insert into public.location_provider_usage as usage (
    owner_id, kind, window_started, request_count
  ) values (request_owner, p_kind, current_window, 1)
  on conflict (owner_id, kind) do update
    set window_started = current_window,
        request_count = case
          when usage.window_started = current_window
            then usage.request_count + 1
          else 1
        end
    where usage.window_started <> current_window
      or usage.request_count < request_limit
  returning request_count into saved_count;

  return saved_count is not null;
end;
$$;

revoke all on function public.consume_location_provider_quota(text)
  from public, anon;
grant execute on function public.consume_location_provider_quota(text)
  to authenticated;
