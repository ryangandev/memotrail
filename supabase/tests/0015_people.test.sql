begin;
create extension if not exists pgtap with schema extensions;
select plan(23);
insert into public.entries(id, owner_id, title, body)
values('91000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Shared memory','A walk with a friend.');
insert into public.people(id, owner_id, name)
values('92000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Original person');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.save_person('  Friend  ','Mentor','Notes',
 array['91000000-0000-4000-8000-000000000001'::uuid],
 '92000000-0000-4000-8000-000000000001',1)),1::bigint,'Save updates a Person');
select is((select name from public.people where id='92000000-0000-4000-8000-000000000001'),'Friend','Name is trimmed');
select is((select revision from public.people where id='92000000-0000-4000-8000-000000000001'),2,'Revision increments');
select is((select count(*) from public.person_versions where person_id='92000000-0000-4000-8000-000000000001'),1::bigint,'History captured');
select is((select count(*) from public.save_person('Stale','','','{}',
 '92000000-0000-4000-8000-000000000001',1)),0::bigint,'Stale edit rejected');
select is((select count(*) from public.entry_people where person_id='92000000-0000-4000-8000-000000000001'),1::bigint,'Conflict preserves links');
select is((select count(*) from public.trash_person('92000000-0000-4000-8000-000000000001',2)),0::bigint,'Linked Person cannot be trashed');
select is((select jsonb_array_length(linked_entries) from public.people_workspace() where id='92000000-0000-4000-8000-000000000001'),1,'Workspace includes connected memory');
select throws_ok($$select * from public.save_person('','','','{}',null,null)$$,'22023','invalid_person_details','Blank name rejected');
select throws_ok($$select * from public.save_person('Friend','','',array['91000000-0000-4000-8000-999999999999'::uuid],null,null)$$,'22023','invalid_person_entries','Inaccessible Entry rejected');
select throws_ok($$select * from public.people_workspace(101,0)$$,'22023','invalid_people_page','Pagination validated');
select is((select count(*) from public.save_person('Friend','Mentor','Unlinked','{}',
 '92000000-0000-4000-8000-000000000001',2)),1::bigint,'Unlink and edit atomically');
select is((select count(*) from public.trash_person('92000000-0000-4000-8000-000000000001',3)),1::bigint,'Unlinked Person moves to Trash');
select is((select count(*) from public.people_workspace() where id='92000000-0000-4000-8000-000000000001'),0::bigint,'Trashed Person hidden');
select is((select count(*) from public.trash_workspace() where item_kind='person' and item_id='92000000-0000-4000-8000-000000000001'),1::bigint,'Shared Trash includes Person');
select is((select count(*) from public.restore_trash_item('person','92000000-0000-4000-8000-000000000001',4,
 (select deleted_at from public.people where id='92000000-0000-4000-8000-000000000001'))),1::bigint,'Restore works');
select is((select count(*) from public.trash_person('92000000-0000-4000-8000-000000000001',5)),1::bigint,'Restored Person can be trashed again');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000099',true);
select is((select count(*) from public.people_workspace()),0::bigint,'Other user cannot browse owner People');
select is((select count(*) from public.person_versions where person_id='92000000-0000-4000-8000-000000000001'),0::bigint,'Other user cannot read history');
select is((select count(*) from public.save_person('Attack','','','{}','92000000-0000-4000-8000-000000000001',6)),0::bigint,'Other user cannot mutate Person');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.delete_trash_item_forever('person','92000000-0000-4000-8000-000000000001',6,
 (select deleted_at from public.people where id='92000000-0000-4000-8000-000000000001'))),1::bigint,'Delete forever works');
select is((select count(*) from public.person_versions where person_id='92000000-0000-4000-8000-000000000001'),0::bigint,'Permanent deletion removes history');
reset role;
select ok(not has_function_privilege('anon','public.save_person(text,text,text,uuid[],uuid,integer)','execute'),'Anonymous mutation denied');
select * from finish();
rollback;
