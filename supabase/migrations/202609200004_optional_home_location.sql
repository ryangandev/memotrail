-- Home's Location is optional. Keep the legacy RPC signature for iOS and
-- existing clients, but never create a synthetic "Location not set" row.
do $migration$
declare
  definition text;
  old_fragment text;
  new_fragment text;
begin
  select pg_get_functiondef(
    'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)'::regprocedure
  ) into definition;

  old_fragment := 'if normalized_place_name is null or length(normalized_place_name) > 200';
  new_fragment := 'if length(coalesce(normalized_place_name, '''')) > 200';
  if position(old_fragment in definition) = 0 then
    raise exception 'Home Location validation changed unexpectedly';
  end if;
  definition := replace(definition, old_fragment, new_fragment);

  old_fragment := $old$
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
$old$;
  new_fragment := $new$
  if p_place_id is not null
    or normalized_address is not null
    or normalized_city is not null
    or normalized_region is not null
    or normalized_country is not null
    or p_latitude is not null
  then
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
  else
    saved_place_id := null;
  end if;
$new$;
  if position(old_fragment in definition) = 0 then
    raise exception 'Home Location resolution changed unexpectedly';
  end if;
  definition := replace(definition, old_fragment, new_fragment);

  old_fragment := 'if saved_place_id is null then
    raise exception using errcode = ''22023'', message = ''invalid_home_place'';
  end if;';
  new_fragment := 'if saved_place_id is null and (
    p_place_id is not null or normalized_address is not null
    or normalized_city is not null or normalized_region is not null
    or normalized_country is not null or p_latitude is not null
  ) then
    raise exception using errcode = ''22023'', message = ''invalid_home_place'';
  end if;';
  if position(old_fragment in definition) = 0 then
    raise exception 'Home Location result check changed unexpectedly';
  end if;
  definition := replace(definition, old_fragment, new_fragment);

  old_fragment := $old$
  insert into public.entry_places (
    entry_id,
    place_id,
    owner_id,
    relationship
  )
  values (
    saved_entry_id,
    saved_place_id,
    home_owner_id,
    'home'
  );
$old$;
  new_fragment := $new$
  if saved_place_id is not null then
    insert into public.entry_places (
      entry_id,
      place_id,
      owner_id,
      relationship
    ) values (
      saved_entry_id,
      saved_place_id,
      home_owner_id,
      'home'
    );
  end if;
$new$;
  if position(old_fragment in definition) = 0 then
    raise exception 'Home Location relationship changed unexpectedly';
  end if;
  execute replace(definition, old_fragment, new_fragment);
end;
$migration$;
