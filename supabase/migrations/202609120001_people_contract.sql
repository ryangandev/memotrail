-- People are reusable context, with atomic links and the same recoverable lifecycle as Places.
alter table public.people
  add column revision integer not null default 1 check (revision > 0),
  add column deleted_at timestamptz;

create table public.person_versions (
  id bigint generated always as identity primary key,
  person_id uuid not null,
  owner_id uuid not null,
  version integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now(),
  unique(person_id, version),
  foreign key(person_id, owner_id) references public.people(id, owner_id) on delete cascade
);
alter table public.person_versions enable row level security;
create policy "Read own Person history" on public.person_versions for select to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on public.person_versions from public, anon, authenticated;
grant select on public.person_versions to authenticated;

create function public.archive_person_version() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.person_versions(person_id, owner_id, version, snapshot)
  values(old.id, old.owner_id, old.revision, jsonb_build_object(
    'person', to_jsonb(old),
    'entry_links', coalesce((select jsonb_agg(to_jsonb(ep)) from public.entry_people ep
      where ep.person_id = old.id and ep.owner_id = old.owner_id), '[]'::jsonb)
  ));
  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    return new;
  end if;
  return old;
end;
$$;
revoke all on function public.archive_person_version() from public;
create trigger people_archive_version before update or delete on public.people
  for each row execute function public.archive_person_version();
create index people_owner_active_idx on public.people(owner_id, updated_at desc, id)
  where deleted_at is null;

create function public.people_workspace(p_limit integer default 100, p_offset integer default 0)
returns table(id uuid, name text, relationship_label text, notes text, revision integer,
  linked_entries jsonb, total_count bigint)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0
    or p_offset > 10000 then
    raise exception using errcode = '22023', message = 'invalid_people_page';
  end if;
  return query select p.id, p.name, p.relationship_label, p.notes, p.revision,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'title', e.title, 'body', e.body, 'entry_type', e.entry_type,
      'is_deleted', e.deleted_at is not null
    ) order by e.updated_at desc, e.id)
    from public.entry_people ep join public.entries e on e.id = ep.entry_id and e.owner_id = ep.owner_id
    where ep.person_id = p.id and ep.owner_id = auth.uid()), '[]'::jsonb), count(*) over()
  from public.people p where p.owner_id = auth.uid() and p.deleted_at is null
  order by p.updated_at desc, p.id limit p_limit offset p_offset;
end;
$$;

create function public.save_person(p_name text, p_relationship_label text, p_notes text,
  p_related_entry_ids uuid[], p_person_id uuid, p_expected_revision integer)
returns table(person_id uuid, revision integer)
language plpgsql security invoker set search_path = '' as $$
declare
  saved_id uuid;
  saved_revision integer;
begin
  if auth.uid() is null then return; end if;
  if nullif(btrim(p_name), '') is null or length(btrim(p_name)) > 200
    or length(coalesce(p_relationship_label, '')) > 200 or length(coalesce(p_notes, '')) > 10000
    or p_related_entry_ids is null or cardinality(p_related_entry_ids) > 100 then
    raise exception using errcode = '22023', message = 'invalid_person_details';
  end if;
  if (p_person_id is null and p_expected_revision is not null)
    or (p_person_id is not null and (p_expected_revision is null or p_expected_revision < 1)) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  -- A Person row lock serializes edits with Trash and protects the original links on conflicts.
  if p_person_id is not null then
    perform 1 from public.people p where p.id = p_person_id and p.owner_id = auth.uid()
      and p.revision = p_expected_revision and p.deleted_at is null for update;
    if not found then return; end if;
  end if;
  -- Retain existing links to trashed Entries, but never create a new link to one.
  if exists(select 1 from unnest(p_related_entry_ids) eid where eid is null or not exists(
    select 1 from public.entries e where e.id = eid and e.owner_id = auth.uid()
      and (e.deleted_at is null or exists(select 1 from public.entry_people ep
        where ep.person_id = p_person_id and ep.entry_id = eid and ep.owner_id = auth.uid()))
  )) then
    raise exception using errcode = '22023', message = 'invalid_person_entries';
  end if;
  if p_person_id is null then
    insert into public.people(owner_id, name, relationship_label, notes)
    values(auth.uid(), btrim(p_name), nullif(btrim(p_relationship_label), ''), nullif(btrim(p_notes), ''))
    returning people.id, people.revision into saved_id, saved_revision;
  else
    update public.people set name = btrim(p_name),
      relationship_label = nullif(btrim(p_relationship_label), ''), notes = nullif(btrim(p_notes), '')
    where people.id = p_person_id and people.owner_id = auth.uid()
    returning people.id, people.revision into saved_id, saved_revision;
  end if;
  delete from public.entry_people ep where ep.person_id = saved_id and ep.owner_id = auth.uid();
  insert into public.entry_people(entry_id, person_id, owner_id)
    select distinct eid, saved_id, auth.uid() from unnest(p_related_entry_ids) eid;
  return query select saved_id, saved_revision;
end;
$$;

create function public.trash_person(p_person_id uuid, p_expected_revision integer)
returns table(person_id uuid, revision integer)
language plpgsql security invoker set search_path = '' as $$
begin
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  return query update public.people p set deleted_at = now()
    where p.id = p_person_id and p.owner_id = auth.uid() and p.revision = p_expected_revision
      and p.deleted_at is null and not exists(select 1 from public.entry_people ep
        where ep.person_id = p.id and ep.owner_id = auth.uid())
    returning p.id, p.revision;
end;
$$;
revoke all on function public.people_workspace(integer, integer) from public, anon;
revoke all on function public.save_person(text, text, text, uuid[], uuid, integer) from public, anon;
revoke all on function public.trash_person(uuid, integer) from public, anon;
grant execute on function public.people_workspace(integer, integer) to authenticated;
grant execute on function public.save_person(text, text, text, uuid[], uuid, integer) to authenticated;
grant execute on function public.trash_person(uuid, integer) to authenticated;

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

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;
