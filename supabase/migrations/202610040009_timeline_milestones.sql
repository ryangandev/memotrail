-- Timeline shows life milestones instead of a record type on customizable tracks.
--
-- Any Entry can be marked as a milestone: a Moment or a Period, in the Work and study lane
-- or the Other lane, and optionally a First Time. Homes and Vehicles appear on Timeline on
-- their own, so they need no placement. Moments, Periods, and First Times become plain
-- Entries with a milestone, and tracks are gone.

create table public.milestones (
  entry_id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  shape text not null check (shape in ('moment', 'period')),
  lane text not null check (lane in ('work_study', 'other')),
  is_first_time boolean not null default false,
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);
comment on table public.milestones is
  'Marks an Entry as a life milestone on Timeline. Homes and Vehicles appear on Timeline without one.';
create index milestones_owner_idx on public.milestones (owner_id, lane);
alter table public.milestones enable row level security;
create policy "Users can manage their own rows" on public.milestones
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
revoke all on public.milestones from public, anon, authenticated;
grant select, insert, update, delete on public.milestones to authenticated;
grant all on public.milestones to service_role;

create trigger milestones_set_updated_at
before update on public.milestones
for each row execute function public.set_updated_at();

-- Only an ordinary Entry is a milestone; a Home or Vehicle is on Timeline already.
create function public.enforce_milestone_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.entries
    where entries.id = new.entry_id
      and entries.owner_id = new.owner_id
      and entries.item_kind = 'entry'
  ) then
    raise exception using errcode = '23514', message = 'milestone_requires_entry';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_milestone_entry() from public, anon, authenticated;
create trigger milestones_enforce_entry
before insert or update of entry_id, owner_id on public.milestones
for each row execute function public.enforce_milestone_entry();

-- What Timeline showed stays on Timeline: every First Time, every Entry placed on a visible track,
-- and any Moment or Period with no placement become milestones. An Entry placed only on hidden
-- tracks becomes a plain Entry. A Period placement, a Period, or a date span makes a Period. An
-- Education or Career placement puts it in Work and study. A First Time, or a placement on the
-- First Times track, makes a First Time.
insert into public.milestones (entry_id, owner_id, shape, lane, is_first_time)
select
  entry.id,
  entry.owner_id,
  case
    when entry.item_subtype = 'period'
      or entry.occurred_end is not null
      or entry.date_precision = 'range'
      or exists (
        select 1 from public.timeline_items as item
        where item.entry_id = entry.id and item.timeline_kind = 'stage'
      )
    then 'period'
    else 'moment'
  end,
  case
    when exists (
      select 1
      from public.timeline_items as item
      join public.timeline_tracks as track on track.id = item.track_id
      where item.entry_id = entry.id and track.system_key in ('education', 'career')
    )
    then 'work_study'
    else 'other'
  end,
  entry.item_subtype = 'first_time' or exists (
    select 1
    from public.timeline_items as item
    join public.timeline_tracks as track on track.id = item.track_id
    where item.entry_id = entry.id and track.system_key = 'first_times'
  )
from public.entries as entry
where entry.item_kind = 'entry'
  and (
    entry.item_subtype = 'first_time'
    or exists (
      select 1
      from public.timeline_items as item
      join public.timeline_tracks as track on track.id = item.track_id
      where item.entry_id = entry.id and not track.is_hidden
    )
    or (
      entry.item_subtype in ('moment', 'period')
      and not exists (select 1 from public.timeline_items as item where item.entry_id = entry.id)
    )
  );

-- A track name other than First Times and Other Events still describes the Entries on it,
-- so it becomes a tag on them, like Collections did. Homes and Vehicles need no placement.
insert into public.tags (owner_id, name)
select distinct on (track.owner_id, lower(btrim(track.name)))
  track.owner_id, left(btrim(track.name), 80)
from public.timeline_tracks as track
join public.timeline_items as item on item.track_id = track.id
join public.entries as entry on entry.id = item.entry_id and entry.item_kind = 'entry'
where track.system_key is distinct from 'first_times'
  and track.system_key is distinct from 'other_events'
  and not exists (
    select 1 from public.tags
    where tags.owner_id = track.owner_id and lower(tags.name) = lower(left(btrim(track.name), 80))
  )
order by track.owner_id, lower(btrim(track.name)), track.created_at
on conflict do nothing;

-- An Entry keeps within the 70-tag limit, so its next save stays valid.
with new_tags as (
  select distinct item.entry_id, tag.id as tag_id, item.owner_id, lower(tag.name) as tag_key
  from public.timeline_items as item
  join public.timeline_tracks as track on track.id = item.track_id
  join public.entries as entry on entry.id = item.entry_id and entry.item_kind = 'entry'
  join public.tags as tag
    on tag.owner_id = track.owner_id
    and lower(tag.name) = lower(left(btrim(track.name), 80))
  where track.system_key is distinct from 'first_times'
    and track.system_key is distinct from 'other_events'
    and not exists (
      select 1 from public.entry_tags
      where entry_tags.entry_id = item.entry_id and entry_tags.tag_id = tag.id
    )
),
ranked as (
  select
    new_tags.*,
    row_number() over (partition by new_tags.entry_id order by new_tags.tag_key) as position,
    (select count(*) from public.entry_tags where entry_tags.entry_id = new_tags.entry_id) as existing_count
  from new_tags
)
insert into public.entry_tags (entry_id, tag_id, owner_id)
select entry_id, tag_id, owner_id
from ranked
where existing_count + position <= 70
on conflict do nothing;

update public.entries
set item_subtype = 'entry'
where item_kind = 'entry' and item_subtype in ('moment', 'period', 'first_time');

alter table public.entries drop constraint entries_entry_subtype_valid;
alter table public.entries add constraint entries_entry_subtype_valid
  check (item_kind <> 'entry' or item_subtype = 'entry');

-- Tracks, and the functions that placed records on them and edited them.
drop function public.save_timeline_entry_with_occurrence(uuid, text, text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, integer);
drop function public.save_timeline_entry_with_organization(uuid, text, text, text, timestamp with time zone, timestamp with time zone, text, text, text, text[], uuid, integer);
drop function public.trash_timeline_entry(uuid, integer);
drop function public.timeline_workspace_with_organization(boolean);
drop function public.timeline_track_settings(integer, integer);
drop function public.save_timeline_track(text, integer, boolean, uuid, integer);
drop table public.timeline_items;
drop table public.timeline_tracks;
drop function public.advance_timeline_track_revision();

-- The focused First Time form, its save, photos, Trash, and workspace. A First Time is now
-- an Entry with a milestone, so the Entry editor and Item page handle it.
drop function public.save_first_time_with_location(jsonb, jsonb);
drop function public.save_first_time_with_occurrence(text, text, timestamp with time zone, text, text, text, text[], uuid, integer, timestamp with time zone);
drop function public.register_first_time_attachment(uuid, uuid, text, text, text, bigint, integer, integer);
drop function public.trash_first_time_attachment(uuid);
drop function public.trash_first_time_entry(uuid, integer);
drop function public.first_times_workspace_with_occurrence();

-- Homes and Vehicles appear on Timeline on their own, so their saves place nothing.
create or replace function public.save_home_entry_with_occurrence(
  p_title text,
  p_body text,
  p_occurred_start timestamp with time zone,
  p_occurred_end timestamp with time zone,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_move_in_reason text,
  p_move_out_reason text,
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_move_in_reason text := nullif(btrim(p_move_in_reason), '');
  normalized_move_out_reason text := nullif(btrim(p_move_out_reason), '');
begin
  if home_owner_id is null then
    return;
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_home_content';
  end if;

  if length(coalesce(normalized_move_in_reason, '')) > 10000
    or length(coalesce(normalized_move_out_reason, '')) > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_home_details';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_home_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_home_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_home_timezone';
    end;
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_home_range';
  end if;

  if normalized_move_out_reason is not null and p_occurred_end is null then
    raise exception using errcode = '22023', message = 'home_move_out_requires_date';
  end if;

  if p_date_precision is null or p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'home_label_too_long';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      home_owner_id,
      normalized_title,
      normalized_body,
      'entity',
      'home',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = home_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.homes
        where homes.entry_id = entries.id
          and homes.owner_id = home_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  insert into public.homes (
    entry_id,
    owner_id,
    move_in_reason,
    move_out_reason
  )
  values (
    saved_entry_id,
    home_owner_id,
    normalized_move_in_reason,
    normalized_move_out_reason
  )
  on conflict on constraint homes_pkey do update
  set
    move_in_reason = excluded.move_in_reason,
    move_out_reason = excluded.move_out_reason
  where (homes.move_in_reason, homes.move_out_reason)
    is distinct from (excluded.move_in_reason, excluded.move_out_reason);

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$$;

CREATE OR REPLACE FUNCTION public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  vehicle_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_make text := nullif(btrim(p_make), '');
  normalized_model text := nullif(btrim(p_model), '');
  normalized_color text := nullif(btrim(p_color), '');
begin
  if vehicle_owner_id is null then
    return;
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_vehicle_content';
  end if;

  if length(coalesce(normalized_make, '')) > 120
    or length(coalesce(normalized_model, '')) > 120
    or length(coalesce(normalized_color, '')) > 80
    or (p_model_year is not null and p_model_year not between 1886 and 2200)
  then
    raise exception using errcode = '22023', message = 'invalid_vehicle_details';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_vehicle_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_vehicle_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_vehicle_timezone';
    end;
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_vehicle_range';
  end if;

  if p_date_precision is null or p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'vehicle_label_too_long';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      vehicle_owner_id,
      normalized_title,
      normalized_body,
      'entity',
      'vehicle',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'entity',
      item_subtype = 'vehicle',
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = vehicle_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'entity' and entries.item_subtype = 'vehicle'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.vehicles
        where vehicles.entry_id = entries.id
          and vehicles.owner_id = vehicle_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  insert into public.vehicles (
    entry_id,
    owner_id,
    make,
    model,
    model_year,
    color
  )
  values (
    saved_entry_id,
    vehicle_owner_id,
    normalized_make,
    normalized_model,
    p_model_year,
    normalized_color
  )
  on conflict on constraint vehicles_pkey do update
  set
    make = excluded.make,
    model = excluded.model,
    model_year = excluded.model_year,
    color = excluded.color
  where (vehicles.make, vehicles.model, vehicles.model_year, vehicles.color)
    is distinct from (excluded.make, excluded.model, excluded.model_year, excluded.color);

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$function$;

drop function public.homes_workspace(integer, integer);
create function public.homes_workspace(p_limit integer default 50, p_offset integer default 0)
returns table(
  entry_id uuid,
  title text,
  body text,
  occurred_start timestamp with time zone,
  occurred_end timestamp with time zone,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamp with time zone,
  move_in_reason text,
  move_out_reason text,
  tag_names text[],
  attachments jsonb,
  total_count bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
begin
  if home_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_homes_page';
  end if;

  return query
  with visible_homes as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.updated_at,
      homes.move_in_reason,
      homes.move_out_reason,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = home_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = home_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.homes
      on homes.entry_id = entries.id
      and homes.owner_id = entries.owner_id
    where entries.owner_id = home_owner_id
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
  ),
  counted_homes as (
    select visible_homes.*, count(*) over () as total_count
    from visible_homes
  )
  select counted_homes.*
  from counted_homes
  order by
    (counted_homes.occurred_end is null) desc,
    counted_homes.occurred_start desc nulls last,
    lower(counted_homes.title),
    counted_homes.entry_id
  limit p_limit
  offset p_offset;
end;
$$;
revoke all on function public.homes_workspace(integer, integer) from public, anon;
grant execute on function public.homes_workspace(integer, integer) to authenticated, service_role;

drop function public.vehicles_workspace(integer, integer);
create function public.vehicles_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, make text, model text, model_year integer, color text, tag_names text[], attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  vehicle_owner_id uuid := auth.uid();
begin
  if vehicle_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_vehicles_page';
  end if;

  return query
  with visible_vehicles as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.updated_at,
      vehicles.make,
      vehicles.model,
      vehicles.model_year,
      vehicles.color,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = vehicle_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = vehicle_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.vehicles
      on vehicles.entry_id = entries.id
      and vehicles.owner_id = entries.owner_id
    where entries.owner_id = vehicle_owner_id
      and entries.item_kind = 'entity' and entries.item_subtype = 'vehicle'
      and entries.deleted_at is null
  ),
  counted_vehicles as (
    select visible_vehicles.*, count(*) over () as total_count
    from visible_vehicles
  )
  select counted_vehicles.*
  from counted_vehicles
  order by
    (counted_vehicles.occurred_end is null) desc,
    counted_vehicles.occurred_start desc nulls last,
    lower(counted_vehicles.title),
    counted_vehicles.entry_id
  limit p_limit
  offset p_offset;
end;
$function$;
revoke all on function public.vehicles_workspace(integer, integer) from public, anon;
grant execute on function public.vehicles_workspace(integer, integer) to authenticated, service_role;

-- The Dashboard's Now block replaces current chapters, and its First Time count reads milestones.
drop function public.home_workspace(date, text, integer);
create function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer DEFAULT 5)
 RETURNS TABLE(snapshot_date date, profile_display_name text, entry_count bigint, first_time_count bigint, tag_count bigint, now_count bigint, recent_entries jsonb, now_items jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
  local_day_start timestamptz;
  local_day_end timestamptz;
begin
  if home_owner_id is null then
    return;
  end if;

  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;

  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;

  if p_recent_limit is null or p_recent_limit < 1 or p_recent_limit > 10 then
    raise exception using errcode = '22023', message = 'invalid_home_recent_limit';
  end if;

  begin
    local_day_start := pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
    local_day_end := pg_catalog.timezone(
      normalized_timezone,
      (p_local_date + 1)::timestamp
    );
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with active_entries as (
    select entries.*
    from public.entries
    where entries.owner_id = home_owner_id
      and entries.deleted_at is null
  ),
  entry_stats as (
    select
      count(*) as entry_count,
      count(*) filter (
        where exists (
          select 1 from public.milestones
          where milestones.entry_id = active_entries.id and milestones.is_first_time
        )
      ) as first_time_count
    from active_entries
  ),
  tag_stats as (
    select count(*) as tag_count
    from public.tags
    where tags.owner_id = home_owner_id
  ),

  -- Now lists what is still going on: Periods, Homes, and Vehicles that started and have no end.
  now_rows as (
    select
      entries.id as entry_id,
      entries.title,
      entries.item_kind,
      entries.item_subtype,
      case
        when entries.item_subtype = 'home' then 'homes'
        when entries.item_subtype = 'vehicle' then 'vehicles'
        else milestones.lane
      end as lane,
      coalesce(milestones.is_first_time, false) as is_first_time,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone
    from active_entries as entries
    left join public.milestones on milestones.entry_id = entries.id
    where (
        (entries.item_kind = 'entity' and entries.item_subtype in ('home', 'vehicle'))
        or milestones.shape = 'period'
      )
      and entries.occurred_start < local_day_end
      and entries.occurred_end is null
  ),
  recent_entry_rows as (
    select
      entries.*,
      row_number() over (order by entries.created_at desc, entries.id) as recent_position
    from active_entries as entries
    order by entries.created_at desc, entries.id
    limit p_recent_limit
  )
  select
    p_local_date,
    (
      select profiles.display_name
      from public.profiles
      where profiles.user_id = home_owner_id
    ),
    entry_stats.entry_count,
    entry_stats.first_time_count,
    tag_stats.tag_count,
    (select count(*) from now_rows),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', recent_entries.id,
            'title', coalesce(
              nullif(btrim(recent_entries.title), ''),
              nullif(split_part(btrim(recent_entries.body), E'\n', 1), ''),
              'Untitled Entry'
            ),
            'body', recent_entries.body,
            'item_kind', recent_entries.item_kind, 'item_subtype', recent_entries.item_subtype,
            'occurred_start', recent_entries.occurred_start,
            'occurred_end', recent_entries.occurred_end,
            'date_precision', recent_entries.date_precision,
            'occurred_label', recent_entries.occurred_label,
            'occurred_timezone', recent_entries.occurred_timezone,
            'revision', recent_entries.revision,
            'created_at', recent_entries.created_at,
            'updated_at', recent_entries.updated_at,
            'tag_names', coalesce(
              (
                select jsonb_agg(tags.name order by lower(tags.name), tags.id)
                from public.entry_tags
                join public.tags
                  on tags.id = entry_tags.tag_id
                  and tags.owner_id = entry_tags.owner_id
                where entry_tags.entry_id = recent_entries.id
                  and entry_tags.owner_id = home_owner_id
              ),
              '[]'::jsonb
            ),
            'attachments', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'attachment_id', attachments.id,
                    'bucket_id', attachments.bucket_id,
                    'object_path', attachments.object_path,
                    'original_filename', attachments.original_filename,
                    'mime_type', attachments.mime_type,
                    'byte_size', attachments.byte_size,
                    'pixel_width', attachments.pixel_width,
                    'pixel_height', attachments.pixel_height
                  )
                  order by attachments.created_at, attachments.id
                )
                from public.attachments
                where attachments.entry_id = recent_entries.id
                  and attachments.owner_id = home_owner_id
                  and attachments.deleted_at is null
                  and attachments.variant = 'original'
              ),
              '[]'::jsonb
            )
          )
          order by recent_entries.recent_position
        )
        from recent_entry_rows as recent_entries
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', now_rows.entry_id,
            'title', now_rows.title,
            'item_kind', now_rows.item_kind,
            'item_subtype', now_rows.item_subtype,
            'lane', now_rows.lane,
            'is_first_time', now_rows.is_first_time,
            'occurred_start', now_rows.occurred_start,
            'occurred_end', now_rows.occurred_end,
            'date_precision', now_rows.date_precision,
            'occurred_label', now_rows.occurred_label,
            'occurred_timezone', now_rows.occurred_timezone
          )
          order by
            array_position(array['homes', 'vehicles', 'work_study', 'other'], now_rows.lane),
            now_rows.occurred_start desc,
            lower(now_rows.title),
            now_rows.entry_id
        )
        from now_rows
      ),
      '[]'::jsonb
    )
  from entry_stats
  cross join tag_stats;
end;
$function$;
revoke all on function public.home_workspace(date, text, integer) from public, anon;
grant execute on function public.home_workspace(date, text, integer) to authenticated, service_role;

-- A Period is a stretch of life, not a memory to resurface.
CREATE OR REPLACE FUNCTION public.home_resurfaced_memory(p_local_date date, p_timezone text)
 RETURNS TABLE(resurfacing_kind text, years_ago integer, entry_id uuid, title text, body text, item_kind text, item_subtype text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, tag_names jsonb, attachments jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
begin
  if home_owner_id is null then
    return;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;
  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;
  begin
    perform pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with eligible_items as (
    select
      item.*,
      pg_catalog.timezone(coalesce(timezone.name, 'UTC'), item.occurred_start)::date
        as local_occurred_date
    from public.entries as item
    left join pg_catalog.pg_timezone_names as timezone
      on timezone.name = item.occurred_timezone
    where item.owner_id = home_owner_id
      and item.deleted_at is null
      and item.occurred_start is not null
      and not exists (
        select 1 from public.milestones
        where milestones.entry_id = item.id and milestones.shape = 'period'
      )
  ),
  anniversary_memory as (
    select
      eligible_items.*,
      'on_this_day'::text as selected_kind,
      extract(year from p_local_date)::integer
        - extract(year from eligible_items.local_occurred_date)::integer
        as selected_years_ago
    from eligible_items
    where extract(month from eligible_items.local_occurred_date) = extract(month from p_local_date)
      and extract(day from eligible_items.local_occurred_date) = extract(day from p_local_date)
      and extract(year from eligible_items.local_occurred_date) < extract(year from p_local_date)
    order by eligible_items.local_occurred_date desc, eligible_items.created_at desc, eligible_items.id
    limit 1
  ),
  archive_memories as (
    select
      eligible_items.*,
      row_number() over (order by eligible_items.local_occurred_date, eligible_items.id) as archive_position,
      count(*) over () as archive_count
    from eligible_items
    where eligible_items.local_occurred_date <= p_local_date - 30
      and not exists (select 1 from anniversary_memory)
  ),
  archive_memory as (
    select
      archive_memories.*,
      'from_your_archive'::text as selected_kind,
      null::integer as selected_years_ago
    from archive_memories
    where archive_memories.archive_position = (
      pg_catalog.mod(
        (p_local_date - date '2000-01-01')::bigint,
        archive_memories.archive_count
      ) + 1
    )
  ),
  selected_memory as (
    select
      anniversary_memory.selected_kind,
      anniversary_memory.selected_years_ago,
      anniversary_memory.id,
      anniversary_memory.title,
      anniversary_memory.body,
      anniversary_memory.item_kind,
      anniversary_memory.item_subtype,
      anniversary_memory.occurred_start,
      anniversary_memory.occurred_end,
      anniversary_memory.date_precision,
      anniversary_memory.occurred_label,
      anniversary_memory.occurred_timezone,
      anniversary_memory.revision,
      anniversary_memory.created_at,
      anniversary_memory.updated_at
    from anniversary_memory
    union all
    select
      archive_memory.selected_kind,
      archive_memory.selected_years_ago,
      archive_memory.id,
      archive_memory.title,
      archive_memory.body,
      archive_memory.item_kind,
      archive_memory.item_subtype,
      archive_memory.occurred_start,
      archive_memory.occurred_end,
      archive_memory.date_precision,
      archive_memory.occurred_label,
      archive_memory.occurred_timezone,
      archive_memory.revision,
      archive_memory.created_at,
      archive_memory.updated_at
    from archive_memory
  )
  select
    selected_memory.selected_kind,
    selected_memory.selected_years_ago,
    selected_memory.id,
    coalesce(
      nullif(btrim(selected_memory.title), ''),
      nullif(split_part(btrim(selected_memory.body), E'\n', 1), ''),
      'Untitled Entry'
    ),
    selected_memory.body,
    selected_memory.item_kind,
    selected_memory.item_subtype,
    selected_memory.occurred_start,
    selected_memory.occurred_end,
    selected_memory.date_precision,
    selected_memory.occurred_label,
    selected_memory.occurred_timezone,
    selected_memory.revision,
    selected_memory.created_at,
    selected_memory.updated_at,
    coalesce((
      select jsonb_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = selected_memory.id
        and membership.owner_id = home_owner_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'attachment_id', attachment.id,
        'bucket_id', attachment.bucket_id,
        'object_path', attachment.object_path,
        'original_filename', attachment.original_filename,
        'mime_type', attachment.mime_type,
        'byte_size', attachment.byte_size,
        'pixel_width', attachment.pixel_width,
        'pixel_height', attachment.pixel_height
      ) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = selected_memory.id
        and attachment.owner_id = home_owner_id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  from selected_memory;
end;
$function$;

-- The resurfacing index excluded Periods by subtype, which no Entry has any more.
drop index public.entries_owner_resurfacing_entry_idx;
create index entries_owner_resurfacing_entry_idx
  on public.entries (owner_id, occurred_start desc, id)
  where deleted_at is null and occurred_start is not null;

-- The Entry editor reads and writes the milestone with the rest of the Entry.
create or replace function public.editable_entry(p_entry_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(e) || jsonb_build_object(
    'tag_names', coalesce(
      (
        select jsonb_agg(t.name order by t.name)
        from public.entry_tags et
        join public.tags t
          on t.id = et.tag_id
          and t.owner_id = et.owner_id
        where et.entry_id = e.id
          and et.owner_id = auth.uid()
      ),
      '[]'::jsonb
    ),
    'primary_location', (
      select to_jsonb(location)
      from public.entry_locations as link
      join public.locations as location
        on location.id = link.location_id
        and location.owner_id = link.owner_id
      where link.entry_id = e.id
        and link.owner_id = auth.uid()
        and link.relationship = 'primary'
      order by link.created_at desc, location.id
      limit 1
    ),
    'milestone', (
      select jsonb_build_object(
        'shape', milestone.shape,
        'lane', milestone.lane,
        'is_first_time', milestone.is_first_time
      )
      from public.milestones as milestone
      where milestone.entry_id = e.id
        and milestone.owner_id = auth.uid()
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind = 'entry';
$$;

create or replace function public.entry_detail(p_entry_id uuid)
returns jsonb
language sql
stable security definer
set search_path = ''
as $$
  select (to_jsonb(entry) - 'embedding' - 'search_document') || jsonb_build_object(
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = entry.id
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
          'location_id', link.location_id,
          'relationship', link.relationship,
          'formatted_address', location.formatted_address,
          'latitude', location.latitude,
          'longitude', location.longitude
        ) order by link.relationship, link.location_id)
      from public.entry_locations as link
      join public.locations as location on location.id = link.location_id
      where link.entry_id = entry.id
    ), '[]'::jsonb),
    'milestone', (
      select jsonb_build_object(
        'shape', milestone.shape,
        'lane', milestone.lane,
        'is_first_time', milestone.is_first_time
      )
      from public.milestones as milestone
      where milestone.entry_id = entry.id
    ),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('target_entry_id', link.target_entry_id, 'relationship', link.relationship)
        order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = entry.id
    ), '[]'::jsonb)
  )
  from public.entries as entry
  where entry.id = p_entry_id and entry.owner_id = auth.uid();
$$;

-- Sets or clears an Entry's milestone. A Moment is one point in time, so it has no end.
create function public.replace_entry_milestone(p_entry_id uuid, p_milestone jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  milestone_owner_id uuid := auth.uid();
  milestone_shape text;
  milestone_lane text;
begin
  if milestone_owner_id is null then
    return;
  end if;
  if p_milestone is null or p_milestone = 'null'::jsonb then
    delete from public.milestones
    where milestones.entry_id = p_entry_id and milestones.owner_id = milestone_owner_id;
    return;
  end if;

  milestone_shape := p_milestone->>'shape';
  milestone_lane := p_milestone->>'lane';
  if jsonb_typeof(p_milestone) <> 'object'
    or milestone_shape is null or milestone_shape not in ('moment', 'period')
    or milestone_lane is null or milestone_lane not in ('work_study', 'other')
    or jsonb_typeof(p_milestone->'isFirstTime') is distinct from 'boolean'
  then
    raise exception using errcode = '22023', message = 'invalid_milestone';
  end if;
  if milestone_shape = 'moment' and exists (
    select 1 from public.entries
    where entries.id = p_entry_id
      and (entries.occurred_end is not null or entries.date_precision = 'range')
  ) then
    raise exception using errcode = '22023', message = 'moment_has_no_end';
  end if;

  insert into public.milestones (entry_id, owner_id, shape, lane, is_first_time)
  values (
    p_entry_id,
    milestone_owner_id,
    milestone_shape,
    milestone_lane,
    (p_milestone->>'isFirstTime')::boolean
  )
  on conflict on constraint milestones_pkey do update
  set shape = excluded.shape, lane = excluded.lane, is_first_time = excluded.is_first_time
  where (milestones.shape, milestones.lane, milestones.is_first_time)
    is distinct from (excluded.shape, excluded.lane, excluded.is_first_time);
end;
$$;
revoke all on function public.replace_entry_milestone(uuid, jsonb) from public, anon;
grant execute on function public.replace_entry_milestone(uuid, jsonb) to authenticated, service_role;

-- The Entry editor's save. It also creates an Entry, for adding a milestone from Timeline or
-- First Times: a null expected revision creates the Entry with the caller's id, so a retry after
-- a lost response cannot create it twice. A Period, like a Home or a Vehicle, can end at any
-- calendar precision, such as 2017 to 2023.
drop function public.save_entry(uuid, integer, text, text, jsonb, timestamp with time zone, timestamp with time zone, text, text, text, text[], jsonb, jsonb);
create function public.save_entry(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_body_rich jsonb,
  p_occurred_start timestamp with time zone,
  p_occurred_end timestamp with time zone,
  p_occurred_timezone text,
  p_occurred_label text,
  p_date_precision text,
  p_tag_names text[],
  p_primary_location jsonb,
  p_photo_location jsonb,
  p_milestone jsonb
)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  entry_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  photo_attachment_id uuid;
  photo_latitude numeric;
  photo_longitude numeric;
  photo_location_id uuid;
begin
  if entry_owner_id is null then
    return;
  end if;
  if p_entry_id is null then
    raise exception using errcode = '22023', message = 'invalid_entry';
  end if;
  if p_expected_revision is not null and p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  if p_title is null and p_body = '' then
    raise exception using errcode = '22023', message = 'empty_entry';
  end if;
  if length(coalesce(p_title, '')) > 200 or length(p_body) > 50000 then
    raise exception using errcode = '22023', message = 'entry_content_too_long';
  end if;
  if p_body_rich is not null and (
    jsonb_typeof(p_body_rich) is distinct from 'object'
    or p_body_rich->>'version' is distinct from '1'
    or jsonb_typeof(p_body_rich->'text') is distinct from 'string'
    or p_body_rich->>'text' is distinct from p_body
    or jsonb_typeof(p_body_rich->'document') is distinct from 'object'
    or octet_length(p_body_rich::text) > 300000
  ) then
    raise exception using errcode = '22023', message = 'invalid_rich_text';
  end if;

  p_occurred_label := nullif(btrim(p_occurred_label), '');
  if p_date_precision is null or p_date_precision not in ('exact','day','month','year','approximate','age','range','unknown')
    or p_occurred_timezone is null or length(p_occurred_timezone) > 100
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_occurred_timezone)
    or length(coalesce(p_occurred_label, '')) > 200
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and p_occurred_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (
      p_occurred_end is not null
      and p_date_precision not in ('range','approximate','age')
      and (jsonb_typeof(p_milestone) is distinct from 'object' or p_milestone->>'shape' is distinct from 'period')
    )
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_occurrence';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_photo_location is not null and p_photo_location <> 'null'::jsonb then
    -- A new Entry has no photos yet.
    if p_expected_revision is null
      or jsonb_typeof(p_photo_location) <> 'object'
      or coalesce(p_photo_location->>'attachmentId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      or jsonb_typeof(p_photo_location->'latitude') is distinct from 'number'
      or jsonb_typeof(p_photo_location->'longitude') is distinct from 'number'
    then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
    photo_attachment_id := (p_photo_location->>'attachmentId')::uuid;
    photo_latitude := (p_photo_location->>'latitude')::numeric;
    photo_longitude := (p_photo_location->>'longitude')::numeric;
    if photo_latitude not between -90 and 90 or photo_longitude not between -180 and 180 then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
  end if;

  if p_expected_revision is null then
    insert into public.entries (
      id, owner_id, title, body, metadata, item_kind, item_subtype,
      occurred_start, occurred_end, occurred_label, date_precision, occurred_timezone
    )
    values (
      p_entry_id,
      entry_owner_id,
      p_title,
      p_body,
      case when p_body_rich is null then '{}'::jsonb else jsonb_build_object('body_rich', p_body_rich) end,
      'entry',
      'entry',
      p_occurred_start,
      p_occurred_end,
      p_occurred_label,
      p_date_precision,
      btrim(p_occurred_timezone)
    )
    on conflict on constraint entries_pkey do nothing
    returning entries.id, entries.revision
    into saved_entry_id, saved_revision;
  else
    update public.entries as item
    set
      title = p_title,
      body = p_body,
      metadata = case
        when p_body_rich is null then item.metadata - 'body_rich'
        else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
      end,
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      occurred_label = p_occurred_label,
      date_precision = p_date_precision,
      occurred_timezone = btrim(p_occurred_timezone)
    where item.id = p_entry_id
      and item.owner_id = entry_owner_id
      and item.revision = p_expected_revision
      and item.item_kind = 'entry'
      and item.deleted_at is null
    returning item.id, item.revision
    into saved_entry_id, saved_revision;
  end if;

  if saved_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);
  perform public.replace_primary_location(saved_entry_id, p_primary_location);
  perform public.replace_entry_milestone(saved_entry_id, p_milestone);

  if photo_attachment_id is not null then
    if not public.lock_photo_place_source(saved_entry_id, photo_attachment_id) then
      raise exception using errcode = '40001', message = 'photo_source_changed';
    end if;
    insert into public.locations (owner_id, latitude, longitude)
    values (entry_owner_id, round(photo_latitude, 6), round(photo_longitude, 6))
    returning locations.id into photo_location_id;
    insert into public.entry_locations (entry_id, location_id, owner_id, relationship)
    values (saved_entry_id, photo_location_id, entry_owner_id, 'photo');
    perform public.record_photo_location_source(
      photo_location_id, saved_entry_id, photo_attachment_id
    );
  end if;

  return query
  select saved_entry_id, saved_revision;
end;
$$;
revoke all on function public.save_entry(uuid, integer, text, text, jsonb, timestamp with time zone, timestamp with time zone, text, text, text, text[], jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.save_entry(uuid, integer, text, text, jsonb, timestamp with time zone, timestamp with time zone, text, text, text, text[], jsonb, jsonb, jsonb) to authenticated, service_role;

-- First Times is a view of the milestones marked as a First Time.
create function public.first_times_workspace()
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], attachments jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    entries.id,
    entries.title,
    entries.body,
    entries.occurred_start,
    entries.occurred_end,
    entries.date_precision,
    entries.occurred_label,
    entries.occurred_timezone,
    entries.revision,
    entries.updated_at,
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id
        where entry_tags.entry_id = entries.id
          and entry_tags.owner_id = entries.owner_id
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', media.id,
            'parentAttachmentId', media.parent_attachment_id,
            'variant', media.variant,
            'bucketId', media.bucket_id,
            'objectPath', media.object_path,
            'originalFilename', media.original_filename,
            'mimeType', media.mime_type,
            'byteSize', media.byte_size,
            'pixelWidth', media.pixel_width,
            'pixelHeight', media.pixel_height,
            'createdAt', media.created_at
          )
          order by media.created_at, media.id
        )
        from public.attachments as media
        where media.entry_id = entries.id
          and media.owner_id = entries.owner_id
          and media.deleted_at is null and media.variant = 'original'
      ),
      '[]'::jsonb
    )
  from public.entries
  join public.milestones
    on milestones.entry_id = entries.id
    and milestones.owner_id = entries.owner_id
    and milestones.is_first_time
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$function$;
revoke all on function public.first_times_workspace() from public, anon;
grant execute on function public.first_times_workspace() to authenticated, service_role;

-- Marking a Want to Do item done creates a First Time milestone.
CREATE OR REPLACE FUNCTION public.achieve_goal_with_occurrence(p_goal_entry_id uuid, p_expected_revision integer, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_occurred_end timestamp with time zone)
 RETURNS TABLE(goal_entry_id uuid, goal_revision integer, first_time_entry_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
  achieved_goal_title text;
  achieved_goal_revision integer;
  new_first_time_id uuid;
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;


  -- Touching the Goal advances its revision.
  update public.entries
  set updated_at = now()
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = p_expected_revision
    and entries.item_kind = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
        and goals.status <> 'achieved'
    )
  returning entries.title, entries.revision
  into achieved_goal_title, achieved_goal_revision;

  if achieved_goal_title is null then
    return;
  end if;

  update public.goals
  set status = 'achieved'
  where goals.entry_id = p_goal_entry_id
    and goals.owner_id = goal_owner_id;

  -- The First Time is a new Entry marked as a First Time milestone, without the item's notes.
  select saved.entry_id into new_first_time_id
  from public.save_entry(
    gen_random_uuid(), null, achieved_goal_title, '', null,
    p_occurred_start, p_occurred_end, coalesce(normalized_timezone, 'UTC'), normalized_label,
    p_date_precision, '{}', null, null,
    jsonb_build_object(
      'shape', case when p_occurred_end is null and p_date_precision <> 'range' then 'moment' else 'period' end,
      'lane', 'other',
      'isFirstTime', true
    )
  ) as saved;

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$function$;

-- Timeline reads milestones, Homes, and Vehicles. Each lands in a fixed lane: places lived,
-- vehicles, work and study, and other milestones.
create function public.timeline_workspace()
returns table(
  entry_id uuid,
  title text,
  body text,
  item_kind text,
  item_subtype text,
  lane text,
  shape text,
  is_first_time boolean,
  occurred_start timestamp with time zone,
  occurred_end timestamp with time zone,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamp with time zone,
  tag_names text[]
)
language sql
stable
set search_path = ''
as $$
  select
    entries.id,
    coalesce(nullif(btrim(entries.title), ''), nullif(split_part(btrim(entries.body), E'\n', 1), ''), 'Untitled milestone'),
    entries.body,
    entries.item_kind,
    entries.item_subtype,
    case
      when entries.item_kind = 'entity' and entries.item_subtype = 'home' then 'homes'
      when entries.item_kind = 'entity' and entries.item_subtype = 'vehicle' then 'vehicles'
      else milestones.lane
    end,
    coalesce(milestones.shape, 'period'),
    coalesce(milestones.is_first_time, false),
    entries.occurred_start,
    entries.occurred_end,
    entries.date_precision,
    entries.occurred_label,
    coalesce(entries.occurred_timezone, 'UTC'),
    entries.revision,
    entries.updated_at,
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = entries.id and entry_tags.owner_id = entries.owner_id
      ),
      '{}'::text[]
    )
  from public.entries
  left join public.milestones
    on milestones.entry_id = entries.id
    and milestones.owner_id = entries.owner_id
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
    and (
      milestones.entry_id is not null
      or (entries.item_kind = 'entity' and entries.item_subtype in ('home', 'vehicle'))
    )
  order by entries.occurred_start nulls last, lower(entries.title), entries.id;
$$;
revoke all on function public.timeline_workspace() from public, anon;
grant execute on function public.timeline_workspace() to authenticated, service_role;

-- New accounts start without tracks.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'));
  return new;
end;
$$;

create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','tags','entry_tags',
    'locations','entry_locations','milestones',
    'homes','vehicles','goals','attachments','entry_links',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$$;

-- Search reads a First Time, Moment, or Period from the milestone, and treats a Period with
-- no end like a Home or Vehicle with no end: still going on.
drop function public.wiki_item_occurrence_window(timestamp with time zone, timestamp with time zone, text, text, text, text);
create function public.wiki_item_occurrence_window(
  p_start timestamp with time zone,
  p_end timestamp with time zone,
  p_precision text,
  p_timezone text,
  p_ongoing boolean
)
returns daterange
language plpgsql
stable
set search_path = ''
as $$
declare
  first_day date;
  last_day date;
  local_start timestamp;
  local_end timestamp;
begin
  if p_start is null
    or p_precision = 'unknown'
    or not isfinite(p_start)
    or (p_end is not null and not isfinite(p_end))
  then
    return null;
  end if;

  local_start := public.entry_local_timestamp(p_start, p_timezone);
  local_end := public.entry_local_timestamp(coalesce(p_end, p_start), p_timezone);
  first_day := case p_precision
    when 'year' then date_trunc('year', local_start)::date
    when 'month' then date_trunc('month', local_start)::date
    else local_start::date
  end;

  if p_end is null and (p_precision = 'range' or coalesce(p_ongoing, false)) then
    return daterange(first_day, null, '[)');
  end if;

  last_day := case p_precision
    when 'year' then (date_trunc('year', local_end) + interval '1 year - 1 day')::date
    when 'month' then (date_trunc('month', local_end) + interval '1 month - 1 day')::date
    else local_end::date
  end;

  if last_day < first_day then
    return null;
  end if;
  return daterange(first_day, last_day, '[]');
end;
$$;
revoke all on function public.wiki_item_occurrence_window(timestamp with time zone, timestamp with time zone, text, text, boolean) from public, anon;
grant execute on function public.wiki_item_occurrence_window(timestamp with time zone, timestamp with time zone, text, text, boolean) to authenticated, service_role;

drop function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text);
create function public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text, milestone_shape text, is_first_time boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_classifications text[];
  normalized_tag_names text[];
  search_query tsquery;
  has_query boolean;
  has_filters boolean;
begin
  if search_owner_id is null then
    return;
  end if;
  if p_order is null or p_order not in ('relevance', 'oldest', 'newest') then
    raise exception using errcode = '22023', message = 'invalid_search_order';
  end if;
  if length(coalesce(p_query, '')) > 200 then
    raise exception using errcode = '22023', message = 'query_too_long';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_pagination';
  end if;
  if (p_date_from is not null and not isfinite(p_date_from))
    or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to)
  then
    raise exception using errcode = '22023', message = 'invalid_date_range';
  end if;
  if cardinality(coalesce(p_item_classifications, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
      where nullif(btrim(classification), '') is null
        or length(btrim(classification)) > 64
    )
  then
    raise exception using errcode = '22023', message = 'invalid_item_classifications';
  end if;
  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  normalized_query := lower(btrim(coalesce(p_query, '')));
  normalized_classifications := array(
    select distinct lower(btrim(classification))
    from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
    order by lower(btrim(classification))
  );
  normalized_tag_names := array(
    select distinct lower(btrim(tag_name))
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name))
  );
  has_query := normalized_query <> '';
  search_query := case
    when has_query then websearch_to_tsquery('simple', normalized_query)
    else null::tsquery
  end;
  has_filters := cardinality(normalized_classifications) > 0
    or cardinality(normalized_tag_names) > 0
    or p_date_from is not null
    or p_date_to is not null;

  if not has_query and not has_filters then
    return;
  end if;

  return query
  with owned_items as (
    select
      item.*,
      milestone.shape as milestone_shape,
      milestone.lane as milestone_lane,
      coalesce(milestone.is_first_time, false) as is_first_time
    from public.entries as item
    left join public.milestones as milestone
      on milestone.entry_id = item.id
      and milestone.owner_id = item.owner_id
    where item.owner_id = search_owner_id
      and item.deleted_at is null
      and (
        cardinality(normalized_classifications) = 0
        or item.item_kind = any(normalized_classifications)
        or item.item_subtype = any(normalized_classifications)
        or ('milestone' = any(normalized_classifications) and milestone.entry_id is not null)
        or ('first_time' = any(normalized_classifications) and milestone.is_first_time)
      )
      and (
        cardinality(normalized_tag_names) = 0
        or exists (
          select 1
          from public.entry_tags as membership
          join public.tags as tag
            on tag.id = membership.tag_id
            and tag.owner_id = membership.owner_id
          where membership.entry_id = item.id
            and membership.owner_id = search_owner_id
            and lower(tag.name) = any(normalized_tag_names)
        )
      )
      and (
        (p_date_from is null and p_date_to is null)
        or public.wiki_item_occurrence_window(
          item.occurred_start,
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone,
          milestone.shape = 'period'
            or (item.item_kind = 'entity' and item.item_subtype in ('home', 'vehicle'))
        ) && daterange(p_date_from, p_date_to, '[]')
      )
  ),
  enriched as (
    select
      item.*,
      tag_context.tag_names,
      tag_context.tag_text,
      concat_ws(
        ' ',
        item.occurred_label,
        public.entry_occurrence_date_text(
          item.occurred_start,
          item.date_precision,
          item.occurred_timezone
        ),
        public.entry_occurrence_date_text(
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone
        )
      ) as date_text,
      concat_ws(
        ' ',
        replace(item.item_kind, '_', ' '),
        replace(item.item_subtype, '_', ' '),
        item.milestone_shape,
        case when item.is_first_time then 'first time' end,
        item.metadata::text,
        home.move_in_reason,
        home.move_out_reason,
        vehicle.make,
        vehicle.model,
        vehicle.model_year::text,
        vehicle.color,
        goal.status,
        goal.target_date::text,
        case when item.milestone_shape is not null then 'milestone' end,
        case when item.milestone_lane = 'work_study' then 'work study' end,
        location_context.location_text,
        attachment_context.filename_text
      ) as structured_text
    from owned_items as item
    left join public.homes as home
      on home.entry_id = item.id and home.owner_id = search_owner_id
    left join public.vehicles as vehicle
      on vehicle.entry_id = item.id and vehicle.owner_id = search_owner_id
    left join public.goals as goal
      on goal.entry_id = item.id and goal.owner_id = search_owner_id
    left join lateral (
      select
        coalesce(array_agg(tag.name order by lower(tag.name), tag.name), '{}'::text[]) as tag_names,
        coalesce(string_agg(tag.name, ' '), '') as tag_text
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = search_owner_id
    ) as tag_context on true
    left join lateral (
      select string_agg(concat_ws(' ', location.formatted_address, location.address, location.city, location.region, location.country), ' ') as location_text
      from public.entry_locations as link
      join public.locations as location
        on location.id = link.location_id and location.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as location_context on true
    left join lateral (
      select string_agg(attachment.original_filename, ' ') as filename_text
      from public.attachments as attachment
      where attachment.entry_id = item.id and attachment.owner_id = search_owner_id
    ) as attachment_context on true
  ),
  evaluated as (
    select
      enriched.*,
      has_query and (
        position(normalized_query in lower(coalesce(enriched.title, ''))) > 0
        or to_tsvector('simple', coalesce(enriched.title, '')) @@ search_query
      ) as title_matches,
      has_query and (
        position(normalized_query in lower(enriched.body)) > 0
        or to_tsvector('simple', enriched.body) @@ search_query
      ) as body_matches,
      has_query and (
        position(normalized_query in lower(enriched.tag_text)) > 0
        or to_tsvector('simple', enriched.tag_text) @@ search_query
      ) as tag_matches,
      has_query and (
        position(normalized_query in lower(enriched.date_text)) > 0
        or to_tsvector('simple', enriched.date_text) @@ search_query
      ) as date_matches,
      has_query and (
        position(normalized_query in lower(enriched.structured_text)) > 0
        or to_tsvector('simple', enriched.structured_text) @@ search_query
      ) as structured_matches
    from enriched
  ),
  matched as (
    select
      evaluated.*,
      case
        when not has_query then array['Filters']::text[]
        else array_remove(array[
          case when evaluated.title_matches then 'Title' end,
          case when evaluated.body_matches then 'Body' end,
          case when evaluated.tag_matches then 'Tag' end,
          case when evaluated.date_matches then 'Date' end,
          case when evaluated.structured_matches then 'Details' end
        ], null)
      end as computed_match_reasons,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(ts_rank_cd(evaluated.search_document, search_query)::double precision, 0)
      ) as computed_match_rank
    from evaluated
    where not has_query
      or evaluated.title_matches
      or evaluated.body_matches
      or evaluated.tag_matches
      or evaluated.date_matches
      or evaluated.structured_matches
  )
  select
    matched.id,
    matched.title,
    matched.body,
    matched.occurred_start,
    matched.occurred_end,
    matched.occurred_label,
    matched.occurred_timezone,
    matched.revision,
    matched.updated_at,
    matched.tag_names,
    matched.computed_match_reasons,
    matched.computed_match_rank,
    count(*) over (),
    matched.date_precision,
    matched.item_kind,
    matched.item_subtype,
    matched.milestone_shape,
    matched.is_first_time
  from matched
  order by
    case when p_order = 'relevance' then matched.computed_match_rank end desc nulls last,
    case when p_order = 'oldest' then matched.occurred_start end asc nulls last,
    case when p_order <> 'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text) from public, anon;
grant execute on function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text) to authenticated, service_role;

-- Archive evidence carries the milestone, so it can say what was a First Time or a Period.
CREATE OR REPLACE FUNCTION public.archive_wiki_search_evidence(p_queries text[] DEFAULT '{}'::text[], p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_before_latest_home boolean DEFAULT false, p_order text DEFAULT 'relevance'::text, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $$
declare
  evidence_owner_id uuid := auth.uid();
  normalized_queries text[];
  selected_ids uuid[] := '{}'::uuid[];
  candidate_count integer := 0;
  query_truncated boolean := false;
  latest_home_entry public.entries;
  latest_home_facts public.homes;
  latest_home_reference jsonb;
  reference_date date;
  effective_date_to date := p_date_to;
  reference_window_applied boolean := false;
  entry_evidence jsonb := '[]'::jsonb;
begin
  if evidence_owner_id is null then
    return null;
  end if;

  if p_order is null or p_order not in ('relevance', 'oldest', 'newest')
    or p_as_of is null or not isfinite(p_as_of)
    or cardinality(coalesce(p_queries, '{}'::text[])) > 6
    or exists (
      select 1
      from unnest(coalesce(p_queries, '{}'::text[])) as query
      where query is null or length(btrim(query)) > 200
    )
    or (p_date_from is not null and not isfinite(p_date_from))
    or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to)
    or cardinality(coalesce(p_item_classifications, '{}'::text[])) > 20
    or not public.valid_tag_names(p_tag_names)
  then
    raise exception using errcode = '22023', message = 'invalid_evidence_request';
  end if;

  normalized_queries := array(
    select btrim(query)
    from unnest(coalesce(p_queries, '{}'::text[])) as query
  );
  if cardinality(normalized_queries) = 0 then
    normalized_queries := array['']::text[];
  end if;

  if p_before_latest_home then
    select item.*
    into latest_home_entry
    from public.entries as item
    join public.homes as home
      on home.entry_id = item.id and home.owner_id = item.owner_id
    where item.owner_id = evidence_owner_id
      and item.deleted_at is null
      and item.item_kind = 'entity'
      and item.item_subtype = 'home'
      and item.occurred_start is not null
      and public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date <= p_as_of
    order by
      public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date desc,
      item.id
    limit 1;

    if latest_home_entry.id is not null then
      select home.*
      into latest_home_facts
      from public.homes as home
      where home.entry_id = latest_home_entry.id
        and home.owner_id = evidence_owner_id;

      latest_home_reference := jsonb_build_object(
        'id', latest_home_entry.id,
        'title', latest_home_entry.title,
        'body', latest_home_entry.body,
        'item_kind', latest_home_entry.item_kind,
        'item_subtype', latest_home_entry.item_subtype,
        'date_precision', latest_home_entry.date_precision,
        'occurred_start', latest_home_entry.occurred_start,
        'occurred_end', latest_home_entry.occurred_end,
        'occurred_label', latest_home_entry.occurred_label,
        'occurred_timezone', latest_home_entry.occurred_timezone,
        'facts', jsonb_build_object('home', to_jsonb(latest_home_facts))
      );
    end if;

    if latest_home_entry.id is not null
      and latest_home_entry.date_precision in ('exact', 'day')
    then
      reference_date := public.entry_local_timestamp(
        latest_home_entry.occurred_start,
        latest_home_entry.occurred_timezone
      )::date;
      effective_date_to := least(coalesce(p_date_to, p_as_of), reference_date - 1);
      reference_window_applied := true;
    end if;
  end if;

  if p_date_from is null or effective_date_to is null or p_date_from <= effective_date_to then
    with hits as (
      select
        result.entry_id,
        max(result.match_rank) as match_rank,
        max(result.occurred_start) as occurred_start,
        max(result.updated_at) as updated_at,
        bool_or(result.total_count > 100) as query_truncated
      from unnest(normalized_queries) as query
      cross join lateral public.search_wiki_items(
        query,
        case
          when cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0 and query = ''
            then array['entry', 'entity', 'goal']::text[]
          else p_item_classifications
        end,
        p_tag_names,
        p_date_from,
        effective_date_to,
        100,
        0,
        p_order
      ) as result
      group by result.entry_id
    ),
    selected as (
      select *
      from hits
      order by
        case when p_order = 'relevance' then hits.match_rank end desc nulls last,
        case when p_order = 'oldest' then hits.occurred_start end asc nulls last,
        case when p_order <> 'oldest' then coalesce(hits.occurred_start, hits.updated_at) end desc nulls last,
        hits.entry_id
      limit 36
    )
    select
      coalesce(array_agg(selected.entry_id order by
        case when p_order = 'relevance' then selected.match_rank end desc nulls last,
        case when p_order = 'oldest' then selected.occurred_start end asc nulls last,
        case when p_order <> 'oldest' then coalesce(selected.occurred_start, selected.updated_at) end desc nulls last,
        selected.entry_id
      ), '{}'::uuid[]),
      (select count(*)::integer from hits),
      coalesce((select bool_or(hits.query_truncated) from hits), false)
    into selected_ids, candidate_count, query_truncated
    from selected;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', item.id,
      'title', item.title,
      'body', item.body,
      'item_kind', item.item_kind,
      'item_subtype', item.item_subtype,
      'date_precision', item.date_precision,
      'occurred_start', item.occurred_start,
      'occurred_end', item.occurred_end,
      'occurred_label', item.occurred_label,
      'occurred_timezone', item.occurred_timezone,
      'tags', coalesce(tag_context.names, '[]'::jsonb),
      'facts', jsonb_strip_nulls(jsonb_build_object(
        'home', (select to_jsonb(home) from public.homes as home where home.entry_id = item.id),
        'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = item.id),
        'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = item.id),
        'milestone', (
          select jsonb_build_object(
            'shape', milestone.shape,
            'lane', milestone.lane,
            'is_first_time', milestone.is_first_time
          )
          from public.milestones as milestone
          where milestone.entry_id = item.id
        )
      ))
    ) order by selected.ordinality
  ), '[]'::jsonb)
  into entry_evidence
  from unnest(selected_ids) with ordinality as selected(entry_id, ordinality)
  join public.entries as item
    on item.id = selected.entry_id and item.owner_id = evidence_owner_id
  left join lateral (
    select jsonb_agg(tag.name order by lower(tag.name), tag.id) as names
    from public.entry_tags as membership
    join public.tags as tag
      on tag.id = membership.tag_id and tag.owner_id = membership.owner_id
    where membership.entry_id = item.id and membership.owner_id = evidence_owner_id
  ) as tag_context on true;

  return jsonb_build_object(
    'entries', entry_evidence,
    'candidate_count', candidate_count,
    'query_truncated', query_truncated,
    'query_limit', 100,
    'source_limit', 36,
    'queries', normalized_queries,
    'effective_date_to', effective_date_to,
    'latest_home_reference', latest_home_reference,
    'reference_window_applied', reference_window_applied
  );
end;
$$;
