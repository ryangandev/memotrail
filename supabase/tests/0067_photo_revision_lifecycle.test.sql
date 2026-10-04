begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Move to Trash and Goal achievement adopt photo-only revisions exactly like
-- entry_writing_revision, and still refuse any unseen writing.
create temporary table fixtures(kind text, outcome text, id uuid, photo_id uuid);
grant all on fixtures to authenticated;

create function pg_temp.create_record(p_kind text)
returns uuid language plpgsql as $$
declare created uuid;
begin
  case p_kind
    when 'goal', 'achieve', 'legacy achieve' then
      select entry_id into created from public.save_goal_entry(
        'Revision ' || p_kind, 'Original writing', 'someday', 'active', null,
        '{}', '{}', null, null);
    when 'home' then
      select entry_id into created from public.save_home_entry_with_occurrence(
        'Revision home', 'Original writing', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC',
        null, 'Maple Street', null, null, null, null, null, null, null, '', '', '{}', null, null);
    when 'vehicle' then
      select entry_id into created from public.save_vehicle_entry_with_occurrence(
        'Revision vehicle', 'Original writing', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC',
        'Honda', 'Civic', 2018, 'Blue', '{}', null, null);
    when 'first time' then
      select entry_id into created from public.save_first_time_with_occurrence(
        'Revision first time', 'Original writing', '2021-04-12T12:00:00Z', 'day', null, 'UTC', '{}', null, null, null);
    when 'moment' then
      select entry_id into created from public.save_timeline_entry_with_occurrence(
        (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'other_events'),
        'event', 'Revision moment', 'Original writing', null, null, 'unknown', null, 'UTC', null, null);
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
    when 'first time' then
      select revision into written from public.trash_first_time_entry(p_entry_id, p_revision);
    when 'moment' then
      select revision into written from public.trash_timeline_entry(p_entry_id, p_revision);
    when 'achieve' then
      select goal_revision into written from public.achieve_goal_with_occurrence(
        p_entry_id, p_revision, null, 'unknown', null, null, null);
    when 'legacy achieve' then
      select goal_revision into written from public.mark_goal_achieved_with_first_time(
        p_entry_id, p_revision, '2020-01-01T12:00:00Z', 'day', null, 'UTC');
  end case;
  return written;
end;
$$;

-- Whether the lifecycle write landed: in Trash, or achieved with its First Time.
create function pg_temp.written(p_kind text, p_entry_id uuid)
returns boolean language sql as $$
  select case when p_kind like '%achieve'
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
from unnest(array['goal', 'home', 'vehicle', 'first time', 'moment', 'achieve', 'legacy achieve']) as kind,
  unnest(array['adopt', 'conflict']) as outcome;
select is((select count(*) from fixtures where id is not null), 14::bigint, 'Every lifecycle writer has two fresh records');

reset role;
update fixtures set photo_id = pg_temp.add_photo(id);
set local role authenticated;
select is(revision, 2, kind || ' (' || outcome || '): Photo registration creates a revision')
from fixtures join public.entries on entries.id = fixtures.id order by kind, outcome;

-- Another device writes between the photo actions on every conflict record.
update public.entries set body = 'Other device writing'
where id in (select id from fixtures where outcome = 'conflict');
select is((select count(*) from public.trash_entry_attachment(photo_id)), 1::bigint,
  kind || ' (' || outcome || '): The editor moves its photo to Trash')
from fixtures order by kind, outcome;
select is(revision, case when outcome = 'adopt' then 3 else 4 end,
  kind || ' (' || outcome || '): Photo Trash creates a revision')
from fixtures join public.entries on entries.id = fixtures.id order by kind, outcome;

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(pg_temp.write(kind, id, 1), null, kind || ': A foreign caller cannot use reconciliation')
from fixtures where outcome = 'adopt' order by kind;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(pg_temp.write(kind, id, 4), null, kind || ': A revision ahead of the Entry is refused')
from fixtures where outcome = 'adopt' order by kind;

select is(pg_temp.write(kind, id, 1), null, kind || ': Unseen writing is never adopted')
from fixtures where outcome = 'conflict' order by kind;
select ok(not pg_temp.written(kind, id), kind || ': A refused write leaves the record unchanged')
from fixtures where outcome = 'conflict' order by kind;
select is(revision, 4, kind || ': A refused write creates no revision')
from fixtures join public.entries on entries.id = fixtures.id where outcome = 'conflict' order by kind;

select is(pg_temp.write(kind, id, 1), 4, kind || ': The editor''s own photo-only revisions are adopted')
from fixtures where outcome = 'adopt' order by kind;
select ok(pg_temp.written(kind, id), kind || ': The adopted write lands')
from fixtures where outcome = 'adopt' order by kind;
select is(pg_temp.write(kind, id, 3), 5, kind || ': An editor opened after the writing adopts the later photo change')
from fixtures where outcome = 'conflict' order by kind;
select ok(pg_temp.written(kind, id), kind || ': The write after reconciliation lands')
from fixtures where outcome = 'conflict' order by kind;
reset role;

select is(prosecdef, kind = 'achieve', kind || ': Security mode is unchanged')
from (values
  ('achieve', 'public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)'::regprocedure),
  ('goal', 'public.trash_goal_entry(uuid,integer)'::regprocedure),
  ('home', 'public.trash_home_entry(uuid,integer)'::regprocedure),
  ('vehicle', 'public.trash_vehicle_entry(uuid,integer)'::regprocedure),
  ('first time', 'public.trash_first_time_entry(uuid,integer)'::regprocedure),
  ('moment', 'public.trash_timeline_entry(uuid,integer)'::regprocedure)
) as writers(kind, writer) join pg_proc on pg_proc.oid = writers.writer order by kind;
select ok(not has_function_privilege('anon', writer, 'execute')
    and has_function_privilege('authenticated', writer, 'execute'),
  writer || ': Grants are unchanged')
from unnest(array[
  'public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)',
  'public.trash_goal_entry(uuid,integer)',
  'public.trash_home_entry(uuid,integer)',
  'public.trash_vehicle_entry(uuid,integer)',
  'public.trash_first_time_entry(uuid,integer)',
  'public.trash_timeline_entry(uuid,integer)'
]) as writer order by writer;
select * from finish();
rollback;
