-- Add provider-backed Location search and enforce copy-on-write semantics.
-- A Location can be shared by many Entries, but editing geographic facts for
-- one Entry creates a new Location and changes only that Entry's relationship.

alter table public.locations
  add column postal_code text,
  add column country_code text,
  add column timezone_id text,
  add column result_type text,
  add constraint locations_country_code_check
    check (country_code is null or country_code ~ '^[a-z]{2}$');

drop index public.locations_owner_provider_identity_idx;
create unique index locations_owner_provider_identity_idx
  on public.locations (owner_id, provider, provider_location_id)
  where provider is not null and deleted_at is null;

comment on column public.locations.postal_code is
  'Provider-normalized postal or ZIP code when available.';
comment on column public.locations.country_code is
  'Lowercase ISO 3166-1 alpha-2 country code when available.';
comment on column public.locations.timezone_id is
  'IANA time zone identifier returned by the geographic provider.';
comment on column public.locations.result_type is
  'Provider-normalized geographic result type such as building, street, or city.';

-- Location facts are immutable through the table API. Supported writers
-- resolve an existing identity or create a replacement and relink one Entry.
revoke update on public.locations from authenticated;

create or replace function public.search_locations(
  p_query text,
  p_limit integer default 7
)
returns table (
  id uuid,
  revision integer,
  name text,
  formatted_address text,
  address text,
  city text,
  region text,
  postal_code text,
  country text,
  country_code text,
  latitude numeric,
  longitude numeric,
  timezone_id text,
  result_type text
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  normalized_query text := nullif(btrim(p_query), '');
begin
  if location_owner_id is null then return; end if;
  if normalized_query is null or length(normalized_query) < 2
    or length(normalized_query) > 200
    or p_limit is null or p_limit < 1 or p_limit > 20
  then
    raise exception using errcode = '22023', message = 'invalid_location_search';
  end if;

  return query
  select
    location.id,
    location.revision,
    location.name,
    location.formatted_address,
    location.address,
    location.city,
    location.region,
    location.postal_code,
    location.country,
    location.country_code,
    location.latitude,
    location.longitude,
    location.timezone_id,
    location.result_type
  from public.locations as location
  where location.owner_id = location_owner_id
    and location.deleted_at is null
    and concat_ws(
      ' ', location.name, location.formatted_address, location.address,
      location.city, location.region, location.postal_code, location.country
    ) ilike '%' || normalized_query || '%'
  order by
    case when lower(location.name) = lower(normalized_query) then 0 else 1 end,
    location.updated_at desc,
    location.id
  limit p_limit;
end;
$$;

revoke all on function public.search_locations(text,integer) from public, anon;
grant execute on function public.search_locations(text,integer) to authenticated;

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
  normalized_name text := nullif(btrim(p_name), '');
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  geography_unchanged boolean := false;
begin
  if location_owner_id is null or normalized_name is null then return null; end if;

  if p_location_id is not null then
    select * into current_location
    from public.locations as location
    where location.id = p_location_id
      and location.owner_id = location_owner_id
      and location.deleted_at is null;
    if current_location.id is null then return null; end if;

    geography_unchanged :=
      current_location.address is not distinct from normalized_address
      and current_location.city is not distinct from normalized_city
      and current_location.region is not distinct from normalized_region
      and current_location.country is not distinct from normalized_country
      and current_location.latitude is not distinct from p_latitude
      and current_location.longitude is not distinct from p_longitude;

    if current_location.name is not distinct from normalized_name
      and geography_unchanged
      and current_location.notes is not distinct from normalized_notes
    then
      return current_location.id;
    end if;
  end if;

  insert into public.locations (
    owner_id,
    name,
    formatted_address,
    address,
    city,
    region,
    postal_code,
    country,
    country_code,
    latitude,
    longitude,
    timezone_id,
    result_type,
    notes,
    metadata
  ) values (
    location_owner_id,
    normalized_name,
    concat_ws(', ', normalized_address, normalized_city, normalized_region, normalized_country),
    normalized_address,
    normalized_city,
    normalized_region,
    case when geography_unchanged then current_location.postal_code else null end,
    normalized_country,
    case when geography_unchanged then current_location.country_code else null end,
    p_latitude,
    p_longitude,
    case when geography_unchanged then current_location.timezone_id else null end,
    case when geography_unchanged then current_location.result_type else null end,
    normalized_notes,
    case
      when current_location.id is null then '{}'::jsonb
      else jsonb_build_object(
        'forked_from_location_id', current_location.id,
        'copy_on_write', true
      )
    end
  )
  returning locations.id into saved_location_id;

  return saved_location_id;
end;
$$;

revoke all on function public.resolve_home_location_copy_on_write(
  uuid,text,text,text,text,text,numeric,numeric,text
) from public, anon;
grant execute on function public.resolve_home_location_copy_on_write(
  uuid,text,text,text,text,text,numeric,numeric,text
) to authenticated;

-- Rebind the existing Home writer without changing its public wire contract.
do $migration$
declare
  function_definition text;
  old_fragment text := $old$
  if p_place_id is null then
    insert into public.locations (
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
      home_owner_id,
      normalized_place_name,
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_place_notes
    )
    returning locations.id into saved_place_id;
  else
    update public.locations
    set
      name = normalized_place_name,
      address = normalized_address,
      city = normalized_city,
      region = normalized_region,
      country = normalized_country,
      latitude = p_latitude,
      longitude = p_longitude,
      notes = normalized_place_notes
    where locations.id = p_place_id
      and locations.owner_id = home_owner_id
    returning locations.id into saved_place_id;
  end if;
$old$;
  new_fragment text := $new$
  select public.resolve_home_location_copy_on_write(
    p_place_id,
    normalized_place_name,
    normalized_address,
    normalized_city,
    normalized_region,
    normalized_country,
    p_latitude,
    p_longitude,
    normalized_place_notes
  ) into saved_place_id;
$new$;
begin
  select pg_get_functiondef(
    'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)'::regprocedure
  ) into function_definition;
  if position(old_fragment in function_definition) = 0 then
    raise exception 'save_home_entry_with_occurrence Location writer changed unexpectedly';
  end if;
  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

-- Photo-derived Location edits must follow the same rule as Home edits. The
-- legacy writer may relink selected Entries but must never mutate a shared row.
do $migration$
declare
  function_definition text;
  old_fragment text := $old$
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
$old$;
  new_fragment text := $new$
  else
    select location.id into saved_location_id
    from public.locations as location
    where location.id = p_location_id
      and location.owner_id = location_owner_id
      and location.revision = p_expected_revision
      and location.deleted_at is null;
    if saved_location_id is null then return; end if;

    saved_location_id := public.resolve_home_location_copy_on_write(
      p_location_id, normalized_name, normalized_address, normalized_city,
      normalized_region, normalized_country, p_latitude, p_longitude,
      normalized_notes
    );
    if saved_location_id is null then return; end if;
    select location.revision into saved_revision
    from public.locations as location where location.id = saved_location_id;
    if saved_location_id <> p_location_id then
      delete from public.entry_places as link
      where link.place_id = p_location_id
        and link.owner_id = location_owner_id
        and link.entry_id = any(related_ids)
        and link.relationship = 'related';
    end if;
  end if;
$new$;
begin
  select pg_get_functiondef(
    'public.save_location(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)'::regprocedure
  ) into function_definition;
  if position(old_fragment in function_definition) = 0 then
    raise exception 'save_location writer changed unexpectedly';
  end if;
  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

-- Home editors also need to resolve a provider result before their existing
-- copy-on-write writer runs. Resolving never changes an existing Location.
create function public.resolve_geoapify_location(p_location jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  resolved_id uuid;
  provider_identity text;
  normalized_name text;
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
    or jsonb_typeof(p_location->'name') is distinct from 'string'
    or jsonb_typeof(p_location->'formattedAddress') is distinct from 'string'
    or jsonb_typeof(p_location->'latitude') is distinct from 'number'
    or jsonb_typeof(p_location->'longitude') is distinct from 'number'
  then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  provider_identity := nullif(btrim(p_location->>'providerLocationId'), '');
  normalized_name := nullif(btrim(p_location->>'name'), '');
  normalized_formatted_address := nullif(btrim(p_location->>'formattedAddress'), '');
  latitude := (p_location->>'latitude')::numeric;
  longitude := (p_location->>'longitude')::numeric;
  confidence := (p_location->>'confidence')::numeric;
  if provider_identity is null or length(provider_identity) > 500
    or normalized_name is null or length(normalized_name) > 200
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
    owner_id, name, formatted_address, address, city, region,
    postal_code, country, country_code, latitude, longitude,
    timezone_id, result_type, provider, provider_location_id, metadata
  ) values (
    location_owner_id,
    normalized_name,
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
  )
  on conflict (owner_id, provider, provider_location_id)
    where provider is not null and deleted_at is null
  do nothing
  returning locations.id into resolved_id;

  if resolved_id is null then
    select location.id into resolved_id
    from public.locations as location
    where location.owner_id = location_owner_id
      and location.provider = 'geoapify'
      and location.provider_location_id = provider_identity
      and location.deleted_at is null;
  end if;
  return resolved_id;
end;
$$;

revoke all on function public.resolve_geoapify_location(jsonb) from public, anon;
grant execute on function public.resolve_geoapify_location(jsonb) to authenticated;

-- Keep provider resolution and Home creation in one transaction. A stale Home
-- or Capture rolls back the new Location instead of leaving an orphan row.
create function public.save_home_entry_with_geoapify(
  p_input jsonb,
  p_source jsonb,
  p_provider_location jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  location_id uuid;
  saved jsonb;
  collection_names text[];
  tag_names text[];
begin
  if auth.uid() is null then return null; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_home_input';
  end if;

  select coalesce(array_agg(value), '{}'::text[]) into collection_names
  from jsonb_array_elements_text(p_input->'collectionNames') as value;
  select coalesce(array_agg(value), '{}'::text[]) into tag_names
  from jsonb_array_elements_text(p_input->'tagNames') as value;
  location_id := public.resolve_geoapify_location(p_provider_location);
  if location_id is null then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  if p_source is null or p_source = 'null'::jsonb then
    select to_jsonb(result) into saved
    from public.save_home_entry_with_occurrence(
      p_input->>'title', p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision', p_input->>'occurredLabel',
      p_input->>'occurredTimezone', location_id,
      p_input->>'placeName', p_input->>'address', p_input->>'city',
      p_input->>'region', p_input->>'country',
      (p_input->>'latitude')::numeric, (p_input->>'longitude')::numeric,
      p_input->>'placeNotes', p_input->>'moveInReason',
      p_input->>'moveOutReason', collection_names, tag_names,
      (p_input->>'id')::uuid, (p_input->>'revision')::integer
    ) as result;
  else
    select to_jsonb(result) into saved
    from public.extract_capture_to_home(
      (p_source->>'id')::uuid, (p_source->>'revision')::integer,
      p_input->>'title', p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision', p_input->>'occurredLabel',
      p_input->>'occurredTimezone', location_id,
      p_input->>'placeName', p_input->>'address', p_input->>'city',
      p_input->>'region', p_input->>'country',
      (p_input->>'latitude')::numeric, (p_input->>'longitude')::numeric,
      p_input->>'placeNotes', p_input->>'moveInReason',
      p_input->>'moveOutReason', collection_names, tag_names
    ) as result;
  end if;

  if saved is null then
    raise exception using errcode = '40001', message = 'home_changed';
  end if;
  return saved;
end;
$$;

revoke all on function public.save_home_entry_with_geoapify(jsonb,jsonb,jsonb)
  from public, anon;
grant execute on function public.save_home_entry_with_geoapify(jsonb,jsonb,jsonb)
  to authenticated;

create or replace function public.review_wiki_item_with_location_rich(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_photo_place jsonb,
  p_primary_location jsonb,
  p_body_rich jsonb
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  review_owner_id uuid := auth.uid();
  reviewed record;
  target_location_id uuid;
  selected_kind text;
  selected_revision integer;
  normalized_name text;
  normalized_formatted_address text;
  normalized_address text;
  normalized_city text;
  normalized_region text;
  normalized_postal_code text;
  normalized_country text;
  normalized_country_code text;
  normalized_timezone text;
  normalized_result_type text;
  provider_identity text;
  provider_confidence numeric;
  latitude numeric;
  longitude numeric;
begin
  if review_owner_id is null then return; end if;

  -- Reject a stale or inaccessible editor before a provider result can create
  -- an unattached Location. The row lock also protects the later review write.
  perform 1
  from public.entries as item
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind in ('capture', p_item_kind)
    and item.deleted_at is null
  for update;
  if not found then return; end if;

  if p_primary_location is not null and p_primary_location <> 'null'::jsonb then
    if jsonb_typeof(p_primary_location) <> 'object' then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    selected_kind := p_primary_location->>'kind';
    if selected_kind = 'existing' then
      if coalesce(p_primary_location->>'id', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_primary_location->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      selected_revision := (p_primary_location->>'revision')::integer;
      select location.id into target_location_id
      from public.locations as location
      where location.id = (p_primary_location->>'id')::uuid
        and location.owner_id = review_owner_id
        and location.revision = selected_revision
        and location.deleted_at is null;
      if target_location_id is null then
        raise exception using errcode = '40001', message = 'primary_location_changed';
      end if;
    elsif selected_kind = 'provider' then
      if p_primary_location->>'provider' <> 'geoapify'
        or jsonb_typeof(p_primary_location->'providerLocationId') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'name') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'formattedAddress') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'latitude') is distinct from 'number'
        or jsonb_typeof(p_primary_location->'longitude') is distinct from 'number'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      if exists (
        select 1
        from unnest(array[
          'address','city','region','postalCode','country','countryCode',
          'timezone','resultType','matchType','dataSource'
        ]) as optional_key
        where p_primary_location ? optional_key
          and p_primary_location->optional_key is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->optional_key) <> 'string'
      )
        or (
          p_primary_location ? 'confidence'
          and p_primary_location->'confidence' is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->'confidence') <> 'number'
        )
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      provider_identity := nullif(btrim(p_primary_location->>'providerLocationId'), '');
      normalized_name := nullif(btrim(p_primary_location->>'name'), '');
      normalized_formatted_address := nullif(btrim(p_primary_location->>'formattedAddress'), '');
      normalized_address := nullif(btrim(p_primary_location->>'address'), '');
      normalized_city := nullif(btrim(p_primary_location->>'city'), '');
      normalized_region := nullif(btrim(p_primary_location->>'region'), '');
      normalized_postal_code := nullif(btrim(p_primary_location->>'postalCode'), '');
      normalized_country := nullif(btrim(p_primary_location->>'country'), '');
      normalized_country_code := lower(nullif(btrim(p_primary_location->>'countryCode'), ''));
      normalized_timezone := nullif(btrim(p_primary_location->>'timezone'), '');
      normalized_result_type := nullif(btrim(p_primary_location->>'resultType'), '');
      latitude := (p_primary_location->>'latitude')::numeric;
      longitude := (p_primary_location->>'longitude')::numeric;
      provider_confidence := (p_primary_location->>'confidence')::numeric;

      if provider_identity is null or length(provider_identity) > 500
        or normalized_name is null or length(normalized_name) > 200
        or normalized_formatted_address is null or length(normalized_formatted_address) > 1000
        or length(coalesce(normalized_address, '')) > 500
        or length(coalesce(normalized_city, '')) > 200
        or length(coalesce(normalized_region, '')) > 200
        or length(coalesce(normalized_postal_code, '')) > 40
        or length(coalesce(normalized_country, '')) > 200
        or (normalized_country_code is not null and normalized_country_code !~ '^[a-z]{2}$')
        or length(coalesce(normalized_timezone, '')) > 100
        or length(coalesce(normalized_result_type, '')) > 100
        or latitude not between -90 and 90
        or longitude not between -180 and 180
        or provider_confidence not between 0 and 1
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      select location.id into target_location_id
      from public.locations as location
      where location.owner_id = review_owner_id
        and location.provider = 'geoapify'
        and location.provider_location_id = provider_identity
        and location.deleted_at is null;

      if target_location_id is null then
        insert into public.locations (
          owner_id, name, formatted_address, address, city, region,
          postal_code, country, country_code, latitude, longitude,
          timezone_id, result_type, provider, provider_location_id, metadata
        ) values (
          review_owner_id,
          normalized_name,
          normalized_formatted_address,
          normalized_address,
          normalized_city,
          normalized_region,
          normalized_postal_code,
          normalized_country,
          normalized_country_code,
          latitude,
          longitude,
          normalized_timezone,
          normalized_result_type,
          'geoapify',
          provider_identity,
          jsonb_strip_nulls(jsonb_build_object(
            'confidence', p_primary_location->'confidence',
            'match_type', p_primary_location->'matchType',
            'data_source', p_primary_location->'dataSource'
          ))
        )
        on conflict (owner_id, provider, provider_location_id)
          where provider is not null and deleted_at is null
        do nothing
        returning locations.id into target_location_id;

        if target_location_id is null then
          select location.id into target_location_id
          from public.locations as location
          where location.owner_id = review_owner_id
            and location.provider = 'geoapify'
            and location.provider_location_id = provider_identity
            and location.deleted_at is null;
        end if;
      end if;
    else
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
  end if;

  select * into reviewed
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_collection_names,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich,
    false
  );
  if reviewed.entry_id is null then return; end if;

  delete from public.entry_places as link
  where link.entry_id = reviewed.entry_id
    and link.owner_id = review_owner_id
    and link.relationship = 'primary';

  if target_location_id is not null then
    insert into public.entry_places (entry_id, place_id, owner_id, relationship)
    values (reviewed.entry_id, target_location_id, review_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do update
    set relationship = excluded.relationship;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision, reviewed.inbox_status;
end;
$$;

revoke all on function public.review_wiki_item_with_location_rich(
  uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,
  timestamptz,text,text,jsonb,jsonb,jsonb
) from public, anon;
grant execute on function public.review_wiki_item_with_location_rich(
  uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,
  timestamptz,text,text,jsonb,jsonb,jsonb
) to authenticated;

comment on function public.review_wiki_item_with_location_rich(
  uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,
  timestamptz,text,text,jsonb,jsonb,jsonb
) is
  'Atomically reviews or edits a standard Wiki Item and replaces only its primary Location relationship.';

create or replace function public.editable_entry(p_entry_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(e) || jsonb_build_object(
    'collection_names', coalesce(
      (
        select jsonb_agg(c.name order by c.name)
        from public.entry_collections ec
        join public.collections c
          on c.id = ec.collection_id
          and c.owner_id = ec.owner_id
        where ec.entry_id = e.id
          and ec.owner_id = auth.uid()
          and c.archived_at is null
      ),
      '[]'::jsonb
    ),
    'tag_names', coalesce(
      (
        select jsonb_agg(t.name order by t.name)
        from public.entry_tags et
        join public.tags t
          on t.id = et.tag_id
          and t.owner_id = et.owner_id
        where et.entry_id = e.id
          and et.owner_id = auth.uid()
      ),
      '[]'::jsonb
    ),
    'primary_location', (
      select to_jsonb(location)
      from public.entry_places as link
      join public.locations as location
        on location.id = link.place_id
        and location.owner_id = link.owner_id
      where link.entry_id = e.id
        and link.owner_id = auth.uid()
        and link.relationship = 'primary'
        and location.deleted_at is null
      order by link.created_at desc, location.id
      limit 1
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind in ('writing', 'event', 'story');
$$;

revoke all on function public.editable_entry(uuid) from public, anon;
grant execute on function public.editable_entry(uuid) to authenticated;
