-- Shared, read-only retrieval evidence for Web and native clients.
-- Retain the legacy keyword RPC while selecting chronological candidates before LIMIT.
-- This is an evidence contract, not model orchestration or vector search.
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

  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then
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
    where (
        p_date_from is null
        or entries.local_occurred_start::date >= p_date_from
      )
      and (
        p_date_to is null
        or entries.local_occurred_start::date <= p_date_to
      )
  ),
  enriched as (
    select
      entries.*,
      entry_collections.collection_names,
      entry_collections.collection_text,
      entry_tags.tag_names,
      entry_tags.tag_text,
      concat_ws(
        ' ',
        entries.occurred_label,
        case
          when entries.local_occurred_start is null then null
          else to_char(entries.local_occurred_start, 'YYYY-MM-DD')
        end,
        case
          when entries.local_occurred_start is null then null
          else to_char(entries.local_occurred_start, 'YYYY')
        end,
        case
          when entries.local_occurred_start is null then null
          else btrim(to_char(entries.local_occurred_start, 'Month DD YYYY'))
        end,
        case
          when entries.local_occurred_start is null then null
          else to_char(entries.local_occurred_start, 'MM/DD/YYYY')
        end
      ) as date_text,
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

create or replace function public.search_entries(
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
  total_count bigint
)
language sql stable security invoker set search_path='' as $$
  select * from public.search_entries_ordered(p_query,p_entry_types,p_collection_names,p_tag_names,p_date_from,p_date_to,p_limit,p_offset,'relevance');
$$;

-- Read-only, owner-scoped evidence for both search clients. Models never emit SQL.
create function public.archive_entry_sources(p_entry_ids uuid[]) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if cardinality(p_entry_ids) > 40 then
    raise exception using errcode='22023',message='too_many_sources';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'title',e.title,'body',e.body,'entry_type',e.entry_type,
    'inbox_status',e.inbox_status,'revision',e.revision,'created_at',e.created_at,
    'occurred_start',e.occurred_start,'occurred_end',e.occurred_end,
    'date_precision',e.date_precision,'occurred_label',e.occurred_label,'occurred_timezone',e.occurred_timezone,
    'collections',coalesce((select jsonb_agg(c.name order by c.name) from public.entry_collections ec join public.collections c on c.id=ec.collection_id and c.owner_id=ec.owner_id where ec.entry_id=e.id and ec.owner_id=auth.uid() and c.archived_at is null),'[]'),
    'tags',coalesce((select jsonb_agg(t.name order by t.name) from public.entry_tags et join public.tags t on t.id=et.tag_id and t.owner_id=et.owner_id where et.entry_id=e.id and et.owner_id=auth.uid()),'[]'),
    'facts',jsonb_strip_nulls(jsonb_build_object(
      'home',(select to_jsonb(h)-'owner_id'-'entry_id'-'created_at'-'updated_at' from public.homes h where h.entry_id=e.id and h.owner_id=auth.uid()),
      'home_place',(select jsonb_build_object('name',p.name,'address',p.address,'city',p.city,'region',p.region,'country',p.country,'notes',p.notes) from public.homes h join public.places p on p.id=h.place_id and p.owner_id=h.owner_id where h.entry_id=e.id and h.owner_id=auth.uid() and p.deleted_at is null),
      'vehicle',(select to_jsonb(v)-'owner_id'-'entry_id'-'created_at'-'updated_at' from public.vehicles v where v.entry_id=e.id and v.owner_id=auth.uid()),
      'goal',(select to_jsonb(g)-'owner_id'-'entry_id'-'created_at'-'updated_at' from public.goals g where g.entry_id=e.id and g.owner_id=auth.uid()),
      'people',(select jsonb_agg(jsonb_build_object('name',p.name,'relationship',ep.relationship,'relationship_label',p.relationship_label,'notes',p.notes) order by p.name) from public.entry_people ep join public.people p on p.id=ep.person_id and p.owner_id=ep.owner_id where ep.entry_id=e.id and ep.owner_id=auth.uid() and p.deleted_at is null),
      'places',(select jsonb_agg(jsonb_build_object('name',p.name,'relationship',ep.relationship,'address',p.address,'city',p.city,'region',p.region,'country',p.country,'notes',p.notes) order by p.name) from public.entry_places ep join public.places p on p.id=ep.place_id and p.owner_id=ep.owner_id where ep.entry_id=e.id and ep.owner_id=auth.uid() and p.deleted_at is null),
      'timeline',(select jsonb_agg(jsonb_build_object('track',t.name,'kind',i.timeline_kind) order by t.name,t.id) from public.timeline_items i join public.timeline_tracks t on t.id=i.track_id and t.owner_id=i.owner_id where i.entry_id=e.id and i.owner_id=auth.uid())
    ))
  ) order by array_position(p_entry_ids,e.id)),'[]') into result
  from public.entries e where e.id=any(p_entry_ids) and e.owner_id=auth.uid() and e.deleted_at is null;
  return result;
end;
$$;

-- Count scheduled days without expanding a potentially decades-long daily series.
create function public.habit_scheduled_day_count(p_schedule jsonb,p_starts_on date,p_ends_on date,p_from date,p_to date)
returns integer language plpgsql immutable security invoker set search_path='' as $$
declare first_day date:=greatest(p_starts_on,p_from); last_day date:=least(coalesce(p_ends_on,p_to),p_to); days integer; every_days integer; result integer;
begin
  if p_starts_on is null or p_from is null or p_to is null or not public.habit_schedule_is_valid(p_schedule)
    or not isfinite(first_day) or not isfinite(last_day) or last_day<first_day then return 0;end if;
  days:=last_day-first_day+1;
  case p_schedule->>'kind'
    when 'daily' then return days;
    when 'interval' then
      every_days:=(p_schedule->>'every_days')::integer;
      return (last_day-p_starts_on)/every_days - (first_day-p_starts_on+every_days-1)/every_days + 1;
    when 'weekdays' then
      select (days/7)*jsonb_array_length(p_schedule->'weekdays') + count(*)::integer into result
      from generate_series(0,(days%7)-1) n
      where (extract(isodow from first_day+n)::integer)::text in (select value#>>'{}' from jsonb_array_elements(p_schedule->'weekdays'));
      return result;
    else return 0;
  end case;
end;
$$;

create function public.archive_habit_evidence(p_from date default null,p_to date default null,p_as_of date default current_date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_as_of is null or not isfinite(p_as_of) or (p_from is not null and not isfinite(p_from)) or (p_to is not null and not isfinite(p_to)) or (p_from is not null and p_to is not null and p_from>p_to) then
    raise exception using errcode='22023',message='invalid_evidence_dates';end if;
  with owned as (
    select h.*,greatest(h.starts_on,coalesce(p_from,h.starts_on)) as date_from,
      least(coalesce(p_to,p_as_of),p_as_of,coalesce(h.ends_on,p_as_of)) as date_to
    from public.habits h where h.owner_id=auth.uid() and h.archived_at is null and h.deleted_at is null
  ), bounded as (
    select h.*,date_from+((8-extract(isodow from date_from)::integer)%7) as first_monday,
      least(date_to,p_as_of-1)-(extract(isodow from least(date_to,p_as_of-1))::integer%7) as last_sunday
    from owned h where date_from<=date_to
  ), stats as (
    select h.id,h.name,h.revision,h.tracking_mode,h.measurement_unit,h.target_value,h.schedule,h.date_from,h.date_to,
      coalesce(log.completed,0) as completed_days,coalesce(log.skipped,0) as skipped_days,
      coalesce(log.explicit_missed,0) as recorded_missed_days,
      case when h.schedule->>'kind'='weekly_target' then null else
        greatest(0,public.habit_scheduled_day_count(h.schedule,h.starts_on,h.ends_on,h.date_from,least(h.date_to,p_as_of-1))-coalesce(log.excused_scheduled,0)) + coalesce(log.additional_misses,0)
      end as missed_days,
      case when h.schedule->>'kind'='weekly_target' then greatest(0,(h.last_sunday-h.first_monday+1)/7) else null end as complete_weeks,
      case when h.schedule->>'kind'='weekly_target' then greatest(0,(h.last_sunday-h.first_monday+1)/7)-coalesce(weeks.met,0) else null end as shortfall_weeks,
      case when h.schedule->>'kind'='weekly_target' then greatest(0,(h.last_sunday-h.first_monday+1)/7)*(h.schedule->>'target')::integer-coalesce(weeks.credited,0) else null end as missing_weekly_completions,
      coalesce(log.linked_entry_ids,'[]') as linked_entry_ids
    from bounded h
    left join lateral (
      select count(*) filter(where o.status='completed')::integer as completed,
        count(*) filter(where o.status='skipped')::integer as skipped,
        count(*) filter(where o.status='missed')::integer as explicit_missed,
        count(*) filter(where o.local_date<p_as_of and o.status in ('completed','skipped','not_scheduled') and public.habit_is_scheduled(h.schedule,h.starts_on,h.ends_on,o.local_date))::integer as excused_scheduled,
        count(*) filter(where o.status='missed' and (o.local_date=p_as_of or not public.habit_is_scheduled(h.schedule,h.starts_on,h.ends_on,o.local_date)))::integer as additional_misses,
        to_jsonb((array_agg(distinct e.id) filter(where e.id is not null))[1:20]) as linked_entry_ids
      from public.habit_occurrences o left join public.entries e on e.id=o.entry_id and e.owner_id=o.owner_id and e.deleted_at is null
      where o.habit_id=h.id and o.owner_id=auth.uid() and o.local_date between h.date_from and h.date_to
    ) log on true
    left join lateral (
      select count(*) filter(where completed >= (h.schedule->>'target')::integer)::integer as met,
        sum(least(completed,(h.schedule->>'target')::integer))::integer as credited
      from (select date_trunc('week',o.local_date) as week,count(*)::integer as completed
        from public.habit_occurrences o where o.habit_id=h.id and o.owner_id=auth.uid() and o.status='completed'
          and o.local_date between h.first_monday and h.last_sunday group by 1) counts
    ) weeks on h.schedule->>'kind'='weekly_target'
  )
  select jsonb_build_object('total_count',(select count(*) from stats),'habits',coalesce((select jsonb_agg(to_jsonb(s) order by s.name,s.id) from (select * from stats order by name,id limit 50) s),'[]'),
    'as_of',p_as_of,'scope','Active Habits; missed days exclude today unless explicitly recorded. Weekly shortfalls count only complete Monday-Sunday weeks within the selected period. Skips are not misses.') into result;
  return result;
end;
$$;

create function public.archive_search_evidence(
  p_queries text[] default '{}',p_entry_types text[] default '{}',p_collection_names text[] default '{}',p_tag_names text[] default '{}',
  p_date_from date default null,p_date_to date default null,p_before_latest_home boolean default false,p_include_habits boolean default false,
  p_order text default 'relevance',p_as_of date default current_date
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare queries text[]; selected_ids uuid[]; total integer; query_truncated boolean:=false; latest_home public.entries; effective_to date:=p_date_to; reference_applied boolean:=false; result jsonb;
begin
  if auth.uid() is null then return null;end if;
  if p_order is null or p_order not in ('relevance','oldest','newest') or p_as_of is null or not isfinite(p_as_of)
    or cardinality(p_queries)>6 or exists(select 1 from unnest(p_queries) q where q is null or length(btrim(q))>200)
    or (p_date_from is not null and not isfinite(p_date_from)) or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from>p_date_to) then
    raise exception using errcode='22023',message='invalid_evidence_request';end if;
  queries:=case when coalesce(cardinality(p_queries),0)=0 then array[''] else p_queries end;
  if p_before_latest_home then
    select e.* into latest_home from public.entries e join public.homes h on h.entry_id=e.id and h.owner_id=e.owner_id
      where e.owner_id=auth.uid() and e.deleted_at is null and e.occurred_start is not null
        and public.entry_local_timestamp(e.occurred_start,e.occurred_timezone)::date<=p_as_of
      order by e.occurred_start desc,e.id limit 1;
    if latest_home.id is not null and latest_home.date_precision in ('exact','day') then
      effective_to:=least(coalesce(p_date_to,p_as_of),public.entry_local_timestamp(latest_home.occurred_start,latest_home.occurred_timezone)::date-1);
      reference_applied:=true;
    end if;
  end if;
  if p_date_from is not null and effective_to is not null and p_date_from>effective_to then selected_ids:='{}';total:=0;
  else
    with hits as (
      select s.entry_id,max(s.match_rank) as rank,max(s.occurred_start) as occurred_start,max(s.updated_at) as updated_at,bool_or(s.total_count>100) as query_truncated
      from unnest(queries) q cross join lateral public.search_entries_ordered(q,
        case when coalesce(cardinality(p_entry_types),0)=0 and q='' then array['standard','first_time','life_stage','home','vehicle','goal'] else p_entry_types end,
        p_collection_names,p_tag_names,p_date_from,effective_to,100,0,p_order) s group by s.entry_id
    ), selected as (
      select * from hits order by
        case when p_order='relevance' then rank end desc nulls last,
        case when p_order='oldest' then occurred_start end asc nulls last,
        case when p_order<>'oldest' then coalesce(occurred_start,updated_at) end desc nulls last,entry_id limit 36
    ) select coalesce(array_agg(entry_id order by
        case when p_order='relevance' then rank end desc nulls last,
        case when p_order='oldest' then occurred_start end asc nulls last,
        case when p_order<>'oldest' then coalesce(occurred_start,updated_at) end desc nulls last,entry_id),'{}'),
      (select count(*) from hits),coalesce((select bool_or(hits.query_truncated) from hits),false)
      into selected_ids,total,query_truncated from selected;
  end if;
  result:=jsonb_build_object('entries',public.archive_entry_sources(selected_ids),'candidate_count',total,'query_truncated',query_truncated,'query_limit',100,'source_limit',36,
    'queries',queries,'effective_date_to',effective_to,'latest_home_reference',case when latest_home.id is null then null else public.archive_entry_sources(array[latest_home.id])->0 end,
    'reference_window_applied',reference_applied,'habits',case when p_include_habits and coalesce(cardinality(p_entry_types),0)=0 and coalesce(cardinality(p_collection_names),0)=0 and coalesce(cardinality(p_tag_names),0)=0 then public.archive_habit_evidence(p_date_from,p_date_to,p_as_of) else null end);
  if coalesce(cardinality(p_entry_types),0)=0 and coalesce(cardinality(p_collection_names),0)=0 and coalesce(cardinality(p_tag_names),0)=0 and p_date_from is null and p_date_to is null and not p_before_latest_home then
    result:=result||jsonb_build_object(
      'people',coalesce((select jsonb_agg(to_jsonb(p)) from (select id,name,relationship_label,notes,revision from public.people p where p.owner_id=auth.uid() and p.deleted_at is null and exists(select 1 from unnest(queries) q where btrim(q)<>'' and strpos(lower(concat_ws(' ',p.name,p.relationship_label,p.notes)),lower(btrim(q)))>0) order by name,id limit 25) p),'[]'),
      'places',coalesce((select jsonb_agg(to_jsonb(p)) from (select id,name,address,city,region,country,notes,revision from public.places p where p.owner_id=auth.uid() and p.deleted_at is null and exists(select 1 from unnest(queries) q where btrim(q)<>'' and strpos(lower(concat_ws(' ',p.name,p.address,p.city,p.region,p.country,p.notes)),lower(btrim(q)))>0) order by name,id limit 25) p),'[]'));
  else result:=result||jsonb_build_object('people','[]'::jsonb,'places','[]'::jsonb);end if;
  return result;
end;
$$;

revoke all on function public.archive_entry_sources(uuid[]) from public,anon;
revoke all on function public.habit_scheduled_day_count(jsonb,date,date,date,date) from public,anon;
revoke all on function public.archive_habit_evidence(date,date,date) from public,anon;
revoke all on function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date) from public,anon;
grant execute on function public.archive_entry_sources(uuid[]) to authenticated;
grant execute on function public.habit_scheduled_day_count(jsonb,date,date,date,date) to authenticated;
grant execute on function public.archive_habit_evidence(date,date,date) to authenticated;
grant execute on function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date) to authenticated;
