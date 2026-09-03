create index if not exists entries_owner_home_occurrence_idx
  on public.entries (owner_id, occurred_end, occurred_start desc, id)
  where entry_type = 'home' and deleted_at is null;

create index if not exists homes_owner_updated_idx
  on public.homes (owner_id, updated_at desc, entry_id);

create or replace function public.archive_entry_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_snapshot jsonb := to_jsonb(old);
  home_snapshot jsonb;
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

  if home_snapshot is not null then
    archived_snapshot := archived_snapshot || home_snapshot;
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

create or replace function public.homes_workspace(
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
  move_in_reason text,
  move_out_reason text,
  place_id uuid,
  place_name text,
  address text,
  city text,
  region text,
  country text,
  latitude numeric,
  longitude numeric,
  place_notes text,
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
      places.id as place_id,
      places.name as place_name,
      places.address,
      places.city,
      places.region,
      places.country,
      places.latitude,
      places.longitude,
      places.notes as place_notes,
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
            and entry_collections.owner_id = home_owner_id
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
    join public.places
      on places.id = homes.place_id
      and places.owner_id = homes.owner_id
    left join public.timeline_items
      on timeline_items.entry_id = entries.id
      and timeline_items.owner_id = entries.owner_id
      and exists (
        select 1
        from public.timeline_tracks as home_tracks
        where home_tracks.id = timeline_items.track_id
          and home_tracks.owner_id = timeline_items.owner_id
          and home_tracks.system_key = 'homes'
      )
    left join public.timeline_tracks
      on timeline_tracks.id = timeline_items.track_id
      and timeline_tracks.owner_id = timeline_items.owner_id
      and timeline_tracks.system_key = 'homes'
    where entries.owner_id = home_owner_id
      and entries.entry_type = 'home'
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
    counted_homes.occurred_start desc,
    lower(counted_homes.title),
    counted_homes.entry_id
  limit p_limit
  offset p_offset;
end;
$$;

create or replace function public.save_home_entry(
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_place_id uuid,
  p_place_name text,
  p_address text,
  p_city text,
  p_region text,
  p_country text,
  p_latitude numeric,
  p_longitude numeric,
  p_place_notes text,
  p_move_in_reason text,
  p_move_out_reason text,
  p_collection_names text[],
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  place_id uuid,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  saved_place_id uuid;
  home_track_id uuid;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_place_name text := nullif(btrim(p_place_name), '');
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  normalized_place_notes text := nullif(btrim(p_place_notes), '');
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

  if normalized_place_name is null or length(normalized_place_name) > 200
    or length(coalesce(normalized_address, '')) > 500
    or length(coalesce(normalized_city, '')) > 200
    or length(coalesce(normalized_region, '')) > 200
    or length(coalesce(normalized_country, '')) > 200
    or length(coalesce(normalized_place_notes, '')) > 10000
    or length(coalesce(normalized_move_in_reason, '')) > 10000
    or length(coalesce(normalized_move_out_reason, '')) > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_home_details';
  end if;

  if p_occurred_start is null
    or normalized_timezone is null
    or length(normalized_timezone) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_home_occurrence';
  end if;

  begin
    perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_home_range';
  end if;

  if normalized_move_out_reason is not null and p_occurred_end is null then
    raise exception using errcode = '22023', message = 'home_move_out_requires_date';
  end if;

  if p_date_precision not in (
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

  if (p_latitude is null) <> (p_longitude is null)
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
  then
    raise exception using errcode = '22023', message = 'invalid_home_coordinates';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_place_id is not null and not exists (
    select 1
    from public.places
    where places.id = p_place_id
      and places.owner_id = home_owner_id
  ) then
    return;
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
      home_owner_id,
      normalized_title,
      normalized_body,
      'home',
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
      entry_type = 'home',
      inbox_status = 'organized',
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = home_owner_id
      and entries.revision = p_expected_revision
      and entries.entry_type = 'home'
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

  if p_place_id is null then
    insert into public.places (
      owner_id,
      name,
      address,
      city,
      region,
      country,
      latitude,
      longitude,
      notes
    )
    values (
      home_owner_id,
      normalized_place_name,
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_place_notes
    )
    returning places.id into saved_place_id;
  else
    update public.places
    set
      name = normalized_place_name,
      address = normalized_address,
      city = normalized_city,
      region = normalized_region,
      country = normalized_country,
      latitude = p_latitude,
      longitude = p_longitude,
      notes = normalized_place_notes
    where places.id = p_place_id
      and places.owner_id = home_owner_id
    returning places.id into saved_place_id;
  end if;

  if saved_place_id is null then
    raise exception using errcode = '22023', message = 'invalid_home_place';
  end if;

  insert into public.homes (
    entry_id,
    owner_id,
    place_id,
    move_in_reason,
    move_out_reason
  )
  values (
    saved_entry_id,
    home_owner_id,
    saved_place_id,
    normalized_move_in_reason,
    normalized_move_out_reason
  )
  on conflict on constraint homes_pkey do update
  set
    place_id = excluded.place_id,
    move_in_reason = excluded.move_in_reason,
    move_out_reason = excluded.move_out_reason;

  delete from public.entry_places
  where entry_places.entry_id = saved_entry_id
    and entry_places.owner_id = home_owner_id
    and entry_places.relationship = 'home';

  insert into public.entry_places (
    entry_id,
    place_id,
    owner_id,
    relationship
  )
  values (
    saved_entry_id,
    saved_place_id,
    home_owner_id,
    'home'
  );

  select timeline_tracks.id
  into home_track_id
  from public.timeline_tracks
  where timeline_tracks.owner_id = home_owner_id
    and timeline_tracks.system_key = 'homes'
  order by timeline_tracks.sort_order, timeline_tracks.id
  limit 1;

  if home_track_id is null then
    select timeline_tracks.id
    into home_track_id
    from public.timeline_tracks
    where timeline_tracks.owner_id = home_owner_id
      and lower(btrim(timeline_tracks.name)) = 'homes'
      and timeline_tracks.system_key is null
    order by timeline_tracks.sort_order, timeline_tracks.id
    limit 1;

    if home_track_id is not null then
      update public.timeline_tracks
      set system_key = 'homes'
      where timeline_tracks.id = home_track_id
        and timeline_tracks.owner_id = home_owner_id
        and timeline_tracks.system_key is null;
    end if;
  end if;

  if home_track_id is null then
    insert into public.timeline_tracks (
      owner_id,
      name,
      system_key,
      sort_order
    )
    values (
      home_owner_id,
      'Homes',
      'homes',
      40
    )
    returning timeline_tracks.id into home_track_id;
  end if;

  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = home_owner_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    home_track_id,
    home_owner_id,
    'stage'
  );

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select home_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where collections.owner_id = home_owner_id
      and lower(collections.name) = lower(normalized_names.name)
      and collections.archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections
  where entry_collections.entry_id = saved_entry_id
    and entry_collections.owner_id = home_owner_id;

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select saved_entry_id, collections.id, home_owner_id
  from public.collections
  join normalized_names on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = home_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name)))
      btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select home_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where tags.owner_id = home_owner_id
      and lower(tags.name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.entry_id = saved_entry_id
    and entry_tags.owner_id = home_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select saved_entry_id, tags.id, home_owner_id
  from public.tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = home_owner_id
  on conflict do nothing;

  return query
  select saved_entry_id, saved_revision, saved_place_id, p_entry_id is null;
end;
$$;

create or replace function public.trash_home_entry(
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
  home_owner_id uuid := auth.uid();
begin
  if home_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = home_owner_id
    and entries.revision = p_expected_revision
    and entries.entry_type = 'home'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.homes
      where homes.entry_id = entries.id
        and homes.owner_id = home_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

revoke all on function public.homes_workspace(integer, integer) from public, anon;
revoke all on function public.save_home_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) from public, anon;
revoke all on function public.trash_home_entry(uuid, integer) from public, anon;

grant execute on function public.homes_workspace(integer, integer) to authenticated;
grant execute on function public.save_home_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) to authenticated;
grant execute on function public.trash_home_entry(uuid, integer) to authenticated;

comment on function public.homes_workspace(integer, integer) is
  'Returns the authenticated owner''s active Homes with reusable Place, Timeline, organization, and private attachment metadata.';

comment on function public.save_home_entry(
  text,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) is 'Creates or revision-safely updates a Home Entry, reusable Place, Homes Timeline stage, Collections, and tags in one transaction.';

comment on function public.trash_home_entry(uuid, integer) is
  'Revision-safely moves an owned Home Entry to recoverable Trash while preserving specialized history and relationships.';
