-- Separate reusable geographic data from user-authored personal Places.
--
-- `places` remains an independently authored Focused View record. Geographic
-- references owned by Homes and other Wiki Items move to `locations`. The
-- legacy physical names `homes.place_id` and `entry_places` remain for one
-- compatibility window, but now reference `locations`; the canonical
-- `entry_locations` view exposes the intended vocabulary to new clients.

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  formatted_address text,
  address text,
  city text,
  region text,
  country text,
  latitude numeric(9, 6) check (latitude between -90 and 90),
  longitude numeric(9, 6) check (longitude between -180 and 180),
  notes text,
  provider text,
  provider_location_id text,
  metadata jsonb not null default '{}'::jsonb,
  revision integer not null default 1 check (revision > 0),
  deleted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id),
  check ((provider is null) = (provider_location_id is null)),
  check (provider is null or (length(btrim(provider)) > 0 and length(btrim(provider_location_id)) > 0))
);

comment on table public.locations is
  'Lightweight owner-scoped geographic records. Locations are not Wiki Items and do not appear in Library by themselves.';
comment on column public.locations.provider is
  'Optional provider namespace for a future geographic search integration.';
comment on column public.locations.provider_location_id is
  'Opaque provider identity used to deduplicate external geographic results.';

create unique index locations_owner_provider_identity_idx
  on public.locations (owner_id, provider, provider_location_id)
  where provider is not null;
create index locations_owner_name_idx
  on public.locations (owner_id, lower(name), id);
create index locations_owner_hierarchy_idx
  on public.locations (owner_id, country, region, city, id);

create trigger locations_set_updated_at
before update on public.locations
for each row execute function public.set_updated_at();

create or replace function public.bump_location_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.revision = old.revision + 1;
  return new;
end;
$$;

create trigger locations_bump_revision
before update on public.locations
for each row execute function public.bump_location_revision();

alter table public.locations enable row level security;
create policy "Users can view their own locations"
on public.locations for select to authenticated
using ((select auth.uid()) = owner_id);
create policy "Users can create their own locations"
on public.locations for insert to authenticated
with check ((select auth.uid()) = owner_id);
create policy "Users can update their own locations"
on public.locations for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);
create policy "Users can delete their own locations"
on public.locations for delete to authenticated
using ((select auth.uid()) = owner_id);

revoke all on public.locations from public, anon, authenticated;
grant select, insert, update, delete on public.locations to authenticated;

-- Preserve every geographic identity currently referenced by a Home or Wiki
-- Item. The copied Location intentionally becomes independent immediately;
-- later edits to a personal Place do not rewrite it.
insert into public.locations (
  id,
  owner_id,
  name,
  formatted_address,
  address,
  city,
  region,
  country,
  latitude,
  longitude,
  notes,
  metadata,
  revision,
  deleted_at,
  created_at,
  updated_at
)
select
  place.id,
  place.owner_id,
  place.name,
  concat_ws(', ', nullif(btrim(place.address), ''), nullif(btrim(place.city), ''), nullif(btrim(place.region), ''), nullif(btrim(place.country), '')),
  place.address,
  place.city,
  place.region,
  place.country,
  place.latitude,
  place.longitude,
  place.notes,
  jsonb_build_object('migration_source', 'place'),
  place.revision,
  place.deleted_at,
  place.created_at,
  place.updated_at
from public.places as place
where exists (
    select 1 from public.homes as home
    where home.place_id = place.id and home.owner_id = place.owner_id
  )
  or exists (
    select 1 from public.entry_places as link
    where link.place_id = place.id and link.owner_id = place.owner_id
  )
on conflict (id) do nothing;

-- The legacy link table now stores Location relationships. Keeping its
-- physical shape prevents older history snapshots from becoming unreadable.
alter table public.entry_places
  drop constraint entry_places_place_id_owner_id_fkey,
  add constraint entry_places_location_id_owner_id_fkey
    foreign key (place_id, owner_id)
    references public.locations(id, owner_id)
    on delete cascade;

comment on table public.entry_places is
  'Compatibility storage for Wiki Item to Location relationships. New code reads the entry_locations view.';
comment on column public.entry_places.place_id is
  'Legacy physical name for location_id during the cross-client compatibility window.';

create view public.entry_locations
with (security_invoker = true)
as
select
  entry_id,
  place_id as location_id,
  owner_id,
  relationship,
  created_at
from public.entry_places;

revoke all on public.entry_locations from public, anon, authenticated;
grant select on public.entry_locations to authenticated;
comment on view public.entry_locations is
  'Canonical read contract for Wiki Item to Location relationships.';

alter table public.homes
  drop constraint homes_place_id_owner_id_fkey,
  add constraint homes_location_id_owner_id_fkey
    foreign key (place_id, owner_id)
    references public.locations(id, owner_id)
    on delete restrict;

comment on column public.homes.place_id is
  'Legacy physical name for the Home primary location_id during the cross-client compatibility window.';

-- Rebind current Home, history, and photo-location contracts to lightweight
-- Locations without changing their wire signatures in the same release.
do $migration$
declare
  function_name text;
  function_definition text;
begin
  foreach function_name in array array[
    'homes_workspace(integer,integer)',
    'save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)',
    'entry_history_snapshot(entries)',
    'restore_entry_version(uuid,integer,integer)',
    'review_wiki_item_with_photo_place_core(uuid,integer,text,text,text,text,timestamp with time zone,text,text[],text[],boolean,timestamp with time zone,text,text,jsonb,jsonb,boolean)'
  ]
  loop
    select pg_get_functiondef(function_name::regprocedure)
    into function_definition;
    function_definition := replace(function_definition, 'public.places', 'public.locations');
    function_definition := replace(function_definition, 'entry_places.', '__entry_places__.');
    function_definition := replace(function_definition, 'places.', 'locations.');
    function_definition := replace(function_definition, '__entry_places__.', 'entry_places.');
    execute function_definition;
  end loop;
end;
$migration$;

-- Wiki Item search keeps Place as a standalone Focused View while using
-- lightweight Locations as searchable context for linked records.
do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.search_wiki_items(text,text[],text[],text[],date,date,integer,integer,text)'::regprocedure
  ) into function_definition;
  function_definition := replace(
    function_definition,
    'join public.places as related',
    'join public.locations as related'
  );
  execute function_definition;
end;
$migration$;

-- A personal Place owns only its authored details and history. It no longer
-- owns links, Home relationships, or a duplicate canonical Wiki Item.
create or replace function public.archive_place_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.place_versions (
    place_id, owner_id, version, operation, changed_by, snapshot
  )
  values (
    old.id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    jsonb_build_object('place', to_jsonb(old))
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    return new;
  end if;
  return old;
end;
$$;

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
  if place_owner_id is null then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_places_page';
  end if;

  return query
  select
    place.id,
    place.name,
    place.address,
    place.city,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.notes,
    place.revision,
    place.created_at,
    place.updated_at,
    '[]'::jsonb,
    0::bigint,
    0::bigint,
    count(*) over ()
  from public.places as place
  where place.owner_id = place_owner_id
    and place.deleted_at is null
  order by place.updated_at desc, lower(place.name), place.id
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
returns table (place_id uuid, revision integer, was_created boolean)
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
  if place_owner_id is null then return; end if;
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
  if cardinality(coalesce(p_related_entry_ids, '{}'::uuid[])) > 0 then
    raise exception using errcode = '22023', message = 'place_relationships_removed';
  end if;
  if p_place_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;
  if p_place_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_place_id is null then
    insert into public.places (
      owner_id, name, address, city, region, country, latitude, longitude, notes
    ) values (
      place_owner_id, normalized_name, normalized_address, normalized_city,
      normalized_region, normalized_country, p_latitude, p_longitude,
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
    if saved_place_id is null then return; end if;
  end if;

  return query select saved_place_id, saved_revision, p_place_id is null;
end;
$$;

create or replace function public.trash_place(
  p_place_id uuid,
  p_expected_revision integer
)
returns table (place_id uuid, revision integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null or p_place_id is null then return; end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  return query
  update public.places
  set deleted_at = timezone('utc', now())
  where places.id = p_place_id
    and places.owner_id = auth.uid()
    and places.revision = p_expected_revision
    and places.deleted_at is null
  returning places.id, places.revision;
end;
$$;

create or replace function public.delete_trash_item_forever(
  p_item_kind text,
  p_item_id uuid,
  p_expected_revision integer,
  p_expected_deleted_at timestamptz
)
returns table (item_kind text, item_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.entries
      where entries.id=p_item_id and entries.owner_id=trash_owner_id
        and entries.revision=p_expected_revision and entries.deleted_at=p_expected_deleted_at
      returning 'entry'::text,entries.id;
    return;
  end if;
  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode='22023',message='unexpected_trash_revision';
    end if;
    return query delete from public.attachments
      where attachments.id=p_item_id and attachments.owner_id=trash_owner_id
        and attachments.deleted_at=p_expected_deleted_at
        and exists(select 1 from public.entries where entries.id=attachments.entry_id
          and entries.owner_id=trash_owner_id and entries.deleted_at is null)
      returning 'attachment'::text,attachments.id;
    return;
  end if;
  if p_item_kind = 'place' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.places
      where places.id=p_item_id and places.owner_id=trash_owner_id
        and places.revision=p_expected_revision and places.deleted_at=p_expected_deleted_at
      returning 'place'::text,places.id;
    return;
  end if;
  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.people
      where people.id=p_item_id and people.owner_id=trash_owner_id
        and people.revision=p_expected_revision and people.deleted_at=p_expected_deleted_at
        and not exists(select 1 from public.entry_people ep where ep.person_id=people.id)
      returning 'person'::text,people.id;
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
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$$;

-- Stop creating and requiring the duplicate Place Wiki Item identity before
-- removing existing mirrors. Places remain owner-scoped, versioned records.
drop trigger if exists places_create_wiki_item on public.places;
drop trigger if exists places_sync_wiki_item on public.places;
alter table public.places drop constraint if exists places_entry_identity_fk;

delete from public.entries
where item_kind = 'entity' and item_subtype = 'place';

drop function if exists public.sync_place_wiki_item();

-- Places stay exportable as authored records; Locations and their links are
-- added as separate portable datasets.
create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','entry_versions','collections','tags','entry_collections','entry_tags',
    'places','locations','people','entry_locations','entry_people','timeline_tracks','timeline_items',
    'homes','vehicles','goals','attachments','entry_links','person_versions','place_versions',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$$;

revoke all on function public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer) from public, anon;
revoke all on function public.trash_place(uuid,integer) from public, anon;
revoke all on function public.places_workspace(integer,integer) from public, anon;
grant execute on function public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer) to authenticated;
grant execute on function public.trash_place(uuid,integer) to authenticated;
grant execute on function public.places_workspace(integer,integer) to authenticated;
