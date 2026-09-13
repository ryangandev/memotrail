begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000095','export-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000096','export-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title,body,date_precision) values
 ('87000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000095','Original','原始记录','age'),
 ('87000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000096','Private other','Must never export','unknown');
update public.entries set occurred_label='17岁',body='Preserved writing',revision=2 where id='87000000-0000-4000-8000-000000000001';
insert into public.entries(id,owner_id,title,body,deleted_at,date_precision)
 select gen_random_uuid(),'10000000-0000-0000-0000-000000000095','Export row '||n,'body '||n,
   case when n=1 then now() else null end,'unknown' from generate_series(1,1005) n;
insert into public.attachments(id,owner_id,entry_id,object_path,original_filename,mime_type,byte_size) values
 ('87000000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000095','87000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000095/photo.jpg','原图.jpg','image/jpeg',3),
 ('87000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000095','87000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000096/private.jpg','missing.jpg','image/jpeg',3);
insert into storage.objects(bucket_id,name,metadata,version) values
 ('entry-media','10000000-0000-0000-0000-000000000095/photo.jpg','{"size":3,"eTag":"frozen-etag"}','snapshot-v1'),
 ('entry-media','10000000-0000-0000-0000-000000000096/private.jpg','{"size":3,"eTag":"private-etag"}','private-version');
insert into public.ai_preferences(owner_id,enabled) values('10000000-0000-0000-0000-000000000095',false);
insert into public.ai_exploration_turns(id,owner_id,entry_id,question,source_revision,source_snapshot,status,answer,model,finished_at) values
 ('87000000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000095','87000000-0000-4000-8000-000000000001','Why? ',2,'{"body":"Preserved writing"}','completed','A separate thought','claude-haiku-4-5-20251001',now());
create function pg_temp.capture(p_id uuid default '87000000-0000-4000-8000-000000000020') returns jsonb language sql as $$select public.create_export_snapshot(p_id)$$;
create function pg_temp.page(p_after bigint default 0,p_limit integer default 100) returns jsonb language sql as $$select public.read_export_snapshot('87000000-0000-4000-8000-000000000020',p_after,p_limit)$$;
select set_eq($$select unnest(public.export_dataset_names()) except select 'media_objects'$$,
 -- Internal photo revision reconciliation has no user content; complete snapshots
 -- and original membership are already exported through entry_versions/attachments.
 $$select tablename from pg_tables where schemaname='public' and tablename not in ('export_snapshots','export_snapshot_rows','entry_photo_changes')$$,
 'Explicit export inventory covers every canonical table and requires updates for new tables');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);
select throws_ok($$select pg_temp.capture(null)$$,'22023','invalid_export_request','A stable request ID is required');
select is(pg_temp.capture()->>'schema_version','1','Snapshot creation succeeds without enabling AI');
select is(pg_temp.capture()->'datasets'->>'entries','1006','Complete source contains more than the default 1000-row REST limit');
select is(pg_temp.capture()->'datasets'->>'entry_versions','1','Earlier Entry writing is included');
select is(pg_temp.capture()->'datasets'->>'ai_exploration_turns','1','AI conversations are canonical export content');
select is(pg_temp.capture()->'datasets'->>'ai_preferences','1','Consent settings are preserved');
select is(pg_temp.capture()->'datasets'->>'media_objects','2','Every attachment has a frozen media manifest record');
select ok(not (pg_temp.capture() ? 'owner_id'),'Snapshot response need not expose internal ownership metadata');
select is((select count(*) from public.export_snapshots),1::bigint,'Repeated creation reuses one immutable snapshot');
select is(jsonb_array_length(pg_temp.page()->'rows'),100,'Ordinary pages are bounded');
select is(pg_temp.page()->>'next_cursor','100','Cursor is stable and explicit');
select is(pg_temp.page()->>'has_more','true','Remaining content is not silently truncated');
select is(pg_temp.page(100)->'rows'->0->>'position','101','Following pages do not repeat records');
select is(jsonb_array_length(pg_temp.page(100000)->'rows'),0,'Reading past end yields an empty page');
select is(pg_temp.page(100000)->>'has_more','false','Terminal page is explicit');
select throws_ok($$select pg_temp.page(-1)$$,'22023','invalid_export_page','Negative cursor rejected');
select throws_ok($$select pg_temp.page(0,251)$$,'22023','invalid_export_page','Oversized page rejected');
select throws_ok($$select pg_temp.page(0,0)$$,'22023','invalid_export_page','Empty page size rejected');
select throws_ok($$insert into public.export_snapshots(id,owner_id) values(gen_random_uuid(),auth.uid())$$,'42501',null,'Clients cannot forge snapshots');
select throws_ok($$update public.export_snapshot_rows set value='{}'$$,'42501',null,'Clients cannot mutate frozen data');
select is((select value->>'body' from public.export_snapshot_rows where dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000001'),'Preserved writing','Full source text is frozen');
select is((select value->>'date_precision' from public.export_snapshot_rows where dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000001'),'age','Uncertain occurrence semantics are retained');
select ok(not (select value ? 'search_document' from public.export_snapshot_rows where dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000001'),'Regenerable full-text index is not canonical export data');
select is((select count(*) from public.export_snapshot_rows where dataset='entries' and value->>'deleted_at' is not null),1::bigint,'Trash remains part of a complete export');
select is((select value->>'storage_version' from public.export_snapshot_rows where dataset='media_objects' and value->>'attachment_id'='87000000-0000-4000-8000-000000000010'),'snapshot-v1','Manifest pins original storage version');
select is((select value->>'etag' from public.export_snapshot_rows where dataset='media_objects' and value->>'attachment_id'='87000000-0000-4000-8000-000000000010'),'frozen-etag','Manifest retains byte-identity metadata');
select is((select value->>'available' from public.export_snapshot_rows where dataset='media_objects' and value->>'attachment_id'='87000000-0000-4000-8000-000000000011'),'false','Forged other-owner media paths are unavailable');
select is((select value->>'storage_version' from public.export_snapshot_rows where dataset='media_objects' and value->>'attachment_id'='87000000-0000-4000-8000-000000000011'),null::text,'Other-owner storage identity never leaks');
update public.entries set body='Changed after capture',revision=3 where id='87000000-0000-4000-8000-000000000001';
select is((select value->>'body' from public.export_snapshot_rows where dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000001'),'Preserved writing','Concurrent later edits cannot change snapshot pages');
select is(pg_temp.capture()->'datasets'->>'entry_versions','1','Creation retries do not silently capture new history');
select lives_ok($$select pg_temp.capture('87000000-0000-4000-8000-000000000021')$$,'A second distinct snapshot may be active');
select throws_ok($$select pg_temp.capture('87000000-0000-4000-8000-000000000022')$$,'P0001','export_limit_reached','Bound concurrent snapshot storage');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',true);
select is(pg_temp.page(),null::jsonb,'Another owner cannot use a snapshot ID');
select is((select count(*) from public.export_snapshot_rows),0::bigint,'Frozen rows enforce ownership directly');
select is((select count(*) from public.export_snapshots),0::bigint,'Snapshot metadata enforces ownership directly');
select throws_ok($$select pg_temp.capture()$$,'22023','export_request_unavailable','Request IDs cannot be taken over');
select is(public.discard_export_snapshot('87000000-0000-4000-8000-000000000020'),false,'Another owner cannot discard a snapshot');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);
select ok(public.discard_export_snapshot('87000000-0000-4000-8000-000000000021'),'Discard clears only the requested temporary snapshot');
select throws_ok($$select pg_temp.capture('87000000-0000-4000-8000-000000000021')$$,'P0001','export_expired','Discarded request cannot resurrect a newer snapshot');
select is((select body from public.entries where id='87000000-0000-4000-8000-000000000001'),'Changed after capture','Discard never edits canonical writing');
select is((select count(*) from public.attachments),2::bigint,'Discard never removes original media records');
insert into public.entries(id,owner_id,title,body,date_precision) values
 ('87000000-0000-4000-8000-000000000099','10000000-0000-0000-0000-000000000095','Large export record',repeat('中文 ',200000),'unknown');
select lives_ok($$select pg_temp.capture('87000000-0000-4000-8000-000000000023')$$,'Large writing is captured without truncation');
select is(jsonb_array_length(public.read_export_snapshot('87000000-0000-4000-8000-000000000023',
 (select position-1 from public.export_snapshot_rows where snapshot_id='87000000-0000-4000-8000-000000000023' and dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000099'),250)->'rows'),1,'Oversized individual record has its own page');
select is(length(public.read_export_snapshot('87000000-0000-4000-8000-000000000023',
 (select position-1 from public.export_snapshot_rows where snapshot_id='87000000-0000-4000-8000-000000000023' and dataset='entries' and value->>'id'='87000000-0000-4000-8000-000000000099'),250)->'rows'->0->'value'->>'body'),600000,'Individual long Unicode body stays complete');
select ok(public.discard_export_snapshot('87000000-0000-4000-8000-000000000023'),'Large snapshot is explicitly removable');
reset role;
delete from public.entries where id='87000000-0000-4000-8000-000000000099';
set local role authenticated;
do $$declare n integer; request_id uuid;begin
 for n in 24..30 loop
   request_id:=('87000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
   perform public.create_export_snapshot(request_id);
   perform public.discard_export_snapshot(request_id);
 end loop;
end;$$;
select throws_ok($$select pg_temp.capture('87000000-0000-4000-8000-000000000031')$$,'P0001','export_rate_limit','Discard cannot bypass the hourly creation limit');
reset role;
select is((select count(*) from public.export_snapshot_rows where snapshot_id='87000000-0000-4000-8000-000000000021'),0::bigint,'Discard physically removes copied private content');
update public.export_snapshots set expires_at=now()-interval '1 second' where id='87000000-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.page()$$,'P0001','export_expired','Expired snapshot cannot be paged');
select is((select count(*) from public.export_snapshot_rows),0::bigint,'Direct expired snapshot reads are also hidden');
select throws_ok($$select public.purge_expired_export_snapshots()$$,'42501',null,'Client cannot invoke global cleanup');
set local role service_role;
select is(public.purge_expired_export_snapshots(),1::bigint,'Scheduled cleanup purges expired private copies');
select is(public.purge_expired_export_snapshots(),0::bigint,'Cleanup is repeatable');
reset role;
select is((select count(*) from public.export_snapshot_rows where snapshot_id='87000000-0000-4000-8000-000000000020'),0::bigint,'Expired snapshot has no retained content');
select is((select datasets from public.export_snapshots where id='87000000-0000-4000-8000-000000000020'),'{}'::jsonb,'Tombstone no longer retains archive counts');
select is((select count(*) from cron.job where jobname='memotrail-expired-export-snapshots' and active and command='select public.purge_expired_export_snapshots()'),1::bigint,'Hourly cleanup is installed exactly once');
set local role authenticated;
select throws_ok($$select pg_temp.capture()$$,'P0001','export_expired','Purged request stays expired, not a new capture');
set local role anon;
select throws_ok($$select pg_temp.capture()$$,'42501',null,'Anonymous capture denied');
select throws_ok($$select pg_temp.page()$$,'42501',null,'Anonymous reading denied');
select throws_ok($$select public.discard_export_snapshot(gen_random_uuid())$$,'42501',null,'Anonymous discard denied');
reset role;
select * from finish();
rollback;
