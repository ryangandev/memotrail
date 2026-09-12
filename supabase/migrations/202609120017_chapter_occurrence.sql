-- Additive date contracts retain current owner, history, Place, Timeline, and archived-Collection behavior.
CREATE OR REPLACE FUNCTION public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, place_id uuid, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    and entry_collections.owner_id = home_owner_id
    and exists (
      select 1 from public.collections c
      where c.id = entry_collections.collection_id
        and c.owner_id = entry_collections.owner_id
        and c.archived_at is null
    );

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
$function$;
revoke all on function public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer) from public,anon;
grant execute on function public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer) to authenticated;
CREATE OR REPLACE FUNCTION public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, place_id uuid, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then return; end if;
  if exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid() and e.deleted_at is null and (e.occurred_start is null or e.date_precision='exact')) then
    raise exception using errcode='22023',message='home_requires_current_editor';
  end if;
  if p_occurred_start is null then raise exception using errcode='22023',message='invalid_home_occurrence'; end if;
  return query select * from public.save_home_entry_with_occurrence(p_title,p_body,p_occurred_start,p_occurred_end,p_date_precision,p_occurred_label,p_occurred_timezone,p_place_id,p_place_name,p_address,p_city,p_region,p_country,p_latitude,p_longitude,p_place_notes,p_move_in_reason,p_move_out_reason,p_collection_names,p_tag_names,p_entry_id,p_expected_revision);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    and entry_collections.owner_id = vehicle_owner_id
    and exists (
      select 1 from public.collections c
      where c.id = entry_collections.collection_id
        and c.owner_id = entry_collections.owner_id
        and c.archived_at is null
    );

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
$function$;
revoke all on function public.save_vehicle_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],text[],uuid,integer) from public,anon;
grant execute on function public.save_vehicle_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],text[],uuid,integer) to authenticated;
CREATE OR REPLACE FUNCTION public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then return; end if;
  if exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid() and e.deleted_at is null and (e.occurred_start is null or e.date_precision='exact')) then
    raise exception using errcode='22023',message='vehicle_requires_current_editor';
  end if;
  if p_occurred_start is null then raise exception using errcode='22023',message='invalid_vehicle_occurrence'; end if;
  return query select * from public.save_vehicle_entry_with_occurrence(p_title,p_body,p_occurred_start,p_occurred_end,p_date_precision,p_occurred_label,p_occurred_timezone,p_make,p_model,p_model_year,p_color,p_collection_names,p_tag_names,p_entry_id,p_expected_revision);
end;
$function$;
-- Unanchored chapters remain visible, after dated chapters in the same current/past group.
do $ordering$
declare target record; definition text; old_order text;
begin
  for target in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('homes_workspace','vehicles_workspace')
  loop
    definition := pg_get_functiondef(target.oid);
    old_order := case target.proname when 'homes_workspace' then 'counted_homes.occurred_start desc,' else 'counted_vehicles.occurred_start desc,' end;
    if position(old_order in definition)=0 then raise exception 'Unexpected chapter workspace ordering'; end if;
    execute replace(definition,old_order,replace(old_order,' desc,',' desc nulls last,'));
  end loop;
end;
$ordering$;
