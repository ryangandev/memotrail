begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

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
  'register_entry_attachment',
  array['uuid', 'uuid', 'text', 'text', 'text', 'bigint', 'integer', 'integer'],
  'The universal Entry attachment registration function exists'
);

select has_function(
  'public',
  'trash_entry_attachment',
  array['uuid'],
  'The universal Entry attachment removal function exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer)',
    'execute'
  ),
  'Authenticated users can register Entry attachments'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer)',
    'execute'
  ),
  'Anonymous users cannot register Entry attachments'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.trash_entry_attachment(uuid)',
    'execute'
  ),
  'Authenticated users can recoverably remove Entry attachments'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.trash_entry_attachment(uuid)',
    'execute'
  ),
  'Anonymous users cannot remove Entry attachments'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer)'::regprocedure
  ),
  'Attachment registration uses a hardened definer boundary'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer)'::regprocedure
  ),
  array['search_path=""'],
  'Attachment registration uses an empty search path'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.trash_entry_attachment(uuid)'::regprocedure
  ),
  'Attachment removal uses a hardened definer boundary'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.trash_entry_attachment(uuid)'::regprocedure
  ),
  array['search_path=""'],
  'Attachment removal uses an empty search path'
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
  '10000000-0000-0000-0000-000000000009',
  'authenticated',
  'authenticated',
  'universal-media-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Universal Media Other"}'::jsonb,
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
  '97000000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000002'
);

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  item_kind,
  item_subtype,
  inbox_status,
  occurred_start,
  date_precision,
  occurred_timezone
)
values
  (
    '97000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Universal photo capture',
    '',
    'entry','entry',
    'unreviewed',
    '2026-09-03T16:00:00Z',
    'exact',
    'America/Los_Angeles'
  ),
  (
    '97000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000009',
    'Other owner media',
    '',
    'entry','entry',
    'unreviewed',
    '2026-09-03T16:00:00Z',
    'exact',
    'America/Los_Angeles'
  );

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  '97000000-0000-0000-0000-000000000010',
  'entry-media',
  '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000020.jpg',
  '10000000-0000-0000-0000-000000000001',
  '{"mimetype":"image/jpeg","size":2048}'::jsonb
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  pg_temp.capture_sqlstate(
    $$
      insert into public.attachments (owner_id, entry_id, object_path, mime_type)
      values (
        '10000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000001',
        'bypass/photo.jpg',
        'image/jpeg'
      )
    $$
  ),
  '42501',
  'Authenticated clients cannot bypass validated attachment registration'
);

select is(
  (
    select count(*)::integer
    from public.register_entry_attachment(
      '97000000-0000-0000-0000-000000000001',
      '97000000-0000-0000-0000-000000000020',
      '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000020.jpg',
      'memory.jpg',
      'image/jpeg',
      2048,
      1600,
      1200
    )
  ),
  1,
  'A private image can be registered to a standard Inbox Entry'
);

select is(
  (
    select entry_id
    from public.attachments
    where id = '97000000-0000-0000-0000-000000000020'
  ),
  '97000000-0000-0000-0000-000000000001'::uuid,
  'The attachment belongs to the requested Entry'
);

select is(
  (
    select original_filename
    from public.attachments
    where id = '97000000-0000-0000-0000-000000000020'
  ),
  'memory.jpg',
  'The original filename remains private metadata'
);

select is(
  (
    select count(*)::integer
    from public.register_entry_attachment(
      '97000000-0000-0000-0000-000000000001',
      '97000000-0000-0000-0000-000000000020',
      '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000020.jpg',
      'memory.jpg',
      'image/jpeg',
      2048,
      1600,
      1200
    )
  ),
  1,
  'Repeating universal attachment registration is idempotent'
);

select is(
  (
    select count(*)::integer
    from public.attachments
    where id = '97000000-0000-0000-0000-000000000020'
  ),
  1,
  'Idempotent registration does not duplicate metadata'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000021.jpg',
        'missing.jpg',
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Registration requires an uploaded private Storage object'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        '10000000-0000-0000-0000-000000000001/wrong-entry/97000000-0000-0000-0000-000000000021.jpg',
        'wrong.jpg',
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'The private object path must contain the requested Entry ID'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000021.gif',
        'unsupported.gif',
        'image/gif',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Unsupported image formats are rejected'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000021.jpg',
        'large.jpg',
        'image/jpeg',
        52428801,
        null,
        null
      )
    $$
  ),
  '22023',
  'Attachment metadata enforces the 50 MB size limit'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        '10000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000021.jpg',
        repeat('x', 256),
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Original filenames are length limited'
);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000009', true);
set local role authenticated;

select is(
  (
    select count(*)::integer
    from public.register_entry_attachment(
      '97000000-0000-0000-0000-000000000001',
      '97000000-0000-0000-0000-000000000021',
      '10000000-0000-0000-0000-000000000009/97000000-0000-0000-0000-000000000001/97000000-0000-0000-0000-000000000021.jpg',
      'cross-owner.jpg',
      'image/jpeg',
      100,
      null,
      null
    )
  ),
  0,
  'Another owner cannot register a photo to an inaccessible Entry'
);

select is(
  (
    select count(*)::integer
    from public.trash_entry_attachment(
      '97000000-0000-0000-0000-000000000020'
    )
  ),
  0,
  'Another owner cannot remove an inaccessible photo'
);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (
    select count(*)::integer
    from public.trash_entry_attachment(
      '97000000-0000-0000-0000-000000000020'
    )
  ),
  1,
  'The owner can recoverably remove a universal capture photo'
);

select ok(
  (
    select deleted_at is not null
    from public.attachments
    where id = '97000000-0000-0000-0000-000000000020'
  ),
  'Removing a photo preserves its metadata for Trash restoration'
);

select ok(
  exists (
    select 1
    from storage.objects
    where id = '97000000-0000-0000-0000-000000000010'
  ),
  'Recoverable removal preserves the original private Storage object'
);

select is(
  (
    select count(*)::integer
    from public.trash_entry_attachment(
      '97000000-0000-0000-0000-000000000020'
    )
  ),
  0,
  'Repeating attachment removal reports no active photo'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_entry_attachment(
        '97000000-0000-0000-0000-000000000001',
        '97000000-0000-0000-0000-000000000021',
        'path',
        null,
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '42501',
  'Anonymous callers cannot execute attachment registration'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.trash_entry_attachment('97000000-0000-0000-0000-000000000020')$$
  ),
  '42501',
  'Anonymous callers cannot execute attachment removal'
);

select * from finish();

rollback;
