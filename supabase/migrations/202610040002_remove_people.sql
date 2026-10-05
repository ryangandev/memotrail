-- People are removed from MemoTrail, together with all of their data.
-- Each Person's canonical Entity Item is deleted forever like any other Entry, so its
-- photos join the media purge queue and its tombstone stops offline clients from
-- recreating it. Links from other Items to People, and the People recorded in their
-- version history, are removed with it.

delete from public.people;

delete from public.entries
where item_kind = 'entity' and item_subtype = 'person';

update public.entry_versions
set snapshot = snapshot - 'people'
where snapshot ? 'people';

drop function public.people_workspace;
drop function public.person_record;
drop function public.save_person;
drop function public.trash_person;

drop table public.entry_people;
drop table public.person_versions;
drop table public.people;

drop function public.archive_person_version;
drop function public.sync_person_wiki_item;

alter table public.entries drop constraint entries_entity_subtype_valid;
alter table public.entries
  add constraint entries_entity_subtype_valid
  check (item_kind <> 'entity' or item_subtype in ('home', 'vehicle'));

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
      'inbox_status', item.inbox_status,
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
      )),
      'record_source', 'entry',
      'record_id', item.id
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
CREATE OR REPLACE FUNCTION public.delete_trash_item_forever(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(item_kind text, item_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.entries
      where entries.id=p_item_id and entries.owner_id=trash_owner_id
        and entries.revision=p_expected_revision and entries.deleted_at=p_expected_deleted_at
      returning 'entry'::text,entries.id;
    return;
  end if;
  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode='22023',message='unexpected_trash_revision';
    end if;
    return query delete from public.attachments
      where attachments.id=p_item_id and attachments.owner_id=trash_owner_id
        and attachments.deleted_at=p_expected_deleted_at
        and exists(select 1 from public.entries where entries.id=attachments.entry_id
          and entries.owner_id=trash_owner_id and entries.deleted_at is null)
      returning 'attachment'::text,attachments.id;
    return;
  end if;
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$function$;
CREATE OR REPLACE FUNCTION public.entry_history_snapshot(p_entry entries)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.normalize_entry_history_snapshot(to_jsonb(p_entry) || jsonb_build_object(
    'history_schema', 3,
    'home', (select to_jsonb(home) from public.homes as home where home.entry_id = p_entry.id),
    'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = p_entry.id),
    'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = p_entry.id),
    'place', (
      select to_jsonb(place)
      from public.homes as home
      join public.locations as place on place.id = home.place_id
      where home.entry_id = p_entry.id
    ),
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'places', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', place.name) order by link.place_id, link.relationship)
      from public.entry_places as link
      join public.locations as place on place.id = link.place_id
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
  ));
$function$;
CREATE OR REPLACE FUNCTION public.export_dataset_names()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array[
    'profiles','entries','entry_versions','tags','entry_tags',
    'locations','entry_locations','timeline_tracks','timeline_items',
    'homes','vehicles','goals','attachments','entry_links',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$function$;
CREATE OR REPLACE FUNCTION public.normalize_entry_history_snapshot(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
declare
  normalized jsonb := p_snapshot;
  field text;
  rows jsonb;
begin
  foreach field in array array['places', 'timeline_items', 'links', 'attachments'] loop
    if jsonb_typeof(normalized->field) = 'array' then
      select coalesce(jsonb_agg(
        case when field = 'attachments'
          then value - array['created_at', 'updated_at', 'deleted_at']
          else value - array['created_at', 'updated_at']
        end order by position
      ), '[]'::jsonb)
      into rows
      from jsonb_array_elements(normalized->field) with ordinality as relation(value, position);
      normalized := jsonb_set(normalized, array[field], rows);
    end if;
  end loop;
  foreach field in array array['home', 'vehicle', 'goal', 'place'] loop
    if jsonb_typeof(normalized->field) = 'object' then
      normalized := jsonb_set(normalized, array[field],
        (normalized->field) - array['created_at', 'updated_at']);
    end if;
  end loop;
  return normalized;
end;
$function$;
CREATE OR REPLACE FUNCTION public.prepare_empty_trash()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  with candidates as (
    select 'entry'::text as item_kind, entry.id as item_id, entry.deleted_at, entry.revision
    from public.entries as entry
    where entry.owner_id = auth.uid()
      and entry.deleted_at is not null

    union all

    select 'attachment', attachment.id, attachment.deleted_at, null::integer
    from public.attachments as attachment
    join public.entries as entry
      on entry.id = attachment.entry_id and entry.owner_id = attachment.owner_id
    where attachment.owner_id = auth.uid()
      and attachment.deleted_at is not null
      and entry.deleted_at is null
  ),
  bounded as (
    select *
    from candidates
    order by
      case item_kind when 'entry' then 0 else 1 end,
      item_kind,
      item_id
    limit 10001
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(bounded)
      order by
        case item_kind when 'entry' then 0 else 1 end,
        item_kind,
        item_id
    ),
    '[]'::jsonb
  )
  into result
  from bounded;

  if jsonb_array_length(result) > 10000 then
    raise exception using errcode = '54000', message = 'trash_snapshot_too_large';
  end if;

  return result;
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
CREATE OR REPLACE FUNCTION public.restore_trash_item_without_photo_history(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(item_kind text, item_id uuid, revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then
    return;
  end if;

  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    update public.entries
    set deleted_at = null
    where entries.id = p_item_id
      and entries.owner_id = trash_owner_id
      and entries.revision = p_expected_revision
      and entries.deleted_at = p_expected_deleted_at
    returning 'entry'::text, entries.id, entries.revision;
    return;
  end if;

  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_trash_revision';
    end if;

    return query
    update public.attachments
    set deleted_at = null
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.deleted_at = p_expected_deleted_at
      and exists (
        select 1
        from public.entries
        where entries.id = attachments.entry_id
          and entries.owner_id = trash_owner_id
          and entries.deleted_at is null
      )
    returning 'attachment'::text, attachments.id, null::integer;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$function$;
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
        goal.horizon,
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
$function$;
CREATE OR REPLACE FUNCTION public.trash_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(item_kind text, item_id uuid, title text, detail text, deleted_at timestamp with time zone, expires_at timestamp with time zone, revision integer, wiki_item_kind text, wiki_item_subtype text, parent_entry_id uuid, storage_paths text[], total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION public.wiki_items_workspace(p_query text DEFAULT ''::text, p_item_kinds text[] DEFAULT ARRAY[]::text[], p_item_subtypes text[] DEFAULT ARRAY[]::text[], p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(record_source text, item_id uuid, canonical_item_id uuid, item_kind text, item_subtype text, title text, excerpt text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
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
  then
    raise exception using errcode = '22023', message = 'invalid_wiki_items_page';
  end if;

  return query
  with wiki_items as (
    select
      'entry'::text as record_source,
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
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype
      ) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
      and entry.inbox_status = 'organized'
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
    counted.record_source, counted.item_id, counted.canonical_item_id,
    counted.item_kind, counted.item_subtype, counted.title, counted.excerpt,
    counted.inbox_status, counted.occurred_start, counted.occurred_end,
    counted.updated_at, counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.record_source, counted.item_id
  limit p_limit offset p_offset;
end;
$function$;
