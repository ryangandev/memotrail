begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000089','chapter-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000090','chapter-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000089',true);
create function pg_temp.save_home(p_precision text,p_start timestamptz default null,p_end timestamptz default null,p_label text default null,p_id uuid default null,p_revision integer default null,p_reason text default '')
returns uuid language plpgsql as $$
declare result uuid;
begin
 select entry_id into result from public.save_home_entry_with_occurrence('Chapter','Original memory',p_start,p_end,p_precision,p_label,'America/Los_Angeles','',p_reason,'{}',p_id,p_revision);
 return result;
end; $$;
select lives_ok($$select pg_temp.save_home('age',null,null,'Ages 17 to 23')$$,'home: age needs no guessed birthday');
select lives_ok($$select pg_temp.save_home('approximate',null,null,'During college')$$,'home: approximate needs no calendar anchor');
select lives_ok($$select pg_temp.save_home('unknown')$$,'home: unknown needs no date');
select lives_ok($$select pg_temp.save_home('year','2017-01-01','2023-01-01')$$,'home: year supports an end');
select lives_ok($$select pg_temp.save_home('month','2017-07-01','2023-06-01')$$,'home: month supports an end');
select lives_ok($$select pg_temp.save_home('day','2017-07-08','2023-06-01')$$,'home: day supports an end');
select lives_ok($$select pg_temp.save_home('range','2017-07-08')$$,'home: range supports ongoing chapters');
select lives_ok($$select pg_temp.save_home('exact','2026-11-01 09:30:00.123456Z','2026-11-01 10:30:00.654321Z')$$,'home: exact keeps both instants');
select is(count(*),8::bigint,'home: workspace includes all precisions') from public.homes_workspace();
select is(count(*),3::bigint,'home: unanchored rows have no invented timezone') from public.homes_workspace() where occurred_start is null and occurred_timezone is null;
select is(date_precision,'range','home: known current dates sort before unanchored current chapters') from public.homes_workspace() limit 1;
create temporary table home_fixture as select entry_id id from public.homes_workspace() where date_precision='exact';
select is(pg_temp.save_home(date_precision,occurred_start,occurred_end,occurred_label,entry_id,revision),entry_id,'home: exact resave succeeds') from public.homes_workspace() where date_precision='exact';
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'home: start microseconds survive') from public.entries where id=(select id from home_fixture);
select is(occurred_end,'2026-11-01 10:30:00.654321Z'::timestamptz,'home: end microseconds survive') from public.entries where id=(select id from home_fixture);
select is(pg_temp.save_home('unknown',null,null,null,id,1),null::uuid,'home: stale save cannot erase dates') from home_fixture;
select throws_ok($$select pg_temp.save_home('age')$$,'22023','invalid_home_occurrence','home: age requires label');
select throws_ok($$select pg_temp.save_home('unknown','2017-01-01')$$,'22023','invalid_home_occurrence','home: unknown rejects invented date');
select throws_ok($$select pg_temp.save_home('exact','infinity')$$,'22023','invalid_home_occurrence','home: infinite date rejected');
select throws_ok($$select pg_temp.save_home('year','2023-01-01','2017-01-01')$$,'22023','invalid_home_range','home: reversed chapter rejected');
select throws_ok($$select pg_temp.save_home(null)$$,'22023','invalid_date_precision','home: null precision rejected');
select is(count(*),8::bigint,'home: rejected writes create no orphan entries') from public.entries where item_kind='entity' and item_subtype='home';
select throws_ok($$select pg_temp.save_home('unknown',null,null,null,null,null,'Moving away')$$,'22023','home_move_out_requires_date','Home move-out reason still needs a known end');
create function pg_temp.save_vehicle(p_precision text,p_start timestamptz default null,p_end timestamptz default null,p_label text default null,p_id uuid default null,p_revision integer default null,p_reason text default '')
returns uuid language plpgsql as $$
declare result uuid;
begin
 select entry_id into result from public.save_vehicle_entry_with_occurrence('Chapter','Original memory',p_start,p_end,p_precision,p_label,'America/Los_Angeles','Test make','Test model',2020,'Blue','{}',p_id,p_revision);
 return result;
end; $$;
select lives_ok($$select pg_temp.save_vehicle('age',null,null,'Ages 17 to 23')$$,'vehicle: age needs no guessed birthday');
select lives_ok($$select pg_temp.save_vehicle('approximate',null,null,'During college')$$,'vehicle: approximate needs no calendar anchor');
select lives_ok($$select pg_temp.save_vehicle('unknown')$$,'vehicle: unknown needs no date');
select lives_ok($$select pg_temp.save_vehicle('year','2017-01-01','2023-01-01')$$,'vehicle: year supports an end');
select lives_ok($$select pg_temp.save_vehicle('month','2017-07-01','2023-06-01')$$,'vehicle: month supports an end');
select lives_ok($$select pg_temp.save_vehicle('day','2017-07-08','2023-06-01')$$,'vehicle: day supports an end');
select lives_ok($$select pg_temp.save_vehicle('range','2017-07-08')$$,'vehicle: range supports ongoing chapters');
select lives_ok($$select pg_temp.save_vehicle('exact','2026-11-01 09:30:00.123456Z','2026-11-01 10:30:00.654321Z')$$,'vehicle: exact keeps both instants');
select is(count(*),8::bigint,'vehicle: workspace includes all precisions') from public.vehicles_workspace();
select is(count(*),3::bigint,'vehicle: unanchored rows have no invented timezone') from public.vehicles_workspace() where occurred_start is null and occurred_timezone is null;
select is(date_precision,'range','vehicle: known current dates sort before unanchored current chapters') from public.vehicles_workspace() limit 1;
create temporary table vehicle_fixture as select entry_id id from public.vehicles_workspace() where date_precision='exact';
select is(pg_temp.save_vehicle(date_precision,occurred_start,occurred_end,occurred_label,entry_id,revision),entry_id,'vehicle: exact resave succeeds') from public.vehicles_workspace() where date_precision='exact';
select is(occurred_start,'2026-11-01 09:30:00.123456Z'::timestamptz,'vehicle: start microseconds survive') from public.entries where id=(select id from vehicle_fixture);
select is(occurred_end,'2026-11-01 10:30:00.654321Z'::timestamptz,'vehicle: end microseconds survive') from public.entries where id=(select id from vehicle_fixture);
select is(pg_temp.save_vehicle('unknown',null,null,null,id,1),null::uuid,'vehicle: stale save cannot erase dates') from vehicle_fixture;
select throws_ok($$select pg_temp.save_vehicle('age')$$,'22023','invalid_vehicle_occurrence','vehicle: age requires label');
select throws_ok($$select pg_temp.save_vehicle('unknown','2017-01-01')$$,'22023','invalid_vehicle_occurrence','vehicle: unknown rejects invented date');
select throws_ok($$select pg_temp.save_vehicle('exact','infinity')$$,'22023','invalid_vehicle_occurrence','vehicle: infinite date rejected');
select throws_ok($$select pg_temp.save_vehicle('year','2023-01-01','2017-01-01')$$,'22023','invalid_vehicle_range','vehicle: reversed chapter rejected');
select throws_ok($$select pg_temp.save_vehicle(null)$$,'22023','invalid_date_precision','vehicle: null precision rejected');
select is(count(*),8::bigint,'vehicle: rejected writes create no orphan entries') from public.entries where item_kind='entity' and item_subtype='vehicle';
select is(count(*),16::bigint,'Timeline retains every specialized chapter') from public.timeline_workspace() where item_kind = 'entity' and item_subtype in ('home','vehicle') and shape = 'period';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000090',true);
select is(pg_temp.save_home('unknown',null,null,null,id,2),null::uuid,'home: cross-owner mutation denied') from home_fixture;
select is(count(*),0::bigint,'home: cross-owner read denied') from public.homes_workspace();
select is(pg_temp.save_vehicle('unknown',null,null,null,id,2),null::uuid,'vehicle: cross-owner mutation denied') from vehicle_fixture;
select is(count(*),0::bigint,'vehicle: cross-owner read denied') from public.vehicles_workspace();
reset role;
select ok(not has_function_privilege('anon',oid,'execute'),'Anonymous chapter mutations denied') from pg_proc where proname in ('save_home_entry_with_occurrence','save_vehicle_entry_with_occurrence');
select ok(not prosecdef,'Chapter mutations retain caller RLS') from pg_proc where proname in ('save_home_entry_with_occurrence','save_vehicle_entry_with_occurrence');
select * from finish();
rollback;
