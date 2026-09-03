create index if not exists collections_owner_active_sort_idx
  on public.collections (owner_id, sort_order, lower(name), id)
  where archived_at is null;

create index if not exists entry_collections_owner_collection_entry_idx
  on public.entry_collections (owner_id, collection_id, entry_id);

create or replace function public.collections_workspace()
returns table (
  collection_id uuid,
  name text,
  system_key text,
  color text,
  sort_order integer,
  entry_count bigint,
  unreviewed_count bigint,
  latest_entry_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    collections.id,
    collections.name,
    collections.system_key,
    collections.color,
    collections.sort_order,
    count(entries.id),
    count(entries.id) filter (where entries.inbox_status = 'unreviewed'),
    max(coalesce(entries.occurred_start, entries.created_at)),
    collections.created_at,
    collections.updated_at
  from public.collections
  left join public.entry_collections
    on entry_collections.collection_id = collections.id
    and entry_collections.owner_id = collections.owner_id
  left join public.entries
    on entries.id = entry_collections.entry_id
    and entries.owner_id = entry_collections.owner_id
    and entries.deleted_at is null
  where collections.owner_id = auth.uid()
    and collections.archived_at is null
  group by collections.id
  order by collections.sort_order, lower(collections.name), collections.id;
$$;

revoke all on function public.collections_workspace() from public, anon;
grant execute on function public.collections_workspace() to authenticated;

comment on function public.collections_workspace() is
  'Returns every active Collection owned by the authenticated user with non-Trash Entry counts and recency.';

create or replace function public.collection_entries(
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
  attachments jsonb
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'invalid_collection_limit';
  end if;

  if p_offset is null or p_offset < 0 or p_offset > 10000 then
    raise exception using errcode = '22023', message = 'invalid_collection_offset';
  end if;

  return query
  with visible_entries as (
    select
      collections.id as collection_id,
      collections.name as collection_name,
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.entry_type,
      entries.inbox_status,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.created_at,
      entries.updated_at
    from public.collections
    join public.entry_collections
      on entry_collections.collection_id = collections.id
      and entry_collections.owner_id = collections.owner_id
    join public.entries
      on entries.id = entry_collections.entry_id
      and entries.owner_id = entry_collections.owner_id
    where collections.id = p_collection_id
      and collections.owner_id = auth.uid()
      and collections.archived_at is null
      and entries.deleted_at is null
  )
  select
    visible_entries.collection_id,
    visible_entries.collection_name,
    count(*) over () as total_count,
    visible_entries.entry_id,
    visible_entries.title,
    visible_entries.body,
    visible_entries.entry_type,
    visible_entries.inbox_status,
    visible_entries.occurred_start,
    visible_entries.occurred_end,
    visible_entries.date_precision,
    visible_entries.occurred_label,
    visible_entries.occurred_timezone,
    visible_entries.revision,
    visible_entries.created_at,
    visible_entries.updated_at,
    coalesce(
      (
        select array_agg(linked_collections.name order by lower(linked_collections.name), linked_collections.id)
        from public.entry_collections as all_entry_collections
        join public.collections as linked_collections
          on linked_collections.id = all_entry_collections.collection_id
          and linked_collections.owner_id = all_entry_collections.owner_id
        where all_entry_collections.entry_id = visible_entries.entry_id
          and all_entry_collections.owner_id = auth.uid()
          and linked_collections.archived_at is null
      ),
      '{}'::text[]
    ) as collection_names,
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags
          on tags.id = entry_tags.tag_id
          and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = visible_entries.entry_id
          and entry_tags.owner_id = auth.uid()
      ),
      '{}'::text[]
    ) as tag_names,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', media.id,
            'parentAttachmentId', media.parent_attachment_id,
            'variant', media.variant,
            'bucketId', media.bucket_id,
            'objectPath', media.object_path,
            'originalFilename', media.original_filename,
            'mimeType', media.mime_type,
            'byteSize', media.byte_size,
            'pixelWidth', media.pixel_width,
            'pixelHeight', media.pixel_height,
            'createdAt', media.created_at
          )
          order by media.created_at, media.id
        )
        from public.attachments as media
        where media.entry_id = visible_entries.entry_id
          and media.owner_id = auth.uid()
          and media.deleted_at is null
      ),
      '[]'::jsonb
    ) as attachments
  from visible_entries
  order by
    visible_entries.occurred_start desc nulls last,
    visible_entries.created_at desc,
    visible_entries.entry_id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.collection_entries(uuid, integer, integer) from public, anon;
grant execute on function public.collection_entries(uuid, integer, integer) to authenticated;

comment on function public.collection_entries(uuid, integer, integer) is
  'Returns one owned active Collection page with enriched non-Trash Entries, organization, and active private attachment metadata.';
