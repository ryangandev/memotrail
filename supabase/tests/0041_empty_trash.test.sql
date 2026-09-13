begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000095','empty-trash-owner@memotrail.local'),
 ('10000000-0000-0000-0000-000000000096','empty-trash-other@memotrail.local');
insert into public.entries(id,owner_id,title,deleted_at) values
 ('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000095','Trashed original','2026-09-01T12:00:00.123456Z'),
 ('95000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000095','Active original',null),
 ('95000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000096','Foreign original',now());
insert into public.habits(id,owner_id,name,deleted_at) values
 ('95000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000095','Trashed Habit',now());
insert into public.habits(owner_id,name,archived_at) values
 ('10000000-0000-0000-0000-000000000095','Archived but not Trash',now());
insert into public.places(owner_id,name,deleted_at) values
 ('10000000-0000-0000-0000-000000000095','Trashed Place',now());
insert into public.people(owner_id,name,deleted_at) values
 ('10000000-0000-0000-0000-000000000095','Trashed Person',now());
insert into public.collections(owner_id,name,archived_at) values
 ('10000000-0000-0000-0000-000000000095','Trashed Collection',now());
create temporary table captured(snapshot jsonb);
grant all on captured to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);
insert into captured values(public.prepare_empty_trash());
select is(jsonb_array_length(public.prepare_empty_trash()),5,'All standalone Trash kinds are captured, not active or archived-only Habits');
select is(public.prepare_empty_trash()->0->>'item_kind','entry','Entry deletion precedes independent grouping definitions');
select is((public.prepare_empty_trash()->0->>'deleted_at')::timestamptz,'2026-09-01T12:00:00.123456Z'::timestamptz,'Full deletion timestamp is retained');
select ok(not (public.prepare_empty_trash()->0 ? 'title'),'Preparation excludes private titles');
select ok(not (public.prepare_empty_trash()->0 ? 'owner_id'),'Preparation excludes owner identifiers');
select is((select count(*) from public.entries),2::bigint,'Read-only preparation neither deletes nor exposes foreign records');
select is(public.prepare_empty_trash(),(select snapshot from captured),'Unchanged archive has a deterministic manifest');
update public.entries set deleted_at=null where id='95000000-0000-4000-8000-000000000001';
select is(count(*),0::bigint,'An item restored after preparation cannot be deleted by its old confirmation') from public.delete_trash_item_forever(
 'entry','95000000-0000-4000-8000-000000000001',1,'2026-09-01T12:00:00.123456Z');
update public.entries set deleted_at=now() where id='95000000-0000-4000-8000-000000000001';
select is(count(*),0::bigint,'Restore then re-trash also invalidates the old confirmation') from public.delete_trash_item_forever(
 'entry','95000000-0000-4000-8000-000000000001',1,'2026-09-01T12:00:00.123456Z');
insert into public.people(owner_id,name,deleted_at) values(auth.uid(),'Added after preparation',now());
select is(jsonb_array_length((select snapshot from captured)),5,'Prepared targets do not grow when more items enter Trash');
select is(jsonb_array_length(public.prepare_empty_trash()),6,'A new review includes the newly trashed record');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',true);
select is(jsonb_array_length(public.prepare_empty_trash()),1,'Second owner sees only their own exact manifest');
select is(count(*),0::bigint,'Known foreign target remains protected') from public.delete_trash_item_forever(
 'entry','95000000-0000-4000-8000-000000000001',1,'2026-09-01T12:00:00.123456Z');
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.prepare_empty_trash()$$,'42501','authentication_required','A session owner is required');
reset role;
insert into public.people(owner_id,name,deleted_at) select
 '10000000-0000-0000-0000-000000000096','Paged Trash '||i,now() from generate_series(1,105) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',true);
select is(jsonb_array_length(public.prepare_empty_trash()),106,'Manifest covers more than 100 records without relying on loaded pages');
reset role;
insert into public.people(owner_id,name,deleted_at) select
 '10000000-0000-0000-0000-000000000096','Limit Trash '||i,now() from generate_series(1,9895) i;
set local role authenticated;
select throws_ok($$select public.prepare_empty_trash()$$,'54000','trash_snapshot_too_large','Oversized Trash refuses partial Empty Trash preparation');
reset role;
select ok(not has_function_privilege('anon','public.prepare_empty_trash()','execute'),'Anonymous preparation is denied');
select * from finish();
rollback;
