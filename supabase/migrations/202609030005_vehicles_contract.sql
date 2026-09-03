create index if not exists entries_owner_vehicle_occurrence_idx
  on public.entries (owner_id, occurred_end, occurred_start desc, id)
  where entry_type = 'vehicle' and deleted_at is null;

create index if not exists vehicles_owner_updated_idx
  on public.vehicles (owner_id, updated_at desc, entry_id);

create or replace function public.archive_entry_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_snapshot jsonb := to_jsonb(old);
  home_snapshot jsonb;
  vehicle_snapshot jsonb;
begin
  select jsonb_build_object(
    'home', to_jsonb(homes),
    'place', case when places.id is null then null else to_jsonb(places) end,
    'timeline', case
      when timeline_items.entry_id is null then null
      else jsonb_build_object(
        'track_id', timeline_tracks.id,
        'track_name', timeline_tracks.name,
        'track_system_key', timeline_tracks.system_key,
        'timeline_kind', timeline_items.timeline_kind
      )
    end
  )
  into home_snapshot
  from public.homes
  left join public.places
    on places.id = homes.place_id
    and places.owner_id = homes.owner_id
  left join public.timeline_items
    on timeline_items.entry_id = homes.entry_id
    and timeline_items.owner_id = homes.owner_id
  left join public.timeline_tracks
    on timeline_tracks.id = timeline_items.track_id
    and timeline_tracks.owner_id = timeline_items.owner_id
  where homes.entry_id = old.id
    and homes.owner_id = old.owner_id
  order by
    (timeline_tracks.system_key = 'homes') desc,
    timeline_items.created_at,
    timeline_tracks.id
  limit 1;

  select jsonb_build_object(
    'vehicle', to_jsonb(vehicles),
    'timeline', case
      when timeline_items.entry_id is null then null
      else jsonb_build_object(
        'track_id', timeline_tracks.id,
        'track_name', timeline_tracks.name,
        'track_system_key', timeline_tracks.system_key,
        'timeline_kind', timeline_items.timeline_kind
      )
    end
  )
  into vehicle_snapshot
  from public.vehicles
  left join public.timeline_items
    on timeline_items.entry_id = vehicles.entry_id
    and timeline_items.owner_id = vehicles.owner_id
  left join public.timeline_tracks
    on timeline_tracks.id = timeline_items.track_id
    and timeline_tracks.owner_id = timeline_items.owner_id
  where vehicles.entry_id = old.id
    and vehicles.owner_id = old.owner_id
  order by
    (timeline_tracks.system_key = 'vehicles') desc,
    timeline_items.created_at,
    timeline_tracks.id
  limit 1;

  if home_snapshot is not null then
    archived_snapshot := archived_snapshot || home_snapshot;
  end if;

  if vehicle_snapshot is not null then
    archived_snapshot := archived_snapshot || vehicle_snapshot;
  end if;

  insert into public.entry_versions (
    entry_id,
    owner_id,
    version,
    operation,
    changed_by,
    snapshot
  )
  values (
    old.id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    archived_snapshot
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    new.updated_at = timezone('utc', now());
    return new;
  end if;

  return old;
end;
$$;

revoke all on function public.archive_entry_version() from public;

create or replace function public.vehicles_workspace(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  entry_id uuid,
  title text,
  body text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  make text,
  model text,
  model_year integer,
  color text,
  timeline_track_id uuid,
  timeline_track_name text,
  collection_names text[],
  tag_names text[],
  attachments jsonb,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
      timeline_tracks.id as timeline_track_id,
      timeline_tracks.name as timeline_track_name,
      coalesce(
        (
          select array_agg(collections.name order by lower(collections.name), collections.id)
          from public.entry_collections
          join public.collections
            on collections.id = entry_collections.collection_id
            and collections.owner_id = entry_collections.owner_id
          where entry_collections.entry_id = entries.id
            and entry_collections.owner_id = vehicle_owner_id
            and collections.archived_at is null
        ),
        array[]::text[]
      ) as collection_names,
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
    left join public.timeline_items
      on timeline_items.entry_id = entries.id
      and timeline_items.owner_id = entries.owner_id
      and exists (
        select 1
        from public.timeline_tracks as vehicle_tracks
        where vehicle_tracks.id = timeline_items.track_id
          and vehicle_tracks.owner_id = timeline_items.owner_id
          and vehicle_tracks.system_key = 'vehicles'
      )
    left join public.timeline_tracks
      on timeline_tracks.id = timeline_items.track_id
      and timeline_tracks.owner_id = timeline_items.owner_id
      and timeline_tracks.system_key = 'vehicles'
    where entries.owner_id = vehicle_owner_id
      and entries.entry_type = 'vehicle'
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
    counted_vehicles.occurred_start desc,
    lower(counted_vehicles.title),
    counted_vehicles.entry_id
  limit p_limit
  offset p_offset;
end;
$$;

create or replace function public.save_vehicle_entry(
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_make text,
  p_model text,
  p_model_year integer,
  p_color text,
  p_collection_names text[],
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  vehicle_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  vehicle_track_id uuid;
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

  if p_occurred_start is null
    or normalized_timezone is null
    or length(normalized_timezone) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_vehicle_occurrence';
  end if;

  begin
    perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_vehicle_timezone';
  end;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_vehicle_range';
  end if;

  if p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'vehicle_label_too_long';
  end if;

  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
      where nullif(btrim(collection_name), '') is null
        or length(btrim(collection_name)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;

  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1
      from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null
        or length(btrim(tag_name)) > 60
    )
  then
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
      entry_type,
      inbox_status,
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
      'vehicle',
      'organized',
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
      entry_type = 'vehicle',
      inbox_status = 'organized',
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = vehicle_owner_id
      and entries.revision = p_expected_revision
      and entries.entry_type = 'vehicle'
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
    color = excluded.color;

  select timeline_tracks.id
  into vehicle_track_id
  from public.timeline_tracks
  where timeline_tracks.owner_id = vehicle_owner_id
    and timeline_tracks.system_key = 'vehicles'
  order by timeline_tracks.sort_order, timeline_tracks.id
  limit 1;

  if vehicle_track_id is null then
    select timeline_tracks.id
    into vehicle_track_id
    from public.timeline_tracks
    where timeline_tracks.owner_id = vehicle_owner_id
      and lower(btrim(timeline_tracks.name)) = 'vehicles'
      and timeline_tracks.system_key is null
    order by timeline_tracks.sort_order, timeline_tracks.id
    limit 1;

    if vehicle_track_id is not null then
      update public.timeline_tracks
      set system_key = 'vehicles'
      where timeline_tracks.id = vehicle_track_id
        and timeline_tracks.owner_id = vehicle_owner_id
        and timeline_tracks.system_key is null;
    end if;
  end if;

  if vehicle_track_id is null then
    insert into public.timeline_tracks (
      owner_id,
      name,
      system_key,
      sort_order
    )
    values (
      vehicle_owner_id,
      'Vehicles',
      'vehicles',
      50
    )
    returning timeline_tracks.id into vehicle_track_id;
  end if;

  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = vehicle_owner_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    vehicle_track_id,
    vehicle_owner_id,
    'stage'
  );

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select vehicle_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where collections.owner_id = vehicle_owner_id
      and lower(collections.name) = lower(normalized_names.name)
      and collections.archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections
  where entry_collections.entry_id = saved_entry_id
    and entry_collections.owner_id = vehicle_owner_id;

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select saved_entry_id, collections.id, vehicle_owner_id
  from public.collections
  join normalized_names on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = vehicle_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name)))
      btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select vehicle_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where tags.owner_id = vehicle_owner_id
      and lower(tags.name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.entry_id = saved_entry_id
    and entry_tags.owner_id = vehicle_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select saved_entry_id, tags.id, vehicle_owner_id
  from public.tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = vehicle_owner_id
  on conflict do nothing;

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$$;

create or replace function public.trash_vehicle_entry(
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  vehicle_owner_id uuid := auth.uid();
begin
  if vehicle_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = vehicle_owner_id
    and entries.revision = p_expected_revision
    and entries.entry_type = 'vehicle'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.vehicles
      where vehicles.entry_id = entries.id
        and vehicles.owner_id = vehicle_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

revoke all on function public.vehicles_workspace(integer, integer) from public, anon;
revoke all on function public.save_vehicle_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text[],
  text[],
  uuid,
  integer
) from public, anon;
revoke all on function public.trash_vehicle_entry(uuid, integer) from public, anon;

grant execute on function public.vehicles_workspace(integer, integer) to authenticated;
grant execute on function public.save_vehicle_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text[],
  text[],
  uuid,
  integer
) to authenticated;
grant execute on function public.trash_vehicle_entry(uuid, integer) to authenticated;

comment on function public.vehicles_workspace(integer, integer) is
  'Returns the authenticated owner''s active and completed vehicle chapters with organization and private attachment metadata.';

comment on function public.save_vehicle_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  text[],
  text[],
  uuid,
  integer
) is 'Creates or revision-safely updates an organized Vehicle Entry, structured vehicle facts, Timeline Stage, Collections, and tags atomically.';

comment on function public.trash_vehicle_entry(uuid, integer) is
  'Revision-safely moves an owned Vehicle Entry to recoverable Trash.';
