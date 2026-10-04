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
-- Transaction-only Storage catalog fixture for the photo's object.
insert into storage.objects(bucket_id,name,metadata) select bucket_id,object_path,'{"size":1000}' from public.attachments where id='93000000-0000-4000-8000-000000000002';
create function pg_temp.photo_location() returns jsonb language sql as $$
 select '{"attachmentId":"93000000-0000-4000-8000-000000000002","latitude":39.95,"longitude":-75.166667}'::jsonb;
$$;
create function pg_temp.save(photo_location jsonb, rev integer default null) returns bigint language sql as $$
 select count(*) from public.save_entry(
 '93000000-0000-4000-8000-000000000001',coalesce(rev,(select revision from public.entries where id='93000000-0000-4000-8000-000000000001'),1),
 'Photo memory','My edited words',null,null,null,'UTC',null,'unknown','{}',null,photo_location);
$$;
create function pg_temp.photo_locations() returns bigint language sql as $$
 select count(*) from public.entry_locations
 where entry_id='93000000-0000-4000-8000-000000000001' and relationship='photo';
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
select is(pg_temp.save(pg_temp.photo_location()),1::bigint,'Saving creates a Location from photo GPS');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'The photo GPS Location is created once');
select is((select formatted_address from public.locations where owner_id='10000000-0000-0000-0000-000000000093'),null::text,'No address is inferred from photo GPS');
select is((select coordinate_source from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),'photo_gps','The Location records photo GPS as its coordinate source');
select is((select source_attachment_id from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),'93000000-0000-4000-8000-000000000002'::uuid,'The Location keeps its source photo');
select is(pg_temp.photo_locations(),1::bigint,'The photo Location is linked in the same transaction');
select is((select body from public.entries where id='93000000-0000-4000-8000-000000000001'),'My edited words','The writing is saved with the photo Location');
select is(pg_temp.save(pg_temp.photo_location(),1),0::bigint,'A same-revision retry cannot create another Location');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093' and latitude=39.95 and longitude=-75.166667),1::bigint,'A refused retry leaves one photo GPS Location');
select throws_ok($$select pg_temp.save(pg_temp.photo_location() || '{"latitude":91}')$$,'22023','invalid_photo_location','Out-of-bounds coordinates are refused');
select throws_ok($$select pg_temp.save(pg_temp.photo_location() || '{"longitude":null}')$$,'22023','invalid_photo_location','A partial coordinate pair is refused');
select throws_ok($$select pg_temp.save(pg_temp.photo_location() || '{"attachmentId":"not-a-photo"}')$$,'22023','invalid_photo_location','A malformed photo identity is refused');
select throws_ok($$select pg_temp.save(pg_temp.photo_location() || '{"attachmentId":"93000000-0000-4000-8000-000000000099"}')$$,'40001','photo_source_changed','A missing photo rolls back the writing and the Location together');
select is((select revision from public.entries where id='93000000-0000-4000-8000-000000000001'),2,'A refused photo source does not advance the Entry revision');
select is((select count(*) from public.locations where owner_id='10000000-0000-0000-0000-000000000093'),1::bigint,'A refused photo source creates no Location');
select is(pg_temp.save(null),1::bigint,'Saving without a photo Location still works');
select is(pg_temp.photo_locations(),1::bigint,'Saving without a photo Location keeps the existing one');
select ok(public.lock_photo_place_source('93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002'),'The source helper can lock an owned original');
select lives_ok($$select public.trash_entry_attachment('93000000-0000-4000-8000-000000000002')$$,'The photo can move to Trash');
select throws_ok($$select pg_temp.save(pg_temp.photo_location())$$,'40001','photo_source_changed','A photo in Trash cannot supply a Location');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000094',true);
select ok(not public.lock_photo_place_source('93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002'),'The source helper never exposes another owner''s photo');
select is(pg_temp.save(pg_temp.photo_location()),0::bigint,'Another owner cannot change the Entry or create a Location');
reset role;
select ok(not has_function_privilege('anon','public.save_entry(uuid,integer,text,text,jsonb,timestamptz,timestamptz,text,text,text,text[],jsonb,jsonb)','execute'),'Signed-out visitors cannot save an Entry');
select ok(not has_function_privilege('anon','public.lock_photo_place_source(uuid,uuid)','execute'),'Signed-out visitors cannot lock photos');
select * from finish();
rollback;
