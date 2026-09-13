begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000091','media-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000092','media-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title,body,entry_type,date_precision) values
 ('91000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000091','Photos','Original writing','first_time','unknown');
insert into public.attachments(id,owner_id,entry_id,object_path,mime_type,byte_size) values
 ('91000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000091','91000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000091/91000000-0000-4000-8000-000000000001/91000000-0000-4000-8000-000000000002.jpg','image/jpeg',1000);
create temporary table fixture as select '10000000-0000-0000-0000-000000000091'::uuid owner,'91000000-0000-4000-8000-000000000002'::uuid original,
 '10000000-0000-0000-0000-000000000091/91000000-0000-4000-8000-000000000001/derived/91000000-0000-4000-8000-000000000002/v1/'||repeat('a',64)||'/' prefix;
insert into storage.objects(bucket_id,name,metadata,version)
 select 'entry-media',object_path,'{"size":1000,"eTag":"original-etag"}','original-v1' from public.attachments;
insert into storage.objects(bucket_id,name,metadata,version)
 select 'entry-media',prefix||v||'.webp','{"size":100,"eTag":"generated-etag"}','generated-v1' from fixture cross join unnest(array['display','thumbnail']) v;
create function pg_temp.variants() returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_object('variant',v,'object_path',prefix||v||'.webp','byte_size',100,'width',100,'height',100,'sha256',repeat('b',64)))
 from fixture cross join unnest(array['display','thumbnail']) v;
$$;
grant select on fixture to service_role,authenticated;
set local role service_role;
select ok(public.register_media_derivatives(owner,original,'original-v1',repeat('a',64),pg_temp.variants()),'Service registers both generated variants') from fixture;
select ok(public.register_media_derivatives(owner,original,'original-v1',repeat('a',64),pg_temp.variants()),'Identical registration is idempotent') from fixture;
reset role;
select is(count(*),3::bigint,'One original plus two variants, never duplicates') from public.attachments;
set local role service_role;
select is(public.media_source(owner,original)->>'version','original-v1','Source identity includes the Storage version') from fixture;
select is(jsonb_array_length(public.media_source(owner,original)->'variants'),2,'Source exposes reusable derivatives') from fixture;
select ok(not public.register_media_derivatives(owner,original,'stale-version',repeat('a',64),pg_temp.variants()),'Stale original version cannot register previews') from fixture;
select is(public.media_source('10000000-0000-0000-0000-000000000092',original),null::jsonb,'Mismatched owner never receives a source') from fixture;
select throws_ok($$select public.register_media_derivatives(owner,original,'original-v1',repeat('a',64),'[]') from fixture$$,'22023','invalid_media_derivatives','Both variants required atomically');
select throws_ok($$select public.register_media_derivatives(owner,original,'original-v1',repeat('a',64),jsonb_set(pg_temp.variants(),'{0,object_path}','"other-owner/private.webp"')) from fixture$$,'22023','invalid_media_derivative','Foreign Storage paths rejected');
reset role;
select is(count(*),3::bigint,'Invalid registration leaves rows unchanged') from public.attachments;
select is(jsonb_array_length(public.entry_history_snapshot(e)->'attachments'),1,'Generated variants are not canonical historical photos') from public.entries e where e.id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',true);
select is(jsonb_array_length(attachments),1,'Current First Times projects original photos only') from public.first_times_workspace_with_occurrence();
select is(jsonb_array_length(attachments),1,'Legacy First Times also counts originals only') from public.first_times_workspace();
select throws_ok($$select public.media_source(owner,original) from fixture$$,'42501',null,'Clients cannot call the privileged source resolver');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'entry-media',prefix||'spoof.webp' from fixture$$,'42501',null,'Clients cannot upload into the derived namespace');
with changed as (update storage.objects set metadata='{"size":1}' where split_part(name,'/',3)='derived' returning name)
select is(count(*),0::bigint,'Client cannot update derived Storage objects') from changed;
select lives_ok($$select public.trash_entry_attachment(original) from fixture$$,'Original photo moves to Trash');
select is(count(*),1::bigint,'Trash lists one original, not generated artifacts') from public.trash_workspace();
select is(count(*),3::bigint,'Permanent-removal manifest includes the original and its generated family') from public.trash_item_storage_paths('attachment',
 '91000000-0000-4000-8000-000000000002',null,(select deleted_at from public.attachments where id='91000000-0000-4000-8000-000000000002'));
set local role service_role;
select is(public.media_source(owner,original),null::jsonb,'Normal grants stop reading trashed originals') from fixture;
select isnt(public.media_source(owner,original,true),null::jsonb,'Explicit Trash grant may preview an owned original') from fixture;
set local role authenticated;
select lives_ok($$select public.restore_trash_item('attachment',id,null,deleted_at) from public.attachments where id='91000000-0000-4000-8000-000000000002'$$,'Restoring the original keeps its generated family usable');
select is(count(*),0::bigint,'Restored photo disappears from Trash') from public.trash_workspace();
select lives_ok($$update public.entries set body='Edited writing',revision=revision+1 where id='91000000-0000-4000-8000-000000000001'$$,'Writing edits record history independently of previews');
select is(jsonb_array_length(snapshot->'attachments'),1,'Saved historical version retains only original membership') from public.entry_versions where entry_id='91000000-0000-4000-8000-000000000001' order by version desc limit 1;
reset role;
-- These are transaction-only catalog fixtures, with no actual Storage objects.
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where split_part(name,'/',3)='derived';
set local role authenticated;
select is(public.restore_entry_version('91000000-0000-4000-8000-000000000001',1,2),3,'Missing cached preview cannot block restoring writing');
select is(body,'Original writing','History restores original writing') from public.entries where id='91000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',true);
select is(count(*),0::bigint,'Other owner cannot read originals or derivatives') from public.attachments;
select is(count(*),0::bigint,'Other owner cannot resolve a deletion manifest') from public.trash_item_storage_paths('attachment','91000000-0000-4000-8000-000000000002',null,now());
reset role;
select * from finish();
rollback;
