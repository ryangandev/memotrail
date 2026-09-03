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
    or p_offset is null or p_offset < 0 or p_offset > 10000 then
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
  ), counted as (
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

  if p_item_kind = 'habit' then
    return;
  end if;

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

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;

revoke all on function public.trash_workspace(integer, integer) from public, anon;
revoke all on function public.restore_trash_item(text, uuid, integer, timestamptz) from public, anon;
revoke all on function public.trash_item_storage_paths(text, uuid, integer, timestamptz) from public, anon;
revoke all on function public.delete_trash_item_forever(text, uuid, integer, timestamptz) from public, anon;

grant execute on function public.trash_workspace(integer, integer) to authenticated;
grant execute on function public.restore_trash_item(text, uuid, integer, timestamptz) to authenticated;
grant execute on function public.trash_item_storage_paths(text, uuid, integer, timestamptz) to authenticated;
grant execute on function public.delete_trash_item_forever(text, uuid, integer, timestamptz) to authenticated;

comment on function public.trash_workspace(integer, integer) is
  'Returns one owner-scoped, paginated Trash feed across Entries, Habits, and individually removed attachments.';

comment on function public.restore_trash_item(text, uuid, integer, timestamptz) is
  'Restores one owned Trash item only when its kind, revision, and deletion timestamp still match.';

comment on function public.trash_item_storage_paths(text, uuid, integer, timestamptz) is
  'Returns private Storage paths that must be removed before permanently deleting an owned Trash item.';

comment on function public.delete_trash_item_forever(text, uuid, integer, timestamptz) is
  'Permanently deletes one owned Trash item after the client separately removes any returned private Storage objects.';
