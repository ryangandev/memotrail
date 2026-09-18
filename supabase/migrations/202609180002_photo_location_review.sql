-- Keep the existing review RPC wire shape while persisting photo geography as
-- lightweight Locations rather than standalone personal Places.

create or replace function public.save_location(
  p_name text,
  p_address text,
  p_city text,
  p_region text,
  p_country text,
  p_latitude numeric,
  p_longitude numeric,
  p_notes text,
  p_related_entry_ids uuid[],
  p_location_id uuid,
  p_expected_revision integer
)
returns table (place_id uuid, revision integer, was_created boolean)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  saved_location_id uuid;
  saved_revision integer;
  normalized_name text := nullif(btrim(p_name), '');
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  related_ids uuid[];
begin
  if location_owner_id is null then return; end if;
  related_ids := array(
    select distinct related_id
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_id
    order by related_id
  );
  if normalized_name is null or length(normalized_name) > 200
    or length(coalesce(normalized_address, '')) > 500
    or length(coalesce(normalized_city, '')) > 200
    or length(coalesce(normalized_region, '')) > 200
    or length(coalesce(normalized_country, '')) > 200
    or length(coalesce(normalized_notes, '')) > 10000
    or cardinality(related_ids) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_location_details';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
  then
    raise exception using errcode = '22023', message = 'invalid_location_coordinates';
  end if;
  if exists (
    select 1
    from unnest(related_ids) as related_id
    left join public.entries as entry
      on entry.id = related_id
      and entry.owner_id = location_owner_id
      and entry.deleted_at is null
    where entry.id is null
  ) then
    raise exception using errcode = '22023', message = 'invalid_location_relationships';
  end if;
  if p_location_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;
  if p_location_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_location_id is null then
    insert into public.locations (
      owner_id, name, formatted_address, address, city, region, country,
      latitude, longitude, notes
    ) values (
      location_owner_id,
      normalized_name,
      concat_ws(', ', normalized_address, normalized_city, normalized_region, normalized_country),
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_notes
    )
    returning locations.id, locations.revision
      into saved_location_id, saved_revision;
  else
    update public.locations
    set
      name = normalized_name,
      formatted_address = concat_ws(
        ', ', normalized_address, normalized_city, normalized_region, normalized_country
      ),
      address = normalized_address,
      city = normalized_city,
      region = normalized_region,
      country = normalized_country,
      latitude = p_latitude,
      longitude = p_longitude,
      notes = normalized_notes
    where locations.id = p_location_id
      and locations.owner_id = location_owner_id
      and locations.revision = p_expected_revision
      and locations.deleted_at is null
    returning locations.id, locations.revision
      into saved_location_id, saved_revision;
    if saved_location_id is null then return; end if;
  end if;

  insert into public.entry_places(entry_id, place_id, owner_id, relationship)
  select related_id, saved_location_id, location_owner_id, 'related'
  from unnest(related_ids) as related_id
  on conflict on constraint entry_places_pkey do nothing;

  return query select saved_location_id, saved_revision, p_location_id is null;
end;
$$;

do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.review_wiki_item_with_photo_place_core(uuid,integer,text,text,text,text,timestamp with time zone,text,text[],text[],boolean,timestamp with time zone,text,text,jsonb,jsonb,boolean)'::regprocedure
  ) into function_definition;
  function_definition := replace(
    function_definition,
    'from public.save_place(',
    'from public.save_location('
  );
  execute function_definition;
end;
$migration$;

revoke all on function public.save_location(
  text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer
) from public, anon, authenticated;
