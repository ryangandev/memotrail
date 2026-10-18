-- An untitled Entry is a record of its day, so Web names it by its date at its recorded precision.
-- Formatting a date belongs to the client, which knows the precision and zone it is shown in,
-- so workspaces return the stored title, blank when the Entry has none, instead of a stand-in made from its note.
-- Nothing treats an unorganized Entry as unfinished any more, so Library loses its Needs organizing filter.

drop function if exists public.wiki_items_workspace(text, text[], text[], integer, integer, boolean);
drop function if exists public.wiki_items_workspace(text, text[], text[], integer, integer);

create function public.wiki_items_workspace(p_query text DEFAULT ''::text, p_item_kinds text[] DEFAULT ARRAY[]::text[], p_item_subtypes text[] DEFAULT ARRAY[]::text[], p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(item_id uuid, canonical_item_id uuid, item_kind text, item_subtype text, title text, excerpt text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, updated_at timestamp with time zone, total_count bigint)
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
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      coalesce(btrim(entry.title), '') as title,
      left(btrim(entry.body), 240) as excerpt,
      entry.occurred_start,
      entry.occurred_end,
      entry.date_precision,
      entry.occurred_label,
      entry.occurred_timezone,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype
      ) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
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
    counted.item_id, counted.canonical_item_id,
    counted.item_kind, counted.item_subtype, counted.title, counted.excerpt,
    counted.occurred_start, counted.occurred_end,
    counted.date_precision, counted.occurred_label, counted.occurred_timezone,
    counted.updated_at, counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.item_id
  limit p_limit offset p_offset;
end;
$function$;

revoke all on function public.wiki_items_workspace(text, text[], text[], integer, integer) from public, anon;
grant execute on function public.wiki_items_workspace(text, text[], text[], integer, integer) to authenticated, service_role;

-- Each Trash row carries its Entry's stored title and date: an Entry's own, or the Entry a photo belongs to.
drop function if exists public.trash_workspace(integer, integer);

create function public.trash_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(item_kind text, item_id uuid, title text, detail text, deleted_at timestamp with time zone, expires_at timestamp with time zone, revision integer, wiki_item_kind text, wiki_item_subtype text, parent_entry_id uuid, storage_paths text[], entry_title text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_trash_page';
  end if;

  return query
  with trash_items as (
    select
      'entry'::text as item_kind,
      item.id as item_id,
      coalesce(btrim(item.title), '') as title,
      nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 240), '') as detail,
      item.deleted_at,
      item.deleted_at + interval '30 days' as expires_at,
      item.revision,
      item.item_kind as wiki_item_kind,
      item.item_subtype as wiki_item_subtype,
      null::uuid as parent_entry_id,
      coalesce((
        select array_agg(media.object_path order by media.created_at, media.id)
        from public.attachments as media
        where media.owner_id = item.owner_id
          and media.entry_id = item.id
          and media.bucket_id = 'entry-media'
      ), '{}'::text[]) as storage_paths,
      coalesce(btrim(item.title), '') as entry_title,
      item.occurred_start,
      item.occurred_end,
      item.date_precision,
      item.occurred_label,
      item.occurred_timezone
    from public.entries as item
    where item.owner_id = auth.uid()
      and item.deleted_at is not null

    union all

    select
      'attachment'::text,
      media.id,
      coalesce(nullif(btrim(media.original_filename), ''), 'Removed photo'),
      null::text,
      media.deleted_at,
      media.deleted_at + interval '30 days',
      null::integer,
      null::text,
      null::text,
      item.id,
      array[media.object_path]::text[],
      coalesce(btrim(item.title), ''),
      item.occurred_start,
      item.occurred_end,
      item.date_precision,
      item.occurred_label,
      item.occurred_timezone
    from public.attachments as media
    join public.entries as item
      on item.id = media.entry_id and item.owner_id = media.owner_id
    where media.owner_id = auth.uid()
      and media.deleted_at is not null
      and media.variant = 'original'
      and item.deleted_at is null
  ),
  counted as (
    select trash_items.*, count(*) over () as total_count
    from trash_items
  )
  select counted.*
  from counted
  order by counted.deleted_at desc, counted.item_kind, counted.item_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.trash_workspace(integer, integer) from public, anon;
grant execute on function public.trash_workspace(integer, integer) to authenticated, service_role;

-- The remaining workspaces keep their shape and return the stored title, blank when there is none.
-- A Someday item's First Time also carries its end and precision, so it can be named by its date.

CREATE OR REPLACE FUNCTION public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer DEFAULT 5)
 RETURNS TABLE(snapshot_date date, profile_display_name text, entry_count bigint, first_time_count bigint, tag_count bigint, now_count bigint, recent_entries jsonb, now_items jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
      count(*) filter (
        where exists (
          select 1 from public.milestones
          where milestones.entry_id = active_entries.id and milestones.is_first_time
        )
      ) as first_time_count
    from active_entries
  ),
  tag_stats as (
    select count(*) as tag_count
    from public.tags
    where tags.owner_id = home_owner_id
  ),

  -- Now lists what is still going on: Periods, Homes, and Vehicles that started and have no end.
  now_rows as (
    select
      entries.id as entry_id,
      entries.title,
      entries.item_kind,
      entries.item_subtype,
      case
        when entries.item_subtype = 'home' then 'homes'
        when entries.item_subtype = 'vehicle' then 'vehicles'
        else milestones.lane
      end as lane,
      coalesce(milestones.is_first_time, false) as is_first_time,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone
    from active_entries as entries
    left join public.milestones on milestones.entry_id = entries.id
    where (
        (entries.item_kind = 'entity' and entries.item_subtype in ('home', 'vehicle'))
        or milestones.shape = 'period'
      )
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
            'item_kind', now_rows.item_kind,
            'item_subtype', now_rows.item_subtype,
            'lane', now_rows.lane,
            'is_first_time', now_rows.is_first_time,
            'occurred_start', now_rows.occurred_start,
            'occurred_end', now_rows.occurred_end,
            'date_precision', now_rows.date_precision,
            'occurred_label', now_rows.occurred_label,
            'occurred_timezone', now_rows.occurred_timezone
          )
          order by
            array_position(array['homes', 'vehicles', 'work_study', 'other'], now_rows.lane),
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
$function$
;

CREATE OR REPLACE FUNCTION public.home_resurfaced_memory(p_local_date date, p_timezone text)
 RETURNS TABLE(resurfacing_kind text, years_ago integer, entry_id uuid, title text, body text, item_kind text, item_subtype text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, tag_names jsonb, attachments jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
      and not exists (
        select 1 from public.milestones
        where milestones.entry_id = item.id and milestones.shape = 'period'
      )
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
$function$
;

CREATE OR REPLACE FUNCTION public.timeline_workspace()
 RETURNS TABLE(entry_id uuid, title text, body text, item_kind text, item_subtype text, lane text, shape text, is_first_time boolean, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[])
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    entries.id,
    coalesce(btrim(entries.title), ''),
    entries.body,
    entries.item_kind,
    entries.item_subtype,
    case
      when entries.item_kind = 'entity' and entries.item_subtype = 'home' then 'homes'
      when entries.item_kind = 'entity' and entries.item_subtype = 'vehicle' then 'vehicles'
      else milestones.lane
    end,
    coalesce(milestones.shape, 'period'),
    coalesce(milestones.is_first_time, false),
    entries.occurred_start,
    entries.occurred_end,
    entries.date_precision,
    entries.occurred_label,
    coalesce(entries.occurred_timezone, 'UTC'),
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
  left join public.milestones
    on milestones.entry_id = entries.id
    and milestones.owner_id = entries.owner_id
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
    and (
      milestones.entry_id is not null
      or (entries.item_kind = 'entity' and entries.item_subtype in ('home', 'vehicle'))
    )
  order by entries.occurred_start nulls last, lower(entries.title), entries.id;
$function$
;

CREATE OR REPLACE FUNCTION public.first_times_workspace()
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], attachments jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    entries.id,
    coalesce(btrim(entries.title), ''),
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
  join public.milestones
    on milestones.entry_id = entries.id
    and milestones.owner_id = entries.owner_id
    and milestones.is_first_time
  where entries.owner_id = auth.uid()
    and entries.deleted_at is null
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$function$
;

CREATE OR REPLACE FUNCTION public.goals_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, status text, target_date date, tag_names text[], related_entries jsonb, attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
begin
  if goal_owner_id is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_goals_page';
  end if;

  return query
  with visible_goals as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.revision,
      entries.created_at,
      entries.updated_at,
      goals.status,
      goals.target_date,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = goal_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', related.id,
              'title', coalesce(btrim(related.title), ''),
              'body', related.body,
              'item_kind', related.item_kind, 'item_subtype', related.item_subtype,
              'occurred_start', related.occurred_start,
              'occurred_end', related.occurred_end,
              'date_precision', related.date_precision,
              'occurred_label', related.occurred_label,
              'occurred_timezone', related.occurred_timezone,
              'revision', related.revision,
              'updated_at', related.updated_at,
              'relationship', entry_links.relationship
            )
            order by related.updated_at desc, related.id
          )
          from public.entry_links
          join public.entries as related
            on related.id = entry_links.target_entry_id
            and related.owner_id = entry_links.owner_id
          where entry_links.source_entry_id = entries.id
            and entry_links.owner_id = goal_owner_id
            and entry_links.relationship = 'achievement'
            and related.deleted_at is null
        ),
        '[]'::jsonb
      ) as related_entries,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = goal_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.goals
      on goals.entry_id = entries.id
      and goals.owner_id = entries.owner_id
    where entries.owner_id = goal_owner_id
      and entries.item_kind = 'goal'
      and entries.deleted_at is null
  ),
  counted_goals as (
    select visible_goals.*, count(*) over () as total_count
    from visible_goals
  )
  select counted_goals.*
  from counted_goals
  order by
    case counted_goals.status
      when 'active' then 10
      when 'achieved' then 20
      else 30
    end,
    counted_goals.target_date asc nulls last,
    counted_goals.updated_at desc,
    lower(counted_goals.title),
    counted_goals.entry_id
  limit p_limit
  offset p_offset;
end;
$function$
;
