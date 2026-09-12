-- Hidden related Entries remain recoverable while in Trash. Editors submit only
-- visible targets, so omission cannot mean an explicit unlink for a hidden row.
do $$
declare
  definition text;
  old_statement text := E'delete from public.entry_links\n  where entry_links.source_entry_id = saved_entry_id\n    and entry_links.owner_id = goal_owner_id\n    and entry_links.relationship = ''related'';';
  new_statement text := E'delete from public.entry_links\n  where entry_links.source_entry_id = saved_entry_id\n    and entry_links.owner_id = goal_owner_id\n    and entry_links.relationship = ''related''\n    and exists (\n      select 1 from public.entries target\n      where target.id = entry_links.target_entry_id\n        and target.owner_id = entry_links.owner_id\n        and target.deleted_at is null\n    );';
begin
  select pg_get_functiondef(p.oid) into strict definition from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='save_goal_entry';
  if (length(definition)-length(replace(definition,old_statement,''))) <> length(old_statement)
    then raise exception 'Expected exactly one Goal related-link replacement'; end if;
  execute replace(definition,old_statement,new_statement);
end;
$$;
