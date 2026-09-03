alter table public.places
  add column revision integer not null default 1,
  add column deleted_at timestamptz,
  add constraint places_revision_positive check (revision > 0);

comment on column public.places.revision is
  'Optimistic concurrency version advanced by the Place history trigger.';
comment on column public.places.deleted_at is
  'A non-null value places an unlinked Place in recoverable Trash.';

create table public.place_versions (
  id bigint generated always as identity primary key,
  place_id uuid not null,
  owner_id uuid not null,
  version integer not null check (version > 0),
  operation text not null check (operation in ('update', 'delete')),
  changed_by uuid references auth.users(id) on delete set null,
  snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (place_id, version),
  foreign key (place_id, owner_id)
    references public.places(id, owner_id)
    on delete cascade
);

alter table public.place_versions enable row level security;

create policy "Users can view their own place history"
on public.place_versions for select
to authenticated
using ((select auth.uid()) = owner_id);

revoke all on public.place_versions from public, anon, authenticated;
grant select on public.place_versions to authenticated;

create or replace function public.archive_place_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_snapshot jsonb;
begin
  select jsonb_build_object(
    'place', to_jsonb(old),
    'entry_links', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', entry_places.entry_id,
            'relationship', entry_places.relationship
          )
          order by entry_places.relationship, entry_places.entry_id
        )
        from public.entry_places
        where entry_places.place_id = old.id
          and entry_places.owner_id = old.owner_id
      ),
      '[]'::jsonb
    )
  )
  into archived_snapshot;

  insert into public.place_versions (
    place_id,
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
    return new;
  end if;

  return old;
end;
$$;

revoke all on function public.archive_place_version() from public;

create trigger places_archive_version
before update or delete on public.places
for each row execute function public.archive_place_version();

create index places_owner_active_updated_idx
  on public.places (owner_id, updated_at desc, id)
  where deleted_at is null;

create index places_owner_active_coordinates_idx
  on public.places (owner_id, latitude, longitude, id)
  where deleted_at is null and latitude is not null and longitude is not null;

create index entry_places_owner_place_relationship_idx
  on public.entry_places (owner_id, place_id, relationship, entry_id);

create index place_versions_owner_place_version_idx
  on public.place_versions (owner_id, place_id, version desc);

create or replace function public.places_workspace(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  place_id uuid,
  name text,
  address text,
  city text,
  region text,
  country text,
  latitude numeric,
  longitude numeric,
  notes text,
  revision integer,
  created_at timestamptz,
  updated_at timestamptz,
  linked_entries jsonb,
  linked_entry_count bigint,
  home_count bigint,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  place_owner_id uuid := auth.uid();
begin
  if place_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_places_page';
  end if;

  return query
  with visible_places as (
    select
      places.id as place_id,
      places.name,
      places.address,
      places.city,
      places.region,
      places.country,
      places.latitude,
      places.longitude,
      places.notes,
      places.revision,
      places.created_at,
      places.updated_at,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', entries.id,
              'title', entries.title,
              'body', entries.body,
              'entry_type', entries.entry_type,
              'inbox_status', entries.inbox_status,
              'occurred_start', entries.occurred_start,
              'occurred_end', entries.occurred_end,
              'date_precision', entries.date_precision,
              'occurred_label', entries.occurred_label,
              'occurred_timezone', entries.occurred_timezone,
              'revision', entries.revision,
              'updated_at', entries.updated_at,
              'relationship', entry_places.relationship,
              'attachments', coalesce(
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
                    and attachments.owner_id = place_owner_id
                    and attachments.deleted_at is null
                    and attachments.variant = 'original'
                ),
                '[]'::jsonb
              )
            )
            order by
              entries.occurred_start desc nulls last,
              entries.updated_at desc,
              entries.id,
              entry_places.relationship
          )
          from public.entry_places
          join public.entries
            on entries.id = entry_places.entry_id
            and entries.owner_id = entry_places.owner_id
          where entry_places.place_id = places.id
            and entry_places.owner_id = place_owner_id
            and entries.deleted_at is null
        ),
        '[]'::jsonb
      ) as linked_entries,
      (
        select count(*)
        from public.entry_places
        join public.entries
          on entries.id = entry_places.entry_id
          and entries.owner_id = entry_places.owner_id
        where entry_places.place_id = places.id
          and entry_places.owner_id = place_owner_id
          and entries.deleted_at is null
      ) as linked_entry_count,
      (
        select count(*)
        from public.homes
        join public.entries
          on entries.id = homes.entry_id
          and entries.owner_id = homes.owner_id
        where homes.place_id = places.id
          and homes.owner_id = place_owner_id
          and entries.deleted_at is null
      ) as home_count
    from public.places
    where places.owner_id = place_owner_id
      and places.deleted_at is null
  ),
  counted_places as (
    select visible_places.*, count(*) over () as total_count
    from visible_places
  )
  select counted_places.*
  from counted_places
  order by
    counted_places.updated_at desc,
    lower(counted_places.name),
    counted_places.place_id
  limit p_limit
  offset p_offset;
end;
$$;

create or replace function public.save_place(
  p_name text,
  p_address text,
  p_city text,
  p_region text,
  p_country text,
  p_latitude numeric,
  p_longitude numeric,
  p_notes text,
  p_related_entry_ids uuid[],
  p_place_id uuid,
  p_expected_revision integer
)
returns table (
  place_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  place_owner_id uuid := auth.uid();
  saved_place_id uuid;
  saved_revision integer;
  normalized_name text := nullif(btrim(p_name), '');
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  normalized_notes text := nullif(btrim(p_notes), '');
begin
  if place_owner_id is null then
    return;
  end if;

  if normalized_name is null or length(normalized_name) > 200
    or length(coalesce(normalized_address, '')) > 500
    or length(coalesce(normalized_city, '')) > 200
    or length(coalesce(normalized_region, '')) > 200
    or length(coalesce(normalized_country, '')) > 200
    or length(coalesce(normalized_notes, '')) > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_place_details';
  end if;

  if (p_latitude is null) <> (p_longitude is null)
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
  then
    raise exception using errcode = '22023', message = 'invalid_place_coordinates';
  end if;

  if cardinality(coalesce(p_related_entry_ids, '{}'::uuid[])) > 100
    or exists (
      select 1
      from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
      where related_entry_id is null
    )
  then
    raise exception using errcode = '22023', message = 'invalid_place_entries';
  end if;

  if p_place_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_place_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
    where not exists (
      select 1
      from public.entries
      where entries.id = related_entry_id
        and entries.owner_id = place_owner_id
        and entries.deleted_at is null
    )
  ) then
    raise exception using errcode = '22023', message = 'invalid_place_entries';
  end if;

  if p_place_id is null then
    insert into public.places (
      owner_id,
      name,
      address,
      city,
      region,
      country,
      latitude,
      longitude,
      notes
    )
    values (
      place_owner_id,
      normalized_name,
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_notes
    )
    returning places.id, places.revision into saved_place_id, saved_revision;
  else
    update public.places
    set
      name = normalized_name,
      address = normalized_address,
      city = normalized_city,
      region = normalized_region,
      country = normalized_country,
      latitude = p_latitude,
      longitude = p_longitude,
      notes = normalized_notes
    where places.id = p_place_id
      and places.owner_id = place_owner_id
      and places.revision = p_expected_revision
      and places.deleted_at is null
    returning places.id, places.revision into saved_place_id, saved_revision;

    if saved_place_id is null then
      return;
    end if;
  end if;

  delete from public.entry_places
  where entry_places.place_id = saved_place_id
    and entry_places.owner_id = place_owner_id
    and entry_places.relationship = 'related';

  insert into public.entry_places (
    entry_id,
    place_id,
    owner_id,
    relationship
  )
  select
    related_entry_id,
    saved_place_id,
    place_owner_id,
    'related'
  from (
    select distinct related_entry_id
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
  ) as related_entries
  where not exists (
    select 1
    from public.entry_places as existing_links
    where existing_links.entry_id = related_entries.related_entry_id
      and existing_links.place_id = saved_place_id
      and existing_links.owner_id = place_owner_id
  )
  on conflict do nothing;

  return query select saved_place_id, saved_revision, p_place_id is null;
end;
$$;

create or replace function public.trash_place(
  p_place_id uuid,
  p_expected_revision integer
)
returns table (
  place_id uuid,
  revision integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  place_owner_id uuid := auth.uid();
begin
  if place_owner_id is null or p_place_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  return query
  update public.places
  set deleted_at = timezone('utc', now())
  where places.id = p_place_id
    and places.owner_id = place_owner_id
    and places.revision = p_expected_revision
    and places.deleted_at is null
    and not exists (
      select 1
      from public.entry_places
      where entry_places.place_id = places.id
        and entry_places.owner_id = place_owner_id
    )
    and not exists (
      select 1
      from public.homes
      where homes.place_id = places.id
        and homes.owner_id = place_owner_id
    )
  returning places.id, places.revision;
end;
$$;

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

  if p_item_kind in ('habit', 'place') then
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

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;

revoke all on function public.places_workspace(integer, integer) from public, anon;
revoke all on function public.save_place(
  text, text, text, text, text, numeric, numeric, text, uuid[], uuid, integer
) from public, anon;
revoke all on function public.trash_place(uuid, integer) from public, anon;

grant execute on function public.places_workspace(integer, integer) to authenticated;
grant execute on function public.save_place(
  text, text, text, text, text, numeric, numeric, text, uuid[], uuid, integer
) to authenticated;
grant execute on function public.trash_place(uuid, integer) to authenticated;

comment on function public.places_workspace(integer, integer) is
  'Returns the authenticated owner''s active reusable Places with Map-ready details, linked Entries, and private attachment metadata.';
comment on function public.save_place(
  text, text, text, text, text, numeric, numeric, text, uuid[], uuid, integer
) is 'Creates or revision-safely updates an owned reusable Place and its editable related Entry links.';
comment on function public.trash_place(uuid, integer) is
  'Revision-safely moves an unlinked owned Place to recoverable Trash.';
comment on function public.trash_workspace(integer, integer) is
  'Returns one owner-scoped, paginated Trash feed across Entries, Habits, Places, and individually removed attachments.';
