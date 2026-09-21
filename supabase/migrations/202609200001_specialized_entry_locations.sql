-- Save a specialized Wiki Item and its primary Location in one transaction.
-- Relinking affects only the saved Item; shared Location facts are never edited.

create function public.resolve_selected_location(p_location jsonb)
returns uuid
language plpgsql
security invoker
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
      and location.revision = (p_location->>'revision')::integer
      and location.deleted_at is null;
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

  raise exception using errcode = '22023', message = 'invalid_primary_location';
end;
$$;

revoke all on function public.resolve_selected_location(jsonb) from public, anon;
grant execute on function public.resolve_selected_location(jsonb) to authenticated;

create function public.save_first_time_with_location(
  p_input jsonb,
  p_location jsonb
)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved record;
  selected_location_id uuid;
  first_time_owner_id uuid := auth.uid();
begin
  if first_time_owner_id is null then return; end if;
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
    array(select jsonb_array_elements_text(coalesce(p_input->'collectionNames', '[]'::jsonb))),
    array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb))),
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer,
    (p_input->>'occurredEnd')::timestamptz
  );
  if saved.entry_id is null then return; end if;

  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_places as link
  where link.entry_id = saved.entry_id
    and link.owner_id = first_time_owner_id
    and link.relationship = 'primary';
  if selected_location_id is not null then
    insert into public.entry_places(entry_id, place_id, owner_id, relationship)
    values (saved.entry_id, selected_location_id, first_time_owner_id, 'primary');
  end if;

  return query select saved.entry_id, saved.revision, saved.was_created;
end;
$$;

revoke all on function public.save_first_time_with_location(jsonb,jsonb)
  from public, anon;
grant execute on function public.save_first_time_with_location(jsonb,jsonb)
  to authenticated;

create function public.save_vehicle_with_location(
  p_input jsonb,
  p_source jsonb,
  p_location jsonb
)
returns table(entry_id uuid, revision integer, was_created boolean)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved record;
  saved_entry_id uuid;
  saved_revision integer;
  created_vehicle boolean;
  selected_location_id uuid;
  vehicle_owner_id uuid := auth.uid();
  collection_names text[];
  tag_names text[];
begin
  if vehicle_owner_id is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_vehicle_input';
  end if;

  collection_names := array(select jsonb_array_elements_text(coalesce(p_input->'collectionNames', '[]'::jsonb)));
  tag_names := array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb)));

  if p_source is null or p_source = 'null'::jsonb then
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
      collection_names,
      tag_names,
      (p_input->>'id')::uuid,
      (p_input->>'revision')::integer
    );
    if saved.entry_id is null then return; end if;
    saved_entry_id := saved.entry_id;
    saved_revision := saved.revision;
    created_vehicle := saved.was_created;
  else
    if jsonb_typeof(p_source) is distinct from 'object'
      or p_input->>'id' is not null
    then
      raise exception using errcode = '22023', message = 'invalid_vehicle_source';
    end if;
    select * into saved
    from public.extract_capture_to_vehicle(
      (p_source->>'id')::uuid,
      (p_source->>'revision')::integer,
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
      collection_names,
      tag_names
    );
    if saved.vehicle_entry_id is null then return; end if;
    saved_entry_id := saved.vehicle_entry_id;
    saved_revision := saved.vehicle_revision;
    created_vehicle := true;
  end if;

  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_places as link
  where link.entry_id = saved_entry_id
    and link.owner_id = vehicle_owner_id
    and link.relationship = 'primary';
  if selected_location_id is not null then
    insert into public.entry_places(entry_id, place_id, owner_id, relationship)
    values (saved_entry_id, selected_location_id, vehicle_owner_id, 'primary');
  end if;

  return query select saved_entry_id, saved_revision, created_vehicle;
end;
$$;

revoke all on function public.save_vehicle_with_location(jsonb,jsonb,jsonb)
  from public, anon;
grant execute on function public.save_vehicle_with_location(jsonb,jsonb,jsonb)
  to authenticated;
