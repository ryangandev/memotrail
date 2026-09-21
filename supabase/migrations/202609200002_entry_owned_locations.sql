-- A Location is an Entry-owned geographic snapshot, not a saved landmark.
-- Keep the legacy name and notes columns only for older client/RPC signatures.
-- Their values are normalized from address facts and are never user-authored.

drop function if exists public.search_locations(text, integer);
drop index if exists public.locations_owner_provider_identity_idx;
drop index if exists public.locations_owner_name_idx;

alter table public.locations add column bound_entry_id uuid;
create index locations_owner_bound_entry_idx
  on public.locations (owner_id, bound_entry_id)
  where bound_entry_id is not null;

-- Split any shared identity before claiming ownership. Home's physical link and
-- entry_places for that same Home are one use, not two separate uses.
do $migration$
declare
  use_row record;
  copy_id uuid;
begin
  for use_row in
    with uses as (
      select distinct place_id as location_id, owner_id, entry_id
      from public.entry_places
      union
      select distinct place_id, owner_id, entry_id
      from public.homes
    )
    select location_id, owner_id, entry_id,
      row_number() over (partition by location_id order by entry_id) as use_number
    from uses
  loop
    if use_row.use_number > 1 then
      insert into public.locations (
        owner_id, name, formatted_address, address, city, region, country,
        latitude, longitude, notes, provider, provider_location_id, metadata,
        postal_code, country_code, timezone_id, result_type, deleted_at
      )
      select owner_id, name, formatted_address, address, city, region, country,
        latitude, longitude, notes, provider, provider_location_id, metadata,
        postal_code, country_code, timezone_id, result_type, deleted_at
      from public.locations
      where id = use_row.location_id and owner_id = use_row.owner_id
      returning id into copy_id;

      update public.homes
      set place_id = copy_id
      where place_id = use_row.location_id
        and owner_id = use_row.owner_id
        and entry_id = use_row.entry_id;

      update public.entry_places
      set place_id = copy_id
      where place_id = use_row.location_id
        and owner_id = use_row.owner_id
        and entry_id = use_row.entry_id;
    end if;
  end loop;
end;
$migration$;

update public.locations as location
set bound_entry_id = uses.entry_id
from (
  select distinct on (location_id) location_id, entry_id
  from (
    select place_id as location_id, entry_id from public.entry_places
    union
    select place_id, entry_id from public.homes
  ) as all_uses
  order by location_id, entry_id
) as uses
where location.id = uses.location_id;

do $migration$
begin
  if exists (
    select 1
    from (
      select place_id as location_id, entry_id from public.entry_places
      union
      select place_id, entry_id from public.homes
    ) as uses
    join public.locations as location on location.id = uses.location_id
    where location.bound_entry_id is distinct from uses.entry_id
  ) then
    raise exception 'shared_location_remains';
  end if;
end;
$migration$;

-- Unlinked Location catalog rows have no Entry or map meaning.
delete from public.locations where bound_entry_id is null;

update public.locations
set
  formatted_address = coalesce(
    nullif(btrim(formatted_address), ''),
    nullif(concat_ws(', ', address, city, region, country), '')
  ),
  name = left(coalesce(
    nullif(btrim(formatted_address), ''),
    nullif(concat_ws(', ', address, city, region, country), ''),
    'Location not set'
  ), 200),
  notes = null;

create function public.normalize_location_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.formatted_address := coalesce(
    nullif(btrim(new.formatted_address), ''),
    nullif(concat_ws(', ', new.address, new.city, new.region, new.country), '')
  );
  new.name := left(coalesce(new.formatted_address, 'Location not set'), 200);
  new.notes := null;
  return new;
end;
$$;

create trigger locations_normalize_snapshot
before insert or update of name, notes, formatted_address, address, city, region, country
on public.locations
for each row execute function public.normalize_location_snapshot();

create function public.claim_location_for_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner_id uuid;
  location_entry_id uuid;
begin
  if new.place_id is null then return new; end if;
  if auth.uid() is not null and auth.uid() <> new.owner_id then
    raise exception using errcode = '42501', message = 'location_owner_mismatch';
  end if;

  select owner_id, bound_entry_id
    into location_owner_id, location_entry_id
  from public.locations
  where id = new.place_id and deleted_at is null
  for update;

  if location_owner_id is distinct from new.owner_id then
    raise exception using errcode = '23503', message = 'location_not_found';
  end if;
  if location_entry_id is not null and location_entry_id <> new.entry_id then
    raise exception using errcode = '23505', message = 'location_belongs_to_another_entry';
  end if;
  if location_entry_id is null then
    update public.locations
    set bound_entry_id = new.entry_id
    where id = new.place_id and owner_id = new.owner_id;
  end if;
  return new;
end;
$$;

create trigger homes_claim_location
after insert or update of place_id, entry_id, owner_id on public.homes
for each row execute function public.claim_location_for_entry();

create trigger entry_places_claim_location
after insert or update of place_id, entry_id, owner_id on public.entry_places
for each row execute function public.claim_location_for_entry();

comment on table public.locations is
  'Private Entry-owned address and coordinate snapshots for geographic search and future map views.';
comment on column public.locations.bound_entry_id is
  'Entry that owns this snapshot. The same address may have independent rows for different Entries.';
comment on column public.locations.name is
  'Compatibility display label derived from address facts, never a custom Location name.';
comment on column public.locations.notes is
  'Compatibility-only column kept for old clients; new writes clear it.';
comment on column public.locations.provider_location_id is
  'Provider provenance only. The same provider result can create separate Entry snapshots.';

-- Provider selection now always creates a fresh snapshot. Reusing a provider
-- identity must never attach one Entry's Location row to another Entry.
create or replace function public.resolve_geoapify_location(p_location jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  resolved_id uuid;
  provider_identity text;
  normalized_formatted_address text;
  latitude numeric;
  longitude numeric;
  confidence numeric;
begin
  if location_owner_id is null then return null; end if;
  if jsonb_typeof(p_location) is distinct from 'object'
    or p_location->>'kind' <> 'provider'
    or p_location->>'provider' <> 'geoapify'
    or jsonb_typeof(p_location->'providerLocationId') is distinct from 'string'
    or jsonb_typeof(p_location->'formattedAddress') is distinct from 'string'
    or jsonb_typeof(p_location->'latitude') is distinct from 'number'
    or jsonb_typeof(p_location->'longitude') is distinct from 'number'
  then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  provider_identity := nullif(btrim(p_location->>'providerLocationId'), '');
  normalized_formatted_address := nullif(btrim(p_location->>'formattedAddress'), '');
  latitude := (p_location->>'latitude')::numeric;
  longitude := (p_location->>'longitude')::numeric;
  confidence := (p_location->>'confidence')::numeric;
  if provider_identity is null or length(provider_identity) > 500
    or normalized_formatted_address is null or length(normalized_formatted_address) > 1000
    or latitude not between -90 and 90 or longitude not between -180 and 180
    or confidence not between 0 and 1
    or length(coalesce(p_location->>'address', '')) > 500
    or length(coalesce(p_location->>'city', '')) > 200
    or length(coalesce(p_location->>'region', '')) > 200
    or length(coalesce(p_location->>'postalCode', '')) > 40
    or length(coalesce(p_location->>'country', '')) > 200
    or length(coalesce(p_location->>'countryCode', '')) > 2
    or length(coalesce(p_location->>'timezone', '')) > 100
    or length(coalesce(p_location->>'resultType', '')) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  insert into public.locations (
    owner_id, name, formatted_address, address, city, region, postal_code,
    country, country_code, latitude, longitude, timezone_id, result_type,
    provider, provider_location_id, metadata
  ) values (
    location_owner_id,
    left(normalized_formatted_address, 200),
    normalized_formatted_address,
    nullif(btrim(p_location->>'address'), ''),
    nullif(btrim(p_location->>'city'), ''),
    nullif(btrim(p_location->>'region'), ''),
    nullif(btrim(p_location->>'postalCode'), ''),
    nullif(btrim(p_location->>'country'), ''),
    lower(nullif(btrim(p_location->>'countryCode'), '')),
    latitude,
    longitude,
    nullif(btrim(p_location->>'timezone'), ''),
    nullif(btrim(p_location->>'resultType'), ''),
    'geoapify',
    provider_identity,
    jsonb_strip_nulls(jsonb_build_object(
      'confidence', p_location->'confidence',
      'match_type', p_location->'matchType',
      'data_source', p_location->'dataSource'
    ))
  ) returning id into resolved_id;

  return resolved_id;
end;
$$;

-- Keep the established rich review wire contract, but route its provider
-- branch through the snapshot resolver rather than its old deduplication SQL.
do $migration$
declare
  function_definition text;
  start_marker text := $start$      select location.id into target_location_id
      from public.locations as location
      where location.owner_id = review_owner_id
        and location.provider = 'geoapify'$start$;
  end_marker text := $end$      end if;
    else
      raise exception using errcode = '22023', message = 'invalid_primary_location';$end$;
  start_pos integer;
  end_pos integer;
begin
  select pg_get_functiondef(
    'public.review_wiki_item_with_location_rich(uuid,integer,text,text,text,text,timestamp with time zone,text,text[],text[],boolean,timestamp with time zone,text,text,jsonb,jsonb,jsonb)'::regprocedure
  ) into function_definition;
  start_pos := strpos(function_definition, start_marker);
  end_pos := strpos(function_definition, end_marker);
  if start_pos = 0 or end_pos <= start_pos then
    raise exception 'review_wiki_item_with_location_rich provider writer changed unexpectedly';
  end if;
  function_definition :=
    left(function_definition, start_pos - 1)
    || '      target_location_id := public.resolve_geoapify_location(p_primary_location);'
    || chr(10)
    || substr(function_definition, end_pos + length('      end if;') + 1);
  execute function_definition;
end;
$migration$;
