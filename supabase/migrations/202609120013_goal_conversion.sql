create function public.convert_entry_to_goal(
  p_entry_id uuid, p_expected_revision integer, p_title text,
  p_horizon text, p_status text, p_target_date date
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
  source public.entries;
  result_revision integer;
begin
  if auth.uid() is null then return null; end if;
  if p_expected_revision is null or p_expected_revision < 1
    or nullif(btrim(p_title),'') is null or length(btrim(p_title)) > 200
    or p_horizon is null or p_horizon not in ('short_term','long_term','someday')
    or p_status is null or p_status not in ('considering','active','paused','achieved','let_go')
    or (p_target_date is not null and (not isfinite(p_target_date)
      or p_target_date < date '0001-01-01' or p_target_date > date '9999-12-31'))
  then raise exception using errcode='22023',message='invalid_goal_conversion'; end if;
  select * into source from public.entries
    where id=p_entry_id and owner_id=auth.uid() and deleted_at is null for update;
  if not found then return null; end if;
  -- A lost successful response may be retried without another mutation or snapshot.
  if source.entry_type='goal' and source.revision::bigint=p_expected_revision::bigint+1
    and source.title=btrim(p_title) and exists (
      select 1 from public.goals g where g.entry_id=source.id and g.owner_id=auth.uid()
      and g.horizon=p_horizon and g.status=p_status and g.target_date is not distinct from p_target_date
    ) then return source.revision; end if;
  if source.entry_type <> 'standard' or source.revision <> p_expected_revision then return null; end if;
  update public.entries set entry_type='goal',title=btrim(p_title)
    where id=source.id and owner_id=auth.uid() returning revision into result_revision;
  insert into public.goals(entry_id,owner_id,horizon,status,target_date)
    values(source.id,auth.uid(),p_horizon,p_status,p_target_date);
  return result_revision;
end;
$$;
revoke all on function public.convert_entry_to_goal(uuid,integer,text,text,text,date) from public,anon;
grant execute on function public.convert_entry_to_goal(uuid,integer,text,text,text,date) to authenticated;

-- Subsequent Goal edits must not erase the original Idea's occurrence metadata.
do $$
declare
  definition text;
  old_assignment text := E'inbox_status = ''organized'',\n      occurred_start = null,\n      occurred_end = null,\n      date_precision = ''unknown'',\n      occurred_label = null,\n      occurred_timezone = null';
begin
  select pg_get_functiondef(p.oid) into strict definition from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='save_goal_entry';
  if (length(definition)-length(replace(definition,old_assignment,''))) <> length(old_assignment)
    then raise exception 'Expected exactly one Goal occurrence assignment'; end if;
  execute replace(definition,old_assignment,'inbox_status = ''organized''');
end;
$$;
