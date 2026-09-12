-- Amend only the active-Collection replacement step in the four existing
-- specialized mutations. Their signatures, grants, validation, revision checks,
-- history snapshots, and specialized writes remain unchanged.
-- Guard the exact old statement so schema drift fails rather than silently
-- applying an incomplete or overly broad migration.
do $$
declare
  target record;
  definition text;
  old_statement text;
  new_statement text;
  function_id oid;
begin
  for target in
    select * from (values
      ('save_first_time_with_occurrence', 'first_time_owner_id'),
      ('save_home_entry', 'home_owner_id'),
      ('save_vehicle_entry', 'vehicle_owner_id'),
      ('save_goal_entry', 'goal_owner_id')
    ) as mutations(function_name, owner_variable)
  loop
    select p.oid into strict function_id
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = target.function_name;
    definition := pg_get_functiondef(function_id);
    old_statement := format(
      E'delete from public.entry_collections\n  where entry_collections.entry_id = saved_entry_id\n    and entry_collections.owner_id = %s;',
      target.owner_variable
    );
    if (length(definition) - length(replace(definition, old_statement, '')))
      <> length(old_statement) then
      raise exception 'Expected exactly one Collection replacement in %', target.function_name;
    end if;
    new_statement := format(
      E'delete from public.entry_collections\n  where entry_collections.entry_id = saved_entry_id\n    and entry_collections.owner_id = %s\n    and exists (\n      select 1 from public.collections c\n      where c.id = entry_collections.collection_id\n        and c.owner_id = entry_collections.owner_id\n        and c.archived_at is null\n    );',
      target.owner_variable
    );
    execute replace(definition, old_statement, new_statement);
  end loop;
end;
$$;
