begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

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
  '10000000-0000-0000-0000-000000000004',
  'authenticated',
  'authenticated',
  'collections-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Collections Other User"}'::jsonb,
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
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000003',
  '51000000-0000-0000-0000-000000000004'
);

delete from public.collections
where id in (
  '21000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000002',
  '21000000-0000-0000-0000-000000000003',
  '21000000-0000-0000-0000-000000000004',
  '21000000-0000-0000-0000-000000000005'
);

delete from public.tags
where id = '31000000-0000-0000-0000-000000000001';

insert into public.collections (
  id,
  owner_id,
  name,
  system_key,
  color,
  sort_order,
  archived_at,
  created_at,
  updated_at
)
values
  (
    '21000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Travel',
    'collection-test-travel',
    '#315E4F',
    30,
    null,
    '2026-01-01T00:00:00Z',
    '2026-01-02T00:00:00Z'
  ),
  (
    '21000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Learning',
    'collection-test-learning',
    null,
    10,
    null,
    '2026-01-01T00:00:00Z',
    '2026-01-02T00:00:00Z'
  ),
  (
    '21000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Empty',
    null,
    null,
    10,
    null,
    '2026-01-01T00:00:00Z',
    '2026-01-02T00:00:00Z'
  ),
  (
    '21000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Archived',
    null,
    null,
    0,
    '2026-08-01T00:00:00Z',
    '2026-01-01T00:00:00Z',
    '2026-08-01T00:00:00Z'
  ),
  (
    '21000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000004',
    'Collection Test Other Owner',
    null,
    null,
    10,
    null,
    '2026-01-01T00:00:00Z',
    '2026-01-02T00:00:00Z'
  );

insert into public.tags (id, owner_id, name)
values (
  '31000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'collection-test-tag'
);

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  entry_type,
  inbox_status,
  occurred_start,
  occurred_end,
  date_precision,
  occurred_label,
  occurred_timezone,
  created_at,
  updated_at,
  deleted_at
)
values
  (
    '51000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Ski Trip',
    'A bright day in the snow.',
    'first_time',
    'organized',
    '2026-07-03T19:00:00Z',
    null,
    'day',
    'July 3, 2026',
    'America/Los_Angeles',
    '2026-07-04T00:00:00Z',
    '2026-07-04T01:00:00Z',
    null
  ),
  (
    '51000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    null,
    'A body-only Collection test thought.',
    'standard',
    'unreviewed',
    null,
    null,
    'unknown',
    null,
    null,
    '2026-09-01T00:00:00Z',
    '2026-09-01T01:00:00Z',
    null
  ),
  (
    '51000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'Collection Test Trashed',
    'This Entry should not appear.',
    'standard',
    'organized',
    '2027-01-01T00:00:00Z',
    null,
    'day',
    null,
    'UTC',
    '2027-01-01T00:00:00Z',
    '2027-01-01T00:00:00Z',
    '2027-01-02T00:00:00Z'
  ),
  (
    '51000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000004',
    'Collection Test Other Entry',
    'Private to the other owner.',
    'standard',
    'organized',
    '2026-06-01T00:00:00Z',
    null,
    'day',
    null,
    'UTC',
    '2026-06-01T00:00:00Z',
    '2026-06-01T00:00:00Z',
    null
  );

insert into public.entry_collections (entry_id, collection_id, owner_id)
values
  (
    '51000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '51000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '51000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '51000000-0000-0000-0000-000000000003',
    '21000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '51000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000004'
  );

insert into public.entry_tags (entry_id, tag_id, owner_id)
values (
  '51000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001'
);

insert into public.attachments (
  id,
  owner_id,
  entry_id,
  variant,
  bucket_id,
  object_path,
  original_filename,
  mime_type,
  byte_size,
  pixel_width,
  pixel_height,
  created_at,
  deleted_at
)
values
  (
    '61000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    'original',
    'entry-media',
    'collection-test/active.jpg',
    'active.jpg',
    'image/jpeg',
    1234,
    120,
    80,
    '2026-07-04T00:00:00Z',
    null
  ),
  (
    '61000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    'original',
    'entry-media',
    'collection-test/deleted.jpg',
    'deleted.jpg',
    'image/jpeg',
    5678,
    120,
    80,
    '2026-07-04T00:01:00Z',
    '2026-07-05T00:00:00Z'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.collections_workspace()
    where collection_id in (
      '21000000-0000-0000-0000-000000000001',
      '21000000-0000-0000-0000-000000000002',
      '21000000-0000-0000-0000-000000000003'
    )
  ),
  3,
  'The Collections workspace includes all active owned Collections, including empty ones'
);

select is(
  (
    select count(*)::integer
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000004'
  ),
  0,
  'The Collections workspace excludes archived Collections'
);

select is(
  (
    select array_agg(name)
    from public.collections_workspace()
    where collection_id in (
      '21000000-0000-0000-0000-000000000001',
      '21000000-0000-0000-0000-000000000002',
      '21000000-0000-0000-0000-000000000003'
    )
  ),
  array[
    'Collection Test Empty',
    'Collection Test Learning',
    'Collection Test Travel'
  ],
  'Collections use stable configured and alphabetical ordering'
);

select is(
  (
    select entry_count::integer
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000001'
  ),
  2,
  'Collection counts include only active Entries'
);

select is(
  (
    select unreviewed_count::integer
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000001'
  ),
  1,
  'Collection summaries count Entries still awaiting Inbox review'
);

select is(
  (
    select latest_entry_at
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000001'
  ),
  '2026-09-01T00:00:00Z'::timestamptz,
  'Collection recency falls back to creation time for Entries without an occurrence date'
);

select is(
  (
    select entry_count::integer
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000003'
  ),
  0,
  'An empty Collection returns a zero count'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
  ),
  2,
  'Collection detail returns every active linked Entry'
);

select is(
  (
    select min(total_count)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
  ),
  2,
  'Every Collection detail row reports the full result count'
);

select is(
  (
    select array_agg(entry_id)
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
  ),
  array[
    '51000000-0000-0000-0000-000000000001'::uuid,
    '51000000-0000-0000-0000-000000000002'::uuid
  ],
  'Dated Entries appear before Entries with unknown dates'
);

select ok(
  (
    select title is null
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000002'
  ),
  'Collection detail preserves a body-only Entry title'
);

select is(
  (
    select body
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000002'
  ),
  'A body-only Collection test thought.',
  'Collection detail returns the complete Entry body'
);

select is(
  (
    select entry_type
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000001'
  ),
  'first_time',
  'Collection detail preserves specialized Entry Types'
);

select is(
  (
    select tag_names
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000001'
  ),
  array['collection-test-tag'],
  'Collection detail includes linked tags'
);

select is(
  (
    select collection_names
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000001'
  ),
  array['Collection Test Learning', 'Collection Test Travel'],
  'Collection detail includes every active linked Collection'
);

select is(
  (
    select jsonb_array_length(attachments)
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000001'
  ),
  1,
  'Collection detail includes active private attachment metadata'
);

select is(
  (
    select attachments -> 0 ->> 'objectPath'
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000001'
  ),
  'collection-test/active.jpg',
  'Collection attachment metadata includes the private object path'
);

select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      (
        select attachments
        from public.collection_entries('21000000-0000-0000-0000-000000000001')
        where entry_id = '51000000-0000-0000-0000-000000000001'
      )
    ) as attachment
    where attachment ->> 'id' = '61000000-0000-0000-0000-000000000002'
  ),
  0,
  'Recoverably removed attachment metadata stays out of Collection detail'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
    where entry_id = '51000000-0000-0000-0000-000000000003'
  ),
  0,
  'Trash Entries stay out of Collection detail'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries(
      '21000000-0000-0000-0000-000000000001',
      1,
      0
    )
  ),
  1,
  'Collection detail respects its page limit'
);

select is(
  (
    select entry_id
    from public.collection_entries(
      '21000000-0000-0000-0000-000000000001',
      1,
      1
    )
  ),
  '51000000-0000-0000-0000-000000000002'::uuid,
  'Collection detail respects its page offset'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.collection_entries(
        '21000000-0000-0000-0000-000000000001',
        0,
        0
      )
    $$
  ),
  '22023',
  'Collection detail rejects an invalid page limit'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.collection_entries(
        '21000000-0000-0000-0000-000000000001',
        25,
        -1
      )
    $$
  ),
  '22023',
  'Collection detail rejects an invalid page offset'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000005')
  ),
  0,
  'An owner cannot browse another owner''s Collection'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);

select is(
  (
    select count(*)::integer
    from public.collections_workspace()
    where name like 'Collection Test %'
      and collection_id <> '21000000-0000-0000-0000-000000000005'
  ),
  0,
  'Another owner cannot see the first owner''s Collections'
);

select is(
  (
    select count(*)::integer
    from public.collections_workspace()
    where collection_id = '21000000-0000-0000-0000-000000000005'
  ),
  1,
  'Another owner can see their own Collection summary'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000005')
  ),
  1,
  'Another owner can browse their own Collection Entries'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.collections_workspace()),
  0,
  'An unauthenticated request receives no Collections'
);

select is(
  (
    select count(*)::integer
    from public.collection_entries('21000000-0000-0000-0000-000000000001')
  ),
  0,
  'An unauthenticated request receives no Collection Entries'
);

select ok(
  has_function_privilege('authenticated', 'public.collections_workspace()', 'execute'),
  'Authenticated users can execute the Collections workspace contract'
);

select ok(
  not has_function_privilege('anon', 'public.collections_workspace()', 'execute'),
  'Anonymous users cannot execute the Collections workspace contract through the API'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.collection_entries(uuid,integer,integer)',
    'execute'
  ),
  'Authenticated users can execute Collection detail'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.collection_entries(uuid,integer,integer)',
    'execute'
  ),
  'Anonymous users cannot execute Collection detail through the API'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.collections_workspace()'::regprocedure
  ),
  array['search_path=""'],
  'The Collections workspace function uses an empty search path'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.collection_entries(uuid,integer,integer)'::regprocedure
  ),
  array['search_path=""'],
  'The Collection detail function uses an empty search path'
);

select * from finish();

rollback;
