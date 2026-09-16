-- Preserve the bounded AI evidence behavior on top of canonical Wiki Item
-- identity. This replaces the old Entry-type archive contract without
-- restoring any legacy column or RPC.

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
  place_evidence jsonb := '[]'::jsonb;
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
            then array['writing', 'event', 'story', 'entity', 'goal']::text[]
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
        'person', (select to_jsonb(person) from public.people as person where person.id = item.id),
        'place', (select to_jsonb(place) from public.places as place where place.id = item.id)
      )),
      'record_source', case
        when item.item_kind = 'entity' and item.item_subtype = 'person' then 'person'
        when item.item_kind = 'entity' and item.item_subtype = 'place' then 'place'
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

    if cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0
      or p_item_classifications && array['entity', 'place']::text[]
    then
      select coalesce(jsonb_agg(to_jsonb(place) order by lower(place.name), place.id), '[]'::jsonb)
      into place_evidence
      from public.places as place
      where place.owner_id = evidence_owner_id
        and place.deleted_at is null
        and exists (
          select 1
          from unnest(normalized_queries) as query
          where query <> ''
            and strpos(lower(concat_ws(' ', place.name, place.address, place.city, place.region, place.country, place.notes)), lower(query)) > 0
        );
    end if;
  end if;

  return jsonb_build_object(
    'entries', entry_evidence,
    'people', people_evidence,
    'places', place_evidence,
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

revoke all on function public.archive_wiki_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date) from public, anon;
grant execute on function public.archive_wiki_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date) to authenticated;

comment on function public.archive_wiki_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date) is
  'Returns bounded owner-scoped AI evidence using canonical Wiki Item Kind and subtype identity.';
