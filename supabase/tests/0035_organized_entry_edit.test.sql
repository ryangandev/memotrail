begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision,occurred_start,occurred_timezone) values
 ('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Organized memory','Keep original','entry','entry','organized','exact','2017-07-08T12:34:56.123456Z','Asia/Kathmandu'),
 ('95000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','Specialized Goal','Goal facts','goal','goal','organized','unknown',null,'UTC');
insert into public.collections(id,owner_id,name,archived_at) values
 ('95000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000001','Retained archived group',now()),
 ('95000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000001','Active editable group',null);
insert into public.entry_collections(entry_id,owner_id,collection_id) values
 ('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','95000000-0000-4000-8000-000000000003'),
 ('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','95000000-0000-4000-8000-000000000004');
create function pg_temp.edit(id uuid default '95000000-0000-4000-8000-000000000001',rev integer default 1) returns bigint language sql as $$
 select count(*) from public.review_wiki_item_with_photo_place(id,rev,'Edited title','Edited words','entry','entry','2017-07-08T12:34:56.123456Z','Asia/Kathmandu',array['Active editable group'],array['kept'],false,null,null,'exact',null);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(public.editable_entry('95000000-0000-4000-8000-000000000001')->>'inbox_status','organized','Organized Entry can be loaded for editing');
select is(public.editable_entry('95000000-0000-4000-8000-000000000001')->'collection_names','["Active editable group"]'::jsonb,'Edit context excludes archived Collections instead of recreating them');
select is(public.editable_entry('95000000-0000-4000-8000-000000000002'),null::jsonb,'Specialized Goal cannot enter a lossy generic editor');
select is(pg_temp.edit(),1::bigint,'Organized Standard Entry is editable');
select is((select inbox_status from public.entries where id='95000000-0000-4000-8000-000000000001'),'organized','Save does not return the Entry to Inbox');
select is((select occurred_start from public.entries where id='95000000-0000-4000-8000-000000000001'),'2017-07-08T12:34:56.123456Z'::timestamptz,'Unchanged exact occurrence retains microseconds');
select is((select snapshot->>'body' from public.entry_versions where entry_id='95000000-0000-4000-8000-000000000001' and version=1),'Keep original','Original text remains restorable');
select is((select count(*) from public.entry_collections where entry_id='95000000-0000-4000-8000-000000000001'),2::bigint,'Archived grouping survives the later edit');
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
