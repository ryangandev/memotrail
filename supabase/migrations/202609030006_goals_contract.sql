create index if not exists entries_owner_goal_updated_idx
  on public.entries (owner_id, updated_at desc, id)
  where entry_type = 'goal' and deleted_at is null;

create index if not exists goals_owner_status_target_idx
  on public.goals (owner_id, status, target_date nulls last, entry_id);

create index if not exists entry_links_owner_source_relationship_idx
  on public.entry_links (owner_id, source_entry_id, relationship, target_entry_id);

create or replace function public.archive_entry_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_snapshot jsonb := to_jsonb(old);
  home_snapshot jsonb;
  vehicle_snapshot jsonb;
  goal_snapshot jsonb;
begin
  select jsonb_build_object(
    'home', to_jsonb(homes),
    'place', case when places.id is null then null else to_jsonb(places) end,
    'timeline', case
      when timeline_items.entry_id is null then null
      else jsonb_build_object(
        'track_id', timeline_tracks.id,
        'track_name', timeline_tracks.name,
        'track_system_key', timeline_tracks.system_key,
        'timeline_kind', timeline_items.timeline_kind
      )
    end
  )
  into home_snapshot
  from public.homes
  left join public.places
    on places.id = homes.place_id
    and places.owner_id = homes.owner_id
  left join public.timeline_items
    on timeline_items.entry_id = homes.entry_id
    and timeline_items.owner_id = homes.owner_id
  left join public.timeline_tracks
    on timeline_tracks.id = timeline_items.track_id
    and timeline_tracks.owner_id = timeline_items.owner_id
  where homes.entry_id = old.id
    and homes.owner_id = old.owner_id
  order by
    (timeline_tracks.system_key = 'homes') desc,
    timeline_items.created_at,
    timeline_tracks.id
  limit 1;

  select jsonb_build_object(
    'vehicle', to_jsonb(vehicles),
    'timeline', case
      when timeline_items.entry_id is null then null
      else jsonb_build_object(
        'track_id', timeline_tracks.id,
        'track_name', timeline_tracks.name,
        'track_system_key', timeline_tracks.system_key,
        'timeline_kind', timeline_items.timeline_kind
      )
    end
  )
  into vehicle_snapshot
  from public.vehicles
  left join public.timeline_items
    on timeline_items.entry_id = vehicles.entry_id
    and timeline_items.owner_id = vehicles.owner_id
  left join public.timeline_tracks
    on timeline_tracks.id = timeline_items.track_id
    and timeline_tracks.owner_id = timeline_items.owner_id
  where vehicles.entry_id = old.id
    and vehicles.owner_id = old.owner_id
  order by
    (timeline_tracks.system_key = 'vehicles') desc,
    timeline_items.created_at,
    timeline_tracks.id
  limit 1;

  select jsonb_build_object(
    'goal', to_jsonb(goals),
    'related_entry_ids', coalesce(
      (
        select jsonb_agg(entry_links.target_entry_id order by entry_links.target_entry_id)
        from public.entry_links
        where entry_links.source_entry_id = goals.entry_id
          and entry_links.owner_id = goals.owner_id
          and entry_links.relationship = 'related'
      ),
      '[]'::jsonb
    )
  )
  into goal_snapshot
  from public.goals
  where goals.entry_id = old.id
    and goals.owner_id = old.owner_id;

  if home_snapshot is not null then
    archived_snapshot := archived_snapshot || home_snapshot;
  end if;
  if vehicle_snapshot is not null then
    archived_snapshot := archived_snapshot || vehicle_snapshot;
  end if;
  if goal_snapshot is not null then
    archived_snapshot := archived_snapshot || goal_snapshot;
  end if;

  insert into public.entry_versions (
    entry_id,
    owner_id,
    version,
    operation,
    changed_by,
    snapshot
  )
  values (
    old.id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    archived_snapshot
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    new.updated_at = timezone('utc', now());
    return new;
  end if;
  return old;
end;
$$;

revoke all on function public.archive_entry_version() from public;

create or replace function public.goals_workspace(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  entry_id uuid,
  title text,
  body text,
  revision integer,
  created_at timestamptz,
  updated_at timestamptz,
  horizon text,
  status text,
  target_date date,
  collection_names text[],
  tag_names text[],
  related_entries jsonb,
  attachments jsonb,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
      goals.horizon,
      goals.status,
      goals.target_date,
      coalesce(
        (
          select array_agg(collections.name order by lower(collections.name), collections.id)
          from public.entry_collections
          join public.collections
            on collections.id = entry_collections.collection_id
            and collections.owner_id = entry_collections.owner_id
          where entry_collections.entry_id = entries.id
            and entry_collections.owner_id = goal_owner_id
            and collections.archived_at is null
        ),
        array[]::text[]
      ) as collection_names,
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
              'title', related.title,
              'body', related.body,
              'entry_type', related.entry_type,
              'occurred_start', related.occurred_start,
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
      and entries.entry_type = 'goal'
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
      when 'considering' then 20
      when 'paused' then 30
      when 'achieved' then 40
      else 50
    end,
    counted_goals.target_date asc nulls last,
    counted_goals.updated_at desc,
    lower(counted_goals.title),
    counted_goals.entry_id
  limit p_limit
  offset p_offset;
end;
$$;

create or replace function public.save_goal_entry(
  p_title text,
  p_body text,
  p_horizon text,
  p_status text,
  p_target_date date,
  p_collection_names text[],
  p_tag_names text[],
  p_related_entry_ids uuid[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
begin
  if goal_owner_id is null then
    return;
  end if;
  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_goal_content';
  end if;
  if p_horizon not in ('short_term', 'long_term', 'someday') then
    raise exception using errcode = '22023', message = 'invalid_goal_horizon';
  end if;
  if p_status not in ('considering', 'active', 'paused', 'achieved', 'let_go') then
    raise exception using errcode = '22023', message = 'invalid_goal_status';
  end if;
  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
      where nullif(btrim(collection_name), '') is null
        or length(btrim(collection_name)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;
  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1
      from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null
        or length(btrim(tag_name)) > 60
    )
  then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;
  if cardinality(coalesce(p_related_entry_ids, '{}'::uuid[])) > 100
    or exists (
      select 1
      from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
      where related_entry_id is null
    )
  then
    raise exception using errcode = '22023', message = 'invalid_related_entries';
  end if;
  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;
  if p_entry_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      entry_type,
      inbox_status,
      date_precision
    )
    values (
      goal_owner_id,
      normalized_title,
      normalized_body,
      'goal',
      'organized',
      'unknown'
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      entry_type = 'goal',
      inbox_status = 'organized',
      occurred_start = null,
      occurred_end = null,
      date_precision = 'unknown',
      occurred_label = null,
      occurred_timezone = null
    where entries.id = p_entry_id
      and entries.owner_id = goal_owner_id
      and entries.revision = p_expected_revision
      and entries.entry_type = 'goal'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.goals
        where goals.entry_id = entries.id
          and goals.owner_id = goal_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
    where related_entry_id = saved_entry_id
      or not exists (
        select 1
        from public.entries as related
        where related.id = related_entry_id
          and related.owner_id = goal_owner_id
          and related.deleted_at is null
      )
  ) then
    raise exception using errcode = '22023', message = 'invalid_related_entries';
  end if;

  insert into public.goals (entry_id, owner_id, horizon, status, target_date)
  values (saved_entry_id, goal_owner_id, p_horizon, p_status, p_target_date)
  on conflict on constraint goals_pkey do update
  set
    horizon = excluded.horizon,
    status = excluded.status,
    target_date = excluded.target_date;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select goal_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where collections.owner_id = goal_owner_id
      and lower(collections.name) = lower(normalized_names.name)
      and collections.archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections
  where entry_collections.entry_id = saved_entry_id
    and entry_collections.owner_id = goal_owner_id;

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select saved_entry_id, collections.id, goal_owner_id
  from public.collections
  join normalized_names on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = goal_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name))) btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select goal_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where tags.owner_id = goal_owner_id
      and lower(tags.name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.entry_id = saved_entry_id
    and entry_tags.owner_id = goal_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select saved_entry_id, tags.id, goal_owner_id
  from public.tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = goal_owner_id
  on conflict do nothing;

  delete from public.entry_links
  where entry_links.source_entry_id = saved_entry_id
    and entry_links.owner_id = goal_owner_id
    and entry_links.relationship = 'related';

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  select saved_entry_id, related_entry_id, goal_owner_id, 'related'
  from (
    select distinct related_entry_id
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
  ) as related_entries
  on conflict do nothing;

  return query select saved_entry_id, saved_revision, p_entry_id is null;
end;
$$;

create or replace function public.trash_goal_entry(
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (entry_id uuid, revision integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
begin
  if goal_owner_id is null or p_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = p_expected_revision
    and entries.entry_type = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

create or replace function public.mark_goal_achieved_with_first_time(
  p_goal_entry_id uuid,
  p_expected_revision integer,
  p_occurred_start timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text
)
returns table (
  goal_entry_id uuid,
  goal_revision integer,
  first_time_entry_id uuid
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
  achieved_goal_title text;
  achieved_goal_revision integer;
  new_first_time_id uuid;
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1
    or p_occurred_start is null
    or normalized_timezone is null
    or length(normalized_timezone) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;
  if p_date_precision not in ('exact', 'day', 'month', 'year', 'approximate', 'age')
    or length(coalesce(normalized_label, '')) > 200
  then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement_date';
  end if;
  begin
    perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_goal_achievement_timezone';
  end;

  update public.entries
  set inbox_status = 'organized'
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = p_expected_revision
    and entries.entry_type = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
    )
    and exists (
      select 1
      from public.entry_collections
      join public.collections
        on collections.id = entry_collections.collection_id
        and collections.owner_id = entry_collections.owner_id
      where entry_collections.entry_id = entries.id
        and entry_collections.owner_id = goal_owner_id
        and collections.archived_at is null
        and lower(btrim(collections.name)) = 'bucket list'
    )
  returning entries.title, entries.revision
  into achieved_goal_title, achieved_goal_revision;

  if achieved_goal_title is null then
    return;
  end if;

  update public.goals
  set status = 'achieved'
  where goals.entry_id = p_goal_entry_id
    and goals.owner_id = goal_owner_id;

  insert into public.entries (
    owner_id,
    title,
    body,
    entry_type,
    inbox_status,
    occurred_start,
    date_precision,
    occurred_label,
    occurred_timezone
  )
  values (
    goal_owner_id,
    achieved_goal_title,
    '',
    'first_time',
    'organized',
    p_occurred_start,
    p_date_precision,
    normalized_label,
    normalized_timezone
  )
  returning entries.id into new_first_time_id;

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$$;

revoke all on function public.goals_workspace(integer, integer) from public, anon;
revoke all on function public.save_goal_entry(
  text, text, text, text, date, text[], text[], uuid[], uuid, integer
) from public, anon;
revoke all on function public.trash_goal_entry(uuid, integer) from public, anon;
revoke all on function public.mark_goal_achieved_with_first_time(
  uuid, integer, timestamptz, text, text, text
) from public, anon;

grant execute on function public.goals_workspace(integer, integer) to authenticated;
grant execute on function public.save_goal_entry(
  text, text, text, text, date, text[], text[], uuid[], uuid, integer
) to authenticated;
grant execute on function public.trash_goal_entry(uuid, integer) to authenticated;
grant execute on function public.mark_goal_achieved_with_first_time(
  uuid, integer, timestamptz, text, text, text
) to authenticated;

comment on function public.goals_workspace(integer, integer) is
  'Returns the authenticated owner''s active Goals with reflective state, organization, related Entries, and private attachment metadata.';
comment on function public.save_goal_entry(
  text, text, text, text, date, text[], text[], uuid[], uuid, integer
) is 'Creates or revision-safely updates an organized Goal Entry, Goal facts, organization, and related Entry links atomically.';
comment on function public.trash_goal_entry(uuid, integer) is
  'Revision-safely moves an owned Goal Entry to recoverable Trash.';
comment on function public.mark_goal_achieved_with_first_time(
  uuid, integer, timestamptz, text, text, text
) is 'Marks an owned Bucket List Goal achieved and creates a linked organized First Time without copying the Goal description.';
