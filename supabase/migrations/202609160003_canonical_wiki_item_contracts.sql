create or replace function public.wiki_item_occurrence_window(
  p_start timestamptz,
  p_end timestamptz,
  p_precision text,
  p_timezone text,
  p_item_kind text,
  p_item_subtype text
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

  if p_end is null and (
    p_precision = 'range'
    or (p_item_kind = 'event' and p_item_subtype = 'life_stage')
    or (p_item_kind = 'entity' and p_item_subtype in ('home', 'vehicle'))
  ) then
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

create or replace function public.restore_entry_version(
  p_entry_id uuid,
  p_version integer,
  p_expected_revision integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
    or snapshot->>'item_kind' not in ('capture', 'writing', 'entity', 'event', 'story', 'goal')
    or coalesce(snapshot->>'item_subtype', '') !~ '^[a-z][a-z0-9_]{0,63}$'
  then
    raise exception using errcode = 'P0001', message = 'history_schema_unsupported';
  end if;

  for relation in select value from jsonb_array_elements(coalesce(snapshot->'collections', '[]')) loop
    perform 1
    from public.collections
    where id = (relation->>'id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'tags', '[]')) loop
    perform 1
    from public.tags
    where id = (relation->>'id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'people', '[]')) loop
    perform 1
    from public.people
    where id = (relation->>'person_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'places', '[]')) loop
    perform 1
    from public.places
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
      from public.places
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
    item_kind = snapshot->>'item_kind',
    item_subtype = snapshot->>'item_subtype',
    inbox_status = snapshot->>'inbox_status',
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
    insert into public.goals (entry_id, owner_id, horizon, status, target_date)
    values (item_record.id, item_record.owner_id, goal_record.horizon, goal_record.status, goal_record.target_date);
  end if;

  delete from public.entry_collections where entry_id = item_record.id;
  insert into public.entry_collections (entry_id, owner_id, collection_id)
  select item_record.id, item_record.owner_id, (value->>'id')::uuid
  from jsonb_array_elements(coalesce(snapshot->'collections', '[]'));
  delete from public.entry_tags where entry_id = item_record.id;
  insert into public.entry_tags (entry_id, owner_id, tag_id)
  select item_record.id, item_record.owner_id, (value->>'id')::uuid
  from jsonb_array_elements(coalesce(snapshot->'tags', '[]'));
  delete from public.entry_people where entry_id = item_record.id;
  insert into public.entry_people (entry_id, owner_id, person_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'person_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'people', '[]'));
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
$$;

revoke all on function public.restore_entry_version(uuid, integer, integer) from public, anon;
grant execute on function public.restore_entry_version(uuid, integer, integer) to authenticated;

drop function public.home_resurfaced_memory(date, text);

create function public.home_resurfaced_memory(
  p_local_date date,
  p_timezone text
)
returns table(
  resurfacing_kind text,
  years_ago integer,
  entry_id uuid,
  title text,
  body text,
  item_kind text,
  item_subtype text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  created_at timestamptz,
  updated_at timestamptz,
  collection_names jsonb,
  tag_names jsonb,
  attachments jsonb
)
language plpgsql
stable
set search_path = ''
as $$
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
      and item.inbox_status = 'organized'
      and item.occurred_start is not null
      and not (item.item_kind = 'event' and item.item_subtype = 'life_stage')
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
      anniversary_memory.inbox_status,
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
      archive_memory.inbox_status,
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
    selected_memory.inbox_status,
    selected_memory.occurred_start,
    selected_memory.occurred_end,
    selected_memory.date_precision,
    selected_memory.occurred_label,
    selected_memory.occurred_timezone,
    selected_memory.revision,
    selected_memory.created_at,
    selected_memory.updated_at,
    coalesce((
      select jsonb_agg(collection.name order by lower(collection.name), collection.id)
      from public.entry_collections as membership
      join public.collections as collection
        on collection.id = membership.collection_id
        and collection.owner_id = membership.owner_id
      where membership.entry_id = selected_memory.id
        and membership.owner_id = home_owner_id
        and collection.archived_at is null
    ), '[]'::jsonb),
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
$$;

revoke all on function public.home_resurfaced_memory(date, text) from public, anon;
grant execute on function public.home_resurfaced_memory(date, text) to authenticated;

create or replace function public.search_wiki_items(
  p_query text default '',
  p_item_classifications text[] default '{}'::text[],
  p_collection_names text[] default '{}'::text[],
  p_tag_names text[] default '{}'::text[],
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_order text default 'relevance'
)
returns table(
  entry_id uuid,
  title text,
  body text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[],
  match_reasons text[],
  match_rank double precision,
  total_count bigint,
  date_precision text,
  item_kind text,
  item_subtype text,
  record_source text,
  record_id uuid
)
language plpgsql
stable
set search_path = ''
as $$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_classifications text[];
  normalized_collection_names text[];
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

  normalized_query := lower(btrim(coalesce(p_query, '')));
  normalized_classifications := array(
    select distinct lower(btrim(classification))
    from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
    order by lower(btrim(classification))
  );
  normalized_collection_names := array(
    select distinct lower(btrim(collection_name))
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name))
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
    or cardinality(normalized_collection_names) > 0
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
        cardinality(normalized_collection_names) = 0
        or exists (
          select 1
          from public.entry_collections as membership
          join public.collections as collection
            on collection.id = membership.collection_id
            and collection.owner_id = membership.owner_id
          where membership.entry_id = item.id
            and membership.owner_id = search_owner_id
            and collection.archived_at is null
            and lower(collection.name) = any(normalized_collection_names)
        )
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
      collection_context.collection_names,
      collection_context.collection_text,
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
        person.name,
        person.relationship_label,
        person.notes,
        place.name,
        place.address,
        place.city,
        place.region,
        place.country,
        place.notes,
        home.move_in_reason,
        home.move_out_reason,
        vehicle.make,
        vehicle.model,
        vehicle.model_year::text,
        vehicle.color,
        goal.horizon,
        goal.status,
        goal.target_date::text,
        timeline_context.timeline_text,
        related_place_context.place_text,
        related_person_context.person_text,
        attachment_context.filename_text
      ) as structured_text
    from owned_items as item
    left join public.people as person
      on person.id = item.id and person.owner_id = search_owner_id
    left join public.places as place
      on place.id = item.id and place.owner_id = search_owner_id
    left join public.homes as home
      on home.entry_id = item.id and home.owner_id = search_owner_id
    left join public.vehicles as vehicle
      on vehicle.entry_id = item.id and vehicle.owner_id = search_owner_id
    left join public.goals as goal
      on goal.entry_id = item.id and goal.owner_id = search_owner_id
    left join lateral (
      select
        coalesce(array_agg(collection.name order by lower(collection.name), collection.name), '{}'::text[]) as collection_names,
        coalesce(string_agg(collection.name, ' '), '') as collection_text
      from public.entry_collections as membership
      join public.collections as collection
        on collection.id = membership.collection_id
        and collection.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = search_owner_id
        and collection.archived_at is null
    ) as collection_context on true
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
      join public.places as related
        on related.id = link.place_id and related.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as related_place_context on true
    left join lateral (
      select string_agg(concat_ws(' ', related.name, related.relationship_label, related.notes, link.relationship), ' ') as person_text
      from public.entry_people as link
      join public.people as related
        on related.id = link.person_id and related.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as related_person_context on true
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
        position(normalized_query in lower(enriched.collection_text)) > 0
        or to_tsvector('simple', enriched.collection_text) @@ search_query
      ) as collection_matches,
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
          case when evaluated.collection_matches then 'Collection' end,
          case when evaluated.tag_matches then 'Tag' end,
          case when evaluated.date_matches then 'Date' end,
          case when evaluated.structured_matches then 'Details' end
        ], null)
      end as computed_match_reasons,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.collection_matches then 3 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(ts_rank_cd(evaluated.search_document, search_query)::double precision, 0)
      ) as computed_match_rank
    from evaluated
    where not has_query
      or evaluated.title_matches
      or evaluated.body_matches
      or evaluated.collection_matches
      or evaluated.tag_matches
      or evaluated.date_matches
      or evaluated.structured_matches
  )
  select
    matched.id,
    matched.title,
    matched.body,
    matched.inbox_status,
    matched.occurred_start,
    matched.occurred_end,
    matched.occurred_label,
    matched.occurred_timezone,
    matched.revision,
    matched.updated_at,
    matched.collection_names,
    matched.tag_names,
    matched.computed_match_reasons,
    matched.computed_match_rank,
    count(*) over (),
    matched.date_precision,
    matched.item_kind,
    matched.item_subtype,
    case
      when matched.item_kind = 'entity' and matched.item_subtype = 'person' then 'person'
      when matched.item_kind = 'entity' and matched.item_subtype = 'place' then 'place'
      else 'entry'
    end,
    matched.id
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

revoke all on function public.search_wiki_items(text, text[], text[], text[], date, date, integer, integer, text) from public, anon;
grant execute on function public.search_wiki_items(text, text[], text[], text[], date, date, integer, integer, text) to authenticated;

comment on function public.search_wiki_items(text, text[], text[], text[], date, date, integer, integer, text)
is 'Owner-scoped canonical Wiki Item search. Classifications accept item Kind or subtype only.';

create or replace function public.archive_wiki_search_evidence(
  p_queries text[] default '{}'::text[],
  p_item_classifications text[] default '{}'::text[],
  p_collection_names text[] default '{}'::text[],
  p_tag_names text[] default '{}'::text[],
  p_date_from date default null,
  p_date_to date default null,
  p_before_latest_home boolean default false,
  p_order text default 'relevance',
  p_as_of date default current_date
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  evidence_owner_id uuid := auth.uid();
  normalized_queries text[];
  latest_home jsonb;
  reference_date date;
  effective_date_to date := p_date_to;
  entries jsonb;
  people jsonb;
  places jsonb;
begin
  if evidence_owner_id is null then
    return null;
  end if;
  if cardinality(coalesce(p_queries, '{}'::text[])) > 6
    or exists (
      select 1 from unnest(coalesce(p_queries, '{}'::text[])) as query
      where length(query) > 200
    )
  then
    raise exception using errcode = '22023', message = 'invalid_queries';
  end if;
  if p_as_of is null or not isfinite(p_as_of) then
    raise exception using errcode = '22023', message = 'invalid_as_of';
  end if;

  normalized_queries := array(
    select distinct btrim(query)
    from unnest(coalesce(p_queries, '{}'::text[])) as query
    order by btrim(query)
  );
  if cardinality(normalized_queries) = 0 then
    normalized_queries := array['']::text[];
  end if;

  select jsonb_build_object(
    'id', item.id,
    'title', item.title,
    'occurred_start', item.occurred_start,
    'occurred_timezone', item.occurred_timezone
  ), public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date
  into latest_home, reference_date
  from public.entries as item
  where item.owner_id = evidence_owner_id
    and item.deleted_at is null
    and item.item_kind = 'entity'
    and item.item_subtype = 'home'
    and item.occurred_start is not null
    and public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date <= p_as_of
  order by public.entry_local_timestamp(item.occurred_start, item.occurred_timezone) desc, item.id
  limit 1;

  if p_before_latest_home and reference_date is not null then
    effective_date_to := least(coalesce(p_date_to, reference_date - 1), reference_date - 1);
  end if;

  with found as (
    select distinct on (result.entry_id) result.*
    from unnest(normalized_queries) as query
    cross join lateral public.search_wiki_items(
      query,
      p_item_classifications,
      p_collection_names,
      p_tag_names,
      p_date_from,
      effective_date_to,
      50,
      0,
      p_order
    ) as result
    order by result.entry_id, result.match_rank desc, result.updated_at desc
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', found.entry_id,
      'title', found.title,
      'body', found.body,
      'item_kind', found.item_kind,
      'item_subtype', found.item_subtype,
      'date_precision', found.date_precision,
      'occurred_start', found.occurred_start,
      'occurred_end', found.occurred_end,
      'occurred_label', found.occurred_label,
      'occurred_timezone', found.occurred_timezone,
      'collections', found.collection_names,
      'tags', found.tag_names,
      'record_source', found.record_source,
      'record_id', found.record_id
    )
    order by case when p_order = 'oldest' then found.occurred_start end asc nulls last,
      case when p_order <> 'oldest' then coalesce(found.occurred_start, found.updated_at) end desc nulls last,
      found.entry_id
  ), '[]'::jsonb)
  into entries
  from found;

  if cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0
    or p_item_classifications && array['entity', 'person']::text[]
  then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', person.id,
      'name', person.name,
      'relationship_label', person.relationship_label,
      'notes', person.notes
    ) order by lower(person.name), person.id), '[]'::jsonb)
    into people
    from public.people as person
    where person.owner_id = evidence_owner_id
      and person.deleted_at is null
      and exists (
        select 1 from unnest(normalized_queries) as query
        where btrim(query) <> ''
          and strpos(lower(concat_ws(' ', person.name, person.relationship_label, person.notes)), lower(query)) > 0
      );
  else
    people := '[]'::jsonb;
  end if;

  if cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0
    or p_item_classifications && array['entity', 'place']::text[]
  then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', place.id,
      'name', place.name,
      'address', place.address,
      'city', place.city,
      'region', place.region,
      'country', place.country,
      'notes', place.notes
    ) order by lower(place.name), place.id), '[]'::jsonb)
    into places
    from public.places as place
    where place.owner_id = evidence_owner_id
      and place.deleted_at is null
      and exists (
        select 1 from unnest(normalized_queries) as query
        where btrim(query) <> ''
          and strpos(lower(concat_ws(' ', place.name, place.address, place.city, place.region, place.country, place.notes)), lower(query)) > 0
      );
  else
    places := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'entries', entries,
    'people', people,
    'places', places,
    'latest_home_reference', latest_home,
    'reference_window_applied', p_before_latest_home and reference_date is not null
  );
end;
$$;

revoke all on function public.archive_wiki_search_evidence(text[], text[], text[], text[], date, date, boolean, text, date) from public;
grant execute on function public.archive_wiki_search_evidence(text[], text[], text[], text[], date, date, boolean, text, date) to authenticated;

drop function public.collection_wiki_items(uuid, integer, integer);

create function public.collection_wiki_items(
  p_collection_id uuid,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table(
  collection_id uuid,
  collection_name text,
  total_count bigint,
  entry_id uuid,
  title text,
  body text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  created_at timestamptz,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[],
  attachments jsonb,
  item_kind text,
  item_subtype text,
  record_source text,
  record_id uuid
)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'invalid_collection_limit';
  end if;
  if p_offset is null or p_offset < 0 or p_offset > 10000 then
    raise exception using errcode = '22023', message = 'invalid_collection_offset';
  end if;

  return query
  with visible_items as (
    select
      collection.id as collection_id,
      collection.name as collection_name,
      item.*
    from public.collections as collection
    join public.entry_collections as membership
      on membership.collection_id = collection.id
      and membership.owner_id = collection.owner_id
    join public.entries as item
      on item.id = membership.entry_id
      and item.owner_id = membership.owner_id
    where collection.id = p_collection_id
      and collection.owner_id = auth.uid()
      and collection.archived_at is null
      and item.deleted_at is null
  )
  select
    item.collection_id,
    item.collection_name,
    count(*) over (),
    item.id,
    item.title,
    item.body,
    item.inbox_status,
    item.occurred_start,
    item.occurred_end,
    item.date_precision,
    item.occurred_label,
    item.occurred_timezone,
    item.revision,
    item.created_at,
    item.updated_at,
    coalesce((
      select array_agg(collection.name order by lower(collection.name), collection.id)
      from public.entry_collections as membership
      join public.collections as collection
        on collection.id = membership.collection_id
        and collection.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = auth.uid()
        and collection.archived_at is null
    ), '{}'::text[]),
    coalesce((
      select array_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = auth.uid()
    ), '{}'::text[]),
    coalesce((
      select jsonb_agg(jsonb_build_object(
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
      ) order by media.created_at, media.id)
      from public.attachments as media
      where media.entry_id = item.id
        and media.owner_id = auth.uid()
        and media.deleted_at is null
    ), '[]'::jsonb),
    item.item_kind,
    item.item_subtype,
    case
      when item.item_kind = 'entity' and item.item_subtype = 'person' then 'person'
      when item.item_kind = 'entity' and item.item_subtype = 'place' then 'place'
      else 'entry'
    end,
    item.id
  from visible_items as item
  order by item.occurred_start desc nulls last, item.created_at desc, item.id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.collection_wiki_items(uuid, integer, integer) from public, anon;
grant execute on function public.collection_wiki_items(uuid, integer, integer) to authenticated;

drop function public.timeline_workspace_with_organization(boolean);

create function public.timeline_workspace_with_organization(
  p_include_hidden boolean default false
)
returns table(
  track_id uuid,
  track_name text,
  track_system_key text,
  track_sort_order integer,
  track_is_hidden boolean,
  entry_id uuid,
  title text,
  body text,
  item_kind text,
  item_subtype text,
  timeline_kind text,
  item_sort_order integer,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[]
)
language plpgsql
stable
set search_path = ''
as $$
declare
  timeline_owner_id uuid := auth.uid();
begin
  if timeline_owner_id is null or p_include_hidden is null then
    return;
  end if;

  return query
  with owned_tracks as (
    select track.*
    from public.timeline_tracks as track
    where track.owner_id = timeline_owner_id
      and (p_include_hidden or not track.is_hidden)
  ),
  visible_items as (
    select
      placement.track_id,
      placement.timeline_kind,
      placement.sort_order,
      item.*
    from public.timeline_items as placement
    join public.entries as item
      on item.id = placement.entry_id
      and item.owner_id = placement.owner_id
    where placement.owner_id = timeline_owner_id
      and item.deleted_at is null
  )
  select
    track.id,
    track.name,
    track.system_key,
    track.sort_order,
    track.is_hidden,
    item.id,
    item.title,
    item.body,
    item.item_kind,
    item.item_subtype,
    item.timeline_kind,
    item.sort_order,
    item.occurred_start,
    item.occurred_end,
    item.date_precision,
    item.occurred_label,
    item.occurred_timezone,
    item.revision,
    item.updated_at,
    coalesce((
      select array_agg(collection.name order by lower(collection.name), collection.id)
      from public.entry_collections as membership
      join public.collections as collection
        on collection.id = membership.collection_id
        and collection.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = timeline_owner_id
        and collection.archived_at is null
    ), '{}'::text[]),
    coalesce((
      select array_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = timeline_owner_id
    ), '{}'::text[])
  from owned_tracks as track
  left join visible_items as item on item.track_id = track.id
  order by
    track.sort_order,
    lower(track.name),
    item.occurred_start nulls last,
    item.sort_order,
    item.id;
end;
$$;

revoke all on function public.timeline_workspace_with_organization(boolean) from public, anon;
grant execute on function public.timeline_workspace_with_organization(boolean) to authenticated;

drop function public.trash_workspace(integer, integer);

create function public.trash_workspace(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  item_kind text,
  item_id uuid,
  title text,
  detail text,
  deleted_at timestamptz,
  expires_at timestamptz,
  revision integer,
  wiki_item_kind text,
  wiki_item_subtype text,
  parent_entry_id uuid,
  storage_paths text[],
  total_count bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_trash_page';
  end if;

  return query
  with trash_items as (
    select
      'entry'::text as item_kind,
      item.id as item_id,
      coalesce(
        nullif(btrim(item.title), ''),
        nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 120), ''),
        'Untitled Entry'
      ) as title,
      nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 240), '') as detail,
      item.deleted_at,
      item.deleted_at + interval '30 days' as expires_at,
      item.revision,
      item.item_kind as wiki_item_kind,
      item.item_subtype as wiki_item_subtype,
      null::uuid as parent_entry_id,
      coalesce((
        select array_agg(media.object_path order by media.created_at, media.id)
        from public.attachments as media
        where media.owner_id = item.owner_id
          and media.entry_id = item.id
          and media.bucket_id = 'entry-media'
      ), '{}'::text[]) as storage_paths
    from public.entries as item
    where item.owner_id = auth.uid()
      and item.deleted_at is not null
      and not exists (
        select 1 from public.people as person
        where person.id = item.id and person.owner_id = item.owner_id
      )
      and not exists (
        select 1 from public.places as place
        where place.id = item.id and place.owner_id = item.owner_id
      )

    union all

    select
      'attachment'::text,
      media.id,
      coalesce(nullif(btrim(media.original_filename), ''), 'Removed photo'),
      concat('Photo from ', coalesce(
        nullif(btrim(item.title), ''),
        nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 80), ''),
        'Untitled Entry'
      )),
      media.deleted_at,
      media.deleted_at + interval '30 days',
      null::integer,
      null::text,
      null::text,
      item.id,
      array[media.object_path]::text[]
    from public.attachments as media
    join public.entries as item
      on item.id = media.entry_id and item.owner_id = media.owner_id
    where media.owner_id = auth.uid()
      and media.deleted_at is not null
      and media.variant = 'original'
      and item.deleted_at is null

    union all

    select
      'place'::text,
      place.id,
      place.name,
      nullif(concat_ws(', ', place.address, place.city, place.region, place.country), ''),
      place.deleted_at,
      place.deleted_at + interval '30 days',
      place.revision,
      'entity'::text,
      'place'::text,
      null::uuid,
      '{}'::text[]
    from public.places as place
    where place.owner_id = auth.uid() and place.deleted_at is not null

    union all

    select
      'person'::text,
      person.id,
      person.name,
      person.relationship_label,
      person.deleted_at,
      person.deleted_at + interval '30 days',
      person.revision,
      'entity'::text,
      'person'::text,
      null::uuid,
      '{}'::text[]
    from public.people as person
    where person.owner_id = auth.uid() and person.deleted_at is not null

    union all

    select
      'collection'::text,
      collection.id,
      collection.name,
      'Collection grouping; Entries remain in your archive',
      collection.archived_at,
      collection.archived_at + interval '30 days',
      collection.revision,
      null::text,
      null::text,
      null::uuid,
      '{}'::text[]
    from public.collections as collection
    where collection.owner_id = auth.uid() and collection.archived_at is not null
  ),
  counted as (
    select trash_items.*, count(*) over () as total_count
    from trash_items
  )
  select counted.*
  from counted
  order by counted.deleted_at desc, counted.item_kind, counted.item_id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.trash_workspace(integer, integer) from public, anon;
grant execute on function public.trash_workspace(integer, integer) to authenticated;

create or replace function public.entry_history_snapshot(p_entry public.entries)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(p_entry) - 'entry_type') || jsonb_build_object(
    'history_schema', 3,
    'home', (select to_jsonb(home) from public.homes as home where home.entry_id = p_entry.id),
    'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = p_entry.id),
    'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = p_entry.id),
    'place', (
      select to_jsonb(place)
      from public.homes as home
      join public.places as place on place.id = home.place_id
      where home.entry_id = p_entry.id
    ),
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object('id', collection.id, 'name', collection.name) order by collection.name)
      from public.entry_collections as membership
      join public.collections as collection on collection.id = membership.collection_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'people', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', person.name) order by link.person_id, link.relationship)
      from public.entry_people as link
      join public.people as person on person.id = link.person_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'places', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', place.name) order by link.place_id, link.relationship)
      from public.entry_places as link
      join public.places as place on place.id = link.place_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline_items', coalesce((
      select jsonb_agg(to_jsonb(placement) || jsonb_build_object('track_name', track.name) order by placement.track_id)
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline', (
      select jsonb_build_object(
        'track_id', track.id,
        'track_name', track.name,
        'track_system_key', track.system_key,
        'timeline_kind', placement.timeline_kind
      )
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
      order by (
        track.system_key = case
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'home' then 'homes'
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'vehicle' then 'vehicles'
          else ''
        end
      ) desc, placement.created_at, track.id
      limit 1
    ),
    'links', coalesce((
      select jsonb_agg(to_jsonb(link) order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id
    ), '[]'::jsonb),
    'related_entry_ids', coalesce((
      select jsonb_agg(link.target_entry_id order by link.target_entry_id)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id and link.relationship = 'related'
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(to_jsonb(attachment) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = p_entry.id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  );
$$;

update public.entry_versions as version
set snapshot = (version.snapshot - 'entry_type') || jsonb_build_object(
  'history_schema', 3,
  'item_kind', coalesce(version.snapshot->>'item_kind', item.item_kind),
  'item_subtype', coalesce(version.snapshot->>'item_subtype', item.item_subtype)
)
from public.entries as item
where item.id = version.entry_id;

drop function public.entry_history_index(text, integer, integer);

create function public.entry_history_index(
  p_query text default '',
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  entry_id uuid,
  title text,
  excerpt text,
  item_kind text,
  item_subtype text,
  revision integer,
  is_deleted boolean,
  version_count bigint,
  last_changed timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_limit is null or p_limit not between 1 and 50
    or p_offset is null or p_offset not between 0 and 100000
    or length(coalesce(p_query, '')) > 200
  then
    raise exception using errcode = '22023', message = 'invalid_history_page';
  end if;
  return query
  select
    item.id,
    item.title,
    left(item.body, 160),
    item.item_kind,
    item.item_subtype,
    item.revision,
    item.deleted_at is not null,
    count(version.id),
    item.updated_at,
    count(*) over ()
  from public.entries as item
  join public.entry_versions as version on version.entry_id = item.id
  where item.owner_id = auth.uid()
    and (
      coalesce(btrim(p_query), '') = ''
      or strpos(lower(concat_ws(' ', item.title, item.body, item.item_kind, item.item_subtype)), lower(btrim(p_query))) > 0
    )
  group by item.id
  order by item.updated_at desc, item.id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.entry_history_index(text, integer, integer) from public, anon;
grant execute on function public.entry_history_index(text, integer, integer) to authenticated;

do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.goals_workspace(integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '''entry_type'', related.entry_type,',
    '''item_kind'', related.item_kind, ''item_subtype'', related.item_subtype,'
  );
  definition := replace(
    definition,
    'entries.entry_type = ''goal''',
    'entries.item_kind = ''goal'''
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'goals_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.homes_workspace(integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    'entries.entry_type = ''home''',
    'entries.item_kind = ''entity'' and entries.item_subtype = ''home'''
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'homes_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.vehicles_workspace(integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    'entries.entry_type = ''vehicle''',
    'entries.item_kind = ''entity'' and entries.item_subtype = ''vehicle'''
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'vehicles_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.first_times_workspace_with_occurrence()'::regprocedure)
  into definition;
  definition := replace(
    definition,
    'entries.entry_type = ''first_time''',
    'entries.item_kind = ''event'' and entries.item_subtype = ''first_time'''
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'first_times_workspace_with_occurrence still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.places_workspace(integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '''entry_type'', entries.entry_type,',
    '''item_kind'', entries.item_kind, ''item_subtype'', entries.item_subtype,'
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'places_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.people_workspace(integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '''entry_type'', e.entry_type,',
    '''item_kind'', e.item_kind, ''item_subtype'', e.item_subtype,'
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'people_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.person_record(uuid)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '''entry_type'',e.entry_type,',
    '''item_kind'',e.item_kind,''item_subtype'',e.item_subtype,'
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'person_record still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.home_workspace(date,text,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    'count(*) filter (where entry_type = ''first_time'')',
    'count(*) filter (where item_kind = ''event'' and item_subtype = ''first_time'')'
  );
  definition := replace(
    definition,
    '''entry_type'', recent_entries.entry_type,',
    '''item_kind'', recent_entries.item_kind, ''item_subtype'', recent_entries.item_subtype,'
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'home_workspace still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.entry_relations(uuid,text,text,integer,integer)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    'e.entry_type,e.deleted_at',
    'e.item_kind,e.item_subtype,e.deleted_at'
  );
  if position('entry_type' in definition) > 0 then
    raise exception 'entry_relations still depends on entry_type';
  end if;
  execute definition;

  select pg_get_functiondef('public.capture_extraction_source(uuid)'::regprocedure)
  into definition;
  definition := replace(definition, '''entry_type'', entry.entry_type,', '');
  if position('entry_type' in definition) > 0 then
    raise exception 'capture_extraction_source still depends on entry_type';
  end if;
  execute definition;
end;
$$;

create or replace function public.review_wiki_item_with_occurrence_rich(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_body_rich jsonb,
  p_preserve_rich_text boolean
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql
set search_path = ''
as $$
declare
  review_owner_id uuid := auth.uid();
  reviewed_entry_id uuid;
  reviewed_revision integer;
  reviewed_inbox_status text;
begin
  if review_owner_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  if p_item_kind not in ('writing', 'event', 'story')
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    or not (case p_item_kind
      when 'writing' then p_item_subtype in ('note', 'journal', 'reflection', 'lesson', 'idea')
      when 'event' then p_item_subtype in ('memory', 'first_time', 'milestone', 'trip', 'life_stage', 'other')
      when 'story' then p_item_subtype in ('chapter', 'story')
      else false
    end)
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
  if p_item_kind = 'event' and p_item_subtype = 'first_time' and p_title is null then
    raise exception using errcode = '22023', message = 'first_time_requires_title';
  end if;
  if p_preserve_rich_text is null then
    raise exception using errcode = '22023', message = 'invalid_rich_text';
  end if;
  if not p_preserve_rich_text and p_body_rich is not null and (
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

  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1 from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
      where nullif(btrim(collection_name), '') is null or length(btrim(collection_name)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;
  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1 from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null or length(btrim(tag_name)) > 60
    )
  then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if exists (
    select 1
    from public.entries as item
    where item.id = p_entry_id
      and item.owner_id = review_owner_id
      and item.revision = p_expected_revision
      and item.deleted_at is null
      and item.item_kind in ('writing', 'event', 'story')
      and item.item_kind <> 'capture'
      and item.item_kind <> p_item_kind
  ) then
    raise exception using errcode = '22023', message = 'invalid_item_kind_transition';
  end if;

  update public.entries as item
  set
    title = p_title,
    body = p_body,
    metadata = case
      when p_preserve_rich_text then item.metadata
      when p_body_rich is null then item.metadata - 'body_rich'
      else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
    end,
    item_kind = p_item_kind,
    item_subtype = p_item_subtype,
    inbox_status = case when p_mark_done then 'organized' else item.inbox_status end,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    occurred_label = p_occurred_label,
    date_precision = p_date_precision,
    occurred_timezone = btrim(p_occurred_timezone)
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind in ('capture', p_item_kind)
    and item.deleted_at is null
  returning item.id, item.revision, item.inbox_status
  into reviewed_entry_id, reviewed_revision, reviewed_inbox_status;

  if reviewed_entry_id is null then
    return;
  end if;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name))) btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select review_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where owner_id = review_owner_id
      and lower(name) = lower(normalized_names.name)
      and archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections as membership
  where membership.entry_id = reviewed_entry_id
    and membership.owner_id = review_owner_id
    and exists (
      select 1
      from public.collections as collection
      where collection.id = membership.collection_id and collection.archived_at is null
    );

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select reviewed_entry_id, collection.id, review_owner_id
  from public.collections as collection
  join normalized_names on lower(collection.name) = normalized_names.normalized_name
  where collection.owner_id = review_owner_id and collection.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name))) btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select review_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where owner_id = review_owner_id and lower(name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags as membership
  where membership.entry_id = reviewed_entry_id and membership.owner_id = review_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select reviewed_entry_id, tag.id, review_owner_id
  from public.tags as tag
  join normalized_names on lower(tag.name) = normalized_names.normalized_name
  where tag.owner_id = review_owner_id
  on conflict do nothing;

  return query
  select reviewed_entry_id, reviewed_revision, reviewed_inbox_status;
end;
$$;

revoke all on function public.review_wiki_item_with_occurrence_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,boolean) from public, anon, authenticated;

create or replace function public.review_wiki_item_with_photo_place_core(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_photo_place jsonb,
  p_body_rich jsonb,
  p_preserve_rich_text boolean
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql
set search_path = ''
as $$
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
      from public.places as place
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
    p_collection_names,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_body_rich,
    p_preserve_rich_text
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
      from public.save_place(
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
    elsif not exists (
      select 1
      from public.entry_places as link
      where link.entry_id = reviewed.entry_id
        and link.place_id = target_place_id
        and link.owner_id = review_owner_id
    ) then
      update public.places as place
      set notes = place.notes
      where place.id = target_place_id and place.owner_id = review_owner_id;
      insert into public.entry_places (entry_id, place_id, owner_id, relationship)
      values (reviewed.entry_id, target_place_id, review_owner_id, 'related');
    end if;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision, reviewed.inbox_status;
end;
$$;

revoke all on function public.review_wiki_item_with_photo_place_core(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb,boolean) from public, anon, authenticated;

create or replace function public.review_wiki_item_with_photo_place_rich(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_photo_place jsonb,
  p_body_rich jsonb
)
returns table(entry_id uuid, revision integer, inbox_status text)
language sql
security definer
set search_path = ''
as $$
  select *
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_collection_names,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich,
    false
  );
$$;

revoke all on function public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) to authenticated;

create or replace function public.review_wiki_item_with_photo_place(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_photo_place jsonb
)
returns table(entry_id uuid, revision integer, inbox_status text)
language sql
security definer
set search_path = ''
as $$
  select *
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_collection_names,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    null,
    true
  );
$$;

revoke all on function public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) to authenticated;

do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.extract_capture_item(uuid,integer,text,text,text,text,timestamptz,timestamptz,text,text,text)'::regprocedure)
  into definition;
  definition := replace(definition, E'    entry_type,\n    item_kind,', E'    item_kind,');
  definition := replace(definition, E'    public.legacy_entry_type_for_item(p_item_kind, p_item_subtype),\n    p_item_kind,', E'    p_item_kind,');
  if position('entry_type' in definition) > 0 then raise exception 'extract_capture_item still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date)'::regprocedure)
  into definition;
  definition := replace(definition, E'    entry_type,\n    item_kind,', E'    item_kind,');
  definition := replace(definition, E'    ''goal'',\n    ''goal'',\n    ''goal'',', E'    ''goal'',\n    ''goal'',');
  if position('entry_type' in definition) > 0 then raise exception 'extract_goal_from_item still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.sync_person_wiki_item()'::regprocedure)
  into definition;
  definition := replace(definition, 'id, owner_id, title, body, entry_type, item_kind, item_subtype,', 'id, owner_id, title, body, item_kind, item_subtype,');
  definition := replace(definition, E'      ''standard'', ''entity'', ''person'',', E'      ''entity'', ''person'',');
  definition := replace(definition, E'      entry_type = ''standard'',\n      item_kind', E'      item_kind');
  if position('entry_type' in definition) > 0 then raise exception 'sync_person_wiki_item still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.sync_place_wiki_item()'::regprocedure)
  into definition;
  definition := replace(definition, 'id, owner_id, title, body, entry_type, item_kind, item_subtype,', 'id, owner_id, title, body, item_kind, item_subtype,');
  definition := replace(definition, E'      ''standard'', ''entity'', ''place'',', E'      ''entity'', ''place'',');
  definition := replace(definition, E'      entry_type = ''standard'',\n      item_kind', E'      item_kind');
  if position('entry_type' in definition) > 0 then raise exception 'sync_place_wiki_item still depends on entry_type'; end if;
  execute definition;
end;
$$;

do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)'::regprocedure)
  into definition;
  definition := replace(definition, 'entries.entry_type = ''goal''', 'entries.item_kind = ''goal''');
  if position('entry_type' in definition) > 0 then raise exception 'achieve_goal_with_occurrence still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.register_first_time_attachment(uuid,uuid,text,text,text,bigint,integer,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'entry_type=''first_time''', 'item_kind=''event'' and item_subtype=''first_time''');
  if position('entry_type' in definition) > 0 then raise exception 'register_first_time_attachment still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.trash_first_time_attachment(uuid)'::regprocedure)
  into definition;
  definition := replace(definition, 'e.entry_type=''first_time''', 'e.item_kind=''event'' and e.item_subtype=''first_time''');
  if position('entry_type' in definition) > 0 then raise exception 'trash_first_time_attachment still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.trash_first_time_entry(uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'entries.entry_type = ''first_time''', 'entries.item_kind = ''event'' and entries.item_subtype = ''first_time''');
  if position('entry_type' in definition) > 0 then raise exception 'trash_first_time_entry still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.trash_goal_entry(uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'entries.entry_type = ''goal''', 'entries.item_kind = ''goal''');
  if position('entry_type' in definition) > 0 then raise exception 'trash_goal_entry still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.trash_home_entry(uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'entries.entry_type = ''home''', 'entries.item_kind = ''entity'' and entries.item_subtype = ''home''');
  if position('entry_type' in definition) > 0 then raise exception 'trash_home_entry still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.trash_vehicle_entry(uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'entries.entry_type = ''vehicle''', 'entries.item_kind = ''entity'' and entries.item_subtype = ''vehicle''');
  if position('entry_type' in definition) > 0 then raise exception 'trash_vehicle_entry still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.save_first_time_with_occurrence(text,text,timestamptz,text,text,text,text[],text[],uuid,integer,timestamptz)'::regprocedure)
  into definition;
  definition := replace(definition, E'entry_type,\n      inbox_status', E'item_kind,\n      item_subtype,\n      inbox_status');
  definition := replace(definition, E'''first_time'',\n      ''organized''', E'''event'',\n      ''first_time'',\n      ''organized''');
  definition := replace(definition, 'entries.entry_type = ''first_time''', 'entries.item_kind = ''event'' and entries.item_subtype = ''first_time''');
  if position('entry_type' in definition) > 0 then raise exception 'save_first_time_with_occurrence still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.save_goal_entry(text,text,text,text,date,text[],text[],uuid[],uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, E'entry_type,\n      inbox_status', E'item_kind,\n      item_subtype,\n      inbox_status');
  definition := replace(definition, E'''goal'',\n      ''organized''', E'''goal'',\n      ''goal'',\n      ''organized''');
  definition := replace(definition, E'entry_type = ''goal'',\n      inbox_status', E'item_kind = ''goal'',\n      item_subtype = ''goal'',\n      inbox_status');
  definition := replace(definition, 'entries.entry_type = ''goal''', 'entries.item_kind = ''goal''');
  if position('entry_type' in definition) > 0 then raise exception 'save_goal_entry still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.save_home_entry_with_occurrence(text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, E'entry_type,\n      inbox_status', E'item_kind,\n      item_subtype,\n      inbox_status');
  definition := replace(definition, E'''home'',\n      ''organized''', E'''entity'',\n      ''home'',\n      ''organized''');
  definition := replace(definition, E'entry_type = ''home'',\n      inbox_status', E'item_kind = ''entity'',\n      item_subtype = ''home'',\n      inbox_status');
  definition := replace(definition, 'entries.entry_type = ''home''', 'entries.item_kind = ''entity'' and entries.item_subtype = ''home''');
  if position('entry_type' in definition) > 0 then raise exception 'save_home_entry_with_occurrence still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.save_vehicle_entry_with_occurrence(text,text,timestamptz,timestamptz,text,text,text,text,text,integer,text,text[],text[],uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, E'entry_type,\n      inbox_status', E'item_kind,\n      item_subtype,\n      inbox_status');
  definition := replace(definition, E'''vehicle'',\n      ''organized''', E'''entity'',\n      ''vehicle'',\n      ''organized''');
  definition := replace(definition, E'entry_type = ''vehicle'',\n      inbox_status', E'item_kind = ''entity'',\n      item_subtype = ''vehicle'',\n      inbox_status');
  definition := replace(definition, 'entries.entry_type = ''vehicle''', 'entries.item_kind = ''entity'' and entries.item_subtype = ''vehicle''');
  if position('entry_type' in definition) > 0 then raise exception 'save_vehicle_entry_with_occurrence still depends on entry_type'; end if;
  execute definition;

  select pg_get_functiondef('public.save_timeline_entry_with_occurrence(uuid,text,text,text,timestamptz,timestamptz,text,text,text,uuid,integer)'::regprocedure)
  into definition;
  definition := replace(definition, 'expected_entry_type', 'expected_item_subtype');
  definition := replace(definition, E'entry_type,\n      inbox_status', E'item_kind,\n      item_subtype,\n      inbox_status');
  definition := replace(definition, E'expected_item_subtype,\n      ''organized''', E'''event'',\n      expected_item_subtype,\n      ''organized''');
  definition := replace(definition, 'else ''standard''', 'else ''other''');
  definition := replace(definition, E'entry_type = expected_item_subtype,\n    inbox_status', E'item_kind = ''event'',\n    item_subtype = expected_item_subtype,\n    inbox_status');
  definition := replace(definition, 'entries.entry_type in (''life_stage'', ''standard'')', 'entries.item_kind = ''event'' and entries.item_subtype in (''life_stage'', ''other'')');
  if position('entry_type' in definition) > 0 then raise exception 'save_timeline_entry_with_occurrence still depends on entry_type'; end if;
  execute definition;
end;
$$;

drop function if exists public.review_entry(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean);
drop function if exists public.review_entry_with_occurrence(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text);
drop function if exists public.review_entry_with_occurrence_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,boolean);
drop function if exists public.review_entry_with_photo_place(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb);
drop function if exists public.review_entry_with_photo_place_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb);

drop function if exists public.archive_entry_sources(uuid[]);
drop function if exists public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date);
drop function if exists public.collection_entries(uuid,integer,integer);
drop function if exists public.convert_entry_to_goal(uuid,integer,text,text,text,date);
drop function if exists public.first_times_workspace();
drop function if exists public.save_first_time_entry(text,text,timestamptz,text,text,text,text[],text[],uuid,integer);
drop function if exists public.search_entries(text,text[],text[],text[],date,date,integer,integer);
drop function if exists public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text);
drop function if exists public.search_entries_with_occurrence(text,text[],text[],text[],date,date,integer,integer);
drop function if exists public.timeline_workspace(boolean);
drop function if exists public.entry_occurrence_window(timestamptz,timestamptz,text,text,text);

drop trigger if exists a_sync_entry_information_model on public.entries;
drop function if exists public.sync_entry_information_model();
drop function if exists public.legacy_entry_type_for_item(text,text);
drop function if exists public.legacy_item_kind(text,text);
drop function if exists public.legacy_item_subtype(text,text);

alter table public.entries drop constraint if exists entries_legacy_information_model_valid;
drop index if exists public.entries_owner_type_occurred_idx;
drop index if exists public.entries_owner_resurfacing_idx;
drop index if exists public.entries_owner_home_occurrence_idx;
drop index if exists public.entries_owner_vehicle_occurrence_idx;
drop index if exists public.entries_owner_goal_updated_idx;

alter table public.entries drop column entry_type;

alter table public.entries
  alter column item_kind set default 'capture',
  alter column item_subtype set default 'quick_capture';

create index entries_owner_kind_occurred_idx
  on public.entries (owner_id, item_kind, item_subtype, occurred_start desc nulls last)
  where deleted_at is null;
create index entries_owner_resurfacing_idx
  on public.entries (owner_id, occurred_start desc, id)
  where deleted_at is null
    and occurred_start is not null
    and inbox_status = 'organized'
    and not (item_kind = 'event' and item_subtype = 'life_stage');
create index entries_owner_home_occurrence_idx
  on public.entries (owner_id, occurred_end, occurred_start desc, id)
  where item_kind = 'entity' and item_subtype = 'home' and deleted_at is null;
create index entries_owner_vehicle_occurrence_idx
  on public.entries (owner_id, occurred_end, occurred_start desc, id)
  where item_kind = 'entity' and item_subtype = 'vehicle' and deleted_at is null;
create index entries_owner_goal_updated_idx
  on public.entries (owner_id, updated_at desc, id)
  where item_kind = 'goal' and deleted_at is null;

create or replace function public.entry_history_snapshot(p_entry public.entries)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p_entry) || jsonb_build_object(
    'history_schema', 3,
    'home', (select to_jsonb(home) from public.homes as home where home.entry_id = p_entry.id),
    'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = p_entry.id),
    'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = p_entry.id),
    'place', (
      select to_jsonb(place)
      from public.homes as home
      join public.places as place on place.id = home.place_id
      where home.entry_id = p_entry.id
    ),
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object('id', collection.id, 'name', collection.name) order by collection.name)
      from public.entry_collections as membership
      join public.collections as collection on collection.id = membership.collection_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'people', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', person.name) order by link.person_id, link.relationship)
      from public.entry_people as link
      join public.people as person on person.id = link.person_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'places', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', place.name) order by link.place_id, link.relationship)
      from public.entry_places as link
      join public.places as place on place.id = link.place_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline_items', coalesce((
      select jsonb_agg(to_jsonb(placement) || jsonb_build_object('track_name', track.name) order by placement.track_id)
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline', (
      select jsonb_build_object(
        'track_id', track.id,
        'track_name', track.name,
        'track_system_key', track.system_key,
        'timeline_kind', placement.timeline_kind
      )
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
      order by (
        track.system_key = case
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'home' then 'homes'
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'vehicle' then 'vehicles'
          else ''
        end
      ) desc, placement.created_at, track.id
      limit 1
    ),
    'links', coalesce((
      select jsonb_agg(to_jsonb(link) order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id
    ), '[]'::jsonb),
    'related_entry_ids', coalesce((
      select jsonb_agg(link.target_entry_id order by link.target_entry_id)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id and link.relationship = 'related'
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(to_jsonb(attachment) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = p_entry.id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.entry_history_snapshot(public.entries) from public, anon, authenticated;
