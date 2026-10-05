begin;
create extension if not exists pgtap with schema extensions;
select plan(8);
select is(to_regclass('public.people'), null, 'People no longer exist');
select is(to_regclass('public.entry_people'), null, 'People links no longer exist');
select is(to_regclass('public.person_versions'), null, 'Person history no longer exists');
select is(to_regprocedure('public.save_person(text,text,text,uuid[],uuid,integer)'), null, 'People can no longer be saved');
select is(to_regprocedure('public.people_workspace(integer,integer)'), null, 'People can no longer be listed');
select throws_ok(
  $$insert into public.entries(owner_id,title,item_kind,item_subtype) values('10000000-0000-0000-0000-000000000001','Avery','entity','person')$$,
  '23514', null, 'Person Entities are refused'
);
select ok(not (public.export_dataset_names() && array['people','entry_people','person_versions']), 'Exports no longer list People');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select throws_ok(
  $$select * from public.restore_trash_item(p_item_kind => 'person', p_item_id => '10000000-0000-4000-8000-000000000001', p_expected_revision => 1, p_expected_deleted_at => now())$$,
  '22023', 'invalid_trash_item_kind', 'People can no longer be restored from Trash'
);
select * from finish();
rollback;
