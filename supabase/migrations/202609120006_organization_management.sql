-- Organization definitions keep stable IDs; Entries are never deleted with a Collection.
alter table public.collections add column revision integer not null default 1 check (revision > 0);
alter table public.tags add column revision integer not null default 1 check (revision > 0);

create function public.advance_organization_revision() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then new.revision := old.revision + 1; end if;
  if tg_table_name = 'collections' then
    if lower(btrim(new.name)) = 'bucket list' and new.system_key is null then
      new.system_key := 'bucket_list';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.advance_organization_revision() from public;
create trigger collection_revision before insert or update on public.collections
for each row execute function public.advance_organization_revision();
create trigger tag_revision before update on public.tags
for each row execute function public.advance_organization_revision();
update public.collections set system_key = 'bucket_list'
where lower(btrim(name)) = 'bucket list' and system_key is null;

create function public.organization_workspace(p_kind text, p_query text default '', p_limit integer default 50, p_offset integer default 0)
returns table(id uuid, name text, system_key text, sort_order integer, revision integer,
  entry_count bigint, total_count bigint)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  if p_kind is null or p_kind not in ('collection','tag') or p_query is null or length(p_query) > 200
    or p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023',message='invalid_organization_page';
  end if;
  if p_kind = 'collection' then
    return query select c.id,c.name,c.system_key,c.sort_order,c.revision,
      (select count(*) from public.entry_collections ec join public.entries e on e.id=ec.entry_id and e.owner_id=ec.owner_id
        where ec.collection_id=c.id and ec.owner_id=auth.uid() and e.deleted_at is null), count(*) over()
    from public.collections c where c.owner_id=auth.uid() and c.archived_at is null
      and position(lower(btrim(p_query)) in lower(c.name)) > 0
    order by c.sort_order,lower(c.name),c.id limit p_limit offset p_offset;
  else
    return query select t.id,t.name,null::text,0,t.revision,
      (select count(*) from public.entry_tags et join public.entries e on e.id=et.entry_id and e.owner_id=et.owner_id
        where et.tag_id=t.id and et.owner_id=auth.uid() and e.deleted_at is null), count(*) over()
    from public.tags t where t.owner_id=auth.uid() and position(lower(btrim(p_query)) in lower(t.name)) > 0
    order by lower(t.name),t.id limit p_limit offset p_offset;
  end if;
end;
$$;

create function public.save_organization(p_kind text,p_name text,p_sort_order integer,
  p_id uuid default null,p_expected_revision integer default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare saved_id uuid; affected_id uuid; old_name text;
begin
  if auth.uid() is null then return null; end if;
  if p_kind is null or p_kind not in ('collection','tag') or nullif(btrim(p_name),'') is null or length(btrim(p_name)) > 80
    or p_sort_order is null or p_sort_order < -1000000 or p_sort_order > 1000000
    or (p_kind='tag' and p_sort_order <> 0) then
    raise exception using errcode='22023',message='invalid_organization_details';
  end if;
  if (p_id is null and p_expected_revision is not null) or (p_id is not null and (p_expected_revision is null or p_expected_revision < 1)) then
    raise exception using errcode='22023',message='invalid_revision';
  end if;
  if p_id is null then
    if p_kind='collection' then
      insert into public.collections(owner_id,name,sort_order) values(auth.uid(),btrim(p_name),p_sort_order) returning id into saved_id;
    else
      insert into public.tags(owner_id,name) values(auth.uid(),btrim(p_name)) returning id into saved_id;
    end if;
    return saved_id;
  end if;
  if p_kind='collection' then
    select name into old_name from public.collections where id=p_id and owner_id=auth.uid()
      and revision=p_expected_revision and archived_at is null for no key update;
  else
    select name into old_name from public.tags where id=p_id and owner_id=auth.uid()
      and revision=p_expected_revision for no key update;
  end if;
  if not found then return null; end if;
  -- Snapshot prior names and reject stale cross-device Entry reviews after a rename.
  if old_name <> btrim(p_name) then
    for affected_id in select e.id from public.entries e where e.owner_id=auth.uid() and (
      (p_kind='collection' and exists(select 1 from public.entry_collections ec where ec.entry_id=e.id and ec.collection_id=p_id and ec.owner_id=auth.uid())) or
      (p_kind='tag' and exists(select 1 from public.entry_tags et where et.entry_id=e.id and et.tag_id=p_id and et.owner_id=auth.uid()))
    ) order by e.id for update loop
      update public.entries set updated_at=clock_timestamp() where id=affected_id and owner_id=auth.uid();
    end loop;
  end if;
  if p_kind='collection' then
    update public.collections set name=btrim(p_name),sort_order=p_sort_order where id=p_id and owner_id=auth.uid() returning id into saved_id;
  else
    update public.tags set name=btrim(p_name) where id=p_id and owner_id=auth.uid() returning id into saved_id;
  end if;
  return saved_id;
end;
$$;

create function public.trash_collection(p_id uuid,p_expected_revision integer)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare affected_id uuid; saved_id uuid;
begin
  if auth.uid() is null then return null; end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode='22023',message='invalid_revision';
  end if;
  perform 1 from public.collections where id=p_id and owner_id=auth.uid()
    and revision=p_expected_revision and archived_at is null for no key update;
  if not found then return null; end if;
  for affected_id in select e.id from public.entries e join public.entry_collections ec
    on ec.entry_id=e.id and ec.owner_id=e.owner_id
    where ec.collection_id=p_id and ec.owner_id=auth.uid() order by e.id for update of e loop
    update public.entries set updated_at=clock_timestamp() where id=affected_id and owner_id=auth.uid();
  end loop;
  update public.collections set archived_at=clock_timestamp() where id=p_id and owner_id=auth.uid() returning id into saved_id;
  return saved_id;
end;
$$;
revoke all on function public.organization_workspace(text,text,integer,integer) from public,anon;
revoke all on function public.save_organization(text,text,integer,uuid,integer) from public,anon;
revoke all on function public.trash_collection(uuid,integer) from public,anon;
grant execute on function public.organization_workspace(text,text,integer,integer) to authenticated;
grant execute on function public.save_organization(text,text,integer,uuid,integer) to authenticated;
grant execute on function public.trash_collection(uuid,integer) to authenticated;

-- Collection names are editable, but Bucket List behavior follows the stable role.
drop function public.goals_workspace(integer,integer);
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
  is_bucket_list boolean,
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
      ) as attachments,
      exists(select 1 from public.entry_collections ec join public.collections c on c.id=ec.collection_id and c.owner_id=ec.owner_id
        where ec.entry_id=entries.id and ec.owner_id=goal_owner_id and c.archived_at is null
        and (c.system_key='bucket_list' or lower(btrim(c.name))='bucket list')) as is_bucket_list
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
        and (collections.system_key = 'bucket_list' or lower(btrim(collections.name)) = 'bucket list')
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
revoke all on function public.goals_workspace(integer,integer) from public,anon;
grant execute on function public.goals_workspace(integer,integer) to authenticated;

create or replace function public.trash_workspace(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  item_kind text,
  item_id uuid,
  title text,
  detail text,
  deleted_at timestamptz,
  expires_at timestamptz,
  revision integer,
  entry_type text,
  parent_entry_id uuid,
  storage_paths text[],
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
      entries.id as item_id,
      coalesce(
        nullif(btrim(entries.title), ''),
        nullif(left(btrim(regexp_replace(entries.body, '\s+', ' ', 'g')), 120), ''),
        'Untitled Entry'
      ) as title,
      nullif(left(btrim(regexp_replace(entries.body, '\s+', ' ', 'g')), 240), '') as detail,
      entries.deleted_at,
      entries.deleted_at + interval '30 days' as expires_at,
      entries.revision,
      entries.entry_type,
      null::uuid as parent_entry_id,
      coalesce(
        (
          select array_agg(media.object_path order by media.created_at, media.id)
          from public.attachments as media
          where media.owner_id = entries.owner_id
            and media.entry_id = entries.id
            and media.bucket_id = 'entry-media'
        ),
        array[]::text[]
      ) as storage_paths
    from public.entries
    where entries.owner_id = auth.uid()
      and entries.deleted_at is not null

    union all

    select
      'habit'::text,
      habits.id,
      habits.name,
      case
        when habits.tracking_mode = 'measure' then
          concat(habits.measurement_unit, ' · target ', habits.target_value::text)
        else 'Check Habit'
      end,
      habits.deleted_at,
      habits.deleted_at + interval '30 days',
      habits.revision,
      null::text,
      null::uuid,
      array[]::text[]
    from public.habits
    where habits.owner_id = auth.uid()
      and habits.deleted_at is not null

    union all

    select
      'attachment'::text,
      media.id,
      coalesce(nullif(btrim(media.original_filename), ''), 'Removed photo'),
      concat(
        'Photo from ',
        coalesce(
          nullif(btrim(entries.title), ''),
          nullif(left(btrim(regexp_replace(entries.body, '\s+', ' ', 'g')), 80), ''),
          'Untitled Entry'
        )
      ),
      media.deleted_at,
      media.deleted_at + interval '30 days',
      null::integer,
      'attachment'::text,
      entries.id,
      array[media.object_path]::text[]
    from public.attachments as media
    join public.entries
      on entries.id = media.entry_id
      and entries.owner_id = media.owner_id
    where media.owner_id = auth.uid()
      and media.deleted_at is not null
      and entries.deleted_at is null

    union all

    select
      'place'::text,
      places.id,
      places.name,
      nullif(
        concat_ws(', ', places.address, places.city, places.region, places.country),
        ''
      ),
      places.deleted_at,
      places.deleted_at + interval '30 days',
      places.revision,
      'place'::text,
      null::uuid,
      array[]::text[]
    from public.places
    where places.owner_id = auth.uid()
      and places.deleted_at is not null
    union all
    select 'person'::text, people.id, people.name, people.relationship_label,
      people.deleted_at, people.deleted_at + interval '30 days', people.revision,
      'person'::text, null::uuid, array[]::text[]
    from public.people where people.owner_id = auth.uid() and people.deleted_at is not null
    union all
    select 'collection'::text,c.id,c.name,'Collection grouping; Entries remain in your archive',
      c.archived_at,c.archived_at+interval '30 days',c.revision,'collection'::text,null::uuid,array[]::text[]
    from public.collections c where c.owner_id=auth.uid() and c.archived_at is not null
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
$$;

create or replace function public.restore_trash_item(
  p_item_kind text,
  p_item_id uuid,
  p_expected_revision integer,
  p_expected_deleted_at timestamptz
)
returns table (
  item_kind text,
  item_id uuid,
  revision integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then
    return;
  end if;

  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    update public.entries
    set deleted_at = null
    where entries.id = p_item_id
      and entries.owner_id = trash_owner_id
      and entries.revision = p_expected_revision
      and entries.deleted_at = p_expected_deleted_at
    returning 'entry'::text, entries.id, entries.revision;
    return;
  end if;

  if p_item_kind = 'habit' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    update public.habits
    set deleted_at = null
    where habits.id = p_item_id
      and habits.owner_id = trash_owner_id
      and habits.revision = p_expected_revision
      and habits.deleted_at = p_expected_deleted_at
    returning 'habit'::text, habits.id, habits.revision;
    return;
  end if;

  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_trash_revision';
    end if;

    return query
    update public.attachments
    set deleted_at = null
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.deleted_at = p_expected_deleted_at
      and exists (
        select 1
        from public.entries
        where entries.id = attachments.entry_id
          and entries.owner_id = trash_owner_id
          and entries.deleted_at is null
      )
    returning 'attachment'::text, attachments.id, null::integer;
    return;
  end if;

  if p_item_kind = 'place' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    update public.places
    set deleted_at = null
    where places.id = p_item_id
      and places.owner_id = trash_owner_id
      and places.revision = p_expected_revision
      and places.deleted_at = p_expected_deleted_at
    returning 'place'::text, places.id, places.revision;
    return;
  end if;

  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;
    return query update public.people set deleted_at = null
      where people.id = p_item_id and people.owner_id = trash_owner_id
        and people.revision = p_expected_revision and people.deleted_at = p_expected_deleted_at
      returning 'person'::text, people.id, people.revision;
    return;
  end if;

  if p_item_kind = 'collection' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    perform 1 from public.collections where collections.id=p_item_id and collections.owner_id=trash_owner_id
      and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at for no key update;
    if not found then return; end if;
    declare affected_id uuid;
    begin
      for affected_id in select e.id from public.entries e join public.entry_collections ec
        on ec.entry_id=e.id and ec.owner_id=e.owner_id where ec.collection_id=p_item_id
        and ec.owner_id=trash_owner_id order by e.id for update of e loop
        update public.entries set updated_at=clock_timestamp() where id=affected_id and owner_id=trash_owner_id;
      end loop;
    end;
    return query update public.collections set archived_at=null
      where collections.id=p_item_id and collections.owner_id=trash_owner_id
        and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at
      returning 'collection'::text,collections.id,collections.revision;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;

create or replace function public.trash_item_storage_paths(
  p_item_kind text,
  p_item_id uuid,
  p_expected_revision integer,
  p_expected_deleted_at timestamptz
)
returns table (object_path text)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null or p_item_id is null or p_expected_deleted_at is null then
    return;
  end if;

  if p_item_kind = 'entry' then
    return query
    select media.object_path
    from public.entries
    join public.attachments as media
      on media.entry_id = entries.id
      and media.owner_id = entries.owner_id
    where entries.id = p_item_id
      and entries.owner_id = auth.uid()
      and entries.revision = p_expected_revision
      and entries.deleted_at = p_expected_deleted_at
      and media.bucket_id = 'entry-media'
    order by media.created_at, media.id;
    return;
  end if;

  if p_item_kind = 'attachment' then
    return query
    select media.object_path
    from public.attachments as media
    join public.entries
      on entries.id = media.entry_id
      and entries.owner_id = media.owner_id
    where media.id = p_item_id
      and media.owner_id = auth.uid()
      and media.deleted_at = p_expected_deleted_at
      and entries.deleted_at is null
      and media.bucket_id = 'entry-media';
    return;
  end if;

  if p_item_kind in ('habit', 'place', 'person') then
    return;
  end if;

  if p_item_kind = 'collection' then return; end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;

create or replace function public.delete_trash_item_forever(
  p_item_kind text,
  p_item_id uuid,
  p_expected_revision integer,
  p_expected_deleted_at timestamptz
)
returns table (
  item_kind text,
  item_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then
    return;
  end if;

  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    delete from public.entries
    where entries.id = p_item_id
      and entries.owner_id = trash_owner_id
      and entries.revision = p_expected_revision
      and entries.deleted_at = p_expected_deleted_at
    returning 'entry'::text, entries.id;
    return;
  end if;

  if p_item_kind = 'habit' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    if not exists (
      select 1
      from public.habits
      where habits.id = p_item_id
        and habits.owner_id = trash_owner_id
        and habits.revision = p_expected_revision
        and habits.deleted_at = p_expected_deleted_at
    ) then
      return;
    end if;

    delete from public.habit_occurrences
    where habit_occurrences.habit_id = p_item_id
      and habit_occurrences.owner_id = trash_owner_id;

    return query
    delete from public.habits
    where habits.id = p_item_id
      and habits.owner_id = trash_owner_id
      and habits.revision = p_expected_revision
      and habits.deleted_at = p_expected_deleted_at
    returning 'habit'::text, habits.id;
    return;
  end if;

  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_trash_revision';
    end if;

    return query
    delete from public.attachments
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.deleted_at = p_expected_deleted_at
      and exists (
        select 1
        from public.entries
        where entries.id = attachments.entry_id
          and entries.owner_id = trash_owner_id
          and entries.deleted_at is null
      )
    returning 'attachment'::text, attachments.id;
    return;
  end if;

  if p_item_kind = 'place' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    delete from public.places
    where places.id = p_item_id
      and places.owner_id = trash_owner_id
      and places.revision = p_expected_revision
      and places.deleted_at = p_expected_deleted_at
      and not exists (
        select 1
        from public.entry_places
        where entry_places.place_id = places.id
          and entry_places.owner_id = trash_owner_id
      )
      and not exists (
        select 1
        from public.homes
        where homes.place_id = places.id
          and homes.owner_id = trash_owner_id
      )
    returning 'place'::text, places.id;
    return;
  end if;

  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;
    return query delete from public.people
      where people.id = p_item_id and people.owner_id = trash_owner_id
        and people.revision = p_expected_revision and people.deleted_at = p_expected_deleted_at
        and not exists(select 1 from public.entry_people ep where ep.person_id = people.id)
      returning 'person'::text, people.id;
    return;
  end if;

  if p_item_kind = 'collection' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.collections
      where collections.id=p_item_id and collections.owner_id=trash_owner_id
        and collections.revision=p_expected_revision and collections.archived_at=p_expected_deleted_at
      returning 'collection'::text,collections.id;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;
