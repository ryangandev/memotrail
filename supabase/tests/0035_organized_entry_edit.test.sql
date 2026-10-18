begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_start,occurred_timezone) values
 ('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Organized memory','Keep original','entry','entry','exact','2017-07-08T12:34:56.123456Z','Asia/Kathmandu'),
 ('95000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','Specialized Home','Home facts','entity','home','unknown',null,'UTC');
create function pg_temp.edit(id uuid default '95000000-0000-4000-8000-000000000001',rev integer default 1) returns bigint language sql as $$
 select count(*) from public.save_entry(id,rev,'Edited title','Edited words', null,'2017-07-08T12:34:56.123456Z',null,'Asia/Kathmandu',null,'exact',array['kept'],null, null, null);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(public.editable_entry('95000000-0000-4000-8000-000000000001')->>'title','Organized memory','An Entry can be loaded for editing');
select is(public.editable_entry('95000000-0000-4000-8000-000000000002'),null::jsonb,'Specialized Home cannot enter a lossy generic editor');
select is(pg_temp.edit(),1::bigint,'A Standard Entry is editable');
select is((select occurred_start from public.entries where id='95000000-0000-4000-8000-000000000001'),'2017-07-08T12:34:56.123456Z'::timestamptz,'Unchanged exact occurrence retains microseconds');
select is((select count(*) from public.entry_tags where entry_id='95000000-0000-4000-8000-000000000001'),1::bigint,'Edit links its tags');
select is(pg_temp.edit(),0::bigint,'Competing stale edit rejected');
select is(pg_temp.edit('95000000-0000-4000-8000-000000000002'),0::bigint,'Generic save cannot strip a specialized Entry type');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000099',true);
select is(public.editable_entry('95000000-0000-4000-8000-000000000001'),null::jsonb,'Another owner cannot read editor context');
select is(pg_temp.edit('95000000-0000-4000-8000-000000000001',2),0::bigint,'Another owner cannot edit');
reset role;
update public.entries set deleted_at=now() where id='95000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(public.editable_entry('95000000-0000-4000-8000-000000000001'),null::jsonb,'Trash is not editable until restored');
select is(pg_temp.edit('95000000-0000-4000-8000-000000000001',3),0::bigint,'Trashed Entry write rejected');
reset role;
select ok(not has_function_privilege('anon','public.editable_entry(uuid)','execute'),'Anonymous edit context denied');
select * from finish();
rollback;
