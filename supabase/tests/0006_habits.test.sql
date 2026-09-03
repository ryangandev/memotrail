begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

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

select has_table('public', 'habit_versions', 'Habit history exists');
select has_table(
  'public',
  'habit_occurrence_versions',
  'Habit occurrence history exists'
);
select has_column('public', 'habits', 'revision', 'Habits have revisions');
select has_column('public', 'habits', 'deleted_at', 'Habits support recoverable Trash');
select has_column(
  'public',
  'habit_occurrences',
  'revision',
  'Habit occurrences have revisions'
);

select ok(
  public.habit_schedule_is_valid('{"kind":"daily"}'),
  'Daily schedules are valid'
);
select ok(
  public.habit_schedule_is_valid('{"kind":"weekdays","weekdays":[1,3,5]}'),
  'Selected weekday schedules are valid'
);
select ok(
  public.habit_schedule_is_valid('{"kind":"weekly_target","target":3}'),
  'Weekly target schedules are valid'
);
select ok(
  public.habit_schedule_is_valid('{"kind":"interval","every_days":14}'),
  'Custom day intervals are valid'
);
select ok(
  not public.habit_schedule_is_valid('{"kind":"weekdays","weekdays":[1,1]}'),
  'Duplicate weekdays are rejected'
);
select ok(
  not public.habit_schedule_is_valid('{"kind":"weekly_target","target":8}'),
  'Out-of-range weekly targets are rejected'
);
select ok(
  not public.habit_schedule_is_valid('{"kind":"sometimes"}'),
  'Unknown schedule kinds are rejected'
);

select ok(
  public.habit_is_scheduled('{"kind":"daily"}', '2026-01-01', null, '2026-01-05'),
  'Daily habits are scheduled on active dates'
);
select ok(
  public.habit_is_scheduled(
    '{"kind":"weekdays","weekdays":[1,3,5]}',
    '2026-01-01',
    null,
    '2026-01-05'
  ),
  'Weekday habits recognize a selected Monday'
);
select ok(
  not public.habit_is_scheduled(
    '{"kind":"weekdays","weekdays":[1,3,5]}',
    '2026-01-01',
    null,
    '2026-01-06'
  ),
  'Weekday habits reject an unselected Tuesday'
);
select ok(
  public.habit_is_scheduled(
    '{"kind":"interval","every_days":2}',
    '2026-01-01',
    null,
    '2026-01-05'
  ),
  'Interval habits anchor their cadence to the start date'
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
  '10000000-0000-0000-0000-000000000005',
  'authenticated',
  'authenticated',
  'habits-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Habits Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

insert into public.habits (
  id,
  owner_id,
  name,
  tracking_mode,
  measurement_unit,
  target_value,
  schedule,
  starts_on
)
values
  (
    '62000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Daily supplement',
    'check',
    null,
    null,
    '{"kind":"daily"}',
    '2026-01-01'
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Read pages',
    'measure',
    'pages',
    20,
    '{"kind":"weekdays","weekdays":[1,3,5]}',
    '2026-01-01'
  ),
  (
    '62000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'Exercise three times',
    'check',
    null,
    null,
    '{"kind":"weekly_target","target":3}',
    '2026-01-01'
  ),
  (
    '62000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000005',
    'Private other habit',
    'check',
    null,
    null,
    '{"kind":"daily"}',
    '2026-01-01'
  );

insert into public.habit_occurrences (
  id,
  habit_id,
  owner_id,
  local_date,
  status,
  note
)
values
  (
    '63000000-0000-0000-0000-000000000001',
    '62000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '2026-01-01',
    'completed',
    'Started the year well.'
  ),
  (
    '63000000-0000-0000-0000-000000000002',
    '62000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '2026-01-02',
    'skipped',
    'Travel day.'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.habits_workspace('2026-01-05')),
  3,
  'The workspace returns every active owned Habit'
);
select is(
  (
    select local_status
    from public.habits_workspace('2026-01-05')
    where habit_id = '62000000-0000-0000-0000-000000000001'
  ),
  'pending',
  'An unrecorded active daily Habit is pending today'
);
select is(
  (
    select local_status
    from public.habits_workspace('2026-01-05')
    where habit_id = '62000000-0000-0000-0000-000000000002'
  ),
  'pending',
  'A selected weekday is pending'
);
select is(
  (
    select local_status
    from public.habits_workspace('2026-01-05')
    where habit_id = '62000000-0000-0000-0000-000000000003'
  ),
  'pending',
  'A weekly target remains available on an active day'
);
select is(
  (
    select count(*)::integer
    from public.habits_workspace('2026-01-05')
    where habit_id = '62000000-0000-0000-0000-000000000004'
  ),
  0,
  'Another owner Habit is absent from the workspace'
);

select is(
  (
    select count(*)::integer
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001',
      2026,
      '2026-01-05'
    )
  ),
  365,
  'The yearly calendar returns every day in a common year'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001', 2026, '2026-01-05'
    )
    where local_date = '2026-01-01'
  ),
  'completed',
  'The calendar preserves an explicit completion'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001', 2026, '2026-01-05'
    )
    where local_date = '2026-01-02'
  ),
  'skipped',
  'The calendar preserves an intentional skip'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001', 2026, '2026-01-05'
    )
    where local_date = '2026-01-03'
  ),
  'missed',
  'The calendar derives a past unrecorded scheduled day as missed'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001', 2026, '2026-01-05'
    )
    where local_date = '2026-01-05'
  ),
  'pending',
  'The calendar derives the active as-of date as pending'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000001', 2026, '2026-01-05'
    )
    where local_date = '2026-01-06'
  ),
  'upcoming',
  'The calendar keeps future scheduled days separate from misses'
);
select is(
  (
    select status
    from public.habit_year_calendar(
      '62000000-0000-0000-0000-000000000002', 2026, '2026-01-05'
    )
    where local_date = '2026-01-06'
  ),
  'not_scheduled',
  'The calendar identifies an unselected weekday'
);

select is(
  (
    select count(*)::integer
    from public.record_habit_occurrence(
      '62000000-0000-0000-0000-000000000001',
      '2026-01-03',
      'missed',
      null,
      'Forgot it.',
      null,
      null
    )
  ),
  1,
  'A scheduled occurrence can be recorded'
);
select is(
  (
    select count(*)::integer
    from public.record_habit_occurrence(
      '62000000-0000-0000-0000-000000000001',
      '2026-01-03',
      'completed',
      null,
      'Taken later.',
      null,
      1
    )
  ),
  1,
  'An occurrence can be revision-safely corrected'
);
select is(
  (
    select revision
    from public.habit_occurrences
    where habit_id = '62000000-0000-0000-0000-000000000001'
      and local_date = '2026-01-03'
  ),
  2,
  'Correcting an occurrence increments its revision'
);
select is(
  (
    select snapshot ->> 'status'
    from public.habit_occurrence_versions
    where habit_id = '62000000-0000-0000-0000-000000000001'
      and (snapshot ->> 'local_date')::date = '2026-01-03'
  ),
  'missed',
  'Occurrence history preserves the previous status'
);
select is(
  (
    select count(*)::integer
    from public.record_habit_occurrence(
      '62000000-0000-0000-0000-000000000001',
      '2026-01-03',
      'skipped',
      null,
      null,
      null,
      1
    )
  ),
  0,
  'A stale occurrence revision produces a conflict without overwriting'
);

select is(
  (
    select count(*)::integer
    from public.save_habit(
      '62000000-0000-0000-0000-000000000001',
      1,
      ' Daily supplement updated ',
      'check',
      null,
      null,
      '{"kind":"daily"}',
      '2026-01-01',
      null
    )
  ),
  1,
  'A Habit can be revision-safely updated'
);
select is(
  (
    select revision
    from public.habits
    where id = '62000000-0000-0000-0000-000000000001'
  ),
  2,
  'Updating a Habit increments its revision'
);
select is(
  (
    select snapshot ->> 'name'
    from public.habit_versions
    where habit_id = '62000000-0000-0000-0000-000000000001'
  ),
  'Daily supplement',
  'Habit history preserves the previous definition'
);

select is(
  (
    select count(*)::integer
    from public.trash_habit('62000000-0000-0000-0000-000000000003', 1)
  ),
  1,
  'A Habit can move to recoverable Trash'
);
select is(
  (
    select count(*)::integer
    from public.habits_workspace('2026-01-05')
    where habit_id = '62000000-0000-0000-0000-000000000003'
  ),
  0,
  'A trashed Habit disappears from the active workspace'
);
select is(
  (
    select count(*)::integer
    from public.habit_versions
    where habit_id = '62000000-0000-0000-0000-000000000003'
  ),
  1,
  'Moving a Habit to Trash preserves its prior version'
);

select is(
  pg_temp.capture_sqlstate(
    $sql$
      select * from public.record_habit_occurrence(
        '62000000-0000-0000-0000-000000000004',
        '2026-01-05',
        'completed',
        null,
        null,
        null,
        null
      )
    $sql$
  ),
  '22023',
  'Another owner cannot record against an inaccessible Habit'
);

select is(
  (
    select count(*)::integer
    from public.save_habit(
      null,
      null,
      ' Read every day ',
      'measure',
      ' pages ',
      15,
      '{"kind":"daily"}',
      '2026-01-01',
      null
    )
  ),
  1,
  'A new Habit can be created through the contract'
);
select is(
  (
    select count(*)::integer
    from public.habits
    where name = 'Read every day'
      and measurement_unit = 'pages'
      and target_value = 15
      and revision = 1
  ),
  1,
  'Creating a Habit normalizes and stores its measurement definition'
);
select is(
  pg_temp.capture_sqlstate(
    $sql$
      select * from public.save_habit(
        null,
        null,
        'Invalid check Habit',
        'check',
        'times',
        1,
        '{"kind":"daily"}',
        '2026-01-01',
        null
      )
    $sql$
  ),
  '22023',
  'Check Habits reject measurement configuration'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.habits_workspace(date)',
    'execute'
  ),
  'Authenticated users can execute the Habits workspace contract'
);
select ok(
  not has_function_privilege('anon', 'public.habits_workspace(date)', 'execute'),
  'Anonymous users cannot execute the Habits workspace contract through the API'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_habit_occurrence(uuid,date,text,numeric,text,uuid,integer)',
    'execute'
  ),
  'Authenticated users can record Habit occurrences'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_habit_occurrence(uuid,date,text,numeric,text,uuid,integer)',
    'execute'
  ),
  'Anonymous users cannot record Habit occurrences through the API'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.habits_workspace(date)'::regprocedure
  ),
  array['search_path=""'],
  'The Habits workspace function uses an empty search path'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.habit_year_calendar(uuid,integer,date)'::regprocedure
  ),
  array['search_path=""'],
  'The yearly Habit calendar uses an empty search path'
);

select * from finish();

rollback;
