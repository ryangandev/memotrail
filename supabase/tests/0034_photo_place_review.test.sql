begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000093','photo-place-owner@memotrail.local'),
 ('10000000-0000-0000-0000-000000000094','photo-place-other@memotrail.local');
insert into public.entries(id,owner_id,title,body,date_precision) values
 ('93000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000093','Photo memory','Original writing','unknown');
insert into public.attachments(id,owner_id,entry_id,object_path,mime_type,byte_size) values
 ('93000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000093','93000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000093/93000000-0000-4000-8000-000000000001/93000000-0000-4000-8000-000000000002.jpg','image/jpeg',1000);
-- Transaction-only Storage catalog fixture for history reference validation.
insert into storage.objects(bucket_id,name,metadata) select bucket_id,object_path,'{"size":1000}' from public.attachments where id='93000000-0000-4000-8000-000000000002';
insert into public.locations(id,owner_id,name,latitude,longitude,notes) values
 ('93000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000093','Existing place',10,20,'Keep these facts'),
 ('93000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000094','Foreign place',10,20,'Private');
create function pg_temp.proposal() returns jsonb language sql as $$
 select '{"kind":"new","attachmentId":"93000000-0000-4000-8000-000000000002","name":"  First ski slope  ","latitude":39.95,"longitude":-75.166667}'::jsonb;
$$;
create function pg_temp.review(proposal jsonb, rev integer default null, done boolean default false) returns bigint language sql as $$
 select count(*) from public.review_wiki_item_with_photo_place(
 '93000000-0000-4000-8000-000000000001',coalesce(rev,(select revision from public.entries where id='93000000-0000-4000-8000-000000000001'),1),
 'Photo memory','My edited words','entry','entry',null,'UTC','{}','{}',done,null,null,'unknown',proposal);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
select is(pg_temp.review(pg_temp.proposal()),1::bigint,'Explicit review atomically creates a photo GPS Location');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'New photo GPS Location is created once');
select is((select latitude from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),39.95::numeric,'Confirmed latitude saved');
select is((select longitude from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),(-75.166667)::numeric,'Confirmed longitude saved');
select is((select coordinate_source from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),'photo_gps','Explicit adoption records photo GPS as coordinate provenance');
select is((select source_attachment_id from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),'93000000-0000-4000-8000-000000000002'::uuid,'Explicit adoption retains the source photo identity');
select is((select count(*) from public.entry_places where entry_id='93000000-0000-4000-8000-000000000001'),1::bigint,'Entry link is saved in the same transaction');
select is((select body from public.entries where id='93000000-0000-4000-8000-000000000001'),'My edited words','Writing save succeeds with Location adoption');
select is((select snapshot->>'body' from public.entry_versions where entry_id='93000000-0000-4000-8000-000000000001' and version=1),'Original writing','Prior original writing remains in history');
select is((select jsonb_array_length(snapshot->'places') from public.entry_versions where entry_id='93000000-0000-4000-8000-000000000001' and version=1),0,'Prior history does not invent the later Place link');
select is(pg_temp.review(pg_temp.proposal(),1),0::bigint,'Same-revision retry cannot create another Place');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'Rejected retry leaves one photo GPS Location');
select is(pg_temp.review('{"kind":"existing","attachmentId":"93000000-0000-4000-8000-000000000002","placeId":"93000000-0000-4000-8000-000000000003","revision":1}'),1::bigint,'Existing owned Location can be linked explicitly');
select is((select count(*) from public.entry_places where entry_id='93000000-0000-4000-8000-000000000001'),2::bigint,'Existing relationships are retained');
select is((select notes from public.locations where id='93000000-0000-4000-8000-000000000003'),null::text,'Legacy Location notes are discarded');
select is((select latitude from public.locations where id='93000000-0000-4000-8000-000000000003'),10::numeric,'Existing coordinates stay authoritative');
select ok((select revision > 1 from public.locations where id='93000000-0000-4000-8000-000000000003'),'Link mutation advances Location revision');
select throws_ok($$select pg_temp.review('{"kind":"existing","attachmentId":"93000000-0000-4000-8000-000000000002","placeId":"93000000-0000-4000-8000-000000000003","revision":1}')$$,'40001','photo_place_changed','Stale shared Place rejected');
select throws_ok($$select pg_temp.review('{"kind":"existing","attachmentId":"93000000-0000-4000-8000-000000000002","placeId":"93000000-0000-4000-8000-000000000004","revision":1}')$$,'40001','photo_place_changed','Foreign Place rejected');
select throws_ok($$select pg_temp.review(pg_temp.proposal() || '{"latitude":91}')$$,'22023','invalid_photo_place','Out-of-bounds coordinates rejected');
select throws_ok($$select pg_temp.review(pg_temp.proposal() || '{"longitude":null}')$$,'22023','invalid_photo_place','Partial coordinate pair rejected');
select throws_ok($$select pg_temp.review(pg_temp.proposal() || '{"name":" "}')$$,'22023','invalid_photo_place','The legacy photo payload still requires its compatibility label');
select throws_ok($$select pg_temp.review(pg_temp.proposal() || '{"attachmentId":"93000000-0000-4000-8000-000000000099"}')$$,'40001','photo_source_changed','Missing source rolls back writing and Place together');
select is((select revision from public.entries where id='93000000-0000-4000-8000-000000000001'),3,'Failed source adoption does not advance Entry revision');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'Failed source adoption creates no orphan Location');
select is(pg_temp.review(null),1::bigint,'No proposal preserves ordinary review behavior');
select is((select count(*) from public.entry_places where entry_id='93000000-0000-4000-8000-000000000001'),2::bigint,'No proposal never clears existing Locations');
select is(public.restore_entry_version('93000000-0000-4000-8000-000000000001',1,4),5,'Earlier Entry version restores before Location adoption');
select is((select count(*) from public.entry_places where entry_id='93000000-0000-4000-8000-000000000001'),0::bigint,'Restoring earlier history removes only the later Entry links');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'History restoration retains the Entry-owned snapshot for later restoration');
select is(public.restore_entry_version('93000000-0000-4000-8000-000000000001',4,5),6,'Later Location relationships can be restored again');
select is((select count(*) from public.entry_places where entry_id='93000000-0000-4000-8000-000000000001'),2::bigint,'Restoration recovers both prior Place links');
select ok(public.lock_photo_place_source('93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002'),'Narrow source helper can lock an owned original');
select lives_ok($$select public.trash_entry_attachment('93000000-0000-4000-8000-000000000002')$$,'Photo can enter Trash');
select throws_ok($$select pg_temp.review(pg_temp.proposal())$$,'40001','photo_source_changed','Trashed photo cannot supply an adopted Place');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000094',true);
select ok(not public.lock_photo_place_source('93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002'),'Narrow source helper never exposes a foreign photo');
select is(pg_temp.review(pg_temp.proposal()),0::bigint,'Another owner cannot change the Entry or create an orphan Location');
reset role;
select ok(not has_function_privilege('anon','public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb)','execute'),'Anonymous adoption denied');
select ok(not has_function_privilege('anon','public.lock_photo_place_source(uuid,uuid)','execute'),'Anonymous source locks denied');
select * from finish();
rollback;
