-- Library only shows Entries after explicit Inbox organization.
begin;

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

commit;
