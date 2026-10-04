begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000087','timeline-date-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000088','timeline-date-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000087',true);
create function pg_temp.save_moment(p_precision text,p_start timestamptz default null,p_end timestamptz default null,p_label text default null,p_id uuid default null,p_revision integer default null,p_kind text default 'stage')
returns uuid language sql as $$
 select entry_id from public.save_timeline_entry_with_occurrence(
 (select id from public.timeline_tracks where owner_id=auth.uid() order by sort_order limit 1),
 p_kind,'A chapter','Original memory',p_start,p_end,p_precision,p_label,'America/Los_Angeles',p_id,p_revision);
$$;
select lives_ok($$select pg_temp.save_moment('age',null,null,'Ages 1 to 12')$$,'Age description needs no guessed birthday');
select lives_ok($$select pg_temp.save_moment('approximate',null,null,'Before college')$$,'Approximate description needs no calendar anchor');
select lives_ok($$select pg_temp.save_moment('unknown')$$,'Unknown stages remain supported');
select lives_ok($$select pg_temp.save_moment('year','2017-01-01','2023-01-01')$$,'Year precision supports a stage end');
select lives_ok($$select pg_temp.save_moment('month','2017-07-01','2023-06-01')$$,'Month precision supports a stage end');
select lives_ok($$select pg_temp.save_moment('day','2017-07-08','2023-06-01')$$,'Day precision supports a stage end');
select lives_ok($$select pg_temp.save_moment('range','2017-07-08')$$,'Range can be ongoing');
select lives_ok($$select pg_temp.save_moment('exact','2026-11-01 09:30:00.123456Z','2026-11-01 10:30:00.654321Z')$$,'Exact stage keeps both instants');
select is(count(*),8::bigint,'Workspace retains all eight moments including unanchored ones') from public.timeline_workspace_with_organization(false) where entry_id is not null;
select is(count(*),3::bigint,'Unanchored moments have no fabricated start or timezone') from public.timeline_workspace_with_organization(false) where entry_id is not null and occurred_start is null and occurred_timezone is null;
create temporary table fixture as select entry_id id from public.timeline_workspace_with_organization(false) where date_precision='exact';
select is(pg_temp.save_moment(date_precision,occurred_start,occurred_end,occurred_label,entry_id,revision),entry_id,'Exact stage can save without rewriting its bounds') from public.timeline_workspace_with_organization(false) where date_precision='exact';
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'Start microseconds survive') from public.entries where id=(select id from fixture);
select is(occurred_end,'2026-11-01 10:30:00.654321Z'::timestamptz,'End microseconds survive') from public.entries where id=(select id from fixture);
select is(pg_temp.save_moment('unknown',null,null,null,id,1),null::uuid,'Stale revision cannot erase exact data') from fixture;
select throws_ok($$select pg_temp.save_moment('age')$$,'22023','invalid_timeline_occurrence','Age requires a description');
select throws_ok($$select pg_temp.save_moment('unknown','2017-07-08')$$,'22023','invalid_timeline_occurrence','Unknown cannot imply a calendar date');
select throws_ok($$select pg_temp.save_moment('exact','infinity')$$,'22023','invalid_timeline_occurrence','Infinite dates are rejected');
select throws_ok($$select pg_temp.save_moment('year','2023-01-01','2017-01-01')$$,'22023','invalid_timeline_range','Reversed stage is rejected');
select throws_ok($$select pg_temp.save_moment('day','2017-07-08','2017-07-09',null,null,null,'event')$$,'22023','event_cannot_have_end','Point events cannot have ends');
select throws_ok($$select pg_temp.save_moment(null)$$,'22023','invalid_date_precision','Null precision is rejected');
select is(count(*),8::bigint,'Rejected writes create no orphan moments') from public.entries;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000088',true);
select is(pg_temp.save_moment('unknown',null,null,null,id,2),null::uuid,'Another owner cannot overwrite a moment') from fixture;
select is(count(*),0::bigint,'Other owner cannot read the moments') from public.timeline_workspace_with_organization(false) where entry_id is not null;
reset role;
select ok(not has_function_privilege('anon','public.save_timeline_entry_with_occurrence(uuid,text,text,text,timestamptz,timestamptz,text,text,text,uuid,integer)','execute'),'Anonymous mutations are denied');
select ok(not prosecdef,'Mutation keeps caller RLS') from pg_proc where oid='public.save_timeline_entry_with_occurrence(uuid,text,text,text,timestamptz,timestamptz,text,text,text,uuid,integer)'::regprocedure;
select * from finish();
rollback;
