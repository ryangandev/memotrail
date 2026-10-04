begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Delete forever leaves an owner-scoped tombstone, so a delayed capture cannot create
-- the same Entry again, and photo registration says why an Entry cannot take photos.
insert into auth.users(id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000691', 'tombstone-owner@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000692', 'tombstone-other@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000693', 'tombstone-leaving@memotrail.local', '{}');

insert into public.entries(id, owner_id, title, deleted_at) values
  ('69000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000691', 'Deleted by Delete forever', clock_timestamp()),
  ('69000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000691', 'Deleted directly', null),
  ('69000000-0000-4000-8000-000000000003', '10000000-0000-0000-0000-000000000691', 'In Trash', clock_timestamp()),
  ('69000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000691', 'Active', null),
  ('69000000-0000-4000-8000-000000000005', '10000000-0000-0000-0000-000000000693', 'Leaving', clock_timestamp()),
  ('69000000-0000-4000-8000-000000000006', '10000000-0000-0000-0000-000000000693', 'Leaving active', null);
insert into storage.objects(bucket_id, name) values (
  'entry-media',
  '10000000-0000-0000-0000-000000000691/69000000-0000-4000-8000-000000000004/69000000-0000-4000-8000-000000000014.jpg'
);

create function pg_temp.register(p_entry uuid, p_attachment uuid)
returns bigint language sql as $$
  select count(*) from public.register_entry_attachment(
    p_entry, p_attachment,
    '10000000-0000-0000-0000-000000000691/' || p_entry::text || '/' || p_attachment::text || '.jpg',
    'trail.jpg', 'image/jpeg', 100, null, null);
$$;

select columns_are(
  'public', 'entry_tombstones', array['owner_id', 'entry_id', 'deleted_at'],
  'A tombstone holds only its owner, the Entry ID, and when it was deleted'
);
select col_is_pk('public', 'entry_tombstones', array['owner_id', 'entry_id'], 'Tombstones are owner-scoped');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.entry_tombstones'::regclass),
  'Row-level security is enabled on tombstones'
);
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'entry_tombstones'
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'Clients have no privileges on tombstones'
);
select ok(
  not has_function_privilege('authenticated', 'public.record_entry_tombstone()', 'execute')
    and not has_function_privilege('authenticated', 'public.refuse_deleted_forever_entry()', 'execute')
    and not has_function_privilege('anon', 'public.record_entry_tombstone()', 'execute')
    and not has_function_privilege('anon', 'public.refuse_deleted_forever_entry()', 'execute'),
  'Clients cannot call the tombstone trigger functions'
);
select ok(
  not ('entry_tombstones' = any(public.export_dataset_names())),
  'Tombstones are not exported'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000691', true);

select is(
  (with trashed as materialized (
     select id, revision, deleted_at from public.entries
     where id = '69000000-0000-4000-8000-000000000001'
   )
   select count(*) from trashed
   cross join lateral public.delete_trash_item_forever('entry', trashed.id, trashed.revision, trashed.deleted_at)),
  1::bigint,
  'Delete forever removes the Entry'
);
select lives_ok(
  $$delete from public.entries where id = '69000000-0000-4000-8000-000000000002'$$,
  'A direct owner delete removes an Entry too'
);

select throws_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000691', 'Queued capture')$$,
  '23505', 'entry_deleted_forever',
  'A queued capture cannot create an Entry deleted forever again'
);
select throws_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000691', 'Queued capture')$$,
  '23505', 'entry_deleted_forever',
  'Every hard delete leaves a tombstone, not only Delete forever'
);
select throws_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000691', 'Queued capture')
    on conflict (id) do nothing$$,
  '23505', 'entry_deleted_forever',
  'An insert that ignores conflicts is refused the same way'
);
select throws_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000691', 'Lost response')$$,
  '23505', 'duplicate key value violates unique constraint "entries_pkey"',
  'An Entry that still exists keeps its ordinary duplicate key error'
);
select lives_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000007', '10000000-0000-0000-0000-000000000691', 'New capture')$$,
  'A new Entry ID is unaffected'
);

-- Photo registration explains why the owner's Entry cannot take photos.
select throws_ok(
  $$select pg_temp.register('69000000-0000-4000-8000-000000000003', '69000000-0000-4000-8000-000000000013')$$,
  '22023', 'entry_in_trash',
  'A photo cannot attach to an Entry in Trash, and the owner learns why'
);
select throws_ok(
  $$select pg_temp.register('69000000-0000-4000-8000-000000000001', '69000000-0000-4000-8000-000000000011')$$,
  '23505', 'entry_deleted_forever',
  'A photo cannot attach to an Entry deleted forever, and the owner learns why'
);
select is(
  pg_temp.register('69000000-0000-4000-8000-000000000004', '69000000-0000-4000-8000-000000000014'),
  1::bigint,
  'A photo still attaches to an active Entry'
);
select is(
  pg_temp.register('69000000-0000-4000-8000-000000000099', '69000000-0000-4000-8000-000000000019'),
  0::bigint,
  'An unknown Entry still returns nothing'
);

select throws_ok(
  $$select count(*) from public.entry_tombstones$$,
  '42501', null, 'The owner cannot read tombstones'
);
select throws_ok(
  $$insert into public.entry_tombstones(owner_id, entry_id) values
    ('10000000-0000-0000-0000-000000000691', '69000000-0000-4000-8000-000000000004')$$,
  '42501', null, 'The owner cannot write tombstones'
);
select throws_ok(
  $$delete from public.entry_tombstones$$,
  '42501', null, 'The owner cannot remove tombstones to bring an Entry back'
);

-- Another owner neither sees nor is blocked by these tombstones.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000692', true);
select is(
  pg_temp.register('69000000-0000-4000-8000-000000000001', '69000000-0000-4000-8000-000000000021'),
  0::bigint,
  'Another owner does not learn that an Entry was deleted forever'
);
select is(
  pg_temp.register('69000000-0000-4000-8000-000000000003', '69000000-0000-4000-8000-000000000023'),
  0::bigint,
  'Another owner does not learn that an Entry is in Trash'
);
select lives_ok(
  $$insert into public.entries(id, owner_id, body) values
    ('69000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000692', 'Same ID, other owner')$$,
  'Another owner''s tombstone does not block an Entry'
);
select throws_ok(
  $$select count(*) from public.entry_tombstones$$,
  '42501', null, 'Another owner cannot read tombstones'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select count(*) from public.entry_tombstones$$,
  '42501', null, 'Anonymous callers cannot read tombstones'
);
reset role;

select is(
  (select array_agg(entry_id order by entry_id) from public.entry_tombstones
   where owner_id = '10000000-0000-0000-0000-000000000691'),
  array['69000000-0000-4000-8000-000000000001', '69000000-0000-4000-8000-000000000002']::uuid[],
  'Only the owner''s permanently deleted Entries are tombstoned'
);
select is(
  (select count(*) from public.entry_tombstones where owner_id = '10000000-0000-0000-0000-000000000692'),
  0::bigint,
  'The other owner has no tombstones'
);

-- Tombstones never outlive the account, and account deletion records none.
delete from public.entries where id = '69000000-0000-4000-8000-000000000005';
select is(
  (select count(*) from public.entry_tombstones where owner_id = '10000000-0000-0000-0000-000000000693'),
  1::bigint,
  'A leaving owner has a tombstone before account deletion'
);
select lives_ok(
  $$delete from auth.users where id = '10000000-0000-0000-0000-000000000693'$$,
  'Account deletion removes Entries without recording tombstones'
);
select is(
  (select count(*) from public.entry_tombstones where owner_id = '10000000-0000-0000-0000-000000000693'),
  0::bigint,
  'Account deletion removes the account''s tombstones'
);

select * from finish();
rollback;
