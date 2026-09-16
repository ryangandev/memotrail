-- Search clients need canonical semantic identity and the specialized record
-- identity used to open Person and Place editors. Extend the established RPC
-- without changing its input signature or removing legacy result fields.

drop function public.search_entries_with_occurrence(
  text,
  text[],
  text[],
  text[],
  date,
  date,
  integer,
  integer
);

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
  date_precision text,
  item_kind text,
  item_subtype text,
  record_source text,
  record_id uuid
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    search_result.*,
    entry.date_precision,
    entry.item_kind,
    entry.item_subtype,
    case
      when person.id is not null then 'person'
      when place.id is not null then 'place'
      else 'entry'
    end as record_source,
    coalesce(person.id, place.id, search_result.entry_id) as record_id
  from public.search_entries_ordered(
    p_query,
    p_entry_types,
    p_collection_names,
    p_tag_names,
    p_date_from,
    p_date_to,
    p_limit,
    p_offset,
    'relevance'
  ) as search_result
  join public.entries as entry
    on entry.id = search_result.entry_id
    and entry.owner_id = auth.uid()
    and entry.deleted_at is null
  left join public.people as person
    on person.id = search_result.entry_id
    and person.owner_id = entry.owner_id
    and person.deleted_at is null
  left join public.places as place
    on place.id = search_result.entry_id
    and place.owner_id = entry.owner_id
    and place.deleted_at is null
  order by
    search_result.match_rank desc nulls last,
    coalesce(search_result.occurred_start, search_result.updated_at) desc nulls last,
    search_result.entry_id;
$$;

revoke all on function public.search_entries_with_occurrence(
  text,
  text[],
  text[],
  text[],
  date,
  date,
  integer,
  integer
) from public, anon;
grant execute on function public.search_entries_with_occurrence(
  text,
  text[],
  text[],
  text[],
  date,
  date,
  integer,
  integer
) to authenticated;

comment on function public.search_entries_with_occurrence(
  text,
  text[],
  text[],
  text[],
  date,
  date,
  integer,
  integer
) is
  'Searches canonical Wiki Items and returns semantic identity plus the specialized Person or Place record identity used for routing.';
