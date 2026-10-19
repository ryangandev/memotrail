begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Schema: Chapters and First Times are marks on an Entry, and the dedicated records are gone.
select hasnt_table('public','milestones','Timeline milestones are retired');
select hasnt_table('public','homes','Homes are Chapters');
select hasnt_table('public','vehicles','Vehicles are Chapters');
select has_column('public','entries','is_first_time','Any Entry can carry the First Time mark');
select col_not_null('public','entries','is_first_time','The First Time mark is never unknown');
select col_default_is('public','entries','is_first_time','false','An Entry is not a First Time by default');
select hasnt_function('public','homes_workspace','The Homes list is retired');
select hasnt_function('public','vehicles_workspace','The Vehicles list is retired');
select hasnt_function('public','save_home_with_location','Homes have no save');
select hasnt_function('public','save_vehicle_with_location','Vehicles have no save');
select hasnt_function('public','save_home_entry_with_occurrence','Homes have no dated save');
select hasnt_function('public','save_vehicle_entry_with_occurrence','Vehicles have no dated save');
select hasnt_function('public','trash_home_entry','Homes move to Trash like any Entry');
select hasnt_function('public','trash_vehicle_entry','Vehicles move to Trash like any Entry');
select hasnt_function('public','replace_entry_milestone','save_entry writes the marks');
select hasnt_function('public','enforce_milestone_entry','Milestones have no trigger');
select hasnt_function('public','wiki_items_workspace',array['text','text[]','text[]','integer','integer','boolean'],'The organizing overload is retired');
select hasnt_function('public','save_entry',array['uuid','integer','text','text','jsonb','timestamp with time zone','timestamp with time zone','text','text','text','text[]','jsonb','jsonb','jsonb'],'The milestone argument is gone from save_entry');
select has_function('public','save_entry',array['uuid','integer','text','text','jsonb','timestamp with time zone','timestamp with time zone','text','text','text','text[]','jsonb','jsonb','boolean','boolean'],'save_entry takes the two marks');
select ok(not ('milestones' = any(public.export_dataset_names())),'Export no longer includes milestones');
select ok(not ('homes' = any(public.export_dataset_names())),'Export no longer includes Homes');
select ok(not ('vehicles' = any(public.export_dataset_names())),'Export no longer includes Vehicles');
select ok('entries' = any(public.export_dataset_names()),'Export includes Entries with their marks');
select ok(not has_function_privilege('anon','public.save_entry(uuid,integer,text,text,jsonb,timestamptz,timestamptz,text,text,text,text[],jsonb,jsonb,boolean,boolean)','execute'),'Signed-out visitors cannot save an Entry');
select ok(not has_function_privilege('anon','public.timeline_workspace()','execute'),'Signed-out visitors cannot read Timeline');
select ok(not has_function_privilege('anon','public.first_times_workspace()','execute'),'Signed-out visitors cannot read First Times');
select ok(has_function_privilege('authenticated','public.timeline_workspace()','execute'),'Signed-in users can read Timeline');

insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000781','chapters-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000782','chapters-other@memotrail.local','{}');

select throws_ok(
  $$insert into public.entries(owner_id,title,item_kind,item_subtype) values ('10000000-0000-0000-0000-000000000781','Old Home','entity','home')$$,
  '23514', null, 'The Entity Kind is retired'
);
select throws_ok(
  $$insert into public.entries(owner_id,title,item_kind,item_subtype) values ('10000000-0000-0000-0000-000000000781','Old Home','entry','home')$$,
  '23514', null, 'The only subtypes are entry and chapter'
);
select lives_ok(
  $$insert into public.entries(owner_id,title,item_kind,item_subtype,date_precision) values ('10000000-0000-0000-0000-000000000781','Pine Street','entry','chapter','unknown')$$,
  'A Chapter is an ordinary row with the chapter subtype'
);
select ok(not has_table_privilege('anon','public.entries','select'),'Signed-out visitors cannot read Entries');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000781',true);

create function pg_temp.save(
  p_precision text,
  p_start timestamptz default null,
  p_end timestamptz default null,
  p_label text default null,
  p_id uuid default null,
  p_revision integer default null,
  p_chapter boolean default true,
  p_first_time boolean default false,
  p_title text default 'Chapter',
  p_tags text[] default '{}'
) returns uuid language plpgsql as $$
declare result uuid;
begin
  select entry_id into result from public.save_entry(
    coalesce(p_id, gen_random_uuid()), p_revision, p_title, 'Original memory', null,
    p_start, p_end, 'America/Los_Angeles', p_label, p_precision, p_tags, null, null,
    p_chapter, p_first_time);
  return result;
end; $$;

-- Every stored precision, saved as a Chapter.
select lives_ok($$select pg_temp.save('age',null,null,'Ages 17 to 23')$$,'chapter: age needs no guessed birthday');
select lives_ok($$select pg_temp.save('approximate',null,null,'During college')$$,'chapter: approximate needs no calendar anchor');
select lives_ok($$select pg_temp.save('unknown')$$,'chapter: unknown needs no date');
select lives_ok($$select pg_temp.save('year','2017-01-01','2023-01-01')$$,'chapter: year supports an end');
select lives_ok($$select pg_temp.save('month','2017-07-01','2023-06-01')$$,'chapter: month supports an end');
select lives_ok($$select pg_temp.save('day','2017-07-08','2023-06-01')$$,'chapter: day supports an end');
select lives_ok($$select pg_temp.save('range','2017-07-08')$$,'chapter: range supports ongoing chapters');
select lives_ok($$select pg_temp.save('exact','2026-11-01 09:30:00.123456Z','2026-11-01 10:30:00.654321Z')$$,'chapter: exact keeps both instants');
select is(count(*),9::bigint,'chapter: Timeline lists every precision, plus the Chapter inserted directly') from public.timeline_workspace();
select is(count(*),4::bigint,'chapter: unanchored rows have no calendar days') from public.timeline_workspace() where occurred_start is null and window_start is null;
create temporary table chapter_fixture as select entry_id id, revision from public.timeline_workspace() where date_precision='exact';
select is(pg_temp.save(date_precision,occurred_start,occurred_end,occurred_label,entry_id,revision),entry_id,'chapter: exact resave succeeds') from public.timeline_workspace() where date_precision='exact';
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'chapter: start microseconds survive') from public.entries where id=(select id from chapter_fixture);
select is(occurred_end,'2026-11-01 10:30:00.654321Z'::timestamptz,'chapter: end microseconds survive') from public.entries where id=(select id from chapter_fixture);
select is((select count(*) from public.save_entry((select id from chapter_fixture),1,'Chapter','Stale',null,null,null,'UTC',null,'unknown','{}',null,null,true,false)),0::bigint,'chapter: a stale save returns no row and cannot erase dates');
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'chapter: a stale save leaves the dates') from public.entries where id=(select id from chapter_fixture);
select throws_ok($$select pg_temp.save('age')$$,'22023','invalid_occurrence','chapter: age requires a label');
select throws_ok($$select pg_temp.save('unknown','2017-01-01')$$,'22023','invalid_occurrence','chapter: unknown rejects an invented date');
select throws_ok($$select pg_temp.save('exact','infinity')$$,'22023','invalid_occurrence','chapter: an infinite date is rejected');
select throws_ok($$select pg_temp.save('year','2023-01-01','2017-01-01')$$,'22023','invalid_occurrence','chapter: a reversed span is rejected');
select throws_ok($$select pg_temp.save(null)$$,'22023','invalid_occurrence','chapter: a missing precision is rejected');
select is(count(*),9::bigint,'chapter: rejected saves leave no orphan Entries') from public.entries where item_subtype='chapter' and owner_id=auth.uid();

-- The marks.
select throws_ok($$select pg_temp.save('unknown',null,null,null,null,null,true,false,null)$$,'22023','chapter_requires_title','A Chapter needs a title');
select throws_ok($$select pg_temp.save('unknown',null,null,null,null,null,true,false,'   ')$$,'22023','chapter_requires_title','A blank title is not a title');
select lives_ok($$select pg_temp.save('unknown',null,null,null,null,null,false,false,null)$$,'An ordinary Entry saves without a title');
select throws_ok($$select pg_temp.save('day','2020-01-01','2020-02-01',null,null,null,false,false)$$,'22023','invalid_occurrence','An ordinary Entry with Day and an end is refused');
select lives_ok($$select pg_temp.save('year','2020-01-01','2022-01-01',null,null,null,true,false)$$,'A Chapter may have a Year with an end');
select throws_ok($$select * from public.save_entry(gen_random_uuid(),null,'x','x',null,null,null,'UTC',null,'unknown','{}',null,null,null,false)$$,'22023','invalid_entry_marks','A null Chapter mark is refused');
select throws_ok($$select * from public.save_entry(gen_random_uuid(),null,'x','x',null,null,null,'UTC',null,'unknown','{}',null,null,false,null)$$,'22023','invalid_entry_marks','A null First Time mark is refused');

-- One save turns an Entry into a Chapter and back, and checks or unchecks First Time.
create temporary table marks_fixture(id uuid, revision integer);
insert into marks_fixture
select entry_id, revision from public.save_entry('78100000-0000-4000-8000-000000000001',null,'Studying','Words',null,'2021-03-01T12:00Z',null,'UTC',null,'day',array['school'],null,null,false,false);
select is((select item_subtype from public.entries where id='78100000-0000-4000-8000-000000000001'),'entry','A new Entry is ordinary');
select is((select is_first_time from public.entries where id='78100000-0000-4000-8000-000000000001'),false,'A new Entry is not a First Time');
select is((select count(*) from public.save_entry('78100000-0000-4000-8000-000000000001',1,'Studying','Words',null,'2021-03-01T12:00Z','2021-09-01T12:00Z','UTC',null,'day',array['school'],null,null,true,true)),1::bigint,'One save makes it a First Time Chapter');
select is((select item_subtype from public.entries where id='78100000-0000-4000-8000-000000000001'),'chapter','The Entry became a Chapter');
select is((select is_first_time from public.entries where id='78100000-0000-4000-8000-000000000001'),true,'A Chapter can also be a First Time');
select is((select revision from public.entries where id='78100000-0000-4000-8000-000000000001'),2,'The mark change advances the revision');
select is((select count(*) from public.entry_tags where entry_id='78100000-0000-4000-8000-000000000001'),1::bigint,'The mark change keeps the tags');
select is((select count(*) from public.save_entry('78100000-0000-4000-8000-000000000001',2,'Studying','Words',null,'2021-03-01T12:00Z',null,'UTC',null,'day',array['school'],null,null,false,false)),1::bigint,'One save turns the Chapter back into an Entry');
select is((select item_subtype || ':' || is_first_time::text from public.entries where id='78100000-0000-4000-8000-000000000001'),'entry:false','Both marks are cleared');
select is((select count(*) from public.save_entry('78100000-0000-4000-8000-000000000001',2,'Studying','Stale',null,'2021-03-01T12:00Z',null,'UTC',null,'day',array['school'],null,null,true,false)),0::bigint,'A stale save cannot change the marks');
select is((select item_subtype from public.entries where id='78100000-0000-4000-8000-000000000001'),'entry','A stale save leaves the Entry ordinary');

-- Editor and detail reads carry the marks and no milestone.
select is(public.editable_entry('78100000-0000-4000-8000-000000000001')->>'item_subtype','entry','The editor read carries item_subtype');
select is(public.editable_entry('78100000-0000-4000-8000-000000000001')->'is_first_time','false'::jsonb,'The editor read carries is_first_time');
select ok(not (public.editable_entry('78100000-0000-4000-8000-000000000001') ? 'milestone'),'The editor read has no milestone');
select ok(not (public.entry_detail('78100000-0000-4000-8000-000000000001') ? 'milestone'),'The detail read has no milestone');
select is(public.entry_detail('78100000-0000-4000-8000-000000000001')->>'item_subtype','entry','The detail read carries item_subtype');

-- Timeline lists Chapters and First Times only, with the days each covers.
reset role;
delete from public.entries where owner_id='10000000-0000-0000-0000-000000000781';
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,is_first_time,occurred_start,occurred_end,date_precision,occurred_timezone,occurred_label,deleted_at) values
 ('78200000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000781','Open chapter','','entry','chapter',false,'2021-03-01T12:00Z',null,'day','UTC',null,null),
 ('78200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000781','Year chapter','','entry','chapter',false,'2019-01-01T00:00Z','2021-01-01T00:00Z','year','UTC',null,null),
 ('78200000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000781','First marathon','x','entry','entry',true,'2022-10-09T12:00Z',null,'day','UTC',null,null),
 ('78200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000781','First year abroad','','entry','chapter',true,'2013-09-01T12:00Z','2014-06-30T12:00Z','day',null,null,null),
 ('78200000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000781','College years','','entry','chapter',false,null,null,'approximate','UTC','college years',null),
 ('78200000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000781','Plain walk','x','entry','entry',false,'2020-05-01T12:00Z',null,'day','UTC',null,null),
 ('78200000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000781','Trashed chapter','','entry','chapter',false,'2020-01-01T12:00Z',null,'day','UTC',null,now()),
 ('78200000-0000-4000-8000-000000000008','10000000-0000-0000-0000-000000000781',null,'Untitled first time','entry','entry',true,null,null,'unknown','UTC',null,null),
 ('78200000-0000-4000-8000-000000000009','10000000-0000-0000-0000-000000000782','Foreign chapter','','entry','chapter',false,'2020-01-01T12:00Z',null,'day','UTC',null,null);
insert into public.tags(id,owner_id,name) values
 ('78300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000781','work'),
 ('78300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000781','Home');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
 ('78200000-0000-4000-8000-000000000002','78300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000781'),
 ('78200000-0000-4000-8000-000000000002','78300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000781');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000781',true);

select is(
  (select array_agg(title order by ordinality) from public.timeline_workspace() with ordinality),
  array['First year abroad','Year chapter','Open chapter','First marathon','College years',''],
  'Timeline lists Chapters and First Times by start, with unanchored items last and stored titles only'
);
select is((select window_start || '/' || window_end from public.timeline_workspace() where title='Year chapter'),'2019-01-01/2022-01-01','A Year Chapter 2019 to 2021 covers through the end of 2021');
select is((select coalesce(window_end::text,'open') from public.timeline_workspace() where title='Open chapter'),'open','An open Chapter has no end day');
select is((select window_start::text from public.timeline_workspace() where title='Open chapter'),'2021-03-01','An open Chapter starts on its day');
select is((select window_start || '/' || window_end from public.timeline_workspace() where title='First marathon'),'2022-10-09/2022-10-10','A First Time that is not a Chapter covers its day');
select is((select count(*) from public.timeline_workspace() where window_start is null),2::bigint,'Unanchored items have no days');
select is((select is_chapter from public.timeline_workspace() where title='First marathon'),false,'A First Time Entry is not a Chapter');
select is((select is_chapter and is_first_time from public.timeline_workspace() where title='First year abroad'),true,'A First Time Chapter is one row with both marks');
select is((select occurred_timezone from public.timeline_workspace() where title='First year abroad'),'UTC','A missing zone reads as UTC');
select is((select tag_names from public.timeline_workspace() where title='Year chapter'),array['Home','work'],'Timeline carries tag names in case-insensitive order');
select ok(not exists(select 1 from public.timeline_workspace() where title in ('Plain walk','Trashed chapter','Foreign chapter')),'Timeline leaves out ordinary Entries, Trash, and other owners');

-- First Times lists the mark, a First Time Chapter included.
select is(
  (select array_agg(title order by ordinality) from public.first_times_workspace() with ordinality),
  array['First marathon','First year abroad',''],
  'First Times lists every Entry marked First Time, newest first'
);
select is((select is_chapter from public.first_times_workspace() where title='First year abroad'),true,'A First Time Chapter says so');
select is((select is_chapter from public.first_times_workspace() where title='First marathon'),false,'A First Time Entry is not a Chapter');

-- Dashboard Now lists the Chapters that have started and not ended.
select is(
  (select first_time_count from public.home_workspace('2026-10-18','UTC',5)),
  3::bigint,
  'The First Time count reads the mark'
);
select is(
  (select now_count from public.home_workspace('2026-10-18','UTC',5)),
  1::bigint,
  'Now counts a started Chapter without an end, and not an ended, Trashed, or unanchored one'
);
select is(
  (select now_items->0->>'title' from public.home_workspace('2026-10-18','UTC',5)),
  'Open chapter',
  'Now lists the open Chapter'
);
select is(
  (select array(select jsonb_object_keys(now_items->0) order by 1) from public.home_workspace('2026-10-18','UTC',5)),
  array['date_precision','entry_id','is_first_time','occurred_end','occurred_label','occurred_start','occurred_timezone','title'],
  'Now items have exactly the Chapter fields'
);
select is(
  (select now_count from public.home_workspace('2021-02-28','UTC',5)),
  0::bigint,
  'A Chapter that has not started is not in Now'
);
reset role;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone,occurred_label) values
 ('78400000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000781','Roughly this year','','entry','chapter','2026-02-01T12:00Z','approximate','UTC','this year');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000781',true);
select is(
  (select now_count from public.home_workspace('2026-10-18','UTC',5)),
  2::bigint,
  'A Not sure Chapter with a rough start and no end counts as going on'
);
select is(
  (select entry_count from public.home_workspace('2026-10-18','UTC',5)),
  8::bigint,
  'Entries counts every active Entry, Chapters included'
);

-- Search: the three classifications.
select is((select count(*) from public.search_wiki_items('chapter',array['entry'])),0::bigint,'The entry classification leaves out Chapters');
select is((select count(*) from public.search_wiki_items('',array['chapter'])),5::bigint,'The chapter classification lists Chapters');
select is((select count(*) from public.search_wiki_items('',array['first_time'])),3::bigint,'The first_time classification lists marked Entries, Chapters included');
select is((select count(*) from public.search_wiki_items('',array['chapter','first_time'])),7::bigint,'Classifications combine with OR');
select is((select count(*) from public.search_wiki_items('',array['entity'])),0::bigint,'A retired classification matches nothing');
select is((select count(*) from public.search_wiki_items('first time')),3::bigint,'Structured search text says first time');
select is((select count(*) from public.search_wiki_items('',array['chapter'],'{}','2030-01-01','2030-01-31')),2::bigint,'A Chapter with no end matches a later date filter');
select is((select count(*) from public.search_wiki_items('',array['first_time'],'{}','2030-01-01','2030-01-31')),0::bigint,'An Entry is not ongoing, so it does not match a later date filter');
select is((select is_first_time from public.search_wiki_items('marathon')),true,'Results carry the First Time mark');
select is((select item_subtype from public.search_wiki_items('abroad')),'chapter','Results carry the Chapter subtype');

-- Library rows carry both marks.
select is((select is_first_time from public.wiki_items_workspace('marathon','{}','{}',50,0)),true,'Library rows carry the First Time mark');
select is((select count(*) from public.wiki_items_workspace('',array['entry'],array['chapter'],50,0)),5::bigint,'Library can filter to Chapters');

reset role;
select * from finish();
rollback;
