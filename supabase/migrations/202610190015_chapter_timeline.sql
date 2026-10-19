-- Timeline and First Times read the two marks directly. Timeline lists the caller's Chapters
-- and First Times with the days each one covers, so the Web can draw a Chapter as a bar, a
-- First Time as a point, and unanchored items without a calendar position. A Chapter that is
-- also a First Time is one row. The First Times list gains a flag so a First Time Chapter can
-- show its span.

begin;

drop function public.timeline_workspace();
drop function public.first_times_workspace();

create function public.timeline_workspace()
returns table (
  entry_id uuid,
  title text,
  is_chapter boolean,
  is_first_time boolean,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  window_start date,
  window_end date,
  revision integer,
  updated_at timestamptz,
  tag_names text[]
)
language sql
stable
set search_path = ''
as $$
  select
    entries.id,
    coalesce(btrim(entries.title), ''),
    entries.item_subtype = 'chapter',
    entries.is_first_time,
    entries.occurred_start,
    entries.occurred_end,
    entries.date_precision,
    entries.occurred_label,
    coalesce(entries.occurred_timezone, 'UTC'),
    lower(dated.days),
    upper(dated.days),
    entries.revision,
    entries.updated_at,
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = entries.id and entry_tags.owner_id = entries.owner_id
      ),
      '{}'::text[]
    )
  from public.entries
  cross join lateral (
    select case
      when entries.item_subtype = 'chapter' then public.chapter_window(
        entries.occurred_start, entries.occurred_end, entries.date_precision, entries.occurred_timezone
      )
      else public.entry_date_window(
        entries.occurred_start, entries.occurred_end, entries.date_precision, entries.occurred_timezone
      )
    end as days
  ) as dated
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
    and (entries.item_subtype = 'chapter' or entries.is_first_time)
  order by
    lower(dated.days) nulls last,
    entries.occurred_start nulls last,
    lower(entries.title),
    entries.id;
$$;

create function public.first_times_workspace()
returns table (
  entry_id uuid,
  title text,
  is_chapter boolean,
  body text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  tag_names text[],
  attachments jsonb
)
language sql
stable
set search_path = ''
as $$
  select
    entries.id,
    coalesce(btrim(entries.title), ''),
    entries.item_subtype = 'chapter',
    entries.body,
    entries.occurred_start,
    entries.occurred_end,
    entries.date_precision,
    entries.occurred_label,
    entries.occurred_timezone,
    entries.revision,
    entries.updated_at,
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id
        where entry_tags.entry_id = entries.id
          and entry_tags.owner_id = entries.owner_id
      ),
      '{}'::text[]
    ),
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
        where media.entry_id = entries.id
          and media.owner_id = entries.owner_id
          and media.deleted_at is null and media.variant = 'original'
      ),
      '[]'::jsonb
    )
  from public.entries
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
    and entries.is_first_time
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$$;

revoke all on function public.timeline_workspace() from public, anon;
grant execute on function public.timeline_workspace() to authenticated, service_role;
revoke all on function public.first_times_workspace() from public, anon;
grant execute on function public.first_times_workspace() to authenticated, service_role;

commit;
