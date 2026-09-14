create or replace function public.timeline_workspace_with_organization(
  p_include_hidden boolean default false
)
returns table (
  track_id uuid,
  track_name text,
  track_system_key text,
  track_sort_order integer,
  track_is_hidden boolean,
  entry_id uuid,
  title text,
  body text,
  entry_type text,
  timeline_kind text,
  item_sort_order integer,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    workspace.*,
    coalesce(
      (
        select array_agg(collections.name order by lower(collections.name), collections.id)
        from public.entry_collections
        join public.collections
          on collections.id = entry_collections.collection_id
          and collections.owner_id = entry_collections.owner_id
        where entry_collections.entry_id = workspace.entry_id
          and entry_collections.owner_id = auth.uid()
          and collections.archived_at is null
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags
          on tags.id = entry_tags.tag_id
          and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = workspace.entry_id
          and entry_tags.owner_id = auth.uid()
      ),
      '{}'::text[]
    )
  from public.timeline_workspace(p_include_hidden) as workspace;
$$;

revoke all on function public.timeline_workspace_with_organization(boolean) from public, anon;
grant execute on function public.timeline_workspace_with_organization(boolean) to authenticated;

create or replace function public.save_timeline_entry_with_organization(
  p_track_id uuid,
  p_timeline_kind text,
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
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
  timeline_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  created boolean;
begin
  if timeline_owner_id is null then
    return;
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

  select saved.entry_id, saved.revision, saved.was_created
  into saved_entry_id, saved_revision, created
  from public.save_timeline_entry_with_occurrence(
    p_track_id,
    p_timeline_kind,
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_entry_id,
    p_expected_revision
  ) as saved;

  if saved_entry_id is null then
    return;
  end if;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select timeline_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where collections.owner_id = timeline_owner_id
      and lower(collections.name) = lower(normalized_names.name)
      and collections.archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections
  where entry_collections.entry_id = saved_entry_id
    and entry_collections.owner_id = timeline_owner_id
    and exists (
      select 1
      from public.collections
      where collections.id = entry_collections.collection_id
        and collections.owner_id = entry_collections.owner_id
        and collections.archived_at is null
    );

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select saved_entry_id, collections.id, timeline_owner_id
  from public.collections
  join normalized_names
    on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = timeline_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name)))
      btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select timeline_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where tags.owner_id = timeline_owner_id
      and lower(tags.name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.entry_id = saved_entry_id
    and entry_tags.owner_id = timeline_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select saved_entry_id, tags.id, timeline_owner_id
  from public.tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = timeline_owner_id
  on conflict do nothing;

  return query select saved_entry_id, saved_revision, created;
end;
$$;

revoke all on function public.save_timeline_entry_with_organization(uuid,text,text,text,timestamptz,timestamptz,text,text,text,text[],text[],uuid,integer) from public, anon;
grant execute on function public.save_timeline_entry_with_organization(uuid,text,text,text,timestamptz,timestamptz,text,text,text,text[],text[],uuid,integer) to authenticated;

create or replace function public.merge_tags(
  p_source_id uuid,
  p_source_revision integer,
  p_target_id uuid,
  p_target_revision integer
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  tag_owner_id uuid := auth.uid();
  affected_id uuid;
begin
  if tag_owner_id is null then
    return null;
  end if;

  if p_source_id is null or p_target_id is null or p_source_id = p_target_id
    or p_source_revision is null or p_source_revision < 1
    or p_target_revision is null or p_target_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_tag_merge';
  end if;

  perform 1
  from public.tags
  where tags.owner_id = tag_owner_id
    and (
      (tags.id = p_source_id and tags.revision = p_source_revision)
      or (tags.id = p_target_id and tags.revision = p_target_revision)
    )
  order by tags.id
  for update;

  if not found or (
    select count(*)
    from public.tags
    where tags.owner_id = tag_owner_id
      and (
        (tags.id = p_source_id and tags.revision = p_source_revision)
        or (tags.id = p_target_id and tags.revision = p_target_revision)
      )
  ) <> 2 then
    return null;
  end if;

  for affected_id in
    select entries.id
    from public.entries
    join public.entry_tags
      on entry_tags.entry_id = entries.id
      and entry_tags.owner_id = entries.owner_id
    where entry_tags.tag_id = p_source_id
      and entry_tags.owner_id = tag_owner_id
    order by entries.id
    for update of entries
  loop
    update public.entries
    set updated_at = clock_timestamp()
    where entries.id = affected_id
      and entries.owner_id = tag_owner_id;
  end loop;

  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select entry_tags.entry_id, p_target_id, tag_owner_id
  from public.entry_tags
  where entry_tags.tag_id = p_source_id
    and entry_tags.owner_id = tag_owner_id
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.tag_id = p_source_id
    and entry_tags.owner_id = tag_owner_id;

  delete from public.tags
  where tags.id = p_source_id
    and tags.owner_id = tag_owner_id;

  return p_target_id;
end;
$$;

create or replace function public.delete_unused_tag(
  p_id uuid,
  p_expected_revision integer
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  deleted_id uuid;
begin
  if auth.uid() is null then
    return null;
  end if;

  if p_id is null or p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_tag_revision';
  end if;

  delete from public.tags
  where tags.id = p_id
    and tags.owner_id = auth.uid()
    and tags.revision = p_expected_revision
    and not exists (
      select 1
      from public.entry_tags
      where entry_tags.tag_id = tags.id
        and entry_tags.owner_id = tags.owner_id
    )
  returning tags.id into deleted_id;

  return deleted_id;
end;
$$;

revoke all on function public.merge_tags(uuid,integer,uuid,integer) from public, anon;
revoke all on function public.delete_unused_tag(uuid,integer) from public, anon;
grant execute on function public.merge_tags(uuid,integer,uuid,integer) to authenticated;
grant execute on function public.delete_unused_tag(uuid,integer) to authenticated;
