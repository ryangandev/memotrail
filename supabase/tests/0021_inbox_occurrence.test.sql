begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into public.entries(id,owner_id,title,body,date_precision,occurred_start) values
 ('97000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Undated memory','A feeling','unknown',null);
create function pg_temp.review(p_precision text, p_start timestamptz default null, p_end timestamptz default null, p_label text default null, p_rev integer default null, p_zone text default 'UTC') returns bigint language sql as $$
 select count(*) from public.save_entry(
 '97000000-0000-4000-8000-000000000001',coalesce(p_rev,(select revision from public.entries where id='97000000-0000-4000-8000-000000000001'),1),
 'Reviewed memory','My words', null,p_start,p_end,p_zone,p_label,p_precision,array['memory'],null, null, false, false);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(pg_temp.review('unknown'),1::bigint,'Unknown occurrence can be reviewed without manufacturing a date');
select is((select occurred_start from public.entries where id='97000000-0000-4000-8000-000000000001'),null::timestamptz,'Unknown start stays null');
select is((select revision from public.entries where id='97000000-0000-4000-8000-000000000001'),2,'One atomic revision per review');
select is((select count(*) from public.entry_tags where entry_id='97000000-0000-4000-8000-000000000001'),1::bigint,'Review links its tags');
select is(pg_temp.review('age',null,null,'17岁'),1::bigint,'Age-only accepted');
select is((select occurred_label from public.entries where id='97000000-0000-4000-8000-000000000001'),'17岁','Bilingual age label retained');
select is(pg_temp.review('approximate',null,null,'Summer before college'),1::bigint,'Approximate description needs no invented date');
select is(pg_temp.review('exact','2026-09-12T06:15:27.123Z',null,null,null,'Asia/Kathmandu'),1::bigint,'Exact fractional offset zone accepted');
select is((select occurred_start from public.entries where id='97000000-0000-4000-8000-000000000001'),'2026-09-12T06:15:27.123Z'::timestamptz,'Exact fractional seconds preserved');
select is(pg_temp.review('day','2017-07-08T12:00Z'),1::bigint,'Day precision accepted');
select is(pg_temp.review('month','2017-07-01T12:00Z'),1::bigint,'Month precision accepted');
select is(pg_temp.review('year','2017-01-01T12:00Z'),1::bigint,'Year precision accepted');
select is((select date_precision from public.entries where id='97000000-0000-4000-8000-000000000001'),'year','Year precision not coerced to exact');
select is(pg_temp.review('range','2017-01-01T12:00Z','2020-01-01T12:00Z'),1::bigint,'Closed date range accepted');
select is(pg_temp.review('range','2017-01-01T12:00Z'),1::bigint,'Open-ended date range accepted');
select throws_ok($$select pg_temp.review('range','2020-01-01','2017-01-01')$$,'22023','invalid_occurrence','Reversed bounds rejected');
select throws_ok($$select pg_temp.review('unknown','2020-01-01')$$,'22023','invalid_occurrence','Unknown cannot conceal an exact date');
select throws_ok($$select pg_temp.review('age')$$,'22023','invalid_occurrence','Age requires description');
select throws_ok($$select pg_temp.review('approximate')$$,'22023','invalid_occurrence','Approximate requires description');
select throws_ok($$select pg_temp.review('day')$$,'22023','invalid_occurrence','Day requires date');
select throws_ok($$select pg_temp.review('nonsense')$$,'22023','invalid_occurrence','Unsupported precision denied');
select throws_ok($$select pg_temp.review(null)$$,'22023','invalid_occurrence','Null precision denied');
select throws_ok($$select pg_temp.review('day','2020-01-01',null,null,null,'Invalid/Zone')$$,'22023','invalid_occurrence','Invalid timezone denied');
select throws_ok($$select pg_temp.review('age',null,null,repeat('x',201))$$,'22023','invalid_occurrence','Description bounded');
select throws_ok($$select pg_temp.review('exact','infinity')$$,'22023','invalid_occurrence','Infinite date denied');
select is(pg_temp.review('unknown',null,null,null,1),0::bigint,'Stale revision rejected');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000099',true);
select is(pg_temp.review('unknown'),0::bigint,'Another owner cannot review');
reset role;
select ok(not has_function_privilege('anon','public.save_entry(uuid,integer,text,text,jsonb,timestamptz,timestamptz,text,text,text,text[],jsonb,jsonb,boolean,boolean)','execute'),'Anonymous review denied');
select hasnt_function('public','review_entry',array['uuid','integer','text','text','text','timestamp with time zone','text','text[]','text[]','boolean'],'Legacy review contract is removed');
select * from finish();
rollback;
