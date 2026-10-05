-- Native iOS no longer needs a compatibility window, so the database drops what it kept only for deployed clients:
-- the retired Inbox status, the Inbox count, the organize flag, the Capture source, the constant record source,
-- the empty storage path helper, the review functions only native called, and their plain-text bypass.

-- Without Inbox there is no Entry state to keep: every Entry already lives in Library.
drop trigger keep_entries_in_library on public.entries;
drop function public.keep_entries_in_library();
drop index public.entries_owner_inbox_idx;
drop index public.entries_owner_resurfacing_entry_idx;
alter table public.entries drop column inbox_status;
create index entries_owner_resurfacing_entry_idx
  on public.entries (owner_id, occurred_start desc, id)
  where deleted_at is null
    and occurred_start is not null
    and not (item_kind = 'entry' and item_subtype = 'period');

-- History snapshots stop carrying the retired status, so versions compare and restore without it.
update public.entry_versions
set snapshot = snapshot - 'inbox_status'
where snapshot ? 'inbox_status';

CREATE OR REPLACE FUNCTION public.save_timeline_entry_with_occurrence(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  timeline_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  expected_item_subtype text;
begin
  if timeline_owner_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.timeline_tracks as tracks
    where tracks.id = p_track_id
      and tracks.owner_id = timeline_owner_id
  ) then
    return;
  end if;

  if p_timeline_kind is null or p_timeline_kind not in ('stage', 'event') then
    raise exception using errcode = '22023', message = 'invalid_timeline_kind';
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_timeline_content';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_timeline_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_timeline_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_timeline_timezone';
    end;
  end if;

  if p_timeline_kind = 'event' and p_occurred_end is not null then
    raise exception using errcode = '22023', message = 'event_cannot_have_end';
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_timeline_range';
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
    raise exception using errcode = '22023', message = 'timeline_label_too_long';
  end if;

  expected_item_subtype := case
    when p_timeline_kind = 'stage' then 'period'
    else 'moment'
  end;

  if p_entry_id is null then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_revision';
    end if;

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
      timeline_owner_id,
      normalized_title,
      normalized_body,
      'entry',
      expected_item_subtype,
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning id, entries.revision into saved_entry_id, saved_revision;

    insert into public.timeline_items (
      entry_id,
      track_id,
      owner_id,
      timeline_kind
    )
    values (
      saved_entry_id,
      p_track_id,
      timeline_owner_id,
      p_timeline_kind
    );

    return query select saved_entry_id, saved_revision, true;
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  update public.entries as entries
  set
    title = normalized_title,
    body = normalized_body,
    item_kind = 'entry',
    item_subtype = expected_item_subtype,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    date_precision = p_date_precision,
    occurred_label = normalized_label,
    occurred_timezone = normalized_timezone
  where entries.id = p_entry_id
    and entries.owner_id = timeline_owner_id
    and entries.revision = p_expected_revision
    and entries.deleted_at is null
    and entries.item_kind = 'entry' and entries.item_subtype in ('period', 'moment')
    and exists (
      select 1
      from public.timeline_items as items
      where items.entry_id = entries.id
        and items.owner_id = timeline_owner_id
    )
  returning entries.id, entries.revision into saved_entry_id, saved_revision;

  if saved_entry_id is null then
    return;
  end if;

  delete from public.timeline_items as items
  where items.entry_id = saved_entry_id
    and items.owner_id = timeline_owner_id
    and items.track_id is distinct from p_track_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    p_track_id,
    timeline_owner_id,
    p_timeline_kind
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  return query select saved_entry_id, saved_revision, false;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_first_time_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer, p_occurred_end timestamp with time zone)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  first_time_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  created_entry boolean := p_entry_id is null;
begin
  if first_time_owner_id is null then
    return;
  end if;

  if normalized_title is null
    or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_first_time_content';
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
    raise exception using errcode = '22023', message = 'first_time_label_too_long';
  end if;

  if p_date_precision is null
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then raise exception using errcode='22023',message='invalid_first_time_occurrence';end if;

  if p_occurred_start is null then
    if p_date_precision not in ('approximate', 'age', 'unknown')
      or normalized_timezone is not null
    then
      raise exception using errcode = '22023', message = 'invalid_first_time_occurrence';
    end if;
  else
    if normalized_timezone is null or length(normalized_timezone) > 100 then
      raise exception using errcode = '22023', message = 'invalid_first_time_occurrence';
    end if;

    begin
      perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
    exception
      when invalid_parameter_value then
        raise exception using errcode = '22023', message = 'invalid_first_time_timezone';
    end;
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if created_entry then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_revision';
    end if;

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
      first_time_owner_id,
      normalized_title,
      normalized_body,
      'entry',
      'first_time',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning id, entries.revision into saved_entry_id, saved_revision;
  else
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_revision';
    end if;

    update public.entries as entries
    set
      title = normalized_title,
      body = normalized_body,
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = first_time_owner_id
      and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
      and entries.revision = p_expected_revision
      and entries.deleted_at is null
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query select saved_entry_id, saved_revision, created_entry;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
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

  if length(coalesce(normalized_place_name, '')) > 200
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

  if not public.valid_tag_names(p_tag_names) then
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
    from public.locations
    where locations.id = p_place_id
      and locations.owner_id = home_owner_id
  ) then
    return;
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
      item_kind = 'entity',
      item_subtype = 'home',
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

  if p_place_id is not null
    or normalized_address is not null
    or normalized_city is not null
    or normalized_region is not null
    or normalized_country is not null
    or p_latitude is not null
  then
    select public.resolve_home_location_copy_on_write(
      p_place_id,
      normalized_place_name,
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_place_notes
    ) into saved_place_id;
  else
    saved_place_id := null;
  end if;

  if saved_place_id is null and (
    p_place_id is not null or normalized_address is not null
    or normalized_city is not null or normalized_region is not null
    or normalized_country is not null or p_latitude is not null
  ) then
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
    move_out_reason = excluded.move_out_reason
  where (homes.place_id, homes.move_in_reason, homes.move_out_reason)
    is distinct from (excluded.place_id, excluded.move_in_reason, excluded.move_out_reason);

  delete from public.entry_places
  where entry_places.entry_id = saved_entry_id
    and entry_places.owner_id = home_owner_id
    and entry_places.relationship = 'home'
    and entry_places.place_id is distinct from saved_place_id;

  if saved_place_id is not null then
    insert into public.entry_places (
      entry_id,
      place_id,
      owner_id,
      relationship
    ) values (
      saved_entry_id,
      saved_place_id,
      home_owner_id,
      'home'
    ) on conflict on constraint entry_places_pkey do nothing;
  end if;

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
    and timeline_items.owner_id = home_owner_id
    and timeline_items.track_id is distinct from home_track_id;

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
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, saved_place_id, p_entry_id is null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
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
    and timeline_items.owner_id = vehicle_owner_id
    and timeline_items.track_id is distinct from vehicle_track_id;

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
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_goal_entry(p_title text, p_body text, p_status text, p_target_date date, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
begin
  if goal_owner_id is null then
    return;
  end if;
  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_goal_content';
  end if;
  if p_status is null or p_status not in ('active', 'achieved', 'let_go') then
    raise exception using errcode = '22023', message = 'invalid_goal_status';
  end if;
  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;
  if p_target_date is not null and (
    not isfinite(p_target_date)
    or p_target_date < date '0001-01-01'
    or p_target_date > date '9999-12-31'
  ) then
    raise exception using errcode = '22023', message = 'invalid_goal_target_date';
  end if;
  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;
  if p_entry_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      date_precision
    )
    values (
      goal_owner_id,
      normalized_title,
      normalized_body,
      'goal',
      'goal',
      'unknown'
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'goal',
      item_subtype = 'goal'
    where entries.id = p_entry_id
      and entries.owner_id = goal_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'goal'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.goals
        where goals.entry_id = entries.id
          and goals.owner_id = goal_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  insert into public.goals (entry_id, owner_id, status, target_date)
  values (saved_entry_id, goal_owner_id, p_status, p_target_date)
  on conflict on constraint goals_pkey do update
  set
    status = excluded.status,
    target_date = excluded.target_date
  where (goals.status, goals.target_date)
    is distinct from (excluded.status, excluded.target_date);

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query select saved_entry_id, saved_revision, p_entry_id is null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.extract_goal_from_item(p_source_entry_id uuid, p_source_revision integer, p_goal_id uuid, p_title text, p_status text, p_target_date date)
 RETURNS TABLE(source_entry_id uuid, source_revision integer, goal_entry_id uuid, goal_revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  created_goal public.entries;
  existing_goal public.entries;
begin
  if extraction_owner_id is null then
    return;
  end if;

  p_title := nullif(btrim(p_title), '');
  if p_source_entry_id is null
    or p_source_revision is null
    or p_source_revision < 1
    or p_goal_id is null
    or p_source_entry_id = p_goal_id
    or p_title is null
    or length(p_title) > 200
    or p_status is null
    or p_status not in ('active', 'achieved', 'let_go')
    or (p_target_date is not null and (
      not isfinite(p_target_date)
      or p_target_date < date '0001-01-01'
      or p_target_date > date '9999-12-31'
    ))
  then
    raise exception using errcode = '22023', message = 'invalid_goal_extraction';
  end if;

  -- The caller chooses the target id so a lost successful response can be
  -- retried without creating a second Goal.
  select goal_entry.*
  into existing_goal
  from public.entries as goal_entry
  join public.goals as goal
    on goal.entry_id = goal_entry.id
    and goal.owner_id = goal_entry.owner_id
  where goal_entry.id = p_goal_id
    and goal_entry.owner_id = extraction_owner_id
    and goal_entry.deleted_at is null
    and goal_entry.item_kind = 'goal'
    and goal_entry.item_subtype = 'goal'
    and goal_entry.title = p_title
    and goal.status = p_status
    and goal.target_date is not distinct from p_target_date
    and exists (
      select 1
      from public.entry_links as link
      where link.owner_id = extraction_owner_id
        and link.source_entry_id = p_source_entry_id
        and link.target_entry_id = goal_entry.id
        and link.relationship = 'derived'
    );

  if found then
    return query
    select source_entry.id, source_entry.revision, existing_goal.id, existing_goal.revision
    from public.entries as source_entry
    where source_entry.id = p_source_entry_id
      and source_entry.owner_id = extraction_owner_id;
    return;
  end if;

  if exists (select 1 from public.entries where id = p_goal_id) then
    return;
  end if;

  select *
  into source
  from public.entries
  where id = p_source_entry_id
    and owner_id = extraction_owner_id
    and revision = p_source_revision
    and item_kind <> 'goal'
    and deleted_at is null
  for update;

  if not found then
    return;
  end if;

  insert into public.entries (
    id,
    owner_id,
    title,
    body,
    metadata,
    source_language,
    item_kind,
    item_subtype,
    date_precision,
    occurred_timezone
  )
  values (
    p_goal_id,
    extraction_owner_id,
    p_title,
    source.body,
    case
      when source.metadata ? 'body_rich'
        then jsonb_build_object('body_rich', source.metadata->'body_rich')
      else '{}'::jsonb
    end,
    source.source_language,
    'goal',
    'goal',
    'unknown',
    'UTC'
  )
  returning * into created_goal;

  insert into public.goals (
    entry_id,
    owner_id,
    status,
    target_date
  )
  values (
    created_goal.id,
    extraction_owner_id,
    p_status,
    p_target_date
  );

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, created_goal.id, extraction_owner_id, 'derived'),
    (created_goal.id, source.id, extraction_owner_id, 'derived_from');

  return query
  select source.id, source.revision, created_goal.id, created_goal.revision;
end;
$function$;

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
  reconciled_revision integer;
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;

  perform 1 from public.entries
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_goal_entry_id, p_expected_revision);

  -- Touching the Goal archives its previous version and advances its revision.
  update public.entries
  set updated_at = now()
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = reconciled_revision
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

  select entry_id into new_first_time_id from public.save_first_time_with_occurrence(
    achieved_goal_title, '', p_occurred_start, p_date_precision, normalized_label,
    case when p_occurred_start is null then null else normalized_timezone end,
    '{}', null, null, p_occurred_end
  );

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_entry_version(p_entry_id uuid, p_version integer, p_expected_revision integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  item_record public.entries;
  snapshot jsonb;
  restored_revision integer;
  relation jsonb;
  timeline_items jsonb;
  home_record public.homes;
  vehicle_record public.vehicles;
  goal_record public.goals;
begin
  select *
  into item_record
  from public.entries
  where id = p_entry_id and owner_id = auth.uid()
  for update;
  if not found
    or item_record.revision is distinct from p_expected_revision
    or item_record.deleted_at is not null
  then
    return null;
  end if;

  select version.snapshot
  into snapshot
  from public.entry_versions as version
  where version.entry_id = item_record.id
    and version.owner_id = item_record.owner_id
    and version.version = p_version;
  if snapshot is null then
    return null;
  end if;
  if coalesce((snapshot->>'history_schema')::integer, 0) <> 3
    or snapshot->>'item_kind' not in ('capture', 'writing', 'event', 'story', 'entry', 'entity', 'goal')
    or coalesce(snapshot->>'item_subtype', '') !~ '^[a-z][a-z0-9_]{0,63}$'
  then
    raise exception using errcode = 'P0001', message = 'history_schema_unsupported';
  end if;

  for relation in select value from jsonb_array_elements(coalesce(snapshot->'tags', '[]')) loop
    perform 1
    from public.tags
    where id = (relation->>'id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'places', '[]')) loop
    perform 1
    from public.locations
    where id = (relation->>'place_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;

  timeline_items := snapshot->'timeline_items';
  if timeline_items is null and snapshot ? 'timeline' then
    timeline_items := case
      when snapshot->'timeline' = 'null'::jsonb then '[]'::jsonb
      else jsonb_build_array(snapshot->'timeline')
    end;
  end if;
  for relation in select value from jsonb_array_elements(coalesce(timeline_items, '[]')) loop
    perform 1
    from public.timeline_tracks
    where id = (relation->>'track_id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'links', '[]')) loop
    perform 1
    from public.entries
    where id = (relation->>'target_entry_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in
    select value
    from jsonb_array_elements(coalesce(snapshot->'attachments', '[]'))
    where coalesce(value->>'variant', 'original') = 'original'
  loop
    perform 1
    from public.attachments as attachment
    join storage.objects as object
      on object.bucket_id = attachment.bucket_id and object.name = attachment.object_path
    where attachment.id = (relation->>'id')::uuid
      and attachment.entry_id = item_record.id
      and attachment.owner_id = item_record.owner_id
    for share of attachment;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_attachment_unavailable';
    end if;
  end loop;

  if snapshot->>'item_kind' = 'entity' and snapshot->>'item_subtype' = 'home' then
    if snapshot->'home' is null or snapshot->'home' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    home_record := jsonb_populate_record(null::public.homes, snapshot->'home');
    if home_record.place_id is not null then
      perform 1
      from public.locations
      where id = home_record.place_id
        and owner_id = item_record.owner_id
        and deleted_at is null
      for share;
      if not found then
        raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
      end if;
    end if;
  elsif snapshot->>'item_kind' = 'entity' and snapshot->>'item_subtype' = 'vehicle' then
    if snapshot->'vehicle' is null or snapshot->'vehicle' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    vehicle_record := jsonb_populate_record(null::public.vehicles, snapshot->'vehicle');
  elsif snapshot->>'item_kind' = 'goal' then
    if snapshot->'goal' is null or snapshot->'goal' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    goal_record := jsonb_populate_record(null::public.goals, snapshot->'goal');
  end if;

  update public.entries
  set
    title = snapshot->>'title',
    body = coalesce(snapshot->>'body', ''),
    item_kind = case when snapshot->>'item_kind' in ('capture', 'writing', 'event', 'story') then 'entry' else snapshot->>'item_kind' end,
    item_subtype = case when snapshot->>'item_kind' in ('capture', 'writing', 'event', 'story') then case snapshot->>'item_subtype' when 'first_time' then 'first_time' when 'life_stage' then 'period' when 'source_capture' then 'source_capture' when 'other' then case when exists (select 1 from jsonb_array_elements(coalesce(timeline_items, '[]'::jsonb)) as placement where placement->>'timeline_kind' = 'event') then 'moment' else 'entry' end else 'entry' end else snapshot->>'item_subtype' end,
    occurred_start = (snapshot->>'occurred_start')::timestamptz,
    occurred_end = (snapshot->>'occurred_end')::timestamptz,
    date_precision = snapshot->>'date_precision',
    occurred_label = snapshot->>'occurred_label',
    occurred_timezone = snapshot->>'occurred_timezone',
    source_language = snapshot->>'source_language',
    metadata = coalesce(snapshot->'metadata', '{}'),
    embedding = null,
    embedding_model = null,
    embedding_updated_at = null
  where id = item_record.id
  returning revision into restored_revision;

  delete from public.homes where entry_id = item_record.id;
  delete from public.vehicles where entry_id = item_record.id;
  delete from public.goals where entry_id = item_record.id;
  if home_record.entry_id is not null then
    insert into public.homes (entry_id, owner_id, place_id, move_in_reason, move_out_reason)
    values (item_record.id, item_record.owner_id, home_record.place_id, home_record.move_in_reason, home_record.move_out_reason);
  elsif vehicle_record.entry_id is not null then
    insert into public.vehicles (entry_id, owner_id, make, model, model_year, color)
    values (item_record.id, item_record.owner_id, vehicle_record.make, vehicle_record.model, vehicle_record.model_year, vehicle_record.color);
  elsif goal_record.entry_id is not null then
    insert into public.goals (entry_id, owner_id, status, target_date)
    values (item_record.id, item_record.owner_id, goal_record.status, goal_record.target_date);
  end if;

  delete from public.entry_tags where entry_id = item_record.id;
  insert into public.entry_tags (entry_id, owner_id, tag_id)
  select item_record.id, item_record.owner_id, (value->>'id')::uuid
  from jsonb_array_elements(coalesce(snapshot->'tags', '[]'));
  delete from public.entry_places where entry_id = item_record.id;
  insert into public.entry_places (entry_id, owner_id, place_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'place_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'places', '[]'));
  delete from public.timeline_items where entry_id = item_record.id;
  insert into public.timeline_items (entry_id, owner_id, track_id, timeline_kind, sort_order)
  select
    item_record.id,
    item_record.owner_id,
    (value->>'track_id')::uuid,
    value->>'timeline_kind',
    coalesce((value->>'sort_order')::integer, 0)
  from jsonb_array_elements(coalesce(timeline_items, '[]'));
  delete from public.entry_links where source_entry_id = item_record.id;
  insert into public.entry_links (source_entry_id, owner_id, target_entry_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'target_entry_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'links', '[]'));
  update public.attachments
  set deleted_at = case
    when id in (
      select (value->>'id')::uuid
      from jsonb_array_elements(coalesce(snapshot->'attachments', '[]'))
    ) then null
    else coalesce(deleted_at, now())
  end
  where entry_id = item_record.id and variant = 'original';

  return restored_revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_wiki_search_evidence(p_queries text[] DEFAULT '{}'::text[], p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_before_latest_home boolean DEFAULT false, p_order text DEFAULT 'relevance'::text, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
        'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = item.id)
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
$function$;

drop function public.first_times_workspace_with_occurrence();

create function public.first_times_workspace_with_occurrence()
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
  where entries.owner_id = auth.uid()
    and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
    and entries.deleted_at is null
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$function$;

revoke all on function public.first_times_workspace_with_occurrence() from public, anon;
grant execute on function public.first_times_workspace_with_occurrence() to authenticated, service_role;

drop function public.home_resurfaced_memory(date, text);

create function public.home_resurfaced_memory(p_local_date date, p_timezone text)
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
      and not (item.item_kind = 'entry' and item.item_subtype = 'period')
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

revoke all on function public.home_resurfaced_memory(date, text) from public, anon;
grant execute on function public.home_resurfaced_memory(date, text) to authenticated, service_role;

drop function public.home_workspace(date, text, integer);

create function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer DEFAULT 5)
 RETURNS TABLE(snapshot_date date, profile_display_name text, entry_count bigint, first_time_count bigint, tag_count bigint, current_stage_count bigint, recent_entries jsonb, current_stages jsonb)
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
      count(*) filter (where item_kind = 'entry' and item_subtype = 'first_time') as first_time_count
    from active_entries
  ),
  tag_stats as (
    select count(*) as tag_count
    from public.tags
    where tags.owner_id = home_owner_id
  ),

  visible_stages as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      tracks.id as track_id,
      tracks.name as track_name,
      tracks.sort_order as track_sort_order,
      items.sort_order as item_sort_order
    from public.timeline_items as items
    join active_entries as entries on entries.id = items.entry_id
    join public.timeline_tracks as tracks
      on tracks.id = items.track_id
      and tracks.owner_id = items.owner_id
    where items.owner_id = home_owner_id
      and items.timeline_kind = 'stage'
      and not tracks.is_hidden
      and entries.occurred_start < local_day_end
      and (entries.occurred_end is null or entries.occurred_end >= local_day_start)
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
    (select count(*) from visible_stages),
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
            'entry_id', stages.entry_id,
            'title', stages.title,
            'body', stages.body,
            'track_id', stages.track_id,
            'track_name', stages.track_name,
            'occurred_start', stages.occurred_start,
            'occurred_end', stages.occurred_end,
            'date_precision', stages.date_precision,
            'occurred_label', stages.occurred_label,
            'occurred_timezone', stages.occurred_timezone
          )
          order by
            stages.track_sort_order,
            lower(stages.track_name),
            stages.occurred_start,
            stages.item_sort_order,
            stages.entry_id
        )
        from visible_stages as stages
      ),
      '[]'::jsonb
    )
  from entry_stats
  cross join tag_stats;
end;
$function$;

revoke all on function public.home_workspace(date, text, integer) from public, anon;
grant execute on function public.home_workspace(date, text, integer) to authenticated, service_role;

drop function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text);

create function public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
    select item.*
    from public.entries as item
    where item.owner_id = search_owner_id
      and item.deleted_at is null
      and (
        cardinality(normalized_classifications) = 0
        or item.item_kind = any(normalized_classifications)
        or item.item_subtype = any(normalized_classifications)
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
          item.item_kind,
          item.item_subtype
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
        item.metadata::text,
        home.move_in_reason,
        home.move_out_reason,
        vehicle.make,
        vehicle.model,
        vehicle.model_year::text,
        vehicle.color,
        goal.status,
        goal.target_date::text,
        timeline_context.timeline_text,
        related_place_context.place_text,
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
      select string_agg(concat_ws(' ', track.name, timeline_item.timeline_kind), ' ') as timeline_text
      from public.timeline_items as timeline_item
      join public.timeline_tracks as track
        on track.id = timeline_item.track_id
        and track.owner_id = timeline_item.owner_id
      where timeline_item.entry_id = item.id
        and timeline_item.owner_id = search_owner_id
    ) as timeline_context on true
    left join lateral (
      select string_agg(concat_ws(' ', related.name, related.address, related.city, related.region, related.country, related.notes, link.relationship), ' ') as place_text
      from public.entry_places as link
      join public.locations as related
        on related.id = link.place_id and related.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as related_place_context on true
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
    matched.item_subtype
  from matched
  order by
    case when p_order = 'relevance' then matched.computed_match_rank end desc nulls last,
    case when p_order = 'oldest' then matched.occurred_start end asc nulls last,
    case when p_order <> 'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text) from public, anon;
grant execute on function public.search_wiki_items(text, text[], text[], date, date, integer, integer, text) to authenticated, service_role;

drop function public.wiki_items_workspace(text, text[], text[], integer, integer, boolean);

create function public.wiki_items_workspace(p_query text DEFAULT ''::text, p_item_kinds text[] DEFAULT ARRAY[]::text[], p_item_subtypes text[] DEFAULT ARRAY[]::text[], p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_needs_organizing boolean DEFAULT false)
 RETURNS TABLE(item_id uuid, canonical_item_id uuid, item_kind text, item_subtype text, title text, excerpt text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  workspace_owner_id uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(p_query, '')));
begin
  if workspace_owner_id is null then return; end if;

  if p_query is null
    or length(p_query) > 200
    or p_item_kinds is null
    or cardinality(p_item_kinds) > 6
    or exists (
      select 1 from unnest(p_item_kinds) as kind
      where kind not in ('entry', 'entity', 'goal')
    )
    or p_item_subtypes is null
    or cardinality(p_item_subtypes) > 50
    or exists (
      select 1 from unnest(p_item_subtypes) as subtype
      where subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    )
    or p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 100000
    or p_needs_organizing is null
  then
    raise exception using errcode = '22023', message = 'invalid_wiki_items_page';
  end if;

  return query
  with wiki_items as (
    select
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      coalesce(
        nullif(btrim(entry.title), ''),
        nullif(left(btrim(entry.body), 120), ''),
        'Untitled item'
      ) as title,
      left(btrim(entry.body), 240) as excerpt,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype
      ) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
      -- An Entry needs organizing while it has neither a title nor a tag, like a fresh Capture.
      and (
        not p_needs_organizing
        or (
          entry.item_kind = 'entry'
          and nullif(btrim(entry.title), '') is null
          and not exists (
            select 1 from public.entry_tags as tagged
            where tagged.entry_id = entry.id and tagged.owner_id = workspace_owner_id
          )
        )
      )
  ),
  matches as (
    select *
    from wiki_items
    where (cardinality(p_item_kinds) = 0 or wiki_items.item_kind = any(p_item_kinds))
      and (cardinality(p_item_subtypes) = 0 or wiki_items.item_subtype = any(p_item_subtypes))
      and (normalized_query = '' or strpos(lower(wiki_items.searchable), normalized_query) > 0)
  ),
  counted as (
    select matches.*, count(*) over () as total_count
    from matches
  )
  select
    counted.item_id, counted.canonical_item_id,
    counted.item_kind, counted.item_subtype, counted.title, counted.excerpt,
    counted.occurred_start, counted.occurred_end,
    counted.updated_at, counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.item_id
  limit p_limit offset p_offset;
end;
$function$;

revoke all on function public.wiki_items_workspace(text, text[], text[], integer, integer, boolean) from public, anon;
grant execute on function public.wiki_items_workspace(text, text[], text[], integer, integer, boolean) to authenticated, service_role;

-- Entry edits no longer choose whether to organize, and only the Web Location editor path remains.
-- Only Web edits remain, and each one states its rich text, so nothing keeps rich text it did not see.
drop function public.review_wiki_item_with_photo_place(uuid, integer, text, text, text, text, timestamptz, text, text[], boolean, timestamptz, text, text, jsonb);
drop function public.review_wiki_item_with_photo_place_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], boolean, timestamptz, text, text, jsonb, jsonb);
drop function public.review_wiki_item_with_location_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], boolean, timestamptz, text, text, jsonb, jsonb, jsonb);
drop function public.review_wiki_item_with_photo_place_core(uuid, integer, text, text, text, text, timestamptz, text, text[], boolean, timestamptz, text, text, jsonb, jsonb, boolean);
drop function public.review_wiki_item_with_occurrence_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], boolean, timestamptz, text, text, jsonb, boolean);

create function public.review_wiki_item_with_occurrence_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_body_rich jsonb)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed_entry_id uuid;
  reviewed_revision integer;
begin
  if review_owner_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  if p_item_kind <> 'entry'
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    or p_item_subtype <> 'entry'
  then
    raise exception using errcode = '22023', message = 'invalid_item_classification';
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
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_occurrence';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if exists (
    select 1
    from public.entries as item
    where item.id = p_entry_id
      and item.owner_id = review_owner_id
      and item.revision = p_expected_revision
      and item.deleted_at is null
      and item.item_kind = 'entry' and item.item_subtype = 'entry'
      
      and item.item_kind <> p_item_kind
  ) then
    raise exception using errcode = '22023', message = 'invalid_item_kind_transition';
  end if;

  update public.entries as item
  set
    title = p_title,
    body = p_body,
    metadata = case
      when p_body_rich is null then item.metadata - 'body_rich'
      else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
    end,
    item_kind = p_item_kind,
    item_subtype = p_item_subtype,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    occurred_label = p_occurred_label,
    date_precision = p_date_precision,
    occurred_timezone = btrim(p_occurred_timezone)
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind = 'entry' and item.item_subtype = 'entry'
    and item.deleted_at is null
  returning item.id, item.revision
  into reviewed_entry_id, reviewed_revision;

  if reviewed_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(reviewed_entry_id, p_tag_names);

  return query
  select reviewed_entry_id, reviewed_revision;
end;
$function$;

revoke all on function public.review_wiki_item_with_occurrence_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.review_wiki_item_with_occurrence_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb) to service_role;

create function public.review_wiki_item_with_photo_place_core(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed record;
  target_place_id uuid;
  source_attachment_id uuid;
  target_revision integer;
  place_name text;
  latitude numeric;
  longitude numeric;
begin
  if review_owner_id is null then
    return;
  end if;
  if p_photo_place is not null and p_photo_place <> 'null'::jsonb then
    if jsonb_typeof(p_photo_place) <> 'object'
      or coalesce(p_photo_place->>'kind', '') not in ('new', 'existing')
      or coalesce(p_photo_place->>'attachmentId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    then
      raise exception using errcode = '22023', message = 'invalid_photo_place';
    end if;
    source_attachment_id := (p_photo_place->>'attachmentId')::uuid;
    if p_photo_place->>'kind' = 'existing' then
      if coalesce(p_photo_place->>'placeId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_photo_place->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
      then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
      target_revision := (p_photo_place->>'revision')::integer;
      select place.id
      into target_place_id
      from public.locations as place
      where place.id = (p_photo_place->>'placeId')::uuid
        and place.owner_id = review_owner_id
        and place.deleted_at is null
        and place.revision = target_revision
      for update;
      if target_place_id is null then
        raise exception using errcode = '40001', message = 'photo_place_changed';
      end if;
    else
      place_name := nullif(btrim(p_photo_place->>'name'), '');
      if place_name is null or length(place_name) > 200
        or jsonb_typeof(p_photo_place->'name') is distinct from 'string'
        or jsonb_typeof(p_photo_place->'latitude') is distinct from 'number'
        or jsonb_typeof(p_photo_place->'longitude') is distinct from 'number'
      then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
      latitude := (p_photo_place->>'latitude')::numeric;
      longitude := (p_photo_place->>'longitude')::numeric;
      if latitude not between -90 and 90 or longitude not between -180 and 180 then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
    end if;
  end if;

  select *
  into reviewed
  from public.review_wiki_item_with_occurrence_rich(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_body_rich
  );
  if reviewed.entry_id is null then
    return;
  end if;

  if source_attachment_id is not null then
    if not public.lock_photo_place_source(reviewed.entry_id, source_attachment_id) then
      raise exception using errcode = '40001', message = 'photo_source_changed';
    end if;
    if target_place_id is null then
      select saved.place_id
      into target_place_id
      from public.save_location(
        place_name,
        null,
        null,
        null,
        null,
        latitude,
        longitude,
        null,
        array[reviewed.entry_id],
        null,
        null
      ) as saved;
      perform public.record_photo_location_source(
        target_place_id, reviewed.entry_id, source_attachment_id
      );
    elsif not exists (
      select 1
      from public.entry_places as link
      where link.entry_id = reviewed.entry_id
        and link.place_id = target_place_id
        and link.owner_id = review_owner_id
    ) then
      update public.locations as place
      set notes = place.notes
      where place.id = target_place_id and place.owner_id = review_owner_id;
      insert into public.entry_places (entry_id, place_id, owner_id, relationship)
      values (reviewed.entry_id, target_place_id, review_owner_id, 'related');
    end if;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision;
end;
$function$;

revoke all on function public.review_wiki_item_with_photo_place_core(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.review_wiki_item_with_photo_place_core(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb, jsonb) to service_role;

create function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed record;
  target_location_id uuid;
  selected_kind text;
  selected_revision integer;
  normalized_name text;
  normalized_formatted_address text;
  normalized_address text;
  normalized_city text;
  normalized_region text;
  normalized_postal_code text;
  normalized_country text;
  normalized_country_code text;
  normalized_timezone text;
  normalized_result_type text;
  provider_identity text;
  provider_confidence numeric;
  latitude numeric;
  longitude numeric;
begin
  if review_owner_id is null then return; end if;

  -- Reject a stale or inaccessible editor before a provider result can create
  -- an unattached Location. The row lock also protects the later review write.
  perform 1
  from public.entries as item
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind = 'entry' and item.item_subtype = 'entry'
    and item.deleted_at is null
  for update;
  if not found then return; end if;

  if p_primary_location is not null and p_primary_location <> 'null'::jsonb then
    if jsonb_typeof(p_primary_location) <> 'object' then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    selected_kind := p_primary_location->>'kind';
    if selected_kind = 'existing' then
      if coalesce(p_primary_location->>'id', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_primary_location->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      selected_revision := (p_primary_location->>'revision')::integer;
      select location.id into target_location_id
      from public.locations as location
      where location.id = (p_primary_location->>'id')::uuid
        and location.owner_id = review_owner_id
        and location.revision = selected_revision
        and location.deleted_at is null;
      if target_location_id is null then
        raise exception using errcode = '40001', message = 'primary_location_changed';
      end if;
    elsif selected_kind = 'provider' then
      if p_primary_location->>'provider' <> 'geoapify'
        or jsonb_typeof(p_primary_location->'providerLocationId') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'name') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'formattedAddress') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'latitude') is distinct from 'number'
        or jsonb_typeof(p_primary_location->'longitude') is distinct from 'number'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      if exists (
        select 1
        from unnest(array[
          'address','city','region','postalCode','country','countryCode',
          'timezone','resultType','matchType','dataSource'
        ]) as optional_key
        where p_primary_location ? optional_key
          and p_primary_location->optional_key is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->optional_key) <> 'string'
      )
        or (
          p_primary_location ? 'confidence'
          and p_primary_location->'confidence' is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->'confidence') <> 'number'
        )
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      provider_identity := nullif(btrim(p_primary_location->>'providerLocationId'), '');
      normalized_name := nullif(btrim(p_primary_location->>'name'), '');
      normalized_formatted_address := nullif(btrim(p_primary_location->>'formattedAddress'), '');
      normalized_address := nullif(btrim(p_primary_location->>'address'), '');
      normalized_city := nullif(btrim(p_primary_location->>'city'), '');
      normalized_region := nullif(btrim(p_primary_location->>'region'), '');
      normalized_postal_code := nullif(btrim(p_primary_location->>'postalCode'), '');
      normalized_country := nullif(btrim(p_primary_location->>'country'), '');
      normalized_country_code := lower(nullif(btrim(p_primary_location->>'countryCode'), ''));
      normalized_timezone := nullif(btrim(p_primary_location->>'timezone'), '');
      normalized_result_type := nullif(btrim(p_primary_location->>'resultType'), '');
      latitude := (p_primary_location->>'latitude')::numeric;
      longitude := (p_primary_location->>'longitude')::numeric;
      provider_confidence := (p_primary_location->>'confidence')::numeric;

      if provider_identity is null or length(provider_identity) > 500
        or normalized_name is null or length(normalized_name) > 200
        or normalized_formatted_address is null or length(normalized_formatted_address) > 1000
        or length(coalesce(normalized_address, '')) > 500
        or length(coalesce(normalized_city, '')) > 200
        or length(coalesce(normalized_region, '')) > 200
        or length(coalesce(normalized_postal_code, '')) > 40
        or length(coalesce(normalized_country, '')) > 200
        or (normalized_country_code is not null and normalized_country_code !~ '^[a-z]{2}$')
        or length(coalesce(normalized_timezone, '')) > 100
        or length(coalesce(normalized_result_type, '')) > 100
        or latitude not between -90 and 90
        or longitude not between -180 and 180
        or provider_confidence not between 0 and 1
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      target_location_id := public.resolve_geoapify_location(p_primary_location);
    else
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
  end if;

  select * into reviewed
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich
  );
  if reviewed.entry_id is null then return; end if;

  delete from public.entry_places as link
  where link.entry_id = reviewed.entry_id
    and link.owner_id = review_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from target_location_id;

  if target_location_id is not null then
    insert into public.entry_places (entry_id, place_id, owner_id, relationship)
    values (reviewed.entry_id, target_location_id, review_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision;
end;
$function$;

revoke all on function public.review_wiki_item_with_location_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_location_rich(uuid, integer, text, text, text, text, timestamptz, text, text[], timestamptz, text, text, jsonb, jsonb, jsonb) to authenticated, service_role;

-- Home and Vehicle saves no longer take a Capture source.
drop function public.save_home_entry_with_geoapify(jsonb, jsonb, jsonb);

create function public.save_home_entry_with_geoapify(p_input jsonb, p_provider_location jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  location_id uuid;
  saved jsonb;
  tag_names text[];
begin
  if auth.uid() is null then return null; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_home_input';
  end if;

  select coalesce(array_agg(value), '{}'::text[]) into tag_names
  from jsonb_array_elements_text(p_input->'tagNames') as value;
  location_id := public.resolve_geoapify_location(p_provider_location);
  if location_id is null then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  select to_jsonb(result) into saved
  from public.save_home_entry_with_occurrence(
    p_input->>'title', p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    (p_input->>'occurredEnd')::timestamptz,
    p_input->>'datePrecision', p_input->>'occurredLabel',
    p_input->>'occurredTimezone', location_id,
    p_input->>'placeName', p_input->>'address', p_input->>'city',
    p_input->>'region', p_input->>'country',
    (p_input->>'latitude')::numeric, (p_input->>'longitude')::numeric,
    p_input->>'placeNotes', p_input->>'moveInReason',
    p_input->>'moveOutReason', tag_names,
    (p_input->>'id')::uuid, (p_input->>'revision')::integer
  ) as result;

  if saved is null then
    raise exception using errcode = '40001', message = 'home_changed';
  end if;
  return saved;
end;
$function$;

revoke all on function public.save_home_entry_with_geoapify(jsonb, jsonb) from public, anon;
grant execute on function public.save_home_entry_with_geoapify(jsonb, jsonb) to authenticated, service_role;

drop function public.save_vehicle_with_location(jsonb, jsonb, jsonb);

create function public.save_vehicle_with_location(p_input jsonb, p_location jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  saved record;
  saved_entry_id uuid;
  saved_revision integer;
  created_vehicle boolean;
  selected_location_id uuid;
  vehicle_owner_id uuid := auth.uid();
  tag_names text[];
begin
  if vehicle_owner_id is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_vehicle_input';
  end if;

  tag_names := array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb)));

  select * into saved
  from public.save_vehicle_entry_with_occurrence(
    p_input->>'title',
    p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    (p_input->>'occurredEnd')::timestamptz,
    p_input->>'datePrecision',
    p_input->>'occurredLabel',
    p_input->>'occurredTimezone',
    p_input->>'make',
    p_input->>'model',
    (p_input->>'modelYear')::integer,
    p_input->>'color',
    tag_names,
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer
  );
  if saved.entry_id is null then return; end if;
  saved_entry_id := saved.entry_id;
  saved_revision := saved.revision;
  created_vehicle := saved.was_created;

  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_places as link
  where link.entry_id = saved_entry_id
    and link.owner_id = vehicle_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from selected_location_id;
  if selected_location_id is not null then
    insert into public.entry_places(entry_id, place_id, owner_id, relationship)
    values (saved_entry_id, selected_location_id, vehicle_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;
  end if;

  return query select saved_entry_id, saved_revision, created_vehicle;
end;
$function$;

revoke all on function public.save_vehicle_with_location(jsonb, jsonb) from public, anon;
grant execute on function public.save_vehicle_with_location(jsonb, jsonb) to authenticated, service_role;

-- Trash computes storage paths on the server, so the empty helper deployed clients called is gone.
drop function public.trash_item_storage_paths(text, uuid, integer, timestamptz);
