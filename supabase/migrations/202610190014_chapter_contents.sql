-- What a Chapter contains is read, never stored. An Entry is inside a Chapter when the
-- Chapter's days contain all of the Entry's days, each read in its own recorded time zone, so
-- a year the Chapter covers only in part is not counted inside. Chapters are never listed
-- inside another Chapter; chapter_overlaps lists the Chapters that share any day with this
-- one, so nested and partly overlapping Chapters both show there.

begin;

create function public.chapter_entries(
  p_chapter_id uuid,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  entry_id uuid,
  title text,
  excerpt text,
  is_first_time boolean,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  tag_names text[],
  cover_photo jsonb,
  total_count bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  chapter_days daterange;
begin
  if reader_id is null then
    return;
  end if;
  if p_chapter_id is null
    or p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 100000
  then
    raise exception using errcode = '22023', message = 'invalid_chapter_page';
  end if;

  select public.chapter_window(
    chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone
  )
  into chapter_days
  from public.entries as chapter
  where chapter.id = p_chapter_id
    and chapter.owner_id = reader_id
    and chapter.item_subtype = 'chapter'
    and chapter.deleted_at is null;

  if chapter_days is null then
    return;
  end if;

  return query
  with members as (
    select
      entry.id,
      entry.title,
      entry.body,
      entry.is_first_time,
      entry.occurred_start,
      entry.occurred_end,
      entry.date_precision,
      entry.occurred_label,
      entry.occurred_timezone,
      entry.created_at,
      dated.days
    from public.entries as entry
    cross join lateral (
      select public.entry_date_window(
        entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone
      ) as days
    ) as dated
    where entry.owner_id = reader_id
      and entry.deleted_at is null
      and entry.item_subtype = 'entry'
      and entry.id <> p_chapter_id
      and chapter_days @> dated.days
  ),
  counted as (
    select members.*, count(*) over () as total_count
    from members
  )
  select
    counted.id,
    coalesce(btrim(counted.title), ''),
    left(btrim(counted.body), 240),
    counted.is_first_time,
    counted.occurred_start,
    counted.occurred_end,
    counted.date_precision,
    counted.occurred_label,
    coalesce(counted.occurred_timezone, 'UTC'),
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags
          on tags.id = entry_tags.tag_id
          and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = counted.id
          and entry_tags.owner_id = reader_id
      ),
      '{}'::text[]
    ),
    (
      select jsonb_build_object(
        'attachment_id', attachments.id,
        'bucket_id', attachments.bucket_id,
        'object_path', attachments.object_path,
        'original_filename', attachments.original_filename,
        'mime_type', attachments.mime_type,
        'byte_size', attachments.byte_size,
        'pixel_width', attachments.pixel_width,
        'pixel_height', attachments.pixel_height
      )
      from public.attachments
      where attachments.entry_id = counted.id
        and attachments.owner_id = reader_id
        and attachments.deleted_at is null
        and attachments.variant = 'original'
        and attachments.mime_type like 'image/%'
      order by attachments.created_at, attachments.id
      limit 1
    ),
    counted.total_count
  from counted
  order by lower(counted.days), counted.occurred_start, counted.created_at, counted.id
  limit p_limit offset p_offset;
end;
$$;

create function public.chapter_overlaps(p_chapter_id uuid)
returns table (
  entry_id uuid,
  title text,
  is_first_time boolean,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  window_start date,
  window_end date
)
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  chapter_days daterange;
begin
  if reader_id is null or p_chapter_id is null then
    return;
  end if;

  select public.chapter_window(
    chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone
  )
  into chapter_days
  from public.entries as chapter
  where chapter.id = p_chapter_id
    and chapter.owner_id = reader_id
    and chapter.item_subtype = 'chapter'
    and chapter.deleted_at is null;

  if chapter_days is null then
    return;
  end if;

  return query
  with overlapping as (
    select
      other.id,
      coalesce(btrim(other.title), '') as title,
      other.is_first_time,
      other.occurred_start,
      other.occurred_end,
      other.date_precision,
      other.occurred_label,
      coalesce(other.occurred_timezone, 'UTC') as occurred_timezone,
      dated.days
    from public.entries as other
    cross join lateral (
      select public.chapter_window(
        other.occurred_start, other.occurred_end, other.date_precision, other.occurred_timezone
      ) as days
    ) as dated
    where other.owner_id = reader_id
      and other.deleted_at is null
      and other.item_subtype = 'chapter'
      and other.id <> p_chapter_id
      and chapter_days && dated.days
  )
  select
    overlapping.id,
    overlapping.title,
    overlapping.is_first_time,
    overlapping.occurred_start,
    overlapping.occurred_end,
    overlapping.date_precision,
    overlapping.occurred_label,
    overlapping.occurred_timezone,
    lower(overlapping.days),
    upper(overlapping.days)
  from overlapping
  order by lower(overlapping.days), lower(overlapping.title), overlapping.id
  limit 100;
end;
$$;

revoke all on function public.chapter_entries(uuid, integer, integer) from public, anon;
grant execute on function public.chapter_entries(uuid, integer, integer) to authenticated, service_role;
revoke all on function public.chapter_overlaps(uuid) from public, anon;
grant execute on function public.chapter_overlaps(uuid) to authenticated, service_role;

commit;
