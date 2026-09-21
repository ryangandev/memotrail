-- Legacy Home and photo writers still pass Location name and notes fields.
-- Those fields no longer carry product meaning, so they must not cause a new
-- Entry-owned snapshot when the address and coordinates are unchanged.

create or replace function public.resolve_home_location_copy_on_write(
  p_location_id uuid,
  p_name text,
  p_address text,
  p_city text,
  p_region text,
  p_country text,
  p_latitude numeric,
  p_longitude numeric,
  p_notes text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  current_location public.locations%rowtype;
  saved_location_id uuid;
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  formatted_address text;
begin
  if location_owner_id is null then return null; end if;

  formatted_address := nullif(
    concat_ws(', ', normalized_address, normalized_city, normalized_region, normalized_country),
    ''
  );

  if p_location_id is not null then
    select * into current_location
    from public.locations as location
    where location.id = p_location_id
      and location.owner_id = location_owner_id
      and location.deleted_at is null;
    if current_location.id is null then return null; end if;

    if current_location.address is not distinct from normalized_address
      and current_location.city is not distinct from normalized_city
      and current_location.region is not distinct from normalized_region
      and current_location.country is not distinct from normalized_country
      and current_location.latitude is not distinct from p_latitude
      and current_location.longitude is not distinct from p_longitude
    then
      return current_location.id;
    end if;
  end if;

  insert into public.locations (
    owner_id, name, formatted_address, address, city, region, country,
    latitude, longitude, notes, metadata
  ) values (
    location_owner_id,
    left(coalesce(formatted_address, 'Location not set'), 200),
    formatted_address,
    normalized_address,
    normalized_city,
    normalized_region,
    normalized_country,
    p_latitude,
    p_longitude,
    null,
    case
      when current_location.id is null then '{}'::jsonb
      else jsonb_build_object(
        'replaces_location_id', current_location.id,
        'entry_owned_snapshot', true
      )
    end
  )
  returning locations.id into saved_location_id;

  return saved_location_id;
end;
$$;

comment on function public.resolve_home_location_copy_on_write(
  uuid,text,text,text,text,text,numeric,numeric,text
) is
  'Compatibility writer for Entry-owned snapshots. Legacy name and notes arguments are ignored.';

alter table public.locations
  add constraint locations_bound_entry_owner_fkey
  foreign key (bound_entry_id, owner_id)
  references public.entries(id, owner_id)
  on delete cascade;

-- Provider resolvers create the snapshot before the enclosing writer knows
-- the Entry id. Require the snapshot to be claimed before that transaction
-- commits so calling a resolver directly cannot rebuild a saved catalog.
create function public.enforce_location_entry_ownership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.locations as location
    where location.id = new.id
      and location.deleted_at is null
      and location.bound_entry_id is null
  ) then
    raise exception using errcode = '23514', message = 'location_requires_entry';
  end if;
  return null;
end;
$$;

create constraint trigger location_must_be_bound
after insert or update of bound_entry_id on public.locations
deferrable initially deferred
for each row execute function public.enforce_location_entry_ownership();
