begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000097','first-precision-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000098','first-precision-other@memotrail.local','{}');
create function pg_temp.save_first(p_precision text,p_start timestamptz,p_end timestamptz,p_label text default null,p_id uuid default null,p_revision integer default null)
returns uuid language sql as $$
 select entry_id from public.save_first_time_with_occurrence('First memory','Original writing',p_start,p_precision,p_label,
 case when p_start is null then null else 'America/Los_Angeles' end,'{}','{}',p_id,p_revision,p_end);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000097',true);
select lives_ok($$select pg_temp.save_first('range','2017-07-08 12:00Z','2017-07-15 12:00Z')$$,'Range creation accepts both bounds');
select is((select occurred_end from public.first_times_workspace_with_occurrence()),'2017-07-15 12:00Z'::timestamptz,'Workspace returns the complete range');
select lives_ok($$select pg_temp.save_first('range',occurred_start,occurred_end,null,entry_id,revision) from public.first_times_workspace_with_occurrence()$$,'Existing range can be saved without rewriting its precision');
select is((select count(*) from public.entry_versions where owner_id=auth.uid()),1::bigint,'Save retains exactly one previous version');
select is((select snapshot->>'occurred_end' from public.entry_versions where owner_id=auth.uid()),'2017-07-15T12:00:00+00:00','History retains original range end');
select is((select count(*) from public.first_times_workspace_with_occurrence()),1::bigint,'Canonical First Time reads remain available');
select hasnt_function('public','save_first_time_entry',array['text','text','timestamp with time zone','text','text','text','text[]','text[]','uuid','integer'],'Legacy mutation is removed');
select is((select revision from public.first_times_workspace_with_occurrence()),2,'Removing the legacy mutation leaves revision unchanged');
select is((select pg_temp.save_first('range',occurred_start,occurred_end,null,entry_id,1) from public.first_times_workspace_with_occurrence()),null::uuid,'Stale revision cannot overwrite a date');
select throws_ok($$select pg_temp.save_first('range','2017-07-15','2017-07-08')$$,'22023','invalid_first_time_occurrence','End before start is rejected');
select throws_ok($$select pg_temp.save_first('day','2017-07-08','2017-07-09')$$,'22023','invalid_first_time_occurrence','Single-day precision cannot conceal a range');
select throws_ok($$select pg_temp.save_first('unknown','2017-07-08',null)$$,'22023','invalid_first_time_occurrence','Unknown does not invent an anchor');
select throws_ok($$select pg_temp.save_first('age',null,null)$$,'22023','invalid_first_time_occurrence','Age requires a human description');
select throws_ok($$select pg_temp.save_first('approximate',null,null)$$,'22023','invalid_first_time_occurrence','Approximate requires a human description');
select throws_ok($$select pg_temp.save_first('exact','infinity',null)$$,'22023','invalid_first_time_occurrence','Infinite timestamps are rejected');
select throws_ok($$select pg_temp.save_first(null,null,null)$$,'22023','invalid_first_time_occurrence','Null precision is rejected');
select lives_ok($$select pg_temp.save_first('age',null,null,'17岁')$$,'Age-only memory needs no calendar date');
select lives_ok($$select pg_temp.save_first('approximate',null,null,'Summer before college')$$,'Approximate description needs no invented calendar date');
select lives_ok($$select pg_temp.save_first('unknown',null,null)$$,'Title-only memory remains supported');
select lives_ok($$select pg_temp.save_first('exact','2026-11-01 09:30:00.123456Z',null)$$,'Exact instant retains fractional seconds and ambiguous-hour identity');
select lives_ok($$select pg_temp.save_first('day','2017-07-08',null)$$,'Day precision remains supported');
select lives_ok($$select pg_temp.save_first('month','2017-07-01',null)$$,'Month precision remains supported');
select lives_ok($$select pg_temp.save_first('year','2017-01-01',null)$$,'Year precision remains supported');
select is((select count(*) from public.first_times_workspace_with_occurrence()),8::bigint,'All eight precisions are available');
select is((select occurred_start from public.first_times_workspace_with_occurrence() where date_precision='exact'),'2026-11-01 09:30:00.123456Z'::timestamptz,'Exact timestamp does not round microseconds');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000098',true);
select is((select count(*) from public.first_times_workspace_with_occurrence()),0::bigint,'Another account cannot read date metadata');
reset role;
select ok(not has_function_privilege('anon','public.first_times_workspace_with_occurrence()','execute'),'Anonymous workspace access is denied');
select ok(not has_function_privilege('anon','public.save_first_time_with_occurrence(text,text,timestamptz,text,text,text,text[],text[],uuid,integer,timestamptz)','execute'),'Anonymous writes are denied');
select * from finish();
rollback;
