-- Library lists Entries by the date they happened, newest first, so it reads like a life
-- instead of an edit log. An Entry, a Chapter, or a First Time sorts by the start of its date
-- at whatever precision was recorded, so a Chapter sits where it began. Entries without a
-- calendar date come last, the most recently changed first. Editing an Entry no longer moves it.
--
-- search_wiki_items orders "newest" the same way, so Library's Chapters, First Times, tag, and
-- date filters keep that order. Before, an undated Entry sorted among dated ones by when it last
-- changed. Relevance and "oldest" are unchanged.
--
-- Both functions keep their arguments and columns, so iOS and the deployed Web call them as
-- before, and replacing them keeps their grants.

begin;

create or replace function public.wiki_items_workspace(p_query text default ''::text, p_item_kinds text[] default ARRAY[]::text[], p_item_subtypes text[] default ARRAY[]::text[], p_limit integer default 50, p_offset integer default 0)
 returns table(item_id uuid, canonical_item_id uuid, item_kind text, item_subtype text, is_first_time boolean, title text, excerpt text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, updated_at timestamp with time zone, total_count bigint)
language plpgsql
stable
set search_path = ''
as $$
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
      where kind <> 'entry'
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
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      entry.is_first_time,
      coalesce(btrim(entry.title), '') as title,
      left(btrim(entry.body), 240) as excerpt,
      entry.occurred_start,
      entry.occurred_end,
      entry.date_precision,
      entry.occurred_label,
      entry.occurred_timezone,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype
      ) as searchable
    from public.entries as entry
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
    counted.item_id, counted.canonical_item_id,
    counted.item_kind, counted.item_subtype, counted.is_first_time, counted.title, counted.excerpt,
    counted.occurred_start, counted.occurred_end,
    counted.date_precision, counted.occurred_label, counted.occurred_timezone,
    counted.updated_at, counted.total_count
  from counted
  order by counted.occurred_start desc nulls last, counted.updated_at desc, counted.item_id
  limit p_limit offset p_offset;
end;
$$;

create or replace function public.search_wiki_items(p_query text default ''::text, p_item_classifications text[] default '{}'::text[], p_tag_names text[] default '{}'::text[], p_date_from date default NULL::date, p_date_to date default NULL::date, p_limit integer default 50, p_offset integer default 0, p_order text default 'relevance'::text, p_query_embedding real[] default NULL::real[], p_embedding_model text default NULL::text, p_semantic_min_similarity real default 0.5)
 returns table(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text, is_first_time boolean, semantic_similarity real, semantic_char_start integer, semantic_char_end integer, semantic_chunk_count integer)
language plpgsql
stable
set search_path = ''
as $$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_classifications text[];
  normalized_tag_names text[];
  search_query tsquery;
  has_query boolean;
  has_filters boolean;
  semantic_active boolean;
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
  -- Meaning only joins a search that has words to look for.
  semantic_active := has_query
    and p_query_embedding is not null
    and p_embedding_model is not null;

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
        or ('entry' = any(normalized_classifications) and item.item_subtype = 'entry')
        or ('chapter' = any(normalized_classifications) and item.item_subtype = 'chapter')
        or ('first_time' = any(normalized_classifications) and item.is_first_time)
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
          item.item_subtype = 'chapter'
        ) && daterange(p_date_from, p_date_to, '[]')
      )
  ),
  semantic as (
    select
      ranked.ranked_entry_id as semantic_entry_id,
      ranked.ranked_similarity as semantic_score,
      ranked.ranked_start as semantic_start,
      ranked.ranked_end as semantic_end,
      ranked.ranked_chunks as semantic_chunks,
      ranked.ranked_position as semantic_rank
    from (
      select
        found.entry_id as ranked_entry_id,
        found.similarity as ranked_similarity,
        found.char_start as ranked_start,
        found.char_end as ranked_end,
        found.chunk_count as ranked_chunks,
        row_number() over (order by found.similarity desc, found.entry_id) as ranked_position
      -- The gate keeps the function from running at all for a keyword-only search.
      from (select 1 as gate where semantic_active) as gate
      cross join lateral public.semantic_entry_matches(
        p_query_embedding,
        p_embedding_model,
        p_semantic_min_similarity
      ) as found
      join owned_items as candidate on candidate.id = found.entry_id
    ) as ranked
    where ranked.ranked_position <= 50
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
        case when item.is_first_time then 'first time' end,
        (item.metadata - 'body_rich')::text,
        location_context.location_text,
        attachment_context.filename_text
      ) as structured_text
    from owned_items as item
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
  keyword_candidates as (
    select
      evaluated.*,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(ts_rank_cd(evaluated.search_document, search_query)::double precision, 0)
      ) as computed_match_rank,
      (
        evaluated.title_matches
        or evaluated.body_matches
        or evaluated.tag_matches
        or evaluated.date_matches
        or evaluated.structured_matches
      ) as keyword_matches
    from evaluated
  ),
  keyword_ranked as (
    select
      candidate.id as keyword_entry_id,
      rank() over (order by candidate.computed_match_rank desc) as keyword_rank
    from keyword_candidates as candidate
    where candidate.keyword_matches
  ),
  matched as (
    select
      candidate.*,
      case
        when not has_query then array['Filters']::text[]
        else array_remove(array[
          case when candidate.title_matches then 'Title' end,
          case when candidate.body_matches then 'Body' end,
          case when candidate.tag_matches then 'Tag' end,
          case when candidate.date_matches then 'Date' end,
          case when candidate.structured_matches then 'Details' end,
          case when semantic.semantic_entry_id is not null then 'Meaning' end
        ], null)
      end as computed_match_reasons,
      case
        when semantic_active then
          (
            coalesce(1.0 / (60 + keyword_ranked.keyword_rank), 0)
            + coalesce(1.0 / (60 + semantic.semantic_rank), 0)
          )::double precision
        else candidate.computed_match_rank
      end as fused_match_rank,
      semantic.semantic_score,
      semantic.semantic_start,
      semantic.semantic_end,
      semantic.semantic_chunks
    from keyword_candidates as candidate
    left join keyword_ranked on keyword_ranked.keyword_entry_id = candidate.id
    left join semantic on semantic.semantic_entry_id = candidate.id
    where not has_query
      or candidate.keyword_matches
      or semantic.semantic_entry_id is not null
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
    matched.fused_match_rank,
    count(*) over (),
    matched.date_precision,
    matched.item_kind,
    matched.item_subtype,
    matched.is_first_time,
    matched.semantic_score,
    matched.semantic_start,
    matched.semantic_end,
    matched.semantic_chunks
  from matched
  order by
    case when p_order = 'relevance' then matched.fused_match_rank end desc nulls last,
    case when p_order = 'oldest' then matched.occurred_start end asc nulls last,
    case when p_order = 'newest' then matched.occurred_start end desc nulls last,
    case when p_order <> 'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$$;

commit;
