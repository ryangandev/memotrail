begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

create or replace function pg_temp.capture_sqlstate(statement text)
returns text
language plpgsql
as $$
begin
  execute statement;
  return null;
exception
  when others then
    return sqlstate;
end;
$$;

select has_function(
  'public',
  'trash_workspace',
  array['integer', 'integer'],
  'The shared Trash workspace exists'
);
select has_function(
  'public',
  'restore_trash_item',
  array['text', 'uuid', 'integer', 'timestamp with time zone'],
  'The shared Trash restore mutation exists'
);
select has_function(
  'public',
  'trash_item_storage_paths',
  array['text', 'uuid', 'integer', 'timestamp with time zone'],
  'The deployed-client Storage path contract is kept'
);
select has_function(
  'public',
  'delete_trash_item_forever',
  array['text', 'uuid', 'integer', 'timestamp with time zone'],
  'The permanent Trash deletion mutation exists'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-0000-0000-000000000006',
  'authenticated',
  'authenticated',
  'trash-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Trash Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

delete from public.entries
where id in (
  '71000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000002',
  '71000000-0000-0000-0000-000000000003',
  '71000000-0000-0000-0000-000000000004'
);

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  item_kind,
  item_subtype,
  inbox_status,
  deleted_at
)
values
  (
    '71000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'First ski trip',
    'A First Time with private photos.',
    'entry','first_time',
    'organized',
    '2026-08-01T12:00:00Z'
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Photo parent',
    'An active First Time with one removed photo.',
    'entry','first_time',
    'organized',
    null
  ),
  (
    '71000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000006',
    'Other owner Trash',
    'Private.',
    'entry','entry',
    'organized',
    '2026-08-04T12:00:00Z'
  ),
  (
    '71000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    null,
    '  A body-only deleted thought.  ',
    'entry','entry',
    'unreviewed',
    '2026-07-30T12:00:00Z'
  );

insert into public.attachments (
  id,
  owner_id,
  entry_id,
  object_path,
  original_filename,
  mime_type,
  byte_size,
  deleted_at
)
values
  (
    '73000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/one.jpg',
    'one.jpg',
    'image/jpeg',
    100,
    null
  ),
  (
    '73000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000002/two.jpg',
    'two.jpg',
    'image/jpeg',
    200,
    '2026-08-02T12:00:00Z'
  ),
  (
    '73000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/three.jpg',
    'three.jpg',
    'image/jpeg',
    300,
    '2026-08-01T13:00:00Z'
  );

-- Restore requires each original it makes visible to exist in Storage.
insert into storage.objects (bucket_id, name)
select bucket_id, object_path
from public.attachments
where id in (
  '73000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000002',
  '73000000-0000-0000-0000-000000000003'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.trash_workspace(50, 0)),
  3,
  'Trash combines owned deleted Entries and standalone removed attachments'
);
select is(
  (select array_agg(item_kind order by deleted_at desc) from public.trash_workspace(50, 0)),
  array['attachment', 'entry', 'entry'],
  'Trash sorts every item by deletion time across kinds'
);
select is(
  (
    select title
    from public.trash_workspace(50, 0)
    where item_id = '71000000-0000-0000-0000-000000000004'
  ),
  'A body-only deleted thought.',
  'Body-only Entries receive a useful Trash title'
);
select is(
  (
    select expires_at
    from public.trash_workspace(50, 0)
    where item_id = '71000000-0000-0000-0000-000000000001'
  ),
  '2026-08-31T12:00:00Z'::timestamptz,
  'Trash reports the thirty-day retention deadline'
);
select is(
  (
    select storage_paths
    from public.trash_workspace(50, 0)
    where item_id = '71000000-0000-0000-0000-000000000001'
  ),
  array[
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/one.jpg',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/three.jpg'
  ],
  'A trashed Entry exposes every private object path needed for permanent deletion'
);
select is(
  (
    select storage_paths[1]
    from public.trash_workspace(50, 0)
    where item_id = '73000000-0000-0000-0000-000000000002'
  ),
  '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000002/two.jpg',
  'A standalone removed attachment exposes its private object path'
);
select is(
  (
    select total_count::integer
    from public.trash_workspace(2, 0)
    limit 1
  ),
  3,
  'Paginated Trash rows preserve the complete result count'
);
select is(
  (select count(*)::integer from public.trash_workspace(2, 1)),
  2,
  'Trash applies bounded pagination'
);
select is(
  pg_temp.capture_sqlstate('select * from public.trash_workspace(0, 0)'),
  '22023',
  'Trash rejects an invalid page size'
);
select is(
  pg_temp.capture_sqlstate('select * from public.trash_workspace(20, -1)'),
  '22023',
  'Trash rejects an invalid page offset'
);
select is(
  (
    select count(*)::integer
    from public.trash_workspace(50, 0)
    where item_id in (
      '71000000-0000-0000-0000-000000000003',
      '72000000-0000-0000-0000-000000000002'
    )
  ),
  0,
  'Trash hides every other owner''s content'
);
select is(
  (
    select count(*)::integer
    from public.trash_workspace(50, 0)
    where item_id = '73000000-0000-0000-0000-000000000003'
  ),
  0,
  'A removed attachment stays nested while its parent Entry is also in Trash'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      99,
      '2026-08-01T12:00:00Z'
    )
  ),
  0,
  'A stale Entry revision cannot restore Trash'
);
select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      1,
      '2026-08-01T12:00:01Z'
    )
  ),
  0,
  'A changed deletion timestamp cannot restore Trash'
);
select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      '71000000-0000-0000-0000-000000000003',
      1,
      '2026-08-04T12:00:00Z'
    )
  ),
  0,
  'An owner cannot restore another owner''s Entry'
);
select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      1,
      '2026-08-01T12:00:00Z'
    )
  ),
  1,
  'An owned Entry restores with matching optimistic state'
);
select ok(
  (
    select deleted_at is null
    from public.entries
    where id = '71000000-0000-0000-0000-000000000001'
  ),
  'Restoring an Entry clears its deletion timestamp'
);
select is(
  (
    select revision
    from public.entries
    where id = '71000000-0000-0000-0000-000000000001'
  ),
  2,
  'Restoring an Entry advances its revision'
);
select ok(
  exists (
    select 1
    from public.entry_versions
    where entry_id = '71000000-0000-0000-0000-000000000001'
      and (snapshot ->> 'deleted_at') is not null
  ),
  'Restoring an Entry preserves the deleted version in history'
);
select is(
  (
    select count(*)::integer
    from public.trash_workspace(50, 0)
    where item_id = '73000000-0000-0000-0000-000000000003'
  ),
  1,
  'A separately removed attachment reappears after its parent Entry is restored'
);
select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'attachment',
      '73000000-0000-0000-0000-000000000002',
      null,
      '2026-08-02T12:00:00Z'
    )
  ),
  1,
  'A standalone removed attachment can be restored'
);
select ok(
  (
    select deleted_at is null
    from public.attachments
    where id = '73000000-0000-0000-0000-000000000002'
  ),
  'Restoring an attachment clears its deletion timestamp'
);
reset role;

update public.entries
set deleted_at = '2026-08-05T12:00:00Z'
where id = '71000000-0000-0000-0000-000000000001';

update public.attachments
set deleted_at = '2026-08-06T12:00:00Z'
where id = '73000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.trash_item_storage_paths(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      3,
      '2026-08-05T12:00:00Z'
    )
  ),
  0,
  'Deployed clients remove no Entry photos before the Entry is deleted'
);
select is(
  (
    select count(*)::integer
    from public.trash_item_storage_paths(
      'attachment',
      '73000000-0000-0000-0000-000000000002',
      null,
      '2026-08-06T12:00:00Z'
    )
  ),
  0,
  'Deployed clients remove no photo before its record is deleted'
);
select is(
  (
    select count(*)::integer
    from public.trash_item_storage_paths(
      'entry',
      '71000000-0000-0000-0000-000000000003',
      1,
      '2026-08-04T12:00:00Z'
    )
  ),
  0,
  'An owner cannot retrieve another owner''s private object paths'
);
select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.trash_item_storage_paths(
        'unknown',
        '71000000-0000-0000-0000-000000000001',
        3,
        '2026-08-05T12:00:00Z'
      )
    $$
  ),
  '22023',
  'Storage path lookup rejects an unknown Trash kind'
);
select is(
  (
    select count(*)::integer
    from public.delete_trash_item_forever(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      2,
      '2026-08-05T12:00:00Z'
    )
  ),
  0,
  'A stale revision cannot permanently delete an Entry'
);
select is(
  (
    select count(*)::integer
    from public.delete_trash_item_forever(
      'entry',
      '71000000-0000-0000-0000-000000000001',
      3,
      '2026-08-05T12:00:00Z'
    )
  ),
  1,
  'An owned trashed Entry can be permanently deleted'
);
select ok(
  not exists (
    select 1
    from public.entries
    where id = '71000000-0000-0000-0000-000000000001'
  ),
  'Permanent Entry deletion removes the Entry'
);
select is(
  (
    select count(*)::integer
    from public.attachments
    where entry_id = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'Permanent Entry deletion cascades through attachment metadata'
);
select is(
  (
    select count(*)::integer
    from public.entry_versions
    where entry_id = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'Permanent Entry deletion removes its version history under the deletion policy'
);
select is(
  (
    select count(*)::integer
    from public.delete_trash_item_forever(
      'attachment',
      '73000000-0000-0000-0000-000000000002',
      null,
      '2026-08-06T12:00:00Z'
    )
  ),
  1,
  'A standalone removed attachment can be permanently deleted'
);
select ok(
  not exists (
    select 1
    from public.attachments
    where id = '73000000-0000-0000-0000-000000000002'
  ),
  'Permanent attachment deletion removes its metadata'
);
select is(
  (select array_agg(object_path order by object_path) from public.pending_media_purge_paths()),
  array[
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/one.jpg',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000001/three.jpg',
    '10000000-0000-0000-0000-000000000001/71000000-0000-0000-0000-000000000002/two.jpg'
  ],
  'Permanent deletion records every private object for removal afterwards'
);
reset role;

select ok(
  exists (
    select 1
    from public.entries
    where id = '71000000-0000-0000-0000-000000000003'
  ),
  'Permanent deletion leaves another owner''s Trash untouched'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select ok(
  has_function_privilege('authenticated', 'public.trash_workspace(integer,integer)', 'execute'),
  'Authenticated users can execute the Trash workspace'
);
select ok(
  not has_function_privilege('anon', 'public.trash_workspace(integer,integer)', 'execute'),
  'Anonymous users cannot execute the Trash workspace'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.restore_trash_item(text,uuid,integer,timestamp with time zone)',
    'execute'
  ),
  'Authenticated users can execute Trash restoration'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.restore_trash_item(text,uuid,integer,timestamp with time zone)',
    'execute'
  ),
  'Anonymous users cannot execute Trash restoration'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.trash_workspace(integer,integer)'::regprocedure
  ),
  array['search_path=""'],
  'The Trash workspace uses an empty search path'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.restore_trash_item(text,uuid,integer,timestamp with time zone)'::regprocedure
  ),
  array['search_path=""'],
  'The Trash restore mutation uses an empty search path'
);
select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.restore_trash_item(text,uuid,integer,timestamp with time zone)'::regprocedure
  ),
  'Attachment restoration uses a hardened definer boundary'
);
select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.delete_trash_item_forever(text,uuid,integer,timestamp with time zone)'::regprocedure
  ),
  'Permanent attachment deletion uses a hardened definer boundary'
);
select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.trash_workspace(integer,integer)'::regprocedure
  ),
  'Trash browsing stays behind Row Level Security as a security-invoker function'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select is(
  pg_temp.capture_sqlstate('select * from public.trash_workspace(50, 0)'),
  '42501',
  'Anonymous callers cannot execute the Trash workspace'
);

select * from finish();

rollback;
