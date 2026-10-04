begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Photo changes leave the Entry's revision alone, so Move to Trash and Goal
-- achievement still land after the editor's own photo changes, and still refuse
-- any unseen writing.
create temporary table fixtures(kind text, outcome text, id uuid, photo_id uuid);
grant all on fixtures to authenticated;

create function pg_temp.create_record(p_kind text)
returns uuid language plpgsql as $$
declare created uuid;
begin
  case p_kind
    when 'goal', 'achieve' then
      select entry_id into created from public.save_goal_entry(
        'Revision ' || p_kind, 'Original writing', 'active', null,
        '{}', null, null);
    when 'home' then
      select entry_id into created from public.save_home_entry_with_occurrence(
        'Revision home', 'Original writing', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC', '', '', '{}', null, null);
    when 'vehicle' then
      select entry_id into created from public.save_vehicle_entry_with_occurrence(
        'Revision vehicle', 'Original writing', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC',
        'Honda', 'Civic', 2018, 'Blue', '{}', null, null);
    when 'milestone' then
      select entry_id into created from public.save_entry(
        gen_random_uuid(), null, 'Revision milestone', 'Original writing', null,
        '2021-04-12T12:00:00Z', null, 'UTC', null, 'day', '{}', null, null,
        '{"shape":"moment","lane":"other","isFirstTime":true}');
  end case;
  return created;
end;
$$;

-- Returns the written revision, or null when the RPC refused the expected revision.
create function pg_temp.write(p_kind text, p_entry_id uuid, p_revision integer)
returns integer language plpgsql as $$
declare written integer;
begin
  case p_kind
    when 'goal' then
      select revision into written from public.trash_goal_entry(p_entry_id, p_revision);
    when 'home' then
      select revision into written from public.trash_home_entry(p_entry_id, p_revision);
    when 'vehicle' then
      select revision into written from public.trash_vehicle_entry(p_entry_id, p_revision);
    when 'milestone' then
      -- The Item page moves an Entry to Trash with a revision-checked update.
      update public.entries set deleted_at = now()
      where id = p_entry_id and revision = p_revision and deleted_at is null
      returning revision into written;
    when 'achieve' then
      select goal_revision into written from public.achieve_goal_with_occurrence(
        p_entry_id, p_revision, null, 'unknown', null, null, null);
  end case;
  return written;
end;
$$;

-- Whether the lifecycle write landed: in Trash, or achieved with its First Time.
create function pg_temp.written(p_kind text, p_entry_id uuid)
returns boolean language sql as $$
  select case when p_kind = 'achieve'
    then exists(select 1 from public.goals where entry_id = p_entry_id and status = 'achieved')
      and exists(select 1 from public.entry_links where source_entry_id = p_entry_id and relationship = 'achievement')
    else (select deleted_at is not null from public.entries where id = p_entry_id)
  end;
$$;

-- Real registration and Trash through the photo RPCs; Storage rows need the table owner.
create function pg_temp.add_photo(p_entry_id uuid)
returns uuid language plpgsql as $$
declare
  photo_id uuid := gen_random_uuid();
  photo_path text := auth.uid() || '/' || p_entry_id || '/' || photo_id || '.png';
begin
  insert into storage.objects(bucket_id, name) values ('entry-media', photo_path);
  perform public.register_entry_attachment(
    p_entry_id, photo_id, photo_path, 'kept.png', 'image/png', 100, null, null);
  return photo_id;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
insert into fixtures(kind, outcome, id)
select kind, outcome, pg_temp.create_record(kind)
from unnest(array['goal', 'home', 'vehicle', 'milestone', 'achieve']) as kind,
  unnest(array['adopt', 'conflict']) as outcome;
select is((select count(*) from fixtures where id is not null), 10::bigint, 'Every lifecycle writer has two fresh records');

reset role;
update fixtures set photo_id = pg_temp.add_photo(id);
set local role authenticated;
select is(revision, 1, kind || ' (' || outcome || '): Photo registration keeps the revision')
from fixtures join public.entries on entries.id = fixtures.id order by kind, outcome;

-- Another device writes between the photo actions on every conflict record.
update public.entries set body = 'Other device writing'
where id in (select id from fixtures where outcome = 'conflict');
select is((select count(*) from public.trash_entry_attachment(photo_id)), 1::bigint,
  kind || ' (' || outcome || '): The editor moves its photo to Trash')
from fixtures order by kind, outcome;
select is(revision, case when outcome = 'adopt' then 1 else 2 end,
  kind || ' (' || outcome || '): Photo Trash keeps the revision, and writing advances it')
from fixtures join public.entries on entries.id = fixtures.id order by kind, outcome;

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(pg_temp.write(kind, id, 1), null, kind || ': A foreign caller cannot write')
from fixtures where outcome = 'adopt' order by kind;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(pg_temp.write(kind, id, 2), null, kind || ': A revision ahead of the Entry is refused')
from fixtures where outcome = 'adopt' order by kind;

select is(pg_temp.write(kind, id, 1), null, kind || ': Unseen writing is refused')
from fixtures where outcome = 'conflict' order by kind;
select ok(not pg_temp.written(kind, id), kind || ': A refused write leaves the record unchanged')
from fixtures where outcome = 'conflict' order by kind;
select is(revision, 2, kind || ': A refused write creates no revision')
from fixtures join public.entries on entries.id = fixtures.id where outcome = 'conflict' order by kind;

select is(pg_temp.write(kind, id, 1), 2, kind || ': The editor''s own photo changes need no reconciliation')
from fixtures where outcome = 'adopt' order by kind;
select ok(pg_temp.written(kind, id), kind || ': The write after photo changes lands')
from fixtures where outcome = 'adopt' order by kind;
select is(pg_temp.write(kind, id, 2), 3, kind || ': An editor opened after the writing succeeds')
from fixtures where outcome = 'conflict' order by kind;
select ok(pg_temp.written(kind, id), kind || ': The write from the current revision lands')
from fixtures where outcome = 'conflict' order by kind;
reset role;

select is(prosecdef, kind = 'achieve', kind || ': Security mode is unchanged')
from (values
  ('achieve', 'public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)'::regprocedure),
  ('goal', 'public.trash_goal_entry(uuid,integer)'::regprocedure),
  ('home', 'public.trash_home_entry(uuid,integer)'::regprocedure),
  ('vehicle', 'public.trash_vehicle_entry(uuid,integer)'::regprocedure)
) as writers(kind, writer) join pg_proc on pg_proc.oid = writers.writer order by kind;
select ok(not has_function_privilege('anon', writer, 'execute')
    and has_function_privilege('authenticated', writer, 'execute'),
  writer || ': Grants are unchanged')
from unnest(array[
  'public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)',
  'public.trash_goal_entry(uuid,integer)',
  'public.trash_home_entry(uuid,integer)',
  'public.trash_vehicle_entry(uuid,integer)'
]) as writer order by writer;
select * from finish();
rollback;
