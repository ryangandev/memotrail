-- One browse surface spans canonical entries and the legacy Person and Place
-- registries while those Entity presets are migrated behind the same model.

create function public.wiki_items_workspace(
  p_query text default '',
  p_item_kinds text[] default array[]::text[],
  p_item_subtypes text[] default array[]::text[],
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  record_source text,
  item_id uuid,
  item_kind text,
  item_subtype text,
  title text,
  excerpt text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  workspace_owner_id uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(p_query, '')));
begin
  if workspace_owner_id is null then
    return;
  end if;

  if p_query is null
    or length(p_query) > 200
    or p_item_kinds is null
    or cardinality(p_item_kinds) > 6
    or exists (
      select 1 from unnest(p_item_kinds) as kind
      where kind not in ('capture', 'writing', 'entity', 'event', 'story', 'goal')
    )
    or p_item_subtypes is null
    or cardinality(p_item_subtypes) > 50
    or exists (
      select 1 from unnest(p_item_subtypes) as subtype
      where subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    )
    or p_limit is null
    or p_limit < 1
    or p_limit > 100
    or p_offset is null
    or p_offset < 0
    or p_offset > 100000
  then
    raise exception using errcode = '22023', message = 'invalid_wiki_items_page';
  end if;

  return query
  with wiki_items as (
    select
      'entry'::text as record_source,
      entry.id as item_id,
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
      concat_ws(' ', entry.title, entry.body, entry.item_kind, entry.item_subtype) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null

    union all

    select
      'person'::text,
      person.id,
      'entity'::text,
      'person'::text,
      person.name,
      left(btrim(concat_ws(' · ', person.relationship_label, person.notes)), 240),
      'organized'::text,
      null::timestamptz,
      null::timestamptz,
      person.updated_at,
      concat_ws(' ', person.name, person.relationship_label, person.notes, 'entity', 'person')
    from public.people as person
    where person.owner_id = workspace_owner_id
      and person.deleted_at is null

    union all

    select
      'place'::text,
      place.id,
      'entity'::text,
      'place'::text,
      place.name,
      left(btrim(concat_ws(' · ', place.address, place.city, place.region, place.country, place.notes)), 240),
      'organized'::text,
      null::timestamptz,
      null::timestamptz,
      place.updated_at,
      concat_ws(' ', place.name, place.address, place.city, place.region, place.country, place.notes, 'entity', 'place')
    from public.places as place
    where place.owner_id = workspace_owner_id
      and place.deleted_at is null
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
    counted.record_source,
    counted.item_id,
    counted.item_kind,
    counted.item_subtype,
    counted.title,
    counted.excerpt,
    counted.inbox_status,
    counted.occurred_start,
    counted.occurred_end,
    counted.updated_at,
    counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.record_source, counted.item_id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.wiki_items_workspace(text,text[],text[],integer,integer) from public, anon;
grant execute on function public.wiki_items_workspace(text,text[],text[],integer,integer) to authenticated;

comment on function public.wiki_items_workspace(text,text[],text[],integer,integer) is
  'Returns an owner-scoped Life Wiki browse page across Entries and the legacy Person and Place Entity registries.';
