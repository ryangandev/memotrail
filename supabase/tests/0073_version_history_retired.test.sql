begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000173','history-retired-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000174','history-retired-other@memotrail.local');
insert into public.entries(id,owner_id,title,body,date_precision) values
  ('99730000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000173','Kept words','Original words','unknown');
insert into public.tags(id,owner_id,name) values
  ('99730000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000173','Walks');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('99730000-0000-4000-8000-000000000001','99730000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000173');

-- Nothing keeps or restores earlier versions anymore.
select hasnt_table('public','entry_versions','Stored Entry versions are gone');
select hasnt_table('public','entry_photo_changes','Photo-only revisions are gone');
select hasnt_function('public','entry_history','The history reader is gone');
select hasnt_function('public','entry_history_index','The history index is gone');
select hasnt_function('public','restore_entry_version','Version restore is gone');
select hasnt_function('public','archive_entry_version','The archiving trigger function is gone');
select hasnt_function('public','entry_writing_revision','Writing revision reconciliation is gone');
select hasnt_function('public','archive_entry_photo_change','Photo change archiving is gone');
select hasnt_function('public','register_entry_attachment_without_history','The history-free photo variant is gone');
select hasnt_function('public','restore_trash_item_without_photo_history','The history-free restore variant is gone');
select hasnt_trigger('public','entries','archive_entry_before_change','Entry updates are no longer archived');
select ok(not ('entry_versions' = any(public.export_dataset_names())),'Exports no longer list Entry versions');

-- Updates still advance the revision once, for conflict checks.
update public.entries set body = 'Edited words' where id = '99730000-0000-4000-8000-000000000001';
select is((select revision from public.entries where id = '99730000-0000-4000-8000-000000000001'),2,
  'An Entry update advances the revision once');
update public.entries set body = 'Edited again', revision = 40 where id = '99730000-0000-4000-8000-000000000001';
select is((select revision from public.entries where id = '99730000-0000-4000-8000-000000000001'),3,
  'A client cannot choose the next revision');
select ok(not has_function_privilege('authenticated','public.advance_entry_revision()','execute'),
  'Clients cannot call the revision trigger function');

-- Photo changes leave the Entry's revision alone.
insert into storage.objects(bucket_id,name) values
  ('entry-media','10000000-0000-0000-0000-000000000173/99730000-0000-4000-8000-000000000001/99730000-0000-4000-8000-000000000020.png');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000173',true);
select is((select count(*) from public.register_entry_attachment(
    '99730000-0000-4000-8000-000000000001','99730000-0000-4000-8000-000000000020',
    '10000000-0000-0000-0000-000000000173/99730000-0000-4000-8000-000000000001/99730000-0000-4000-8000-000000000020.png',
    'kept.png','image/png',100,null,null)),1::bigint,'The owner can add a photo');
select is((select revision from public.entries where id = '99730000-0000-4000-8000-000000000001'),3,
  'Adding a photo keeps the Entry revision');
select is((select count(*) from public.trash_entry_attachment('99730000-0000-4000-8000-000000000020')),1::bigint,
  'The owner can move a photo to Trash');
select is((select revision from public.entries where id = '99730000-0000-4000-8000-000000000001'),3,
  'Moving a photo to Trash keeps the Entry revision');
select is((select count(*) from public.restore_trash_item('attachment','99730000-0000-4000-8000-000000000020',null,
    (select deleted_at from public.attachments where id = '99730000-0000-4000-8000-000000000020'))),1::bigint,
  'The owner can restore the photo');
select is((select revision from public.entries where id = '99730000-0000-4000-8000-000000000001'),3,
  'Restoring a photo keeps the Entry revision');

-- The Item page reads the current Entry and its relationships, for its owner only.
select is(public.entry_detail('99730000-0000-4000-8000-000000000001')->>'body','Edited again',
  'The owner reads the current writing');
select is(public.entry_detail('99730000-0000-4000-8000-000000000001')->'tags',
  '[{"id":"99730000-0000-4000-8000-000000000010","name":"Walks"}]'::jsonb,
  'The Item page reads tags by name');
select ok(not (public.entry_detail('99730000-0000-4000-8000-000000000001') ? 'search_document'),
  'The Item page omits the search index');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000174',true);
select is(public.entry_detail('99730000-0000-4000-8000-000000000001'),null,
  'Another owner reads nothing');
reset role;
select set_config('request.jwt.claim.sub','',true);
select ok(not has_function_privilege('anon','public.entry_detail(uuid)','execute'),
  'Signed-out visitors cannot read Entries');

-- A Location is dropped at commit once nothing links to it, and kept when relinked.
insert into public.locations(id,owner_id,formatted_address,bound_entry_id) values
  ('99730000-0000-4000-8000-000000000030','10000000-0000-0000-0000-000000000173','Old corner','99730000-0000-4000-8000-000000000001'),
  ('99730000-0000-4000-8000-000000000031','10000000-0000-0000-0000-000000000173','Kept corner','99730000-0000-4000-8000-000000000001');
insert into public.entry_locations(entry_id,location_id,owner_id,relationship) values
  ('99730000-0000-4000-8000-000000000001','99730000-0000-4000-8000-000000000030','10000000-0000-0000-0000-000000000173','primary'),
  ('99730000-0000-4000-8000-000000000001','99730000-0000-4000-8000-000000000031','10000000-0000-0000-0000-000000000173','primary');
set constraints all immediate;
set constraints all deferred;
delete from public.entry_locations where location_id = '99730000-0000-4000-8000-000000000030';
delete from public.entry_locations where location_id = '99730000-0000-4000-8000-000000000031';
insert into public.entry_locations(entry_id,location_id,owner_id,relationship) values
  ('99730000-0000-4000-8000-000000000001','99730000-0000-4000-8000-000000000031','10000000-0000-0000-0000-000000000173','photo');
select is((select count(*) from public.locations where id = '99730000-0000-4000-8000-000000000030'),1::bigint,
  'An unlinked Location waits for the end of the transaction');
set constraints all immediate;
set constraints all deferred;
select is((select count(*) from public.locations where id = '99730000-0000-4000-8000-000000000030'),0::bigint,
  'An unlinked Location is dropped');
select is((select count(*) from public.locations where id = '99730000-0000-4000-8000-000000000031'),1::bigint,
  'A Location relinked in the same transaction is kept');
select ok(not has_function_privilege('authenticated','public.discard_unlinked_location()','execute'),
  'Clients cannot call the Location cleanup trigger function');

select * from finish();
rollback;
