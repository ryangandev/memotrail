-- A versioned check-in mutation distinguishes explicit unlink from older clients' absent UI.
do $migration$
declare original text; updated text;
begin
  original := pg_get_functiondef('public.record_habit_occurrence(uuid,date,text,numeric,text,uuid,integer)'::regprocedure);
  updated := replace(original, 'public.record_habit_occurrence(', 'public.save_habit_check_in(');
  updated := replace(updated, E'  select * into current_habit\n', E'  perform 1 from public.entries where id=p_entry_id and owner_id=auth.uid() for share;\n\n  select * into current_habit\n');
  updated := replace(updated, E'    and deleted_at is null;\n', E'    and deleted_at is null for update;\n');
  updated := replace(updated, E'      and deleted_at is null\n  ) then', E'      and (deleted_at is null or exists (\n        select 1 from public.habit_occurrences o\n        where o.habit_id=p_habit_id and o.local_date=p_local_date\n          and o.owner_id=auth.uid() and o.entry_id=p_entry_id\n          and o.revision=p_expected_revision\n      ))\n  ) then');
  if updated=original or position('public.save_habit_check_in(' in updated)=0
    or position('where id=p_entry_id and owner_id=auth.uid() for share' in updated)=0
    or position('o.revision=p_expected_revision' in updated)=0
    or position('deleted_at is null for update' in updated)=0 then
    raise exception 'habit_entry_link_migration_shape_changed';
  end if;
  execute updated;
end;
$migration$;

-- Existing installed clients always send null because they have no link control.
-- Preserve that same check-in's link; only the versioned mutation can explicitly unlink.
create or replace function public.record_habit_occurrence(
  p_habit_id uuid,p_local_date date,p_status text,p_measured_value numeric,p_note text,p_entry_id uuid,p_expected_revision integer
) returns table(occurrence_id uuid,revision integer,was_created boolean)
language sql security invoker set search_path='' as $$
  select * from public.save_habit_check_in(p_habit_id,p_local_date,p_status,p_measured_value,p_note,
    coalesce(p_entry_id,(select o.entry_id from public.habit_occurrences o
      where o.habit_id=p_habit_id and o.local_date=p_local_date and o.owner_id=auth.uid() and o.revision=p_expected_revision)),p_expected_revision);
$$;

create or replace function public.habit_entry_choices(p_habit_id uuid,p_local_date date,p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_local_date is null or p_query is null or length(p_query)>200 or p_offset is null or p_offset not between 0 and 100000 then
    raise exception using errcode='22023',message='invalid_habit_entry_page';
  end if;
  if not exists(select 1 from public.habits where id=p_habit_id and owner_id=auth.uid() and deleted_at is null and archived_at is null) then return null; end if;
  with matches as (
    select e.id,e.title,left(e.body,160) excerpt,e.deleted_at is not null is_deleted
    from public.entries e where e.owner_id=auth.uid() and e.deleted_at is null
      and (btrim(p_query)='' or strpos(lower(coalesce(e.title,'')||' '||e.body),lower(btrim(p_query)))>0)
  ), page as (
    select * from matches order by lower(coalesce(nullif(btrim(title),''),nullif(excerpt,''),'Untitled Entry')),id limit 20 offset p_offset
  ) select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(page) order by lower(coalesce(nullif(btrim(title),''),nullif(excerpt,''),'Untitled Entry')),id) from page),'[]'),
    'total_count',(select count(*) from matches),
    'selected',(select jsonb_build_object('id',e.id,'title',e.title,'excerpt',left(e.body,160),'is_deleted',e.deleted_at is not null)
      from public.habit_occurrences o join public.entries e on e.id=o.entry_id and e.owner_id=o.owner_id
      where o.habit_id=p_habit_id and o.owner_id=auth.uid() and o.local_date=p_local_date)
  ) into result;
  return result;
end;
$$;
revoke all on function public.save_habit_check_in(uuid,date,text,numeric,text,uuid,integer),public.habit_entry_choices(uuid,date,text,integer) from public,anon;
grant execute on function public.save_habit_check_in(uuid,date,text,numeric,text,uuid,integer),public.habit_entry_choices(uuid,date,text,integer) to authenticated;
