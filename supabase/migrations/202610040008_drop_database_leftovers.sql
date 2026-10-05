-- Database leftovers from earlier Location and review designs are removed.
-- Every link between an Entry and a Location now lives in entry_locations, including a Home's,
-- so homes.place_id and the "home" link are gone and Homes save their Location like Vehicles.
-- Locations lose the name and notes columns kept for old clients, and the unused deleted_at.
-- Functions no client calls are dropped, and the Entry editor saves through one function.
-- Entries a Want to Do item was taken from are plain Entries again, so the editor can save them.

drop function public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.save_timeline_entry(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_entry_id uuid, p_expected_revision integer);
drop function public.mark_goal_achieved_with_first_time(p_goal_entry_id uuid, p_expected_revision integer, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text);
drop function public.library_text_matches(p_text text, p_query text);
drop function public.save_location(p_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_notes text, p_related_entry_ids uuid[], p_location_id uuid, p_expected_revision integer);
drop function public.save_home_entry_with_geoapify(p_input jsonb, p_provider_location jsonb);
drop function public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.resolve_home_location_copy_on_write(p_location_id uuid, p_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_notes text);
drop function public.homes_workspace(p_limit integer, p_offset integer);
drop function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb);
drop function public.review_wiki_item_with_photo_place_core(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb);
drop function public.review_wiki_item_with_occurrence_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_body_rich jsonb);

-- One link table. A Home's Location becomes its primary Location, which every Home already has
-- as a "home" link; the insert covers any Home whose link is missing.
drop view public.entry_locations;

insert into public.entry_places (entry_id, place_id, owner_id, relationship)
select home.entry_id, home.place_id, home.owner_id, 'primary'
from public.homes as home
where home.place_id is not null
union
select link.entry_id, link.place_id, link.owner_id, 'primary'
from public.entry_places as link
where link.relationship = 'home'
on conflict on constraint entry_places_pkey do nothing;
delete from public.entry_places where relationship = 'home';
-- Run the deferred Location checks now: tables with pending trigger events cannot be altered.
set constraints all immediate;
set constraints all deferred;

drop trigger homes_claim_location on public.homes;
drop trigger homes_discard_unlinked_location on public.homes;
alter table public.homes drop column place_id;

alter table public.entry_places rename to entry_locations;
alter table public.entry_locations rename column place_id to location_id;
alter table public.entry_locations rename constraint entry_places_pkey to entry_locations_pkey;
alter table public.entry_locations rename constraint entry_places_entry_id_owner_id_fkey to entry_locations_entry_id_owner_id_fkey;
alter table public.entry_locations rename constraint entry_places_location_id_owner_id_fkey to entry_locations_location_id_owner_id_fkey;
alter index public.entry_places_owner_place_relationship_idx rename to entry_locations_owner_location_relationship_idx;
alter trigger entry_places_claim_location on public.entry_locations rename to entry_locations_claim_location;
alter table public.entry_locations alter column relationship drop default;
update public.entry_locations set relationship = 'photo' where relationship = 'related';
alter table public.entry_locations
  add constraint entry_locations_relationship_check check (relationship in ('primary', 'photo'));
comment on table public.entry_locations is
  'Links an Entry to the Locations it owns: its primary Location, and Locations taken from photo GPS.';

-- Locations: the name and notes kept for old clients, and a deleted_at nothing ever set.
drop trigger locations_normalize_snapshot on public.locations;
alter table public.locations drop column name, drop column notes, drop column deleted_at;

create or replace function public.normalize_location_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.formatted_address := coalesce(
    nullif(btrim(new.formatted_address), ''),
    nullif(concat_ws(', ', new.address, new.city, new.region, new.country), '')
  );
  return new;
end;
$$;
create trigger locations_normalize_snapshot
before insert or update of formatted_address, address, city, region, country
on public.locations
for each row execute function public.normalize_location_snapshot();

create or replace function public.claim_location_for_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner_id uuid;
  location_entry_id uuid;
begin
  if auth.uid() is not null and auth.uid() <> new.owner_id then
    raise exception using errcode = '42501', message = 'location_owner_mismatch';
  end if;

  select owner_id, bound_entry_id
    into location_owner_id, location_entry_id
  from public.locations
  where id = new.location_id
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
    where id = new.location_id and owner_id = new.owner_id;
  end if;
  return new;
end;
$$;

create or replace function public.discard_unlinked_location()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.locations as location
  where location.id = old.location_id and location.owner_id = old.owner_id
    and not exists (select 1 from public.entry_locations as link where link.location_id = old.location_id);
  return null;
end;
$$;

create or replace function public.enforce_location_entry_ownership()
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
      and location.bound_entry_id is null
  ) then
    raise exception using errcode = '23514', message = 'location_requires_entry';
  end if;
  return null;
end;
$$;

-- A constraint trigger's constraint keeps its old name through a rename, so it is recreated.
drop trigger entry_places_discard_unlinked_location on public.entry_locations;
create constraint trigger entry_locations_discard_unlinked_location
after delete or update of location_id on public.entry_locations
deferrable initially deferred
for each row execute function public.discard_unlinked_location();

revoke all on function public.normalize_location_snapshot() from public, anon, authenticated;
revoke all on function public.claim_location_for_entry() from public, anon, authenticated;
revoke all on function public.enforce_location_entry_ownership() from public, anon, authenticated;

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
    owner_id, formatted_address, address, city, region, postal_code,
    country, country_code, latitude, longitude, timezone_id, result_type,
    provider, provider_location_id, metadata
  ) values (
    location_owner_id,
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

create or replace function public.resolve_selected_location(p_location jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  location_owner_id uuid := auth.uid();
  resolved_id uuid;
begin
  if location_owner_id is null then return null; end if;
  if p_location is null or p_location = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p_location) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_primary_location';
  end if;

  if p_location->>'kind' = 'existing' then
    if coalesce(p_location->>'id', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      or coalesce(p_location->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
    then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    select location.id into resolved_id
    from public.locations as location
    where location.id = (p_location->>'id')::uuid
      and location.owner_id = location_owner_id
      and location.revision = (p_location->>'revision')::integer;
    if resolved_id is null then
      raise exception using errcode = '40001', message = 'primary_location_changed';
    end if;
    return resolved_id;
  end if;

  if p_location->>'kind' = 'provider' then
    resolved_id := public.resolve_geoapify_location(p_location);
    if resolved_id is null then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    return resolved_id;
  end if;

  -- An address typed by hand, which has no coordinates.
  if p_location->>'kind' = 'manual' then
    if exists (
      select 1
      from unnest(array['address', 'city', 'region', 'country']) as field
      where p_location ? field
        and p_location->field is distinct from 'null'::jsonb
        and jsonb_typeof(p_location->field) <> 'string'
    )
      or length(coalesce(p_location->>'address', '')) > 500
      or length(coalesce(p_location->>'city', '')) > 200
      or length(coalesce(p_location->>'region', '')) > 200
      or length(coalesce(p_location->>'country', '')) > 200
      or coalesce(nullif(btrim(p_location->>'address'), ''), nullif(btrim(p_location->>'city'), ''),
        nullif(btrim(p_location->>'region'), ''), nullif(btrim(p_location->>'country'), '')) is null
    then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    insert into public.locations (owner_id, address, city, region, country)
    values (
      location_owner_id,
      nullif(btrim(p_location->>'address'), ''),
      nullif(btrim(p_location->>'city'), ''),
      nullif(btrim(p_location->>'region'), ''),
      nullif(btrim(p_location->>'country'), '')
    )
    returning id into resolved_id;
    return resolved_id;
  end if;

  raise exception using errcode = '22023', message = 'invalid_primary_location';
end;
$$;

-- Links the Entry's primary Location, replacing any earlier one. The selection is a Location the
-- Entry already has, a provider result, or a typed address; a null selection clears it.
create function public.replace_primary_location(p_entry_id uuid, p_location jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  link_owner_id uuid := auth.uid();
  selected_location_id uuid;
begin
  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_locations as link
  where link.entry_id = p_entry_id
    and link.owner_id = link_owner_id
    and link.relationship = 'primary'
    and link.location_id is distinct from selected_location_id;
  if selected_location_id is not null then
    insert into public.entry_locations (entry_id, location_id, owner_id, relationship)
    values (p_entry_id, selected_location_id, link_owner_id, 'primary')
    on conflict on constraint entry_locations_pkey do nothing;
  end if;
end;
$$;
revoke all on function public.replace_primary_location(uuid, jsonb) from public, anon;
grant execute on function public.replace_primary_location(uuid, jsonb) to authenticated, service_role;

-- The source of a Want to Do item was marked source_capture, which the editor could open but not save.
update public.entries set item_subtype = 'entry' where item_kind = 'entry' and item_subtype = 'source_capture';
alter table public.entries drop constraint entries_entry_subtype_valid;
alter table public.entries add constraint entries_entry_subtype_valid
  check (item_kind <> 'entry' or item_subtype in ('entry', 'moment', 'first_time', 'period'));

create or replace function public.record_photo_location_source(p_location_id uuid, p_entry_id uuid, p_attachment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.attachments as attachment
    where attachment.id = p_attachment_id
      and attachment.owner_id = auth.uid()
      and attachment.entry_id = p_entry_id
      and attachment.deleted_at is null
      and attachment.variant = 'original'
  ) or not exists (
    select 1 from public.locations as location
    where location.id = p_location_id
      and location.owner_id = auth.uid()
      and location.bound_entry_id = p_entry_id
  ) then
    raise exception using errcode = '42501', message = 'invalid_photo_location_source';
  end if;

  update public.locations
  set coordinate_source = 'photo_gps', source_attachment_id = p_attachment_id
  where id = p_location_id and owner_id = auth.uid();
end;
$$;

create or replace function public.editable_entry(p_entry_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(e) || jsonb_build_object(
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
      from public.entry_locations as link
      join public.locations as location
        on location.id = link.location_id
        and location.owner_id = link.owner_id
      where link.entry_id = e.id
        and link.owner_id = auth.uid()
        and link.relationship = 'primary'
      order by link.created_at desc, location.id
      limit 1
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind = 'entry' and e.item_subtype = 'entry';
$$;

create or replace function public.entry_detail(p_entry_id uuid)
returns jsonb
language sql
stable security definer
set search_path = ''
as $$
  select (to_jsonb(entry) - 'embedding' - 'search_document') || jsonb_build_object(
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = entry.id
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
          'location_id', link.location_id,
          'relationship', link.relationship,
          'formatted_address', location.formatted_address,
          'latitude', location.latitude,
          'longitude', location.longitude
        ) order by link.relationship, link.location_id)
      from public.entry_locations as link
      join public.locations as location on location.id = link.location_id
      where link.entry_id = entry.id
    ), '[]'::jsonb),
    'timeline_items', coalesce((
      select jsonb_agg(jsonb_build_object('track_id', placement.track_id, 'timeline_kind', placement.timeline_kind, 'track_name', track.name)
        order by placement.track_id)
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = entry.id
    ), '[]'::jsonb),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('target_entry_id', link.target_entry_id, 'relationship', link.relationship)
        order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = entry.id
    ), '[]'::jsonb)
  )
  from public.entries as entry
  where entry.id = p_entry_id and entry.owner_id = auth.uid();
$$;

create or replace function public.save_first_time_with_location(p_input jsonb, p_location jsonb)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
set search_path = ''
as $$
declare
  saved record;
begin
  if auth.uid() is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_first_time_input';
  end if;

  select * into saved
  from public.save_first_time_with_occurrence(
    p_input->>'title',
    p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    p_input->>'datePrecision',
    p_input->>'occurredLabel',
    p_input->>'occurredTimezone',
    array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb))),
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer,
    (p_input->>'occurredEnd')::timestamptz
  );
  if saved.entry_id is null then return; end if;

  perform public.replace_primary_location(saved.entry_id, p_location);

  return query select saved.entry_id, saved.revision, saved.was_created;
end;
$$;

create or replace function public.save_vehicle_with_location(p_input jsonb, p_location jsonb)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
set search_path = ''
as $$
declare
  saved record;
begin
  if auth.uid() is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_vehicle_input';
  end if;

  select * into saved
  from public.save_vehicle_entry_with_occurrence(
    p_input->>'title',
    p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    (p_input->>'occurredEnd')::timestamptz,
    p_input->>'datePrecision',
    p_input->>'occurredLabel',
    p_input->>'occurredTimezone',
    p_input->>'make',
    p_input->>'model',
    (p_input->>'modelYear')::integer,
    p_input->>'color',
    array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb))),
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer
  );
  if saved.entry_id is null then return; end if;

  perform public.replace_primary_location(saved.entry_id, p_location);

  return query select saved.entry_id, saved.revision, saved.was_created;
end;
$$;

-- A Home keeps its Location as its primary Location, so it no longer takes address fields.
create function public.save_home_entry_with_occurrence(
  p_title text,
  p_body text,
  p_occurred_start timestamp with time zone,
  p_occurred_end timestamp with time zone,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_move_in_reason text,
  p_move_out_reason text,
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  home_track_id uuid;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_move_in_reason text := nullif(btrim(p_move_in_reason), '');
  normalized_move_out_reason text := nullif(btrim(p_move_out_reason), '');
begin
  if home_owner_id is null then
    return;
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_home_content';
  end if;

  if length(coalesce(normalized_move_in_reason, '')) > 10000
    or length(coalesce(normalized_move_out_reason, '')) > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_home_details';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_home_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_home_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_home_timezone';
    end;
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_home_range';
  end if;

  if normalized_move_out_reason is not null and p_occurred_end is null then
    raise exception using errcode = '22023', message = 'home_move_out_requires_date';
  end if;

  if p_date_precision is null or p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'home_label_too_long';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      home_owner_id,
      normalized_title,
      normalized_body,
      'entity',
      'home',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = home_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.homes
        where homes.entry_id = entries.id
          and homes.owner_id = home_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  insert into public.homes (
    entry_id,
    owner_id,
    move_in_reason,
    move_out_reason
  )
  values (
    saved_entry_id,
    home_owner_id,
    normalized_move_in_reason,
    normalized_move_out_reason
  )
  on conflict on constraint homes_pkey do update
  set
    move_in_reason = excluded.move_in_reason,
    move_out_reason = excluded.move_out_reason
  where (homes.move_in_reason, homes.move_out_reason)
    is distinct from (excluded.move_in_reason, excluded.move_out_reason);

  select timeline_tracks.id
  into home_track_id
  from public.timeline_tracks
  where timeline_tracks.owner_id = home_owner_id
    and timeline_tracks.system_key = 'homes'
  order by timeline_tracks.sort_order, timeline_tracks.id
  limit 1;

  if home_track_id is null then
    select timeline_tracks.id
    into home_track_id
    from public.timeline_tracks
    where timeline_tracks.owner_id = home_owner_id
      and lower(btrim(timeline_tracks.name)) = 'homes'
      and timeline_tracks.system_key is null
    order by timeline_tracks.sort_order, timeline_tracks.id
    limit 1;

    if home_track_id is not null then
      update public.timeline_tracks
      set system_key = 'homes'
      where timeline_tracks.id = home_track_id
        and timeline_tracks.owner_id = home_owner_id
        and timeline_tracks.system_key is null;
    end if;
  end if;

  if home_track_id is null then
    insert into public.timeline_tracks (
      owner_id,
      name,
      system_key,
      sort_order
    )
    values (
      home_owner_id,
      'Homes',
      'homes',
      40
    )
    returning timeline_tracks.id into home_track_id;
  end if;

  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = home_owner_id
    and timeline_items.track_id is distinct from home_track_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    home_track_id,
    home_owner_id,
    'stage'
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$$;
revoke all on function public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, text, text, text[], uuid, integer) from public, anon;
grant execute on function public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, text, text, text[], uuid, integer) to authenticated, service_role;

create function public.save_home_with_location(p_input jsonb, p_location jsonb)
returns table(entry_id uuid, revision integer, was_created boolean, location_id uuid)
language plpgsql
set search_path = ''
as $$
declare
  saved record;
begin
  if auth.uid() is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_home_input';
  end if;

  select * into saved
  from public.save_home_entry_with_occurrence(
    p_input->>'title',
    p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    (p_input->>'occurredEnd')::timestamptz,
    p_input->>'datePrecision',
    p_input->>'occurredLabel',
    p_input->>'occurredTimezone',
    p_input->>'moveInReason',
    p_input->>'moveOutReason',
    array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb))),
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer
  );
  if saved.entry_id is null then return; end if;

  perform public.replace_primary_location(saved.entry_id, p_location);

  return query
  select saved.entry_id, saved.revision, saved.was_created, (
    select link.location_id from public.entry_locations as link
    where link.entry_id = saved.entry_id and link.relationship = 'primary'
  );
end;
$$;
revoke all on function public.save_home_with_location(jsonb, jsonb) from public, anon;
grant execute on function public.save_home_with_location(jsonb, jsonb) to authenticated, service_role;

create function public.homes_workspace(p_limit integer default 50, p_offset integer default 0)
returns table(
  entry_id uuid,
  title text,
  body text,
  occurred_start timestamp with time zone,
  occurred_end timestamp with time zone,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamp with time zone,
  move_in_reason text,
  move_out_reason text,
  timeline_track_id uuid,
  timeline_track_name text,
  tag_names text[],
  attachments jsonb,
  total_count bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
begin
  if home_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_homes_page';
  end if;

  return query
  with visible_homes as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.updated_at,
      homes.move_in_reason,
      homes.move_out_reason,
      timeline_tracks.id as timeline_track_id,
      timeline_tracks.name as timeline_track_name,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = home_owner_id
        ),
        array[]::text[]
      ) as tag_names,
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
            and attachments.owner_id = home_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.homes
      on homes.entry_id = entries.id
      and homes.owner_id = entries.owner_id
    left join public.timeline_items
      on timeline_items.entry_id = entries.id
      and timeline_items.owner_id = entries.owner_id
      and exists (
        select 1
        from public.timeline_tracks as home_tracks
        where home_tracks.id = timeline_items.track_id
          and home_tracks.owner_id = timeline_items.owner_id
          and home_tracks.system_key = 'homes'
      )
    left join public.timeline_tracks
      on timeline_tracks.id = timeline_items.track_id
      and timeline_tracks.owner_id = timeline_items.owner_id
      and timeline_tracks.system_key = 'homes'
    where entries.owner_id = home_owner_id
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
  ),
  counted_homes as (
    select visible_homes.*, count(*) over () as total_count
    from visible_homes
  )
  select counted_homes.*
  from counted_homes
  order by
    (counted_homes.occurred_end is null) desc,
    counted_homes.occurred_start desc nulls last,
    lower(counted_homes.title),
    counted_homes.entry_id
  limit p_limit
  offset p_offset;
end;
$$;
revoke all on function public.homes_workspace(integer, integer) from public, anon;
grant execute on function public.homes_workspace(integer, integer) to authenticated, service_role;

-- The Entry editor's save. It replaces three nested review functions from the Inbox era,
-- which took a classification that could only ever be "entry". The editor can set the
-- primary Location, and add a Location from a photo's GPS position.
create function public.save_entry(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_body_rich jsonb,
  p_occurred_start timestamp with time zone,
  p_occurred_end timestamp with time zone,
  p_occurred_timezone text,
  p_occurred_label text,
  p_date_precision text,
  p_tag_names text[],
  p_primary_location jsonb,
  p_photo_location jsonb
)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  entry_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  photo_attachment_id uuid;
  photo_latitude numeric;
  photo_longitude numeric;
  photo_location_id uuid;
begin
  if entry_owner_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  if p_title is null and p_body = '' then
    raise exception using errcode = '22023', message = 'empty_entry';
  end if;
  if length(coalesce(p_title, '')) > 200 or length(p_body) > 50000 then
    raise exception using errcode = '22023', message = 'entry_content_too_long';
  end if;
  if p_body_rich is not null and (
    jsonb_typeof(p_body_rich) is distinct from 'object'
    or p_body_rich->>'version' is distinct from '1'
    or jsonb_typeof(p_body_rich->'text') is distinct from 'string'
    or p_body_rich->>'text' is distinct from p_body
    or jsonb_typeof(p_body_rich->'document') is distinct from 'object'
    or octet_length(p_body_rich::text) > 300000
  ) then
    raise exception using errcode = '22023', message = 'invalid_rich_text';
  end if;

  p_occurred_label := nullif(btrim(p_occurred_label), '');
  if p_date_precision is null or p_date_precision not in ('exact','day','month','year','approximate','age','range','unknown')
    or p_occurred_timezone is null or length(p_occurred_timezone) > 100
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_occurred_timezone)
    or length(coalesce(p_occurred_label, '')) > 200
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and p_occurred_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_occurrence';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_photo_location is not null and p_photo_location <> 'null'::jsonb then
    if jsonb_typeof(p_photo_location) <> 'object'
      or coalesce(p_photo_location->>'attachmentId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      or jsonb_typeof(p_photo_location->'latitude') is distinct from 'number'
      or jsonb_typeof(p_photo_location->'longitude') is distinct from 'number'
    then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
    photo_attachment_id := (p_photo_location->>'attachmentId')::uuid;
    photo_latitude := (p_photo_location->>'latitude')::numeric;
    photo_longitude := (p_photo_location->>'longitude')::numeric;
    if photo_latitude not between -90 and 90 or photo_longitude not between -180 and 180 then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
  end if;

  update public.entries as item
  set
    title = p_title,
    body = p_body,
    metadata = case
      when p_body_rich is null then item.metadata - 'body_rich'
      else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
    end,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    occurred_label = p_occurred_label,
    date_precision = p_date_precision,
    occurred_timezone = btrim(p_occurred_timezone)
  where item.id = p_entry_id
    and item.owner_id = entry_owner_id
    and item.revision = p_expected_revision
    and item.item_kind = 'entry' and item.item_subtype = 'entry'
    and item.deleted_at is null
  returning item.id, item.revision
  into saved_entry_id, saved_revision;

  if saved_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);
  perform public.replace_primary_location(saved_entry_id, p_primary_location);

  if photo_attachment_id is not null then
    if not public.lock_photo_place_source(saved_entry_id, photo_attachment_id) then
      raise exception using errcode = '40001', message = 'photo_source_changed';
    end if;
    insert into public.locations (owner_id, latitude, longitude)
    values (entry_owner_id, round(photo_latitude, 6), round(photo_longitude, 6))
    returning locations.id into photo_location_id;
    insert into public.entry_locations (entry_id, location_id, owner_id, relationship)
    values (saved_entry_id, photo_location_id, entry_owner_id, 'photo');
    perform public.record_photo_location_source(
      photo_location_id, saved_entry_id, photo_attachment_id
    );
  end if;

  return query
  select saved_entry_id, saved_revision;
end;
$$;
revoke all on function public.save_entry(uuid, integer, text, text, jsonb, timestamp with time zone, timestamp with time zone, text, text, text, text[], jsonb, jsonb) from public, anon;
grant execute on function public.save_entry(uuid, integer, text, text, jsonb, timestamp with time zone, timestamp with time zone, text, text, text, text[], jsonb, jsonb) to authenticated, service_role;

create or replace function public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_classifications text[];
  normalized_tag_names text[];
  search_query tsquery;
  has_query boolean;
  has_filters boolean;
begin
  if search_owner_id is null then
    return;
  end if;
  if p_order is null or p_order not in ('relevance', 'oldest', 'newest') then
    raise exception using errcode = '22023', message = 'invalid_search_order';
  end if;
  if length(coalesce(p_query, '')) > 200 then
    raise exception using errcode = '22023', message = 'query_too_long';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_pagination';
  end if;
  if (p_date_from is not null and not isfinite(p_date_from))
    or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to)
  then
    raise exception using errcode = '22023', message = 'invalid_date_range';
  end if;
  if cardinality(coalesce(p_item_classifications, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
      where nullif(btrim(classification), '') is null
        or length(btrim(classification)) > 64
    )
  then
    raise exception using errcode = '22023', message = 'invalid_item_classifications';
  end if;
  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  normalized_query := lower(btrim(coalesce(p_query, '')));
  normalized_classifications := array(
    select distinct lower(btrim(classification))
    from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
    order by lower(btrim(classification))
  );
  normalized_tag_names := array(
    select distinct lower(btrim(tag_name))
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name))
  );
  has_query := normalized_query <> '';
  search_query := case
    when has_query then websearch_to_tsquery('simple', normalized_query)
    else null::tsquery
  end;
  has_filters := cardinality(normalized_classifications) > 0
    or cardinality(normalized_tag_names) > 0
    or p_date_from is not null
    or p_date_to is not null;

  if not has_query and not has_filters then
    return;
  end if;

  return query
  with owned_items as (
    select item.*
    from public.entries as item
    where item.owner_id = search_owner_id
      and item.deleted_at is null
      and (
        cardinality(normalized_classifications) = 0
        or item.item_kind = any(normalized_classifications)
        or item.item_subtype = any(normalized_classifications)
      )
      and (
        cardinality(normalized_tag_names) = 0
        or exists (
          select 1
          from public.entry_tags as membership
          join public.tags as tag
            on tag.id = membership.tag_id
            and tag.owner_id = membership.owner_id
          where membership.entry_id = item.id
            and membership.owner_id = search_owner_id
            and lower(tag.name) = any(normalized_tag_names)
        )
      )
      and (
        (p_date_from is null and p_date_to is null)
        or public.wiki_item_occurrence_window(
          item.occurred_start,
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone,
          item.item_kind,
          item.item_subtype
        ) && daterange(p_date_from, p_date_to, '[]')
      )
  ),
  enriched as (
    select
      item.*,
      tag_context.tag_names,
      tag_context.tag_text,
      concat_ws(
        ' ',
        item.occurred_label,
        public.entry_occurrence_date_text(
          item.occurred_start,
          item.date_precision,
          item.occurred_timezone
        ),
        public.entry_occurrence_date_text(
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone
        )
      ) as date_text,
      concat_ws(
        ' ',
        replace(item.item_kind, '_', ' '),
        replace(item.item_subtype, '_', ' '),
        item.metadata::text,
        home.move_in_reason,
        home.move_out_reason,
        vehicle.make,
        vehicle.model,
        vehicle.model_year::text,
        vehicle.color,
        goal.status,
        goal.target_date::text,
        timeline_context.timeline_text,
        location_context.location_text,
        attachment_context.filename_text
      ) as structured_text
    from owned_items as item
    left join public.homes as home
      on home.entry_id = item.id and home.owner_id = search_owner_id
    left join public.vehicles as vehicle
      on vehicle.entry_id = item.id and vehicle.owner_id = search_owner_id
    left join public.goals as goal
      on goal.entry_id = item.id and goal.owner_id = search_owner_id
    left join lateral (
      select
        coalesce(array_agg(tag.name order by lower(tag.name), tag.name), '{}'::text[]) as tag_names,
        coalesce(string_agg(tag.name, ' '), '') as tag_text
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = search_owner_id
    ) as tag_context on true
    left join lateral (
      select string_agg(concat_ws(' ', track.name, timeline_item.timeline_kind), ' ') as timeline_text
      from public.timeline_items as timeline_item
      join public.timeline_tracks as track
        on track.id = timeline_item.track_id
        and track.owner_id = timeline_item.owner_id
      where timeline_item.entry_id = item.id
        and timeline_item.owner_id = search_owner_id
    ) as timeline_context on true
    left join lateral (
      select string_agg(concat_ws(' ', location.formatted_address, location.address, location.city, location.region, location.country), ' ') as location_text
      from public.entry_locations as link
      join public.locations as location
        on location.id = link.location_id and location.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as location_context on true
    left join lateral (
      select string_agg(attachment.original_filename, ' ') as filename_text
      from public.attachments as attachment
      where attachment.entry_id = item.id and attachment.owner_id = search_owner_id
    ) as attachment_context on true
  ),
  evaluated as (
    select
      enriched.*,
      has_query and (
        position(normalized_query in lower(coalesce(enriched.title, ''))) > 0
        or to_tsvector('simple', coalesce(enriched.title, '')) @@ search_query
      ) as title_matches,
      has_query and (
        position(normalized_query in lower(enriched.body)) > 0
        or to_tsvector('simple', enriched.body) @@ search_query
      ) as body_matches,
      has_query and (
        position(normalized_query in lower(enriched.tag_text)) > 0
        or to_tsvector('simple', enriched.tag_text) @@ search_query
      ) as tag_matches,
      has_query and (
        position(normalized_query in lower(enriched.date_text)) > 0
        or to_tsvector('simple', enriched.date_text) @@ search_query
      ) as date_matches,
      has_query and (
        position(normalized_query in lower(enriched.structured_text)) > 0
        or to_tsvector('simple', enriched.structured_text) @@ search_query
      ) as structured_matches
    from enriched
  ),
  matched as (
    select
      evaluated.*,
      case
        when not has_query then array['Filters']::text[]
        else array_remove(array[
          case when evaluated.title_matches then 'Title' end,
          case when evaluated.body_matches then 'Body' end,
          case when evaluated.tag_matches then 'Tag' end,
          case when evaluated.date_matches then 'Date' end,
          case when evaluated.structured_matches then 'Details' end
        ], null)
      end as computed_match_reasons,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(ts_rank_cd(evaluated.search_document, search_query)::double precision, 0)
      ) as computed_match_rank
    from evaluated
    where not has_query
      or evaluated.title_matches
      or evaluated.body_matches
      or evaluated.tag_matches
      or evaluated.date_matches
      or evaluated.structured_matches
  )
  select
    matched.id,
    matched.title,
    matched.body,
    matched.occurred_start,
    matched.occurred_end,
    matched.occurred_label,
    matched.occurred_timezone,
    matched.revision,
    matched.updated_at,
    matched.tag_names,
    matched.computed_match_reasons,
    matched.computed_match_rank,
    count(*) over (),
    matched.date_precision,
    matched.item_kind,
    matched.item_subtype
  from matched
  order by
    case when p_order = 'relevance' then matched.computed_match_rank end desc nulls last,
    case when p_order = 'oldest' then matched.occurred_start end asc nulls last,
    case when p_order <> 'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$function$;
