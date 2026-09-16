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
  'home_workspace',
  array['date', 'text', 'integer'],
  'The shared Home workspace exists'
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
  '10000000-0000-0000-0000-000000000007',
  'authenticated',
  'authenticated',
  'home-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Home Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

update public.profiles
set display_name = 'MemoTrail Home'
where user_id = '10000000-0000-0000-0000-000000000001';

-- The development seed uses this owner, so clear its mutable archive inside
-- the transaction before installing deterministic Home fixtures.
delete from public.entries
where owner_id = '10000000-0000-0000-0000-000000000001';

delete from public.collections
where owner_id = '10000000-0000-0000-0000-000000000001';

delete from public.tags
where owner_id = '10000000-0000-0000-0000-000000000001';

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  item_kind,
  item_subtype,
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
    '81000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Newest home thought',
    'A recent Inbox thought.',
    'capture',
    'quick_capture',
    'unreviewed',
    '2026-09-03T16:00:00Z',
    null,
    'exact',
    'America/Los_Angeles',
    '2026-09-03T16:00:00Z',
    null
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'First long drive',
    'A First Time.',
    'event',
    'first_time',
    'organized',
    '2026-09-02T18:00:00Z',
    null,
    'day',
    'America/Los_Angeles',
    '2026-09-02T18:00:00Z',
    null
  ),
  (
    '81000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'Current California chapter',
    'A current stage.',
    'event',
    'life_stage',
    'organized',
    '2025-01-01T08:00:00Z',
    null,
    'year',
    'America/Los_Angeles',
    '2026-09-01T12:00:00Z',
    null
  ),
  (
    '81000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    'Past chapter',
    'An ended stage.',
    'event',
    'life_stage',
    'organized',
    '2020-01-01T08:00:00Z',
    '2021-01-01T08:00:00Z',
    'range',
    'America/Los_Angeles',
    '2026-08-31T12:00:00Z',
    null
  ),
  (
    '81000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000001',
    'Future chapter',
    'A stage that has not started.',
    'event',
    'life_stage',
    'organized',
    '2027-01-01T08:00:00Z',
    null,
    'year',
    'America/Los_Angeles',
    '2026-08-30T12:00:00Z',
    null
  ),
  (
    '81000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-000000000001',
    'Removed thought',
    'This must stay out of Home.',
    'capture',
    'quick_capture',
    'unreviewed',
    '2026-09-03T17:00:00Z',
    null,
    'exact',
    'America/Los_Angeles',
    '2026-09-03T17:00:00Z',
    '2026-09-03T18:00:00Z'
  ),
  (
    '81000000-0000-0000-0000-000000000007',
    '10000000-0000-0000-0000-000000000007',
    'Other owner thought',
    'This must remain private.',
    'capture',
    'quick_capture',
    'unreviewed',
    '2026-09-03T19:00:00Z',
    null,
    'exact',
    'America/Los_Angeles',
    '2026-09-03T19:00:00Z',
    null
  );

insert into public.collections (
  id,
  owner_id,
  name,
  system_key,
  sort_order,
  archived_at
)
values
  (
    '82000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Home Test Learning',
    'home-test-learning',
    10,
    null
  ),
  (
    '82000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Home Test Archived',
    'home-test-archived',
    20,
    '2026-09-01T00:00:00Z'
  );

insert into public.tags (id, owner_id, name)
values (
  '83000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'home-test'
);

insert into public.entry_collections (entry_id, collection_id, owner_id)
values (
  '81000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001'
);

insert into public.entry_tags (entry_id, tag_id, owner_id)
values (
  '81000000-0000-0000-0000-000000000001',
  '83000000-0000-0000-0000-000000000001',
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
  '85000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001/81000000-0000-0000-0000-000000000001/home.jpg',
  'home.jpg',
  'image/jpeg',
  512
);

insert into public.timeline_items (entry_id, track_id, owner_id, timeline_kind, sort_order)
select
  entry_id,
  timeline_tracks.id,
  '10000000-0000-0000-0000-000000000001',
  'stage',
  item_order
from (
  values
    ('81000000-0000-0000-0000-000000000003'::uuid, 1),
    ('81000000-0000-0000-0000-000000000004'::uuid, 2),
    ('81000000-0000-0000-0000-000000000005'::uuid, 3)
) as staged_entries(entry_id, item_order)
cross join lateral (
  select id
  from public.timeline_tracks
  where owner_id = '10000000-0000-0000-0000-000000000001'
    and system_key = 'places'
  limit 1
) as timeline_tracks;

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select is(
  (select count(*)::integer from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1,
  'The Home workspace returns one owner snapshot'
);
select is(
  (select snapshot_date from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  '2026-09-03'::date,
  'The Home snapshot preserves the requested local date'
);
select is(
  (select profile_display_name from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'MemoTrail Home',
  'The Home snapshot returns the owner profile name'
);
select is(
  (select inbox_count from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1::bigint,
  'Inbox count includes only active owner Entries awaiting review'
);
select is(
  (select entry_count from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  5::bigint,
  'Entry count includes every active owner Entry'
);
select is(
  (select first_time_count from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1::bigint,
  'First Time count includes only active owner First Times'
);
select is(
  (select collection_count from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1::bigint,
  'Collection count excludes archived Collections'
);
select is(
  (select current_stage_count from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1::bigint,
  'Current stage count excludes ended and future stages'
);
select is(
  (select jsonb_array_length(recent_entries) from public.home_workspace('2026-09-03', 'America/Los_Angeles', 2)),
  2,
  'Recent Entries obey the requested limit'
);
select is(
  (select recent_entries -> 0 ->> 'title' from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'Newest home thought',
  'Recent Entries use stable newest-capture ordering'
);
select ok(
  not (
    select recent_entries @> '[{"title":"Removed thought"}]'::jsonb
    from public.home_workspace('2026-09-03', 'America/Los_Angeles', 10)
  ),
  'Recent Entries exclude Trash'
);
select ok(
  not (
    select recent_entries @> '[{"title":"Other owner thought"}]'::jsonb
    from public.home_workspace('2026-09-03', 'America/Los_Angeles', 10)
  ),
  'Recent Entries exclude other owners'
);
select is(
  (select recent_entries -> 0 -> 'collection_names' ->> 0 from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'Home Test Learning',
  'Recent Entries include active Collection names'
);
select is(
  (select recent_entries -> 0 -> 'tag_names' ->> 0 from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'home-test',
  'Recent Entries include tag names'
);
select is(
  (select recent_entries -> 0 -> 'attachments' -> 0 ->> 'mime_type' from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'image/jpeg',
  'Recent Entries include active private attachment metadata'
);
select is(
  (select jsonb_array_length(current_stages) from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  1,
  'Current stages contain only active visible ranges'
);
select is(
  (select current_stages -> 0 ->> 'title' from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'Current California chapter',
  'Current stages retain their Entry title'
);
select is(
  (select current_stages -> 0 ->> 'track_name' from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)),
  'Places',
  'Current stages retain their Timeline track'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace(null, 'America/Los_Angeles', 5)$$
  ),
  '22023',
  'A local date is required'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace('2026-09-03', '', 5)$$
  ),
  '22023',
  'An empty timezone is rejected'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace('2026-09-03', 'Not/AZone', 5)$$
  ),
  '22023',
  'An unknown timezone is rejected'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace('2026-09-03', 'America/Los_Angeles', 0)$$
  ),
  '22023',
  'A zero recent limit is rejected'
);
select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace('2026-09-03', 'America/Los_Angeles', 11)$$
  ),
  '22023',
  'An oversized recent limit is rejected'
);
select is(
  (
    select current_stage_count
    from public.home_workspace('2026-09-02', 'Pacific/Kiritimati', 5)
  ),
  1::bigint,
  'Current stage boundaries use the requested local timezone'
);

reset role;

select ok(
  has_function_privilege(
    'authenticated',
    'public.home_workspace(date,text,integer)',
    'execute'
  ),
  'Authenticated users can execute the Home workspace'
);
select ok(
  not has_function_privilege('anon', 'public.home_workspace(date,text,integer)', 'execute'),
  'Anonymous users cannot execute the Home workspace'
);
select ok(
  not has_function_privilege('public', 'public.home_workspace(date,text,integer)', 'execute'),
  'PUBLIC cannot execute the Home workspace'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.home_workspace(date,text,integer)'::regprocedure
  ),
  array['search_path=""'],
  'The Home workspace uses an empty search path'
);
select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.home_workspace(date,text,integer)'::regprocedure
  ),
  false,
  'The Home workspace uses invoker security'
);
select has_index(
  'public',
  'entries',
  'entries_owner_active_created_idx',
  'Recent Home Entries have a supporting partial index'
);

set local role anon;
set local request.jwt.claim.sub = '';
set local request.jwt.claim.role = 'anon';

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.home_workspace('2026-09-03', 'America/Los_Angeles', 5)$$
  ),
  '42501',
  'Anonymous callers cannot execute the Home workspace'
);

select * from finish();

rollback;
