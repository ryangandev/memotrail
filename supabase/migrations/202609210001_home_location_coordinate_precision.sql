-- Provider coordinates can have more precision than locations.numeric(9,6).
-- Compare the value that can actually be stored, or an unchanged provider
-- snapshot looks different and leaves its original row unbound at commit.
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
  normalized_latitude numeric := round(p_latitude, 6);
  normalized_longitude numeric := round(p_longitude, 6);
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
      and current_location.latitude is not distinct from normalized_latitude
      and current_location.longitude is not distinct from normalized_longitude
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
    normalized_latitude,
    normalized_longitude,
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
