begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

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
  '10000000-0000-0000-0000-000000000003',
  'authenticated',
  'authenticated',
  'first-times-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"First Times Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

create temporary table pg_temp.first_times_test_baseline (entry_id uuid primary key);

insert into pg_temp.first_times_test_baseline (entry_id)
select entry_id
from public.first_times_workspace();

grant select on pg_temp.first_times_test_baseline to authenticated;

set local role authenticated;

select is(
  (select count(*)::integer from public.first_times_workspace()),
  (select count(*)::integer from pg_temp.first_times_test_baseline),
  'First Times tests preserve any existing local workspace Entries'
);

select lives_ok(
  $$
    select *
    from public.save_first_time_entry(
      'First time seeing the ocean',
      '',
      null,
      'unknown',
      null,
      null,
      '{}'::text[],
      '{}'::text[],
      null,
      null
    )
  $$,
  'Only a title is required to create a First Time'
);

select is(
  (
    select entry_type
    from public.entries
    where title = 'First time seeing the ocean'
  ),
  'first_time',
  'Direct creation stores the specialized First Time Entry type'
);

select is(
  (
    select inbox_status
    from public.entries
    where title = 'First time seeing the ocean'
  ),
  'organized',
  'Direct First Time creation bypasses the Inbox'
);

select lives_ok(
  $$
    select *
    from public.save_first_time_entry(
      'First time skiing',
      'A clear cold day on the mountain.',
      '2026-07-03T19:00:00Z',
      'day',
      'July 3, 2026',
      'America/Los_Angeles',
      array['Travel', 'travel'],
      array['Snow', 'snow'],
      null,
      null
    )
  $$,
  'A dated First Time can include a reflection, Collections, and tags'
);

select is(
  (
    select occurred_start
    from public.entries
    where title = 'First time skiing'
      and entry_type = 'first_time'
  ),
  '2026-07-03T19:00:00Z'::timestamptz,
  'A First Time preserves its occurrence instant'
);

select is(
  (
    select occurred_timezone
    from public.entries
    where title = 'First time skiing'
      and entry_type = 'first_time'
  ),
  'America/Los_Angeles',
  'A First Time preserves its occurrence timezone'
);

select is(
  (
    select array(
      select lower(collection_name)
      from unnest(collection_names) as collection_name
    )
    from public.first_times_workspace()
    where title = 'First time skiing'
  ),
  array['travel'],
  'Collection names are trimmed and case-insensitively de-duplicated'
);

select is(
  (
    select array(
      select lower(tag_name)
      from unnest(tag_names) as tag_name
    )
    from public.first_times_workspace()
    where title = 'First time skiing'
  ),
  array['snow'],
  'Tag names are trimmed and case-insensitively de-duplicated'
);

select is(
  (
    select jsonb_array_length(attachments)
    from public.first_times_workspace()
    where title = 'First time skiing'
  ),
  0,
  'A First Time without photos returns an empty attachment array'
);

select is(
  (
    select count(*)::integer
    from public.first_times_workspace()
    where entry_id not in (select entry_id from pg_temp.first_times_test_baseline)
  ),
  2,
  'The workspace returns both First Times created by this test'
);

select is(
  (
    select title
    from public.first_times_workspace()
    where entry_id not in (select entry_id from pg_temp.first_times_test_baseline)
    limit 1
  ),
  'First time skiing',
  'Dated First Times sort before unknown dates'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_first_time_entry(
        ' ', '', null, 'unknown', null, null, '{}', '{}', null, null
      )
    $$
  ),
  '22023',
  'A First Time rejects an empty title'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_first_time_entry(
        'Invalid exact date', '', null, 'day', null, null, '{}', '{}', null, null
      )
    $$
  ),
  '22023',
  'Exact date precision requires an occurrence date'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.save_first_time_entry(
        'Invalid timezone',
        '',
        '2026-07-03T19:00:00Z',
        'day',
        null,
        'Not/AZone',
        '{}',
        '{}',
        null,
        null
      )
    $$
  ),
  '22023',
  'A dated First Time rejects an invalid timezone'
);

select lives_ok(
  $$
    select *
    from public.save_first_time_entry(
      'First ski trip',
      'Updated reflection.',
      '2026-07-03T19:00:00Z',
      'day',
      null,
      'America/Los_Angeles',
      array['Milestones'],
      array['Winter'],
      (
        select id
        from public.entries
        where title = 'First time skiing'
          and entry_type = 'first_time'
      ),
      (
        select revision
        from public.entries
        where title = 'First time skiing'
          and entry_type = 'first_time'
      )
    )
  $$,
  'The current revision can update a First Time'
);

select is(
  (
    select revision
    from public.entries
    where title = 'First ski trip'
  ),
  2,
  'Updating a First Time advances its revision once'
);

select is(
  (
    select count(*)::integer
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'First ski trip')
  ),
  1,
  'Updating a First Time preserves its previous Entry version'
);

select is(
  (
    select collection_names
    from public.first_times_workspace()
    where title = 'First ski trip'
  ),
  array['Milestones'],
  'Updating a First Time atomically replaces Collections'
);

select is(
  (
    select count(*)::integer
    from public.save_first_time_entry(
      'Stale overwrite',
      '',
      null,
      'unknown',
      null,
      null,
      '{}',
      '{}',
      (select id from public.entries where title = 'First ski trip'),
      1
    )
  ),
  0,
  'A stale First Time update returns no row'
);

select is(
  (
    select title
    from public.entries
    where title = 'First ski trip'
  ),
  'First ski trip',
  'A stale update leaves the First Time unchanged'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      insert into public.attachments (
        owner_id,
        entry_id,
        object_path,
        mime_type
      )
      values (
        '10000000-0000-0000-0000-000000000001',
        (select id from public.entries where title = 'First ski trip'),
        'bypass/path.jpg',
        'image/jpeg'
      )
    $$
  ),
  '42501',
  'Authenticated clients must use the validated attachment functions instead of writing metadata directly'
);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
select
  '70000000-0000-0000-0000-000000000001',
  'entry-media',
  '10000000-0000-0000-0000-000000000001/' || entries.id::text ||
    '/60000000-0000-0000-0000-000000000001.jpg',
  '10000000-0000-0000-0000-000000000001',
  '{"mimetype":"image/jpeg","size":2048}'::jsonb
from public.entries
where title = 'First ski trip';

select is(
  (
    select count(*)::integer
    from public.register_first_time_attachment(
      (select id from public.entries where title = 'First ski trip'),
      '60000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001/' ||
        (select id::text from public.entries where title = 'First ski trip') ||
        '/60000000-0000-0000-0000-000000000001.jpg',
      'skiing.jpg',
      'image/jpeg',
      2048,
      1600,
      1200
    )
  ),
  1,
  'An uploaded private image can be registered to its First Time'
);

select is(
  (
    select count(*)::integer
    from public.register_first_time_attachment(
      (select id from public.entries where title = 'First ski trip'),
      '60000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001/' ||
        (select id::text from public.entries where title = 'First ski trip') ||
        '/60000000-0000-0000-0000-000000000001.jpg',
      'skiing.jpg',
      'image/jpeg',
      2048,
      1600,
      1200
    )
  ),
  1,
  'Repeating attachment registration is idempotent'
);

select is(
  (
    select count(*)::integer
    from public.attachments
    where id = '60000000-0000-0000-0000-000000000001'
  ),
  1,
  'Idempotent registration does not duplicate attachment metadata'
);

select is(
  (
    select attachments -> 0 ->> 'mimeType'
    from public.first_times_workspace()
    where title = 'First ski trip'
  ),
  'image/jpeg',
  'The workspace returns active private attachment metadata'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_first_time_attachment(
        (select id from public.entries where title = 'First ski trip'),
        '60000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000001/' ||
          (select id::text from public.entries where title = 'First ski trip') ||
          '/60000000-0000-0000-0000-000000000002.jpg',
        'missing.jpg',
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Attachment metadata cannot be registered before its Storage object exists'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_first_time_attachment(
        (select id from public.entries where title = 'First ski trip'),
        '60000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000001/wrong-entry/' ||
          '60000000-0000-0000-0000-000000000002.jpg',
        'wrong.jpg',
        'image/jpeg',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Attachment paths must contain the owning First Time ID'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_first_time_attachment(
        (select id from public.entries where title = 'First ski trip'),
        '60000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000001/' ||
          (select id::text from public.entries where title = 'First ski trip') ||
          '/60000000-0000-0000-0000-000000000002.gif',
        'unsupported.gif',
        'image/gif',
        100,
        null,
        null
      )
    $$
  ),
  '22023',
  'Unsupported image types are rejected by the attachment contract'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select *
      from public.register_first_time_attachment(
        (select id from public.entries where title = 'First ski trip'),
        '60000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000001/' ||
          (select id::text from public.entries where title = 'First ski trip') ||
          '/60000000-0000-0000-0000-000000000002.jpg',
        'too-large.jpg',
        'image/jpeg',
        52428801,
        null,
        null
      )
    $$
  ),
  '22023',
  'Attachment metadata enforces the private bucket size limit'
);

select is(
  (
    select count(*)::integer
    from public.trash_first_time_attachment(
      '60000000-0000-0000-0000-000000000001'
    )
  ),
  1,
  'An owner can recoverably remove a First Time photo'
);

select is(
  (
    select jsonb_array_length(attachments)
    from public.first_times_workspace()
    where title = 'First ski trip'
  ),
  0,
  'A recoverably removed photo disappears from the active workspace'
);

select ok(
  (
    select deleted_at is not null
    from public.attachments
    where id = '60000000-0000-0000-0000-000000000001'
  ),
  'Removing a photo preserves its metadata for future Trash restoration'
);

select ok(
  exists (
    select 1
    from storage.objects
    where id = '70000000-0000-0000-0000-000000000001'
  ),
  'Removing a photo preserves the original private Storage object'
);

create temporary table pg_temp.first_time_test_state (entry_id uuid primary key);

insert into pg_temp.first_time_test_state (entry_id)
select id
from public.entries
where title = 'First ski trip'
  and entry_type = 'first_time';

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.first_times_workspace()),
  0,
  'Another owner cannot see the first owner''s First Times'
);

select is(
  (
    select count(*)::integer
    from public.save_first_time_entry(
      'Cross-owner overwrite',
      '',
      null,
      'unknown',
      null,
      null,
      '{}',
      '{}',
      (select entry_id from pg_temp.first_time_test_state),
      2
    )
  ),
  0,
  'Another owner cannot update an inaccessible First Time'
);

select is(
  (
    select count(*)::integer
    from public.trash_first_time_attachment(
      '60000000-0000-0000-0000-000000000001'
    )
  ),
  0,
  'Another owner cannot remove an inaccessible First Time photo'
);

select is(
  (
    select count(*)::integer
    from public.trash_first_time_entry(
      (select entry_id from pg_temp.first_time_test_state),
      2
    )
  ),
  0,
  'Another owner cannot move an inaccessible First Time to Trash'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.trash_first_time_entry(
      (select entry_id from pg_temp.first_time_test_state),
      2
    )
  ),
  1,
  'The current owner can move a First Time to Trash'
);

select is(
  (
    select count(*)::integer
    from public.first_times_workspace()
    where title = 'First ski trip'
  ),
  0,
  'A trashed First Time disappears from the active workspace'
);

select is(
  (
    select count(*)::integer
    from public.entry_versions
    where entry_id = (select entry_id from pg_temp.first_time_test_state)
  ),
  2,
  'Moving a First Time to Trash preserves another Entry version'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.first_times_workspace()),
  0,
  'An unauthenticated request receives no First Times'
);

select is(
  (
    select count(*)::integer
    from public.save_first_time_entry(
      'Anonymous write', '', null, 'unknown', null, null, '{}', '{}', null, null
    )
  ),
  0,
  'An unauthenticated request cannot create a First Time'
);

select * from finish();

rollback;
