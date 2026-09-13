-- Precision-aware date filters and index text shared by keyword and AI retrieval.
create function public.entry_occurrence_window(p_start timestamptz, p_end timestamptz, p_precision text, p_timezone text, p_type text)
returns daterange language plpgsql stable security invoker set search_path='' as $$
declare first_day date; last_day date; local_start timestamp; local_end timestamp;
begin
  if p_start is null or p_precision='unknown' or not isfinite(p_start) or (p_end is not null and not isfinite(p_end)) then return null; end if;
  local_start:=public.entry_local_timestamp(p_start,p_timezone);
  local_end:=public.entry_local_timestamp(coalesce(p_end,p_start),p_timezone);
  first_day:=case p_precision when 'year' then date_trunc('year',local_start)::date when 'month' then date_trunc('month',local_start)::date else local_start::date end;
  if p_end is null and (p_precision='range' or p_type in ('life_stage','home','vehicle')) then
    return daterange(first_day,null,'[)');
  end if;
  last_day:=case p_precision when 'year' then (date_trunc('year',local_end)+interval '1 year - 1 day')::date when 'month' then (date_trunc('month',local_end)+interval '1 month - 1 day')::date else local_end::date end;
  if last_day<first_day then return null; end if;
  return daterange(first_day,last_day,'[]');
end;
$$;

create function public.entry_occurrence_date_text(p_value timestamptz,p_precision text,p_timezone text)
returns text language plpgsql stable security invoker set search_path='' as $$
declare local_value timestamp;
begin
  if p_value is null or p_precision='unknown' or not isfinite(p_value) then return null; end if;
  local_value:=public.entry_local_timestamp(p_value,p_timezone);
  if p_precision='year' then return to_char(local_value,'YYYY'); end if;
  if p_precision='month' then return concat_ws(' ',to_char(local_value,'YYYY-MM'),btrim(to_char(local_value,'Month YYYY'))); end if;
  return concat_ws(' ',to_char(local_value,'YYYY-MM-DD'),to_char(local_value,'YYYY'),btrim(to_char(local_value,'Month DD YYYY')),to_char(local_value,'MM/DD/YYYY'));
end;
$$;
revoke all on function public.entry_occurrence_window(timestamptz,timestamptz,text,text,text), public.entry_occurrence_date_text(timestamptz,text,text) from public,anon;
grant execute on function public.entry_occurrence_window(timestamptz,timestamptz,text,text,text), public.entry_occurrence_date_text(timestamptz,text,text) to authenticated;

create or replace function public.search_entries_ordered(
  p_query text default '',
  p_entry_types text[] default '{}'::text[],
  p_collection_names text[] default '{}'::text[],
  p_tag_names text[] default '{}'::text[],
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_order text default 'relevance'
)
returns table (
  entry_id uuid,
  title text,
  body text,
  entry_type text,
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
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_entry_types text[];
  normalized_collection_names text[];
  normalized_tag_names text[];
  search_query tsquery;
  has_query boolean;
  has_filters boolean;
begin
  if p_order is null or p_order not in ('relevance','oldest','newest') then
    raise exception using errcode='22023',message='invalid_search_order';
  end if;
  if search_owner_id is null then
    return;
  end if;

  if length(coalesce(p_query, '')) > 200 then
    raise exception using errcode = '22023', message = 'query_too_long';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_pagination';
  end if;

  if (p_date_from is not null and not isfinite(p_date_from)) or (p_date_to is not null and not isfinite(p_date_to)) or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to) then
    raise exception using errcode = '22023', message = 'invalid_date_range';
  end if;

  if cardinality(coalesce(p_entry_types, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_entry_types, '{}'::text[])) as entry_type_filter
      where nullif(btrim(entry_type_filter), '') is null
        or length(btrim(entry_type_filter)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_entry_types';
  end if;

  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_filter
      where nullif(btrim(collection_filter), '') is null
        or length(btrim(collection_filter)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;

  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1
      from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_filter
      where nullif(btrim(tag_filter), '') is null
        or length(btrim(tag_filter)) > 60
    )
  then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  normalized_query := lower(btrim(coalesce(p_query, '')));
  normalized_entry_types := array(
    select distinct lower(btrim(entry_type_filter))
    from unnest(coalesce(p_entry_types, '{}'::text[])) as entry_type_filter
    order by lower(btrim(entry_type_filter))
  );
  normalized_collection_names := array(
    select distinct lower(btrim(collection_filter))
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_filter
    order by lower(btrim(collection_filter))
  );
  normalized_tag_names := array(
    select distinct lower(btrim(tag_filter))
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_filter
    order by lower(btrim(tag_filter))
  );
  has_query := normalized_query <> '';
  search_query := case
    when has_query then websearch_to_tsquery('simple', normalized_query)
    else null::tsquery
  end;
  has_filters := cardinality(normalized_entry_types) > 0
    or cardinality(normalized_collection_names) > 0
    or cardinality(normalized_tag_names) > 0
    or p_date_from is not null
    or p_date_to is not null;

  if not has_query and not has_filters then
    return;
  end if;

  return query
  with owned_entries as (
    select entries.*
    from public.entries as entries
    where entries.owner_id = search_owner_id
      and entries.deleted_at is null
      and (
        cardinality(normalized_entry_types) = 0
        or entries.entry_type = any(normalized_entry_types)
      )
      and (
        cardinality(normalized_collection_names) = 0
        or exists (
          select 1
          from public.entry_collections as entry_collections
          join public.collections as collections
            on collections.id = entry_collections.collection_id
            and collections.owner_id = entry_collections.owner_id
          where entry_collections.entry_id = entries.id
            and entry_collections.owner_id = search_owner_id
            and collections.archived_at is null
            and lower(collections.name) = any(normalized_collection_names)
        )
      )
      and (
        cardinality(normalized_tag_names) = 0
        or exists (
          select 1
          from public.entry_tags as entry_tags
          join public.tags as tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = search_owner_id
            and lower(tags.name) = any(normalized_tag_names)
        )
      )
  ),
  dated_entries as (
    select
      entries.*,
      public.entry_local_timestamp(
        entries.occurred_start,
        entries.occurred_timezone
      ) as local_occurred_start
    from owned_entries as entries
  ),
  filtered_entries as (
    select entries.*
    from dated_entries as entries
    where (p_date_from is null and p_date_to is null)
      or public.entry_occurrence_window(entries.occurred_start, entries.occurred_end,
        entries.date_precision, entries.occurred_timezone, entries.entry_type)
        && daterange(p_date_from, p_date_to, '[]')
  ),
  enriched as (
    select
      entries.*,
      entry_collections.collection_names,
      entry_collections.collection_text,
      entry_tags.tag_names,
      entry_tags.tag_text,
      concat_ws(' ', entries.occurred_label,
        public.entry_occurrence_date_text(entries.occurred_start, entries.date_precision, entries.occurred_timezone),
        public.entry_occurrence_date_text(entries.occurred_end, entries.date_precision, entries.occurred_timezone)) as date_text,
      concat_ws(
        ' ',
        replace(entries.entry_type, '_', ' '),
        entries.metadata::text,
        (
          select string_agg(
            concat_ws(' ', homes.move_in_reason, homes.move_out_reason, places.name,
              places.address, places.city, places.region, places.country, places.notes),
            ' '
          )
          from public.homes as homes
          left join public.places as places
            on places.id = homes.place_id
            and places.owner_id = homes.owner_id
          where homes.entry_id = entries.id
            and homes.owner_id = search_owner_id
        ),
        (
          select string_agg(
            concat_ws(' ', vehicles.make, vehicles.model, vehicles.model_year::text, vehicles.color),
            ' '
          )
          from public.vehicles as vehicles
          where vehicles.entry_id = entries.id
            and vehicles.owner_id = search_owner_id
        ),
        (
          select string_agg(
            concat_ws(' ', replace(goals.horizon, '_', ' '), goals.status, goals.target_date::text),
            ' '
          )
          from public.goals as goals
          where goals.entry_id = entries.id
            and goals.owner_id = search_owner_id
        ),
        (
          select string_agg(
            concat_ws(' ', timeline_tracks.name, replace(timeline_items.timeline_kind, '_', ' ')),
            ' '
          )
          from public.timeline_items as timeline_items
          join public.timeline_tracks as timeline_tracks
            on timeline_tracks.id = timeline_items.track_id
            and timeline_tracks.owner_id = timeline_items.owner_id
          where timeline_items.entry_id = entries.id
            and timeline_items.owner_id = search_owner_id
        ),
        (
          select string_agg(
            concat_ws(' ', places.name, places.address, places.city, places.region,
              places.country, places.notes, entry_places.relationship),
            ' '
          )
          from public.entry_places as entry_places
          join public.places as places
            on places.id = entry_places.place_id
            and places.owner_id = entry_places.owner_id
          where entry_places.entry_id = entries.id
            and entry_places.owner_id = search_owner_id
        ),
        (
          select string_agg(
            concat_ws(' ', people.name, people.relationship_label, people.notes,
              entry_people.relationship),
            ' '
          )
          from public.entry_people as entry_people
          join public.people as people
            on people.id = entry_people.person_id
            and people.owner_id = entry_people.owner_id
          where entry_people.entry_id = entries.id
            and entry_people.owner_id = search_owner_id
        ),
        (
          select string_agg(attachments.original_filename, ' ')
          from public.attachments as attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = search_owner_id
        )
      ) as structured_text
    from filtered_entries as entries
    left join lateral (
      select
        coalesce(
          array_agg(collections.name order by lower(collections.name), collections.name),
          '{}'::text[]
        ) as collection_names,
        coalesce(string_agg(collections.name, ' '), '') as collection_text
      from public.entry_collections as relationships
      join public.collections as collections
        on collections.id = relationships.collection_id
        and collections.owner_id = relationships.owner_id
      where relationships.entry_id = entries.id
        and relationships.owner_id = search_owner_id
        and collections.archived_at is null
    ) as entry_collections on true
    left join lateral (
      select
        coalesce(
          array_agg(tags.name order by lower(tags.name), tags.name),
          '{}'::text[]
        ) as tag_names,
        coalesce(string_agg(tags.name, ' '), '') as tag_text
      from public.entry_tags as relationships
      join public.tags as tags
        on tags.id = relationships.tag_id
        and tags.owner_id = relationships.owner_id
      where relationships.entry_id = entries.id
        and relationships.owner_id = search_owner_id
    ) as entry_tags on true
  ),
  evaluated as (
    select
      enriched.*,
      has_query and (
        position(normalized_query in lower(coalesce(enriched.title, ''))) > 0
        or to_tsvector('simple', coalesce(enriched.title, '')) @@ search_query
      )
        as title_matches,
      has_query and (
        position(normalized_query in lower(enriched.body)) > 0
        or to_tsvector('simple', enriched.body) @@ search_query
      )
        as body_matches,
      has_query and (
        position(normalized_query in lower(enriched.collection_text)) > 0
        or to_tsvector('simple', enriched.collection_text) @@ search_query
      )
        as collection_matches,
      has_query and (
        position(normalized_query in lower(enriched.tag_text)) > 0
        or to_tsvector('simple', enriched.tag_text) @@ search_query
      )
        as tag_matches,
      has_query and (
        position(normalized_query in lower(enriched.date_text)) > 0
        or to_tsvector('simple', enriched.date_text) @@ search_query
      )
        as date_matches,
      has_query and (
        position(normalized_query in lower(enriched.structured_text)) > 0
        or to_tsvector('simple', enriched.structured_text) @@ search_query
      )
        as structured_matches
    from enriched
  ),
  matched as (
    select
      evaluated.*,
      case
        when not has_query then array['Filters']::text[]
        else array_remove(
          array[
            case when evaluated.title_matches then 'Title' end,
            case when evaluated.body_matches then 'Body' end,
            case when evaluated.collection_matches then 'Collection' end,
            case when evaluated.tag_matches then 'Tag' end,
            case when evaluated.date_matches then 'Date' end,
            case when evaluated.structured_matches then 'Details' end
          ],
          null
        )
      end as computed_match_reasons,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.collection_matches then 3 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(
          ts_rank_cd(evaluated.search_document, search_query)::double precision,
          0
        )
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
    matched.entry_type,
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
    count(*) over ()
  from matched
  order by
    case when p_order='relevance' then matched.computed_match_rank end desc nulls last,
    case when p_order='oldest' then matched.occurred_start end asc nulls last,
    case when p_order<>'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text) from public,anon;
grant execute on function public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text) to authenticated;

create function public.search_entries_with_occurrence(
  p_query text default '',
  p_entry_types text[] default '{}'::text[],
  p_collection_names text[] default '{}'::text[],
  p_tag_names text[] default '{}'::text[],
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  entry_id uuid,
  title text,
  body text,
  entry_type text,
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
  date_precision text
)
language sql stable security invoker set search_path='' as $$
  select s.*, e.date_precision from public.search_entries_ordered(p_query,p_entry_types,p_collection_names,p_tag_names,p_date_from,p_date_to,p_limit,p_offset,'relevance') s
  join public.entries e on e.id=s.entry_id and e.owner_id=auth.uid() and e.deleted_at is null
  order by s.match_rank desc nulls last, coalesce(s.occurred_start,s.updated_at) desc nulls last, s.entry_id;
$$;

revoke all on function public.search_entries_with_occurrence(text,text[],text[],text[],date,date,integer,integer) from public,anon;
grant execute on function public.search_entries_with_occurrence(text,text[],text[],text[],date,date,integer,integer) to authenticated;
