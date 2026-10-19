-- The Dashboard reads the two marks. Now lists the Chapters that have started and have not
-- ended, with their dates, in place of the Home, Vehicle, and Period lanes, and the First Time
-- count comes from the mark on each Entry. A resurfaced memory is always an ordinary Entry, so
-- a Chapter never comes back as "on this day".

begin;

create or replace function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer default 5)
returns table(snapshot_date date, profile_display_name text, entry_count bigint, first_time_count bigint, tag_count bigint, now_count bigint, recent_entries jsonb, now_items jsonb)
language plpgsql
stable
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
  local_day_start timestamptz;
  local_day_end timestamptz;
begin
  if home_owner_id is null then
    return;
  end if;

  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;

  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;

  if p_recent_limit is null or p_recent_limit < 1 or p_recent_limit > 10 then
    raise exception using errcode = '22023', message = 'invalid_home_recent_limit';
  end if;

  begin
    local_day_start := pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
    local_day_end := pg_catalog.timezone(
      normalized_timezone,
      (p_local_date + 1)::timestamp
    );
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with active_entries as (
    select entries.*
    from public.entries
    where entries.owner_id = home_owner_id
      and entries.deleted_at is null
  ),
  entry_stats as (
    select
      count(*) as entry_count,
      count(*) filter (where active_entries.is_first_time) as first_time_count
    from active_entries
  ),
  tag_stats as (
    select count(*) as tag_count
    from public.tags
    where tags.owner_id = home_owner_id
  ),

  -- Now lists the Chapters still going on: started, with no end. A Not sure Chapter with a
  -- rough start counts, and one without any start does not.
  now_rows as (
    select
      entries.id as entry_id,
      entries.title,
      entries.is_first_time,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone
    from active_entries as entries
    where entries.item_subtype = 'chapter'
      and entries.date_precision <> 'unknown'
      and entries.occurred_start is not null
      and entries.occurred_start < local_day_end
      and entries.occurred_end is null
  ),
  recent_entry_rows as (
    select
      entries.*,
      row_number() over (order by entries.created_at desc, entries.id) as recent_position
    from active_entries as entries
    order by entries.created_at desc, entries.id
    limit p_recent_limit
  )
  select
    p_local_date,
    (
      select profiles.display_name
      from public.profiles
      where profiles.user_id = home_owner_id
    ),
    entry_stats.entry_count,
    entry_stats.first_time_count,
    tag_stats.tag_count,
    (select count(*) from now_rows),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', recent_entries.id,
            'title', coalesce(btrim(recent_entries.title), ''),
            'body', recent_entries.body,
            'item_kind', recent_entries.item_kind, 'item_subtype', recent_entries.item_subtype,
            'occurred_start', recent_entries.occurred_start,
            'occurred_end', recent_entries.occurred_end,
            'date_precision', recent_entries.date_precision,
            'occurred_label', recent_entries.occurred_label,
            'occurred_timezone', recent_entries.occurred_timezone,
            'revision', recent_entries.revision,
            'created_at', recent_entries.created_at,
            'updated_at', recent_entries.updated_at,
            'tag_names', coalesce(
              (
                select jsonb_agg(tags.name order by lower(tags.name), tags.id)
                from public.entry_tags
                join public.tags
                  on tags.id = entry_tags.tag_id
                  and tags.owner_id = entry_tags.owner_id
                where entry_tags.entry_id = recent_entries.id
                  and entry_tags.owner_id = home_owner_id
              ),
              '[]'::jsonb
            ),
            'attachments', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'attachment_id', attachments.id,
                    'bucket_id', attachments.bucket_id,
                    'object_path', attachments.object_path,
                    'original_filename', attachments.original_filename,
                    'mime_type', attachments.mime_type,
                    'byte_size', attachments.byte_size,
                    'pixel_width', attachments.pixel_width,
                    'pixel_height', attachments.pixel_height
                  )
                  order by attachments.created_at, attachments.id
                )
                from public.attachments
                where attachments.entry_id = recent_entries.id
                  and attachments.owner_id = home_owner_id
                  and attachments.deleted_at is null
                  and attachments.variant = 'original'
              ),
              '[]'::jsonb
            )
          )
          order by recent_entries.recent_position
        )
        from recent_entry_rows as recent_entries
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', now_rows.entry_id,
            'title', coalesce(btrim(now_rows.title), ''),
            'is_first_time', now_rows.is_first_time,
            'occurred_start', now_rows.occurred_start,
            'occurred_end', now_rows.occurred_end,
            'date_precision', now_rows.date_precision,
            'occurred_label', now_rows.occurred_label,
            'occurred_timezone', now_rows.occurred_timezone
          )
          order by
            now_rows.occurred_start desc,
            lower(now_rows.title),
            now_rows.entry_id
        )
        from now_rows
      ),
      '[]'::jsonb
    )
  from entry_stats
  cross join tag_stats;
end;
$$;

create or replace function public.home_resurfaced_memory(p_local_date date, p_timezone text)
returns table(resurfacing_kind text, years_ago integer, entry_id uuid, title text, body text, item_kind text, item_subtype text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, tag_names jsonb, attachments jsonb)
language plpgsql
stable
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
begin
  if home_owner_id is null then
    return;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;
  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;
  begin
    perform pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with eligible_items as (
    select
      item.*,
      pg_catalog.timezone(coalesce(timezone.name, 'UTC'), item.occurred_start)::date
        as local_occurred_date
    from public.entries as item
    left join pg_catalog.pg_timezone_names as timezone
      on timezone.name = item.occurred_timezone
    where item.owner_id = home_owner_id
      and item.deleted_at is null
      and item.occurred_start is not null
      and item.item_subtype = 'entry'
  ),
  anniversary_memory as (
    select
      eligible_items.*,
      'on_this_day'::text as selected_kind,
      extract(year from p_local_date)::integer
        - extract(year from eligible_items.local_occurred_date)::integer
        as selected_years_ago
    from eligible_items
    where extract(month from eligible_items.local_occurred_date) = extract(month from p_local_date)
      and extract(day from eligible_items.local_occurred_date) = extract(day from p_local_date)
      and extract(year from eligible_items.local_occurred_date) < extract(year from p_local_date)
    order by eligible_items.local_occurred_date desc, eligible_items.created_at desc, eligible_items.id
    limit 1
  ),
  archive_memories as (
    select
      eligible_items.*,
      row_number() over (order by eligible_items.local_occurred_date, eligible_items.id) as archive_position,
      count(*) over () as archive_count
    from eligible_items
    where eligible_items.local_occurred_date <= p_local_date - 30
      and not exists (select 1 from anniversary_memory)
  ),
  archive_memory as (
    select
      archive_memories.*,
      'from_your_archive'::text as selected_kind,
      null::integer as selected_years_ago
    from archive_memories
    where archive_memories.archive_position = (
      pg_catalog.mod(
        (p_local_date - date '2000-01-01')::bigint,
        archive_memories.archive_count
      ) + 1
    )
  ),
  selected_memory as (
    select
      anniversary_memory.selected_kind,
      anniversary_memory.selected_years_ago,
      anniversary_memory.id,
      anniversary_memory.title,
      anniversary_memory.body,
      anniversary_memory.item_kind,
      anniversary_memory.item_subtype,
      anniversary_memory.occurred_start,
      anniversary_memory.occurred_end,
      anniversary_memory.date_precision,
      anniversary_memory.occurred_label,
      anniversary_memory.occurred_timezone,
      anniversary_memory.revision,
      anniversary_memory.created_at,
      anniversary_memory.updated_at
    from anniversary_memory
    union all
    select
      archive_memory.selected_kind,
      archive_memory.selected_years_ago,
      archive_memory.id,
      archive_memory.title,
      archive_memory.body,
      archive_memory.item_kind,
      archive_memory.item_subtype,
      archive_memory.occurred_start,
      archive_memory.occurred_end,
      archive_memory.date_precision,
      archive_memory.occurred_label,
      archive_memory.occurred_timezone,
      archive_memory.revision,
      archive_memory.created_at,
      archive_memory.updated_at
    from archive_memory
  )
  select
    selected_memory.selected_kind,
    selected_memory.selected_years_ago,
    selected_memory.id,
    coalesce(btrim(selected_memory.title), ''),
    selected_memory.body,
    selected_memory.item_kind,
    selected_memory.item_subtype,
    selected_memory.occurred_start,
    selected_memory.occurred_end,
    selected_memory.date_precision,
    selected_memory.occurred_label,
    selected_memory.occurred_timezone,
    selected_memory.revision,
    selected_memory.created_at,
    selected_memory.updated_at,
    coalesce((
      select jsonb_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = selected_memory.id
        and membership.owner_id = home_owner_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'attachment_id', attachment.id,
        'bucket_id', attachment.bucket_id,
        'object_path', attachment.object_path,
        'original_filename', attachment.original_filename,
        'mime_type', attachment.mime_type,
        'byte_size', attachment.byte_size,
        'pixel_width', attachment.pixel_width,
        'pixel_height', attachment.pixel_height
      ) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = selected_memory.id
        and attachment.owner_id = home_owner_id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  from selected_memory;
end;
$$;

commit;
