begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000089','achievement-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000090','achievement-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000089',true);
create function pg_temp.new_goal() returns uuid language sql as $$
 select entry_id from public.save_goal_entry('First adventure','Original intention','active',null,'{}',null,null);
$$;
create function pg_temp.achieve(id uuid,p_precision text,start_at timestamptz default null,end_at timestamptz default null,label text default null,revision integer default 1)
returns uuid language sql as $$
 select first_time_entry_id from public.achieve_goal_with_occurrence(id,revision,start_at,p_precision,label,'America/Los_Angeles',end_at);
$$;
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'age',null,null,'17岁')$$,'Age-only completion needs no calendar date');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'approximate',null,null,'Summer before college')$$,'Approximate completion needs no invented date');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'unknown')$$,'Unknown completion is supported');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'year','2017-01-01')$$,'Year completion is supported');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'month','2017-07-01')$$,'Month completion is supported');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'day','2017-07-08')$$,'Day completion is supported');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'range','2017-07-08','2017-07-15')$$,'Range completion retains both bounds');
select lives_ok($$select pg_temp.achieve(pg_temp.new_goal(),'exact','2026-11-01 09:30:00.123456Z')$$,'Exact completion retains its instant');
select is(count(distinct date_precision),8::bigint,'All eight precisions are persisted') from public.entries where item_kind = 'entry' and item_subtype='first_time';
select is(count(*),3::bigint,'Description-only and unknown dates have no invented bounds or timezone') from public.entries where item_kind = 'entry' and item_subtype='first_time' and occurred_start is null and occurred_end is null and occurred_timezone is null;
select is(occurred_end,'2017-07-15'::timestamptz,'Range end survives') from public.entries where item_kind = 'entry' and item_subtype='first_time' and date_precision='range';
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'Microseconds and repeated-hour identity survive') from public.entries where item_kind = 'entry' and item_subtype='first_time' and date_precision='exact';
select is(count(*),8::bigint,'Original Goal writing remains unchanged') from public.entries where item_kind='goal' and body='Original intention';
select is(count(*),8::bigint,'New First Times do not duplicate original writing') from public.entries where item_kind = 'entry' and item_subtype='first_time' and body='';
select is(count(*),8::bigint,'Every completion has exactly one achievement relationship') from public.entry_links where relationship='achievement';
select is(count(*),8::bigint,'Original revisions are retained in history') from public.entry_versions;
create temporary table fixture as select pg_temp.new_goal() id;
select throws_ok($$select pg_temp.achieve(id,'range','2017-07-15','2017-07-08') from fixture$$,'22023','invalid_first_time_occurrence','Reversed bounds are rejected');
select throws_ok($$select pg_temp.achieve(id,'age') from fixture$$,'22023','invalid_first_time_occurrence','Missing age description is rejected');
select throws_ok($$select pg_temp.achieve(id,null) from fixture$$,'22023','invalid_first_time_occurrence','Null precision is rejected');
select throws_ok($$select pg_temp.achieve(id,'exact','infinity') from fixture$$,'22023','invalid_first_time_occurrence','Infinite timestamp is rejected');
select is(revision,1,'Invalid completion rolls back the original revision') from public.entries where id=(select id from fixture);
select is(status,'active','Invalid completion rolls back Goal status') from public.goals where entry_id=(select id from fixture);
select is(count(*),0::bigint,'Invalid completion creates no history') from public.entry_versions where entry_id=(select id from fixture);
select is(count(*),8::bigint,'Invalid completion creates no orphan First Time') from public.entries where item_kind = 'entry' and item_subtype='first_time';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000090',true);
select is(pg_temp.achieve(id,'unknown'),null::uuid,'Other owner cannot complete a Goal') from fixture;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000089',true);
select ok(pg_temp.achieve(id,'unknown') is not null,'Valid completion succeeds after rejected attempts') from fixture;
select is(pg_temp.achieve(id,'unknown'),null::uuid,'Stale retry cannot duplicate a First Time') from fixture;
select is(pg_temp.achieve(id,'unknown',null,null,null,2),null::uuid,'Already-achieved Goal cannot create a second First Time with a fresh revision') from fixture;
select is(count(*),1::bigint,'Retries preserve a single achievement') from public.entry_links where source_entry_id=(select id from fixture) and relationship='achievement';
reset role;
select ok(not has_function_privilege('anon','public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)','execute'),'Anonymous completion is denied');
select ok(prosecdef,'Owner-checked completion writes protected achievement links') from pg_proc where oid='public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz)'::regprocedure;
select * from finish();
rollback;
