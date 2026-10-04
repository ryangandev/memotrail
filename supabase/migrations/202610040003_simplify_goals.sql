-- Goals become a simple list of things the owner wants to do: a title, optional
-- writing, photos, tags, and target date, and one of three states.
-- Considering and Paused Goals become active, and horizons are dropped.
-- Goal related links saved earlier stay in the data, version history, and
-- export, but Goals no longer edit or list them.

drop function public.save_goal_entry(text, text, text, text, date, text[], uuid[], uuid, integer);
drop function public.extract_capture_to_goal(uuid, integer, text, text, text, text, date, text[], uuid[]);
drop function public.extract_goal_from_item(uuid, integer, uuid, text, text, text, date);
drop function public.goals_workspace(integer, integer);

update public.goals set status = 'active' where status in ('considering', 'paused');
alter table public.goals drop constraint goals_status_check;
alter table public.goals drop column horizon;
alter table public.goals alter column status set default 'active';
alter table public.goals add constraint goals_status_check
  check (status in ('active', 'achieved', 'let_go'));

-- Earlier versions restore into the same three states.
update public.entry_versions
set snapshot = snapshot #- '{goal,horizon}'
where jsonb_typeof(snapshot->'goal') = 'object' and snapshot->'goal' ? 'horizon';
update public.entry_versions
set snapshot = jsonb_set(snapshot, '{goal,status}', '"active"'::jsonb)
where snapshot->'goal'->>'status' in ('considering', 'paused');

create function public.save_goal_entry(p_title text, p_body text, p_status text, p_target_date date, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
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
      inbox_status,
      date_precision
    )
    values (
      goal_owner_id,
      normalized_title,
      normalized_body,
      'goal',
      'goal',
      'organized',
      'unknown'
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'goal',
      item_subtype = 'goal',
      inbox_status = 'organized'
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
$function$
;

create function public.extract_capture_to_goal(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_status text, p_target_date date, p_tag_names text[])
 RETURNS TABLE(capture_id uuid, capture_revision integer, goal_entry_id uuid, goal_revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_goal record;
  existing_goal record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_goal_extraction';
  end if;

  select
    target.id as entry_id,
    target.revision,
    capture.revision as source_revision
  into existing_goal
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'goal'
    and target.item_subtype = 'goal'
    and target.deleted_at is null
  join public.goals as goal
    on goal.entry_id = target.id
    and goal.owner_id = target.owner_id
  where capture.id = p_capture_id
    and capture.owner_id = extraction_owner_id
    and capture.item_kind = 'entry'
    and capture.item_subtype = 'source_capture'
    and capture.inbox_status = 'organized'
    and capture.deleted_at is null
  order by provenance.created_at
  limit 1;

  if found then
    return query select
      p_capture_id,
      existing_goal.source_revision,
      existing_goal.entry_id,
      existing_goal.revision;
    return;
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
    and entry.item_kind = 'entry'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null
  for update;

  if not found then
    return;
  end if;

  select *
  into saved_goal
  from public.save_goal_entry(
    p_title,
    p_body,
    p_status,
    p_target_date,
    p_tag_names,
    null,
    null
  );

  if saved_goal.entry_id is null then
    return;
  end if;

  update public.entries as entry
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where entry.id = source.id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
  returning entry.revision into next_capture_revision;

  if next_capture_revision is null then
    raise exception using errcode = '40001', message = 'capture_changed';
  end if;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, saved_goal.entry_id, extraction_owner_id, 'derived'),
    (saved_goal.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_goal.entry_id,
    saved_goal.revision;
end;
$function$
;

create function public.extract_goal_from_item(p_source_entry_id uuid, p_source_revision integer, p_goal_id uuid, p_title text, p_status text, p_target_date date)
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
    inbox_status,
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
    'organized',
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
$function$
;

create function public.goals_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, status text, target_date date, tag_names text[], related_entries jsonb, attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
begin
  if goal_owner_id is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_goals_page';
  end if;

  return query
  with visible_goals as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.revision,
      entries.created_at,
      entries.updated_at,
      goals.status,
      goals.target_date,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = goal_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', related.id,
              'title', related.title,
              'body', related.body,
              'item_kind', related.item_kind, 'item_subtype', related.item_subtype,
              'occurred_start', related.occurred_start,
              'occurred_label', related.occurred_label,
              'occurred_timezone', related.occurred_timezone,
              'revision', related.revision,
              'updated_at', related.updated_at,
              'relationship', entry_links.relationship
            )
            order by related.updated_at desc, related.id
          )
          from public.entry_links
          join public.entries as related
            on related.id = entry_links.target_entry_id
            and related.owner_id = entry_links.owner_id
          where entry_links.source_entry_id = entries.id
            and entry_links.owner_id = goal_owner_id
            and entry_links.relationship = 'achievement'
            and related.deleted_at is null
        ),
        '[]'::jsonb
      ) as related_entries,
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
            and attachments.owner_id = goal_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.goals
      on goals.entry_id = entries.id
      and goals.owner_id = entries.owner_id
    where entries.owner_id = goal_owner_id
      and entries.item_kind = 'goal'
      and entries.deleted_at is null
  ),
  counted_goals as (
    select visible_goals.*, count(*) over () as total_count
    from visible_goals
  )
  select counted_goals.*
  from counted_goals
  order by
    case counted_goals.status
      when 'active' then 10
      when 'achieved' then 20
      else 30
    end,
    counted_goals.target_date asc nulls last,
    counted_goals.updated_at desc,
    lower(counted_goals.title),
    counted_goals.entry_id
  limit p_limit
  offset p_offset;
end;
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text, record_source text, record_id uuid)
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
    matched.inbox_status,
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
    'entry'::text,
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
$function$
;

revoke all on function public.save_goal_entry(text, text, text, date, text[], uuid, integer) from public, anon;
grant execute on function public.save_goal_entry(text, text, text, date, text[], uuid, integer) to authenticated;
revoke all on function public.extract_capture_to_goal(uuid, integer, text, text, text, date, text[]) from public, anon;
grant execute on function public.extract_capture_to_goal(uuid, integer, text, text, text, date, text[]) to authenticated;
revoke all on function public.extract_goal_from_item(uuid, integer, uuid, text, text, date) from public, anon;
grant execute on function public.extract_goal_from_item(uuid, integer, uuid, text, text, date) to authenticated;
revoke all on function public.goals_workspace(integer, integer) from public, anon;
grant execute on function public.goals_workspace(integer, integer) to authenticated;
