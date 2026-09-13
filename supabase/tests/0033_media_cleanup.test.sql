begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000093','cleanup-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000094','cleanup-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title) values
 ('93000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000093','Photos');
insert into public.attachments(id,owner_id,entry_id,object_path,mime_type,byte_size) values
 ('93000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000093','93000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000093/93000000-0000-4000-8000-000000000001/93000000-0000-4000-8000-000000000002.jpg','image/jpeg',1000);
create temporary table cleanup_fixture as select
 '10000000-0000-0000-0000-000000000093/93000000-0000-4000-8000-000000000001/derived/93000000-0000-4000-8000-000000000002/v1/'||repeat('a',64)||'/display.webp' path;
grant select on cleanup_fixture to authenticated;
insert into storage.objects(bucket_id,name) select 'entry-media',path from cleanup_fixture;
select throws_ok($$insert into storage.objects(bucket_id,name) select 'entry-media',replace(path,'000000000093','000000000094') from cleanup_fixture$$,'23503','media_source_removed','Derived path must match the original owner');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'entry-media',replace(path,'/v1/','/invalid/') from cleanup_fixture$$,'22023','invalid_derived_media_path','Invalid reserved path cannot be written');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
select lives_ok($$select public.trash_entry_attachment('93000000-0000-4000-8000-000000000002')$$,'Original remains recoverable in Trash');
select is(count(*),2::bigint,'Removal manifest includes unregistered Storage artifact and original') from public.trash_item_storage_paths('attachment','93000000-0000-4000-8000-000000000002',null,(select deleted_at from public.attachments where id='93000000-0000-4000-8000-000000000002'));
select throws_ok($$select public.delete_trash_item_forever('attachment','93000000-0000-4000-8000-000000000002',null,(select deleted_at from public.attachments where id='93000000-0000-4000-8000-000000000002'))$$,'55000','media_cleanup_required','Late artifact prevents false permanent-deletion success');
select is(count(*),1::bigint,'Guard preserves original record for retry') from public.attachments where id='93000000-0000-4000-8000-000000000002';
select lives_ok($$update public.entries set deleted_at=now(),revision=revision+1 where id='93000000-0000-4000-8000-000000000001'$$,'Entry can still be trashed');
select is(count(*),2::bigint,'Entry removal includes interrupted derivatives') from public.trash_item_storage_paths('entry','93000000-0000-4000-8000-000000000001',3,(select deleted_at from public.entries where id='93000000-0000-4000-8000-000000000001'));
select throws_ok($$select public.delete_trash_item_forever('entry','93000000-0000-4000-8000-000000000001',3,(select deleted_at from public.entries where id='93000000-0000-4000-8000-000000000001'))$$,'55000','media_cleanup_required','Cascading Entry deletion also waits for actual media cleanup');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000094',true);
select is(count(*),0::bigint,'Other owner cannot resolve paths') from public.trash_item_storage_paths('entry','93000000-0000-4000-8000-000000000001',2,now());
reset role;
-- Catalog-only fixture; real E2E deletion uses the Storage API.
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where name=(select path from cleanup_fixture);
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
select lives_ok($$select public.delete_trash_item_forever('entry','93000000-0000-4000-8000-000000000001',3,(select deleted_at from public.entries where id='93000000-0000-4000-8000-000000000001'))$$,'Retry completes after Storage cleanup');
select is(count(*),0::bigint,'Original and Entry are removed') from public.entries where id='93000000-0000-4000-8000-000000000001';
reset role;
select throws_ok($$insert into storage.objects(bucket_id,name) select 'entry-media',path from cleanup_fixture$$,'23503','media_source_removed','Late service upload cannot resurrect deleted media');
select * from finish();
rollback;
