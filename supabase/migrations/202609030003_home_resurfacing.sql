create index if not exists entries_owner_resurfacing_idx
  on public.entries (owner_id, occurred_start desc, id)
  where deleted_at is null
    and occurred_start is not null
    and inbox_status = 'organized'
    and entry_type <> 'life_stage';

create or replace function public.home_resurfaced_memory(
  p_local_date date,
  p_timezone text
)
returns table (
  resurfacing_kind text,
  years_ago integer,
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
  collection_names jsonb,
  tag_names jsonb,
  attachments jsonb
)
language plpgsql
stable
security invoker
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
  with eligible_entries as (
    select
      entries.id,
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
      entries.updated_at,
      pg_catalog.timezone(
        coalesce(entry_timezones.name, 'UTC'),
        entries.occurred_start
      )::date as local_occurred_date
    from public.entries as entries
    left join pg_catalog.pg_timezone_names as entry_timezones
      on entry_timezones.name = entries.occurred_timezone
    where entries.owner_id = home_owner_id
      and entries.deleted_at is null
      and entries.inbox_status = 'organized'
      and entries.occurred_start is not null
      and entries.entry_type <> 'life_stage'
  ),
  anniversary_memory as (
    select
      eligible_entries.*,
      'on_this_day'::text as selected_kind,
      (
        extract(year from p_local_date)::integer
        - extract(year from eligible_entries.local_occurred_date)::integer
      ) as selected_years_ago
    from eligible_entries
    where extract(month from eligible_entries.local_occurred_date)
        = extract(month from p_local_date)
      and extract(day from eligible_entries.local_occurred_date)
        = extract(day from p_local_date)
      and extract(year from eligible_entries.local_occurred_date)
        < extract(year from p_local_date)
    order by
      eligible_entries.local_occurred_date desc,
      eligible_entries.created_at desc,
      eligible_entries.id
    limit 1
  ),
  archive_memories as (
    select
      eligible_entries.*,
      row_number() over (
        order by eligible_entries.local_occurred_date, eligible_entries.id
      ) as archive_position,
      count(*) over () as archive_count
    from eligible_entries
    where eligible_entries.local_occurred_date <= p_local_date - 30
      and not exists (select 1 from anniversary_memory)
  ),
  archive_memory as (
    select
      archive_memories.id,
      archive_memories.title,
      archive_memories.body,
      archive_memories.entry_type,
      archive_memories.inbox_status,
      archive_memories.occurred_start,
      archive_memories.occurred_end,
      archive_memories.date_precision,
      archive_memories.occurred_label,
      archive_memories.occurred_timezone,
      archive_memories.revision,
      archive_memories.created_at,
      archive_memories.updated_at,
      archive_memories.local_occurred_date,
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
    select * from anniversary_memory
    union all
    select * from archive_memory
  )
  select
    selected_memory.selected_kind,
    selected_memory.selected_years_ago,
    selected_memory.id,
    coalesce(
      nullif(btrim(selected_memory.title), ''),
      nullif(split_part(btrim(selected_memory.body), E'\n', 1), ''),
      'Untitled Entry'
    ),
    selected_memory.body,
    selected_memory.entry_type,
    selected_memory.inbox_status,
    selected_memory.occurred_start,
    selected_memory.occurred_end,
    selected_memory.date_precision,
    selected_memory.occurred_label,
    selected_memory.occurred_timezone,
    selected_memory.revision,
    selected_memory.created_at,
    selected_memory.updated_at,
    coalesce(
      (
        select jsonb_agg(
          collections.name
          order by lower(collections.name), collections.id
        )
        from public.entry_collections
        join public.collections
          on collections.id = entry_collections.collection_id
          and collections.owner_id = entry_collections.owner_id
        where entry_collections.entry_id = selected_memory.id
          and entry_collections.owner_id = home_owner_id
          and collections.archived_at is null
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags
          on tags.id = entry_tags.tag_id
          and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = selected_memory.id
          and entry_tags.owner_id = home_owner_id
      ),
      '[]'::jsonb
    ),
    coalesce(
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
        where attachments.entry_id = selected_memory.id
          and attachments.owner_id = home_owner_id
          and attachments.deleted_at is null
          and attachments.variant = 'original'
      ),
      '[]'::jsonb
    )
  from selected_memory;
end;
$$;

revoke all on function public.home_resurfaced_memory(date, text) from public, anon;
grant execute on function public.home_resurfaced_memory(date, text) to authenticated;

comment on function public.home_resurfaced_memory(date, text) is
  'Returns one owner-scoped organized memory using an On This Day match or a stable daily archive rotation.';
