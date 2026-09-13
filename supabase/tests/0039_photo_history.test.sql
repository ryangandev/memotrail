begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into public.entries(id,owner_id,title,body,inbox_status,date_precision) values
('93900000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Photos','Original words','organized','unknown');
create temporary table fixture as select '93900000-0000-4000-8000-000000000001'::uuid entry_id,
 '93900000-0000-4000-8000-000000000002'::uuid attachment_id,
 '10000000-0000-0000-0000-000000000001/93900000-0000-4000-8000-000000000001/93900000-0000-4000-8000-000000000002.png' path;
grant select on fixture to authenticated;
insert into storage.objects(bucket_id,name) select 'entry-media',path from fixture;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(public.entry_writing_revision(entry_id,1),1,'No photo transition keeps original revision') from fixture;
select is(count(*),1::bigint,'Registers the original') from public.register_entry_attachment(
 (select entry_id from fixture),(select attachment_id from fixture),(select path from fixture),'memory.png','image/png',100,null,null);
select is(revision,2,'Registration creates Entry revision') from public.entries where id=(select entry_id from fixture);
select is(jsonb_array_length(snapshot->'attachments'),0,'Pre-upload membership archived') from public.entry_versions where entry_id=(select entry_id from fixture) and version=1;
select is(snapshot->>'body','Original words','Photo version preserves original words') from public.entry_versions where entry_id=(select entry_id from fixture) and version=1;
select is(count(*),1::bigint,'Lost acknowledgment can replay exact photo identity') from public.register_entry_attachment(
 (select entry_id from fixture),(select attachment_id from fixture),(select path from fixture),'memory.png','image/png',100,null,null);
select is(revision,2,'Retry does not create artificial history') from public.entries where id=(select entry_id from fixture);
select throws_ok($$select public.register_entry_attachment(entry_id,attachment_id,path,'memory.png','image/png',101,null,null) from fixture$$,'23505','attachment_conflict','Replay cannot change original metadata');
select is(public.entry_writing_revision(entry_id,1),2,'Writing-only editor can pass a photo-only transition') from fixture;
select is(count(*),1::bigint,'Photo moves to Trash') from public.trash_entry_attachment((select attachment_id from fixture));
select is(revision,3,'Photo Trash creates Entry revision') from public.entries where id=(select entry_id from fixture);
select is(jsonb_array_length(snapshot->'attachments'),1,'Pre-Trash version retains original membership') from public.entry_versions where entry_id=(select entry_id from fixture) and version=2;
select is(count(*),0::bigint,'Repeated Trash does not mutate again') from public.trash_entry_attachment((select attachment_id from fixture));
select throws_ok($$select public.register_entry_attachment(entry_id,attachment_id,path,'memory.png','image/png',100,null,null) from fixture$$,'23505','attachment_conflict','Registration retry cannot resurrect a trashed original');
select is(count(*),0::bigint,'Wrong Trash generation is rejected') from public.restore_trash_item('attachment',(select attachment_id from fixture),null,'2000-01-01');
select is(count(*),1::bigint,'Exact Trash generation restores original') from public.restore_trash_item('attachment',(select attachment_id from fixture),null,(select deleted_at from public.attachments where id=(select attachment_id from fixture)));
select is(revision,4,'Photo restoration creates Entry revision') from public.entries where id=(select entry_id from fixture);
select is(jsonb_array_length(snapshot->'attachments'),0,'Pre-restoration photo absence is archived') from public.entry_versions where entry_id=(select entry_id from fixture) and version=3;
select is(public.entry_writing_revision(entry_id,1),4,'Contiguous photo-only transitions commute with writing') from fixture;
update public.entries set body='Other device writing' where id=(select entry_id from fixture);
select is(public.entry_writing_revision(entry_id,1),1,'An intervening writing edit cannot be adopted') from fixture;
select lives_ok($$select public.trash_entry_attachment(attachment_id) from fixture$$,'Later photo change still works');
select is(public.entry_writing_revision(entry_id,1),1,'Later photo change cannot bridge a writing gap') from fixture;
select is(public.entry_writing_revision(entry_id,5),6,'Editor opened after writing may reconcile subsequent photo change') from fixture;
select is(public.restore_entry_version(entry_id,2,5),null::integer,'History restore still rejects stale photo revisions') from fixture;
select is(public.restore_entry_version(entry_id,2,6),7,'Full history restoration creates exactly one version') from fixture;
select is(body,'Original words','History restoration restores original writing') from public.entries where id=(select entry_id from fixture);
select is(count(*),1::bigint,'History restoration restores original photo membership') from public.attachments where entry_id=(select entry_id from fixture) and deleted_at is null;
select is(public.entry_writing_revision(entry_id,6),6,'History restoration is not mistaken for a photo-only change') from fixture;
select throws_ok($$select public.register_entry_attachment(entry_id,'93900000-0000-4000-8000-000000000003',replace(path,'000000000002.png','000000000003.png'),'absent.png','image/png',100,null,null) from fixture$$,'22023','attachment_object_missing','Missing Storage object refuses registration');
select is(revision,7,'Failed registration rolls back Entry revision and archive') from public.entries where id=(select entry_id from fixture);
select is(count(*),6::bigint,'Failed registration leaves no phantom version') from public.entry_versions where entry_id=(select entry_id from fixture);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is(count(*),0::bigint,'Known foreign Entry cannot register photo') from public.register_entry_attachment(
 (select entry_id from fixture),(select attachment_id from fixture),(select path from fixture),'memory.png','image/png',100,null,null);
select is(count(*),0::bigint,'Known foreign attachment cannot be trashed') from public.trash_entry_attachment((select attachment_id from fixture));
select is(public.entry_writing_revision(entry_id,1),1,'Foreign caller learns no current revision') from fixture;
reset role;
select ok(not has_function_privilege('authenticated','public.archive_entry_photo_change(uuid,uuid,text)','execute'),'Cannot forge photo-only transitions');
select ok(not has_table_privilege('authenticated','public.entry_photo_changes','insert'),'Cannot forge reconciliation evidence');
select ok(not has_function_privilege('authenticated','public.register_entry_attachment_without_history(uuid,uuid,text,text,text,bigint,integer,integer)','execute'),'Cannot bypass registration history');
select ok(not has_function_privilege('authenticated','public.restore_trash_item_without_photo_history(text,uuid,integer,timestamptz)','execute'),'Cannot bypass restoration history');
select ok(not has_function_privilege('anon','public.entry_writing_revision(uuid,integer)','execute'),'Anonymous reconciliation forbidden');
select * from finish();
rollback;
