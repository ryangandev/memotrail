-- Collections are organization lenses over canonical Wiki Items. Preserve the
-- established rich Collection page contract while adding semantic identity and
-- the specialized record identity clients need for typed routing.

create function public.collection_wiki_items(
  p_collection_id uuid,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  collection_id uuid,
  collection_name text,
  total_count bigint,
  entry_id uuid,
  title text,
  body text,
  entry_type text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  created_at timestamptz,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[],
  attachments jsonb,
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
    page.collection_id,
    page.collection_name,
    page.total_count,
    page.entry_id,
    page.title,
    page.body,
    page.entry_type,
    page.inbox_status,
    page.occurred_start,
    page.occurred_end,
    page.date_precision,
    page.occurred_label,
    page.occurred_timezone,
    page.revision,
    page.created_at,
    page.updated_at,
    page.collection_names,
    page.tag_names,
    page.attachments,
    entry.item_kind,
    entry.item_subtype,
    case
      when person.id is not null then 'person'
      when place.id is not null then 'place'
      else 'entry'
    end as record_source,
    coalesce(person.id, place.id, page.entry_id) as record_id
  from public.collection_entries(p_collection_id, p_limit, p_offset) as page
  join public.entries as entry
    on entry.id = page.entry_id
    and entry.owner_id = auth.uid()
    and entry.deleted_at is null
  left join public.people as person
    on person.id = page.entry_id
    and person.owner_id = entry.owner_id
    and person.deleted_at is null
  left join public.places as place
    on place.id = page.entry_id
    and place.owner_id = entry.owner_id
    and place.deleted_at is null
  order by
    page.occurred_start desc nulls last,
    page.created_at desc,
    page.entry_id;
$$;

revoke all on function public.collection_wiki_items(uuid, integer, integer)
  from public, anon;
grant execute on function public.collection_wiki_items(uuid, integer, integer)
  to authenticated;

comment on function public.collection_wiki_items(uuid, integer, integer) is
  'Returns the established Collection page enriched with canonical Kind, subtype, and specialized routing identity.';
