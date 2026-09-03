begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

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
  'home_resurfaced_memory',
  array['date', 'text'],
  'The shared Home resurfacing function exists'
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
values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000008',
    'authenticated',
    'authenticated',
    'resurfacing-archive@memotrail.local',
    '',
    timezone('utc', now()),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Archive Owner"}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now()),
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000009',
    'authenticated',
    'authenticated',
    'resurfacing-empty@memotrail.local',
    '',
    timezone('utc', now()),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Empty Owner"}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now()),
    '',
    '',
    '',
    ''
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
  occurred_timezone,
  created_at,
  deleted_at
)
values
  (
    '87000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Recent anniversary',
    'The most recent matching organized memory.',
    'first_time',
    'organized',
    '2025-09-03T17:00:00Z',
    null,
    'day',
    'America/Los_Angeles',
    '2025-09-04T00:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Older anniversary',
    'A matching but older memory.',
    'standard',
    'organized',
    '2020-09-03T17:00:00Z',
    null,
    'day',
    'America/Los_Angeles',
    '2020-09-04T00:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'Tokyo fourth',
    'This instant is September fourth in its original timezone.',
    'standard',
    'organized',
    '2025-09-04T02:00:00Z',
    null,
    'exact',
    'Asia/Tokyo',
    '2025-09-04T02:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    'Unreviewed anniversary',
    'Inbox material must not resurface.',
    'standard',
    'unreviewed',
    '2025-09-03T18:00:00Z',
    null,
    'day',
    'America/Los_Angeles',
    '2025-09-03T18:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000001',
    'Life stage anniversary',
    'Current stages already have their own Home context.',
    'life_stage',
    'organized',
    '2025-09-03T19:00:00Z',
    null,
    'year',
    'America/Los_Angeles',
    '2025-09-03T19:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-000000000001',
    'Deleted anniversary',
    'Trash must stay out of resurfacing.',
    'standard',
    'organized',
    '2025-09-03T20:00:00Z',
    null,
    'day',
    'America/Los_Angeles',
    '2025-09-03T20:00:00Z',
    '2026-08-01T00:00:00Z'
  ),
  (
    '87000000-0000-0000-0000-000000000007',
    '10000000-0000-0000-0000-000000000008',
    'Archive alpha',
    'The first fallback candidate.',
    'standard',
    'organized',
    '2020-06-01T12:00:00Z',
    null,
    'day',
    'UTC',
    '2020-06-01T12:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000008',
    '10000000-0000-0000-0000-000000000008',
    'Archive beta',
    'The second fallback candidate.',
    'standard',
    'organized',
    '2020-07-01T12:00:00Z',
    null,
    'day',
    'UTC',
    '2020-07-01T12:00:00Z',
    null
  ),
  (
    '87000000-0000-0000-0000-000000000009',
    '10000000-0000-0000-0000-000000000008',
    'Too recent for fallback',
    'Fallback waits until an Entry is at least thirty days old.',
    'standard',
    'organized',
    '2026-08-20T12:00:00Z',
    null,
    'day',
    'UTC',
    '2026-08-20T12:00:00Z',
    null
  );

insert into public.collections (id, owner_id, name, sort_order)
values (
  '88000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Anniversaries',
  90
);

insert into public.tags (id, owner_id, name)
values (
  '89000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'remember-this'
);

insert into public.entry_collections (entry_id, collection_id, owner_id)
values (
  '87000000-0000-0000-0000-000000000001',
  '88000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001'
);

insert into public.entry_tags (entry_id, tag_id, owner_id)
values (
  '87000000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001'
);

insert into public.attachments (
  id,
  owner_id,
  entry_id,
  object_path,
  original_filename,
  mime_type,
  byte_size
)
values (
  '8a000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '87000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001/87000000-0000-0000-0000-000000000001/memory.jpg',
  'memory.jpg',
  'image/jpeg',
  1024
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select is(
  (select count(*)::integer from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  1,
  'Resurfacing returns one owner memory'
);
select is(
  (select resurfacing_kind from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'on_this_day',
  'An anniversary takes priority over archive rotation'
);
select is(
  (select title from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'Recent anniversary',
  'The most recent prior anniversary wins deterministically'
);
select is(
  (select years_ago from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  1,
  'An anniversary includes its elapsed year count'
);
select is(
  (select entry_type from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'first_time',
  'The selected memory preserves its Entry Type'
);
select is(
  (select collection_names ->> 0 from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'Anniversaries',
  'The selected memory includes active Collections'
);
select is(
  (select tag_names ->> 0 from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'remember-this',
  'The selected memory includes tags'
);
select is(
  (select attachments -> 0 ->> 'mime_type' from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'image/jpeg',
  'The selected memory includes active private attachment metadata'
);
select is(
  (select title from public.home_resurfaced_memory('2026-09-04', 'America/Los_Angeles')),
  'Tokyo fourth',
  'Anniversary matching preserves the Entry occurrence timezone'
);
select isnt(
  (select title from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'Unreviewed anniversary',
  'Unreviewed Inbox Entries do not resurface'
);
select isnt(
  (select title from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'Life stage anniversary',
  'Life stages stay in their dedicated Home context'
);
select isnt(
  (select title from public.home_resurfaced_memory('2026-09-03', 'America/Los_Angeles')),
  'Deleted anniversary',
  'Trash does not resurface'
);

set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000008';

select is(
  (select resurfacing_kind from public.home_resurfaced_memory('2026-09-05', 'UTC')),
  'from_your_archive',
  'A stable archive rotation fills days without an anniversary'
);
select is(
  (select count(*)::integer from public.home_resurfaced_memory('2026-09-05', 'UTC')),
  1,
  'Archive rotation returns at most one memory'
);
select is(
  (select title from public.home_resurfaced_memory('2026-09-05', 'UTC')),
  'Archive alpha',
  'Archive rotation selects a deterministic candidate for the date'
);
select isnt(
  (select title from public.home_resurfaced_memory('2026-09-05', 'UTC')),
  'Too recent for fallback',
  'Archive rotation excludes Entries newer than thirty days'
);

set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000009';

select is(
  (select count(*)::integer from public.home_resurfaced_memory('2026-09-05', 'UTC')),
  0,
  'An owner without eligible memories receives an empty result'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_resurfaced_memory(null, 'UTC')$$
  ),
  '22023',
  'A local date is required'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_resurfaced_memory('2026-09-05', '')$$
  ),
  '22023',
  'An empty timezone is rejected'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_resurfaced_memory('2026-09-05', 'Not/AZone')$$
  ),
  '22023',
  'An unknown timezone is rejected'
);

reset role;

select ok(
  has_function_privilege(
    'authenticated',
    'public.home_resurfaced_memory(date,text)',
    'execute'
  ),
  'Authenticated users can execute Home resurfacing'
);
select ok(
  not has_function_privilege('anon', 'public.home_resurfaced_memory(date,text)', 'execute'),
  'Anonymous users cannot execute Home resurfacing'
);
select ok(
  not has_function_privilege('public', 'public.home_resurfaced_memory(date,text)', 'execute'),
  'PUBLIC cannot execute Home resurfacing'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.home_resurfaced_memory(date,text)'::regprocedure
  ),
  array['search_path=""'],
  'Home resurfacing uses an empty search path'
);
select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.home_resurfaced_memory(date,text)'::regprocedure
  ),
  false,
  'Home resurfacing uses invoker security'
);
select has_index(
  'public',
  'entries',
  'entries_owner_resurfacing_idx',
  'Home resurfacing has a supporting partial index'
);

set local role anon;
set local request.jwt.claim.sub = '';
set local request.jwt.claim.role = 'anon';

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_resurfaced_memory('2026-09-05', 'UTC')$$
  ),
  '42501',
  'Anonymous callers cannot execute Home resurfacing'
);

select * from finish();

rollback;
