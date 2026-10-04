begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

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
  '10000000-0000-0000-0000-000000000002',
  'authenticated',
  'authenticated',
  'timeline-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Timeline Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.timeline_tracks where system_key = 'places'),
  0,
  'The obsolete Places system track is absent'
);

select is(
  (select count(*)::integer from public.timeline_workspace_with_organization()),
  8,
  'Timeline workspace includes every visible default track when it is empty'
);

select is(
  (
    select count(distinct track_id)::integer
    from public.timeline_workspace_with_organization()
  ),
  8,
  'Every visible Timeline track is represented, including empty tracks'
);

update public.timeline_tracks
set is_hidden = true
where owner_id = '10000000-0000-0000-0000-000000000001'
  and system_key = 'health';

select is(
  (select count(*)::integer from public.timeline_workspace_with_organization()),
  7,
  'Timeline workspace hides tracks marked hidden by default'
);

select is(
  (select count(*)::integer from public.timeline_workspace_with_organization(true)),
  8,
  'Timeline workspace can explicitly include hidden tracks'
);

update public.timeline_tracks
set is_hidden = false
where owner_id = '10000000-0000-0000-0000-000000000001'
  and system_key = 'health';

select lives_ok(
  $$
    select *
    from public.save_timeline_entry_with_occurrence(
      (
        select id
        from public.timeline_tracks
        where owner_id = '10000000-0000-0000-0000-000000000001'
          and system_key = 'other_events'
      ),
      'stage',
      'Lived in Philadelphia',
      'A long chapter on the East Coast.',
      '2012-08-01T19:00:00Z',
      '2025-06-01T19:00:00Z',
      'approximate',
      'Ages 12 to 25',
      'America/New_York',
      null,
      null
    )
  $$,
  'An owner can create a Timeline stage'
);

select is(
  (
    select item_kind || ':' || item_subtype
    from public.entries
    where title = 'Lived in Philadelphia'
  ),
  'entry:period',
  'A stage is stored as a Life Stage Event'
);

select is(
  (
    select timeline_kind
    from public.timeline_items
    where entry_id = (
      select id
      from public.entries
      where title = 'Lived in Philadelphia'
    )
  ),
  'stage',
  'The stage is linked to its Timeline track'
);

select is(
  (
    select occurred_label
    from public.entries
    where title = 'Lived in Philadelphia'
  ),
  'Ages 12 to 25',
  'A Timeline stage preserves an approximate human date label'
);

select is(
  (
    select count(*)::integer
    from public.timeline_workspace_with_organization()
    where title = 'Lived in Philadelphia'
      and track_system_key = 'other_events'
  ),
  1,
  'The created stage appears in the Timeline workspace'
);

select lives_ok(
  $$
    select *
    from public.save_timeline_entry_with_occurrence(
      (
        select id
        from public.timeline_tracks
        where owner_id = '10000000-0000-0000-0000-000000000001'
          and system_key = 'education'
      ),
      'stage',
      'University',
      'An overlapping education period.',
      '2018-08-20T16:00:00Z',
      null,
      'range',
      null,
      'America/New_York',
      null,
      null
    )
  $$,
  'A stage on another track may overlap an existing stage'
);

select is(
  (
    select occurred_end
    from public.entries
    where title = 'University'
  ),
  null::timestamptz,
  'A Timeline stage may remain open-ended'
);

select is(
  (
    select count(*)::integer
    from public.timeline_workspace_with_organization()
    where title in ('Lived in Philadelphia', 'University')
  ),
  2,
  'The Timeline workspace returns overlapping Entries across tracks'
);

select lives_ok(
  $$
    select *
    from public.save_timeline_entry_with_occurrence(
      (
        select id
        from public.timeline_tracks
        where owner_id = '10000000-0000-0000-0000-000000000001'
          and system_key = 'other_events'
      ),
      'event',
      'Moved to California',
      '',
      '2025-06-02T19:00:00Z',
      null,
      'day',
      null,
      'America/Los_Angeles',
      null,
      null
    )
  $$,
  'An owner can create a point-in-time Timeline event'
);

select is(
  (
    select item_kind || ':' || item_subtype
    from public.entries
    where title = 'Moved to California'
  ),
  'entry:moment',
  'A direct Timeline event uses the canonical Event identity'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_timeline_entry_with_occurrence(
        (select id from public.timeline_tracks where system_key = 'other_events'),
        'event',
        'Invalid event',
        '',
        '2025-06-02T19:00:00Z',
        '2025-06-03T19:00:00Z',
        'day',
        null,
        'UTC',
        null,
        null
      )
    $$
  ),
  '22023',
  'A point event cannot contain an end date'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_timeline_entry_with_occurrence(
        (select id from public.timeline_tracks where system_key = 'other_events'),
        'stage',
        'Invalid range',
        '',
        '2025-06-02T19:00:00Z',
        '2024-06-02T19:00:00Z',
        'range',
        null,
        'UTC',
        null,
        null
      )
    $$
  ),
  '22023',
  'A stage end cannot precede its start'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_timeline_entry_with_occurrence(
        (select id from public.timeline_tracks where system_key = 'other_events'),
        'stage',
        ' ',
        '',
        '2025-06-02T19:00:00Z',
        null,
        'year',
        null,
        'UTC',
        null,
        null
      )
    $$
  ),
  '22023',
  'A Timeline Entry requires a title'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_timeline_entry_with_occurrence(
        (select id from public.timeline_tracks where system_key = 'other_events'),
        'stage',
        'Invalid timezone',
        '',
        '2025-06-02T19:00:00Z',
        null,
        'year',
        null,
        'Not/AZone',
        null,
        null
      )
    $$
  ),
  '22023',
  'New Timeline Entries reject an invalid occurrence timezone'
);

select is(
  (
    select count(*)::integer
    from public.save_timeline_entry_with_occurrence(
      (
        select id
        from public.timeline_tracks
        where owner_id = '10000000-0000-0000-0000-000000000001'
          and system_key = 'career'
      ),
      'stage',
      'University and first role',
      'Updated with the next chapter.',
      '2018-08-20T16:00:00Z',
      '2024-01-01T08:00:00Z',
      'range',
      null,
      'America/New_York',
      (select id from public.entries where title = 'University'),
      (select revision from public.entries where title = 'University')
    )
  ),
  1,
  'The current revision can update a Timeline Entry'
);

select is(
  (
    select revision
    from public.entries
    where title = 'University and first role'
  ),
  2,
  'Updating a Timeline Entry advances its revision once'
);

select is(
  (
    select tracks.system_key
    from public.timeline_items as items
    join public.timeline_tracks as tracks on tracks.id = items.track_id
    where items.entry_id = (
      select id
      from public.entries
      where title = 'University and first role'
    )
  ),
  'career',
  'Updating a Timeline Entry can move it between tracks'
);

select is(
  (
    select count(*)::integer
    from public.save_timeline_entry_with_occurrence(
      (select id from public.timeline_tracks where system_key = 'education'),
      'stage',
      'Stale overwrite',
      '',
      '2018-08-20T16:00:00Z',
      null,
      'year',
      null,
      'UTC',
      (select id from public.entries where title = 'University and first role'),
      1
    )
  ),
  0,
  'A stale Timeline update returns no row'
);

select is(
  (
    select tracks.system_key
    from public.timeline_items as items
    join public.timeline_tracks as tracks on tracks.id = items.track_id
    where items.entry_id = (
      select id
      from public.entries
      where title = 'University and first role'
    )
  ),
  'career',
  'A stale update does not partially change the track relationship'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::integer from public.timeline_workspace_with_organization()),
  8,
  'Another owner sees only their own empty default Timeline tracks'
);

select is(
  (
    select count(*)::integer
    from public.save_timeline_entry_with_occurrence(
      (
        select id
        from public.timeline_tracks
        where owner_id = '10000000-0000-0000-0000-000000000001'
          and system_key = 'other_events'
      ),
      'stage',
      'Cross-owner write',
      '',
      '2020-01-01T00:00:00Z',
      null,
      'year',
      null,
      'UTC',
      null,
      null
    )
  ),
  0,
  'Another owner cannot create an Entry on an inaccessible track'
);

select is(
  (
    select count(*)::integer
    from public.trash_timeline_entry(
      (select id from public.entries where title = 'Moved to California'),
      1
    )
  ),
  0,
  'Another owner cannot move a Timeline Entry to Trash'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.trash_timeline_entry(
      (select id from public.entries where title = 'Moved to California'),
      1
    )
  ),
  1,
  'The current owner can move a Timeline Entry to Trash'
);

select is(
  (
    select count(*)::integer
    from public.timeline_workspace_with_organization()
    where title = 'Moved to California'
  ),
  0,
  'Trashed Entries disappear from the Timeline workspace'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.timeline_workspace_with_organization()),
  0,
  'An unauthenticated caller receives no Timeline data'
);

select is(
  (
    select count(*)::integer
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name in (
        'timeline_workspace',
        'save_timeline_entry',
        'trash_timeline_entry'
      )
      and grantee in ('PUBLIC', 'anon')
      and privilege_type = 'EXECUTE'
  ),
  0,
  'Timeline functions are not executable by PUBLIC or anon'
);

select * from finish();
rollback;
