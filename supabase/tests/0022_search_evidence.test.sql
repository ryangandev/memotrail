begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values('10000000-0000-0000-0000-000000000099','evidence-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title,body,date_precision,occurred_start) values
 ('98000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Before the move','搬家前，我在思考为什么人需要不断学习。','day','2026-01-05T12:00Z'),
 ('98000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','After the move','Electric lighters use an electric arc.','day','2026-01-07T12:00Z'),
 ('98000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000001','An uncertain first','First time skiing at age 17.','age',null),
 ('98000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000099','Private other owner','Private electric lighters note.','day','2026-01-04T12:00Z');
insert into public.entries(id,owner_id,title,entry_type,date_precision,occurred_start) values
 ('98000000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000001','Most recent home','home','day','2026-01-06T12:00Z');
insert into public.homes(entry_id,owner_id,move_in_reason) values('98000000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000001','Closer to work');
insert into public.people(id,owner_id,name,notes) values('98000000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000001','Evidence mentor','Explained electric arcs');
insert into public.places(id,owner_id,name,notes) values('98000000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000001','Evidence workshop','An electric arc workshop');
insert into public.habits(id,owner_id,name,starts_on,schedule) values
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','Evidence vitamin D','2026-01-01','{"kind":"daily"}'),
 ('98000000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000001','Evidence weekly exercise','2026-01-05','{"kind":"weekly_target","target":3}'),
 ('98000000-0000-4000-8000-000000000013','10000000-0000-0000-0000-000000000099','Hidden habit','2026-01-01','{"kind":"daily"}');
insert into public.habit_occurrences(habit_id,owner_id,local_date,status) values
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','2026-01-01','completed'),
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','2026-01-02','skipped'),
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','2026-01-03','missed'),
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','2026-01-04','not_scheduled'),
 ('98000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000001','2026-01-10','missed');
insert into public.habit_occurrences(habit_id,owner_id,local_date,status)
 select '98000000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000001',day::date,'completed' from unnest(array['2026-01-05','2026-01-06','2026-01-12','2026-01-13','2026-01-14','2026-01-15']) day;
create function pg_temp.habit_fact(p_name text,p_from date default null,p_to date default null,p_as_of date default '2026-01-19') returns jsonb language sql as $$
 select value from jsonb_array_elements(public.archive_habit_evidence(p_from,p_to,p_as_of)->'habits') where value->>'name'=p_name;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(jsonb_array_length(public.archive_entry_sources(array['98000000-0000-4000-8000-000000000001','98000000-0000-4000-8000-000000000004']::uuid[])),1,'Sources exclude another owner');
select is(public.archive_entry_sources(array['98000000-0000-4000-8000-000000000003']::uuid[])->0->>'date_precision','age','Source retains uncertainty');
select is(public.archive_entry_sources(array['98000000-0000-4000-8000-000000000003']::uuid[])->0->'occurred_start','null'::jsonb,'No invented date in evidence');
select ok(not (public.archive_entry_sources(array['98000000-0000-4000-8000-000000000001']::uuid[])->0 ? 'attachments'),'Text evidence excludes media');
select is(jsonb_array_length(public.archive_search_evidence(array['不断学习'])->'entries'),1,'Chinese query evidence');
select is(jsonb_array_length(public.archive_search_evidence(array['electric arc'])->'people'),1,'Standalone People can be found');
select is(jsonb_array_length(public.archive_search_evidence(array['electric arc'])->'places'),1,'Standalone Places can be found');
select is(jsonb_array_length(public.archive_search_evidence(array['electric arc'],array['first_time'])->'people'),0,'Entry Type filters do not leak unrelated People');
select is((public.archive_search_evidence('{}',array['standard'],'{}','{}',null,null,true,false,'newest','2026-01-19')->>'reference_window_applied')::boolean,true,'Precise last Home supplies a window');
select is(public.archive_search_evidence('{}',array['standard'],'{}','{}',null,null,true,false,'newest','2026-01-19')->>'effective_date_to','2026-01-05','Before move uses prior calendar days');
select is(public.archive_search_evidence('{}',array['standard'],'{}','{}',null,null,true,false,'newest','2026-01-19')->'latest_home_reference'->'facts'->'home'->>'move_in_reason','Closer to work','Reference includes structured Home facts');
select ok(not exists(select 1 from jsonb_array_elements(public.archive_search_evidence('{}',array['standard'],'{}','{}',null,null,true,false,'newest','2026-01-19')->'entries') e where e->>'id'='98000000-0000-4000-8000-000000000002'),'Post-move note excluded');
update public.entries set date_precision='month' where id='98000000-0000-4000-8000-000000000005';
select is((public.archive_search_evidence('{}','{}','{}','{}',null,null,true,false,'newest','2026-01-19')->>'reference_window_applied')::boolean,false,'Uncertain Home never supplies a pretend exact boundary');
select is(public.habit_scheduled_day_count('{"kind":"daily"}','2026-01-01',null,'2026-01-02','2026-01-10'),9,'Daily scheduled count');
select is(public.habit_scheduled_day_count('{"kind":"weekdays","weekdays":[1,3,5]}','2026-01-01',null,'2026-01-01','2026-01-14'),6,'Weekday scheduled count');
select is(public.habit_scheduled_day_count('{"kind":"interval","every_days":3}','2026-01-01',null,'2026-01-02','2026-01-10'),3,'Interval count retains original anchor');
select is(public.habit_scheduled_day_count('{"kind":"daily"}','2026-01-01','2026-01-05','2026-01-01','2026-01-10'),5,'Ending date clips expected schedule');
select is((pg_temp.habit_fact('Evidence vitamin D',null,null,'2026-01-10')->>'missed_days')::integer,7,'Misses include past missing days and explicit today, not skips or explicit unscheduled dates');
select is((pg_temp.habit_fact('Evidence vitamin D',null,null,'2026-01-10')->>'recorded_missed_days')::integer,2,'Recorded misses distinguish inferred misses');
select is((pg_temp.habit_fact('Evidence vitamin D','2026-01-02','2026-01-05','2026-01-10')->>'missed_days')::integer,2,'Explicit date filters apply to Habit evidence');
select is((pg_temp.habit_fact('Evidence weekly exercise')->>'complete_weeks')::integer,2,'Only completed full weeks count');
select is((pg_temp.habit_fact('Evidence weekly exercise')->>'shortfall_weeks')::integer,1,'Weekly comparison counts unmet target weeks');
select is((pg_temp.habit_fact('Evidence weekly exercise')->>'missing_weekly_completions')::integer,1,'Extra completions never erase a different week deficit');
select is(pg_temp.habit_fact('Evidence weekly exercise')->'missed_days','null'::jsonb,'Weekly targets do not invent scheduled missing days');
select is(pg_temp.habit_fact('Hidden habit'),null::jsonb,'Another owner Habit excluded');
select is(public.archive_search_evidence(array['vitamin'],array['goal'],'{}','{}',null,null,false,true)->'habits','null'::jsonb,'Entry-only filters do not silently ignore constraints for Habits');
select throws_ok($$select public.archive_search_evidence(array['a','b','c','d','e','f','g'])$$,'22023','invalid_evidence_request','Query fanout bounded');
select throws_ok($$select public.archive_search_evidence('{}','{}','{}','{}','2026-02-01','2026-01-01')$$,'22023','invalid_evidence_request','Reversed date range denied');
select throws_ok($$select public.archive_search_evidence('{}','{}','{}','{}',null,null,false,false,'invalid')$$,'22023','invalid_evidence_request','Sort contract validated');
select throws_ok($$select public.archive_entry_sources(array_fill('98000000-0000-4000-8000-000000000001'::uuid,array[41]))$$,'22023','too_many_sources','Source fanout bounded');
reset role;
insert into public.entries(owner_id,title,body,entry_type,occurred_start)
 select '10000000-0000-0000-0000-000000000001','Chronological skiing evidence','Unique skiing stress fixture','first_time',('2000-01-01'::date+n)::timestamptz from generate_series(0,110) n;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((public.archive_search_evidence(array['Unique skiing stress fixture'],array['first_time'],'{}','{}',null,null,false,false,'oldest')->'entries'->0->>'occurred_start')::timestamptz,'2000-01-01'::timestamptz,'Earliest result is selected before limiting even with over 100 matches');
select is((public.archive_search_evidence(array['Unique skiing stress fixture'],array['first_time'])->>'query_truncated')::boolean,true,'Bounded query coverage is explicit');
select is(jsonb_array_length(public.archive_search_evidence(array['Unique skiing stress fixture'],array['first_time'])->'entries'),36,'Evidence payload source count bounded');
select is((select count(*) from public.search_entries('Unique skiing stress fixture','{}','{}','{}',null,null,25,0)),25::bigint,'Existing keyword RPC preserves its public contract');
reset role;
select ok(not has_function_privilege('anon','public.archive_entry_sources(uuid[])','execute'),'Anonymous source read denied');
select ok(not has_function_privilege('anon','public.archive_habit_evidence(date,date,date)','execute'),'Anonymous Habit evidence denied');
select ok(not has_function_privilege('anon','public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date)','execute'),'Anonymous evidence search denied');
select * from finish();
rollback;
