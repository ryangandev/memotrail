-- Homes without a Location remain visible in the Focused View.
do $migration$
declare
  definition text;
  old_fragment text := '    join public.locations
      on locations.id = homes.place_id';
begin
  select pg_get_functiondef('public.homes_workspace(integer,integer)'::regprocedure)
  into definition;
  if position(old_fragment in definition) = 0 then
    raise exception 'Homes workspace Location join changed unexpectedly';
  end if;
  execute replace(definition, old_fragment,
    '    left join public.locations
      on locations.id = homes.place_id');
end;
$migration$;
