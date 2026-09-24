-- Remove authored Place records. Entry-owned Locations and their legacy physical
-- entry_places/homes.place_id links remain intact; those names refer to Location.
begin;

-- Independent Place records were test-only. Delete any old canonical mirrors
-- before tightening the Entity subtype contract.
delete from public.entries
where item_kind = 'entity' and item_subtype = 'place';

alter table public.entries add constraint entries_entity_subtype_valid
  check (item_kind <> 'entity' or item_subtype in ('person', 'home', 'vehicle'));

CREATE OR REPLACE FUNCTION public.archive_wiki_search_evidence(p_queries text[] DEFAULT '{}'::text[], p_item_classifications text[] DEFAULT '{}'::text[], p_collection_names text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_before_latest_home boolean DEFAULT false, p_order text DEFAULT 'relevance'::text, p_as_of date DEFAULT CURRENT_DATE)
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
  people_evidence jsonb := '[]'::jsonb;
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
    or cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
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
        p_collection_names,
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
      'collections', coalesce(collection_context.names, '[]'::jsonb),
      'tags', coalesce(tag_context.names, '[]'::jsonb),
      'facts', jsonb_strip_nulls(jsonb_build_object(
        'home', (select to_jsonb(home) from public.homes as home where home.entry_id = item.id),
        'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = item.id),
        'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = item.id),
        'person', (select to_jsonb(person) from public.people as person where person.id = item.id)
      )),
      'record_source', case
        when item.item_kind = 'entity' and item.item_subtype = 'person' then 'person'
        else 'entry'
      end,
      'record_id', item.id
    ) order by selected.ordinality
  ), '[]'::jsonb)
  into entry_evidence
  from unnest(selected_ids) with ordinality as selected(entry_id, ordinality)
  join public.entries as item
    on item.id = selected.entry_id and item.owner_id = evidence_owner_id
  left join lateral (
    select jsonb_agg(collection.name order by lower(collection.name), collection.id) as names
    from public.entry_collections as membership
    join public.collections as collection
      on collection.id = membership.collection_id
      and collection.owner_id = membership.owner_id
    where membership.entry_id = item.id
      and membership.owner_id = evidence_owner_id
      and collection.archived_at is null
  ) as collection_context on true
  left join lateral (
    select jsonb_agg(tag.name order by lower(tag.name), tag.id) as names
    from public.entry_tags as membership
    join public.tags as tag
      on tag.id = membership.tag_id and tag.owner_id = membership.owner_id
    where membership.entry_id = item.id and membership.owner_id = evidence_owner_id
  ) as tag_context on true;

  if cardinality(coalesce(p_collection_names, '{}'::text[])) = 0
    and cardinality(coalesce(p_tag_names, '{}'::text[])) = 0
    and p_date_from is null
    and p_date_to is null
    and not p_before_latest_home
  then
    if cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0
      or p_item_classifications && array['entity', 'person']::text[]
    then
      select coalesce(jsonb_agg(to_jsonb(person) order by lower(person.name), person.id), '[]'::jsonb)
      into people_evidence
      from public.people as person
      where person.owner_id = evidence_owner_id
        and person.deleted_at is null
        and exists (
          select 1
          from unnest(normalized_queries) as query
          where query <> ''
            and strpos(lower(concat_ws(' ', person.name, person.relationship_label, person.notes)), lower(query)) > 0
        );
    end if;

  end if;

  return jsonb_build_object(
    'entries', entry_evidence,
    'people', people_evidence,
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
  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.people
      where people.id=p_item_id and people.owner_id=trash_owner_id
        and people.revision=p_expected_revision and people.deleted_at=p_expected_deleted_at
        and not exists(select 1 from public.entry_people ep where ep.person_id=people.id)
      returning 'person'::text,people.id;
    return;
  end if;
  if p_item_kind = 'collection' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.collections
      where collections.id=p_item_id and collections.owner_id=trash_owner_id
        and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at
      returning 'collection'::text,collections.id;
    return;
  end if;
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$function$;

CREATE OR REPLACE FUNCTION public.export_dataset_names()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array[
    'profiles','entries','entry_versions','collections','tags','entry_collections','entry_tags',
    'locations','people','entry_locations','entry_people','timeline_tracks','timeline_items',
    'homes','vehicles','goals','attachments','entry_links','person_versions',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
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
      and not exists (
        select 1 from public.people as person
        where person.id = entry.id and person.owner_id = entry.owner_id
      )

    union all

    select 'attachment', attachment.id, attachment.deleted_at, null::integer
    from public.attachments as attachment
    join public.entries as entry
      on entry.id = attachment.entry_id and entry.owner_id = attachment.owner_id
    where attachment.owner_id = auth.uid()
      and attachment.deleted_at is not null
      and entry.deleted_at is null


    union all

    select 'person', person.id, person.deleted_at, person.revision
    from public.people as person
    where person.owner_id = auth.uid() and person.deleted_at is not null

    union all

    select 'collection', collection.id, collection.archived_at, collection.revision
    from public.collections as collection
    where collection.owner_id = auth.uid() and collection.archived_at is not null
  ),
  bounded as (
    select *
    from candidates
    order by
      case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
      item_kind,
      item_id
    limit 10001
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(bounded)
      order by
        case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
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

  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;
    return query update public.people set deleted_at = null
      where people.id = p_item_id and people.owner_id = trash_owner_id
        and people.revision = p_expected_revision and people.deleted_at = p_expected_deleted_at
      returning 'person'::text, people.id, people.revision;
    return;
  end if;

  if p_item_kind = 'collection' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    perform 1 from public.collections where collections.id=p_item_id and collections.owner_id=trash_owner_id
      and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at for no key update;
    if not found then return; end if;
    declare affected_id uuid;
    begin
      for affected_id in select e.id from public.entries e join public.entry_collections ec
        on ec.entry_id=e.id and ec.owner_id=e.owner_id where ec.collection_id=p_item_id
        and ec.owner_id=trash_owner_id order by e.id for update of e loop
        update public.entries set updated_at=clock_timestamp() where id=affected_id and owner_id=trash_owner_id;
      end loop;
    end;
    return query update public.collections set archived_at=null
      where collections.id=p_item_id and collections.owner_id=trash_owner_id
        and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at
      returning 'collection'::text,collections.id,collections.revision;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_collection_names text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, collection_names text[], tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text, record_source text, record_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
      join public.locations as related
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
      and not exists (
        select 1 from public.people as person
        where person.id = item.id and person.owner_id = item.owner_id
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
      case
        when person.id is not null then 'person'
        else 'entry'
      end::text as record_source,
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      coalesce(
        person.name,
        nullif(btrim(entry.title), ''),
        nullif(left(btrim(entry.body), 120), ''),
        'Untitled item'
      ) as title,
      left(btrim(case
        when person.id is not null then concat_ws(' · ', person.relationship_label, person.notes)
        else entry.body
      end), 240) as excerpt,
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype,
        person.name, person.relationship_label, person.notes
      ) as searchable
    from public.entries as entry
    left join public.people as person
      on person.id = entry.id
      and person.owner_id = entry.owner_id
      and person.deleted_at is null
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
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
drop function public.search_library_entities(text, integer, integer, text[]);
drop function public.places_workspace(integer, integer);
drop function public.save_place(text, text, text, text, text, numeric, numeric, text, uuid[], uuid, integer);
drop function public.trash_place(uuid, integer);

drop table public.place_versions;
drop table public.places;
drop function public.archive_place_version();

commit;
