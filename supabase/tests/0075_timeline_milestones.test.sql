begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Timeline is life milestones, not a record type on tracks.
select has_table('public','milestones','An Entry is marked as a milestone');
select hasnt_table('public','timeline_tracks','Timeline has no tracks');
select hasnt_table('public','timeline_items','Timeline has no placements');
select hasnt_function('public','save_timeline_track','Tracks cannot be edited');
select hasnt_function('public','timeline_workspace_with_organization','The track-based Timeline read is gone');
select hasnt_function('public','save_first_time_with_occurrence','First Times have no separate form');
select hasnt_function('public','first_times_workspace_with_occurrence','First Times read milestones');
select ok(not has_table_privilege('anon','public.milestones','select'),'Signed-out visitors cannot read milestones');
select ok(not has_function_privilege('anon','public.timeline_workspace()','execute'),'Signed-out visitors cannot read Timeline');
select ok(not has_function_privilege('anon','public.replace_entry_milestone(uuid,jsonb)','execute'),'Signed-out visitors cannot mark milestones');
select ok('milestones' = any(public.export_dataset_names()),'Export includes milestones');

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000176','milestones-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000177','milestones-other@memotrail.local');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_start,occurred_end,occurred_timezone) values
  ('99750000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000176','Pine Street','','entity','home','year','2019-01-01Z',null,'UTC'),
  ('99750000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000176','Blue Civic','','entity','vehicle','year','2015-01-01Z','2018-01-01Z','UTC'),
  ('99750000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000176','A plain walk','','entry','entry','day','2020-05-01Z',null,'UTC');
insert into public.homes(entry_id,owner_id) values ('99750000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000176');
insert into public.vehicles(entry_id,owner_id,make,model) values ('99750000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000176','Honda','Civic');

select throws_ok(
  $$insert into public.milestones(entry_id,owner_id,shape,lane) values
    ('99750000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000176','period','other')$$,
  '23514','milestone_requires_entry','A Home is on Timeline without a milestone');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000176',true);

create function pg_temp.save(
  p_id uuid, p_revision integer, p_title text, p_start timestamptz, p_end timestamptz,
  p_precision text, p_milestone jsonb
) returns integer language sql as $$
  select revision from public.save_entry(
    p_id, p_revision, p_title, '', null, p_start, p_end, 'UTC', null, p_precision, '{}', null, null, p_milestone);
$$;

-- Adding a milestone creates an Entry with the caller's id, once.
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000010',null,'University','2013-09-01Z','2017-06-01Z','year',
    '{"shape":"period","lane":"work_study","isFirstTime":false}'),
  1,'A Period is created as a new Entry');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000010',null,'University again','2013-09-01Z','2017-06-01Z','year',
    '{"shape":"period","lane":"work_study","isFirstTime":false}'),
  null::integer,'Retrying the create does not make a second Entry');
select is((select title from public.entries where id = '99750000-0000-4000-8000-000000000010'),'University',
  'The retry leaves the first save alone');
select is((select item_kind || ':' || item_subtype from public.entries where id = '99750000-0000-4000-8000-000000000010'),
  'entry:entry','A milestone is a plain Entry');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000011',null,'First flight','2009-07-01Z',null,'month',
    '{"shape":"moment","lane":"other","isFirstTime":true}'),
  1,'A First Time is a Moment marked as a First Time');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000012',null,'Bakery job','2021-03-01Z',null,'month',
    '{"shape":"period","lane":"work_study","isFirstTime":false}'),
  1,'A Period can be still going on');

-- A Period ends at any calendar precision; only a Period can.
select throws_ok(
  $$select pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z','2020-06-01Z','day',null)$$,
  '22023','invalid_occurrence','An Entry that is not a Period cannot end on a day');
select throws_ok(
  $$select pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z','2020-06-01Z','day',
    '{"shape":"moment","lane":"other","isFirstTime":false}')$$,
  '22023','invalid_occurrence','A Moment cannot end on a day');
select throws_ok(
  $$select pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z','2020-06-01Z','range',
    '{"shape":"moment","lane":"other","isFirstTime":false}')$$,
  '22023','moment_has_no_end','A Moment cannot span a range');
select throws_ok(
  $$select pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z',null,'day',
    '{"shape":"moment","lane":"homes","isFirstTime":false}')$$,
  '22023','invalid_milestone','Homes and Vehicles have their own lanes');
select throws_ok(
  $$select pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z',null,'day',
    '{"shape":"moment","lane":"other"}')$$,
  '22023','invalid_milestone','A milestone says whether it is a First Time');
select is((select revision from public.entries where id = '99750000-0000-4000-8000-000000000003'),1,
  'A refused milestone leaves the Entry unchanged');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000003',1,'A plain walk','2020-05-01Z',null,'day',
    '{"shape":"moment","lane":"other","isFirstTime":false}'),
  2,'Any Entry can be marked as a milestone');
select is(public.editable_entry('99750000-0000-4000-8000-000000000003')->'milestone',
  '{"shape":"moment","lane":"other","is_first_time":false}'::jsonb,'The Entry editor reads the milestone');
select is(public.entry_detail('99750000-0000-4000-8000-000000000011')->'milestone'->>'is_first_time','true',
  'The Item page reads the milestone');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000003',2,'A plain walk','2020-05-01Z',null,'day',null),
  3,'Removing the milestone keeps the Entry');
select is((select count(*) from public.milestones where entry_id = '99750000-0000-4000-8000-000000000003'),0::bigint,
  'Removing the milestone takes it off Timeline');
select is(public.editable_entry('99750000-0000-4000-8000-000000000003')->'milestone','null'::jsonb,
  'An Entry with no milestone reads none');

-- Timeline lanes: places lived, vehicles, work and study, and other milestones.
select results_eq(
  $$select title, lane, shape from public.timeline_workspace() order by title$$,
  $$values ('Bakery job','work_study','period'), ('Blue Civic','vehicles','period'),
    ('First flight','other','moment'), ('Pine Street','homes','period'), ('University','work_study','period')$$,
  'Timeline shows milestones, Homes, and Vehicles in their lanes');
select is((select array_agg(title order by title) from public.first_times_workspace()),array['First flight'],
  'First Times lists only First Time milestones');

-- Now lists Periods, Homes, and Vehicles that have not ended.
select is(
  (select array_agg(item->>'title' order by item->>'title')
   from public.home_workspace('2026-10-04','UTC',5), jsonb_array_elements(now_items) as item),
  array['Bakery job','Pine Street'],'Now lists what is still going on');
select is(
  (select now_items->0->>'lane' from public.home_workspace('2026-10-04','UTC',5)),
  'homes','Now starts with the place lived');
select is((select first_time_count from public.home_workspace('2026-10-04','UTC',5)),1::bigint,
  'Dashboard counts First Time milestones');

-- Search filters by milestone and finds First Times by name.
select is(
  (select array_agg(title order by title) from public.search_wiki_items('', array['first_time'])),
  array['First flight'],'Search filters First Times');
select is(
  (select array_agg(title order by title) from public.search_wiki_items('', array['milestone'])),
  array['Bakery job','First flight','University'],'Search filters milestones');
select is(
  (select milestone_shape || ':' || is_first_time from public.search_wiki_items('first time')),
  'moment:true','Search finds a First Time by name and returns its milestone');
select is(
  (select count(*) from public.search_wiki_items('', '{}', '{}', '2026-01-01', '2026-01-31') where title = 'Bakery job'),
  1::bigint,'A Period with no end matches dates after its start');

-- Another owner sees none of it.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000177',true);
select is((select count(*) from public.milestones),0::bigint,'Another owner reads no milestones');
select is((select count(*) from public.timeline_workspace()),0::bigint,'Another owner sees an empty Timeline');
select is(
  pg_temp.save('99750000-0000-4000-8000-000000000011',1,'Taken','2009-07-01Z',null,'month',
    '{"shape":"moment","lane":"other","isFirstTime":false}'),
  null::integer,'Another owner cannot change a milestone');
select throws_ok(
  $$insert into public.milestones(entry_id,owner_id,shape,lane) values
    ('99750000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000176','moment','other')$$,
  '23514','milestone_requires_entry','Another owner cannot mark someone else''s Entry');

-- Trash hides a milestone, and deleting the Entry deletes its milestone.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000176',true);
update public.entries set deleted_at = now() where id = '99750000-0000-4000-8000-000000000012';
select is((select count(*) from public.timeline_workspace() where title = 'Bakery job'),0::bigint,
  'Trash takes a milestone off Timeline');
reset role;
delete from public.entries where id = '99750000-0000-4000-8000-000000000012';
select is((select count(*) from public.milestones where entry_id = '99750000-0000-4000-8000-000000000012'),0::bigint,
  'Deleting an Entry deletes its milestone');

select * from finish();
rollback;
