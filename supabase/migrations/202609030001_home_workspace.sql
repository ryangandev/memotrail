create index if not exists entries_owner_active_created_idx
  on public.entries (owner_id, created_at desc, id)
  where deleted_at is null;

create or replace function public.home_workspace(
  p_local_date date,
  p_timezone text,
  p_recent_limit integer default 5
)
returns table (
  snapshot_date date,
  profile_display_name text,
  inbox_count bigint,
  entry_count bigint,
  first_time_count bigint,
  collection_count bigint,
  active_habit_count bigint,
  due_habit_count bigint,
  completed_habit_count bigint,
  skipped_habit_count bigint,
  current_stage_count bigint,
  recent_entries jsonb,
  current_stages jsonb
)
language plpgsql
stable
security invoker
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
      count(*) filter (where inbox_status = 'unreviewed') as inbox_count,
      count(*) as entry_count,
      count(*) filter (where entry_type = 'first_time') as first_time_count
    from active_entries
  ),
  collection_stats as (
    select count(*) as collection_count
    from public.collections
    where collections.owner_id = home_owner_id
      and collections.archived_at is null
  ),
  habit_rows as (
    select *
    from public.habits_workspace(p_local_date)
  ),
  habit_stats as (
    select
      count(*) as active_habit_count,
      count(*) filter (where local_status <> 'not_scheduled') as due_habit_count,
      count(*) filter (where local_status = 'completed') as completed_habit_count,
      count(*) filter (where local_status = 'skipped') as skipped_habit_count
    from habit_rows
  ),
  visible_stages as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      tracks.id as track_id,
      tracks.name as track_name,
      tracks.sort_order as track_sort_order,
      items.sort_order as item_sort_order
    from public.timeline_items as items
    join active_entries as entries on entries.id = items.entry_id
    join public.timeline_tracks as tracks
      on tracks.id = items.track_id
      and tracks.owner_id = items.owner_id
    where items.owner_id = home_owner_id
      and items.timeline_kind = 'stage'
      and not tracks.is_hidden
      and entries.occurred_start < local_day_end
      and (entries.occurred_end is null or entries.occurred_end >= local_day_start)
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
    entry_stats.inbox_count,
    entry_stats.entry_count,
    entry_stats.first_time_count,
    collection_stats.collection_count,
    habit_stats.active_habit_count,
    habit_stats.due_habit_count,
    habit_stats.completed_habit_count,
    habit_stats.skipped_habit_count,
    (select count(*) from visible_stages),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', recent_entries.id,
            'title', coalesce(
              nullif(btrim(recent_entries.title), ''),
              nullif(split_part(btrim(recent_entries.body), E'\n', 1), ''),
              'Untitled Entry'
            ),
            'body', recent_entries.body,
            'entry_type', recent_entries.entry_type,
            'inbox_status', recent_entries.inbox_status,
            'occurred_start', recent_entries.occurred_start,
            'occurred_end', recent_entries.occurred_end,
            'date_precision', recent_entries.date_precision,
            'occurred_label', recent_entries.occurred_label,
            'occurred_timezone', recent_entries.occurred_timezone,
            'revision', recent_entries.revision,
            'created_at', recent_entries.created_at,
            'updated_at', recent_entries.updated_at,
            'collection_names', coalesce(
              (
                select jsonb_agg(collections.name order by lower(collections.name), collections.id)
                from public.entry_collections
                join public.collections
                  on collections.id = entry_collections.collection_id
                  and collections.owner_id = entry_collections.owner_id
                where entry_collections.entry_id = recent_entries.id
                  and entry_collections.owner_id = home_owner_id
                  and collections.archived_at is null
              ),
              '[]'::jsonb
            ),
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
            'entry_id', stages.entry_id,
            'title', stages.title,
            'body', stages.body,
            'track_id', stages.track_id,
            'track_name', stages.track_name,
            'occurred_start', stages.occurred_start,
            'occurred_end', stages.occurred_end,
            'date_precision', stages.date_precision,
            'occurred_label', stages.occurred_label,
            'occurred_timezone', stages.occurred_timezone
          )
          order by
            stages.track_sort_order,
            lower(stages.track_name),
            stages.occurred_start,
            stages.item_sort_order,
            stages.entry_id
        )
        from visible_stages as stages
      ),
      '[]'::jsonb
    )
  from entry_stats
  cross join collection_stats
  cross join habit_stats;
end;
$$;

revoke all on function public.home_workspace(date, text, integer) from public, anon;
grant execute on function public.home_workspace(date, text, integer) to authenticated;

comment on function public.home_workspace(date, text, integer) is
  'Returns an owner-scoped Home snapshot with archive counts, today Habit progress, current stages, and recent Entries.';
