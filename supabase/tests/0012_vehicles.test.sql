begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

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
  '10000000-0000-0000-0000-000000000012',
  'authenticated',
  'authenticated',
  'vehicles-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Vehicles Other User"}'::jsonb,
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
  (select count(*)::integer from public.vehicles_workspace()),
  0,
  'The Vehicles workspace starts empty for the owner'
);

select is(
  pg_temp.capture_sqlstate($$select * from public.vehicles_workspace(0, 0)$$),
  '22023',
  'The Vehicles workspace rejects an invalid page'
);

select lives_ok(
  $$
    select *
    from public.save_vehicle_entry(
      'Bluebird',
      'My first daily driver.',
      '2020-03-12T12:00:00Z',
      null,
      'day',
      'Since March 2020',
      'America/New_York',
      ' Tesla ',
      ' Model 3 ',
      2020,
      ' Deep Blue ',
      array['Electric', 'first-car', 'ELECTRIC'],
      null,
      null
    )
  $$,
  'An owner can create an open-ended Vehicle period'
);

select is(
  (select item_subtype from public.entries where title = 'Bluebird'),
  'vehicle',
  'A Vehicle is stored as a specialized Entity'
);

select is(
  (
    select concat_ws('|', vehicles.make, vehicles.model, vehicles.model_year::text, vehicles.color)
    from public.vehicles
    join public.entries on entries.id = vehicles.entry_id
    where entries.title = 'Bluebird'
  ),
  'Tesla|Model 3|2020|Deep Blue',
  'Vehicle facts are trimmed and preserved'
);

select is(
  (
    select concat_ws('|', date_precision, occurred_label, occurred_timezone)
    from public.vehicles_workspace()
    where title = 'Bluebird'
  ),
  'day|Since March 2020|America/New_York',
  'A Vehicle preserves occurrence precision, label context, and timezone'
);

select is(
  (
    select concat(timeline_tracks.system_key, '|', timeline_items.timeline_kind)
    from public.timeline_items
    join public.timeline_tracks on timeline_tracks.id = timeline_items.track_id
    join public.entries on entries.id = timeline_items.entry_id
    where entries.title = 'Bluebird'
  ),
  'vehicles|stage',
  'A Vehicle appears as a Stage on the Vehicles Timeline track'
);

select is(
  (select tag_names::text from public.vehicles_workspace() where title = 'Bluebird'),
  '{Electric,first-car}',
  'Vehicle tags are normalized and de-duplicated case-insensitively'
);

select is(
  (select count(*)::integer from public.vehicles_workspace()),
  1,
  'The new Vehicle appears in the active workspace'
);

select is(
  (select total_count from public.vehicles_workspace() limit 1),
  1::bigint,
  'The Vehicles workspace reports its total result count'
);

reset role;

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'entry-media',
  '10000000-0000-0000-0000-000000000001/vehicles/bluebird.jpg',
  '10000000-0000-0000-0000-000000000001',
  '{"mimetype":"image/jpeg","size":1234}'::jsonb
);

insert into public.attachments (
  owner_id,
  entry_id,
  bucket_id,
  object_path,
  original_filename,
  mime_type,
  byte_size
)
select
  '10000000-0000-0000-0000-000000000001',
  entries.id,
  'entry-media',
  '10000000-0000-0000-0000-000000000001/vehicles/bluebird.jpg',
  'bluebird.jpg',
  'image/jpeg',
  1234
from public.entries
where entries.title = 'Bluebird';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select jsonb_array_length(attachments)
    from public.vehicles_workspace()
    where title = 'Bluebird'
  ),
  1,
  'The Vehicles workspace includes active private attachment metadata'
);

select lives_ok(
  $$
    select *
    from public.save_vehicle_entry(
      'Roadster',
      'A short summer chapter.',
      '2018-06-01T19:00:00Z',
      '2019-08-31T19:00:00Z',
      'month',
      null,
      'America/Los_Angeles',
      'Mazda',
      'MX-5',
      2018,
      null,
      array['convertible'],
      null,
      null
    )
  $$,
  'An owner can create a completed Vehicle period'
);

select is(
  (select title from public.vehicles_workspace(1, 0)),
  'Bluebird',
  'An active Vehicle period sorts before completed periods'
);

select is(
  (select title from public.vehicles_workspace(1, 1)),
  'Roadster',
  'Vehicles pagination preserves deterministic range ordering'
);

select is(
  (select total_count from public.vehicles_workspace(1, 1)),
  2::bigint,
  'A paginated Vehicle row still reports the complete count'
);

select is(
  (
    select (occurred_end - occurred_start)::text
    from public.vehicles_workspace()
    where title = 'Roadster'
  ),
  '456 days',
  'A completed Vehicle preserves a duration-ready occurrence range'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_vehicle_entry(
        ' ', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC',
        null, null, null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Vehicle requires a title'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_vehicle_entry(
        'Car', '', '2020-01-01T00:00:00Z', null, 'year', null, 'Not/AZone',
        null, null, null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Vehicle rejects an invalid occurrence timezone'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_vehicle_entry(
        'Car', '', '2020-01-02T00:00:00Z', '2020-01-01T00:00:00Z', 'range', null, 'UTC',
        null, null, null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Vehicle end cannot precede its start'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_vehicle_entry(
        'Car', '', '2020-01-01T00:00:00Z', null, 'unknown', null, 'UTC',
        null, null, null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Vehicle requires a duration-ready date precision'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_vehicle_entry(
        'Car', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC',
        'Make', 'Model', 1800, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Vehicle rejects an impossible model year'
);

select is(
  (
    select count(*)::integer
    from public.save_vehicle_entry(
      'Bluebird EV',
      'The electric road-trip years.',
      '2020-03-12T12:00:00Z',
      '2026-08-31T12:00:00Z',
      'month',
      'March 2020 to August 2026',
      'America/New_York',
      'Tesla',
      'Model Y',
      2021,
      'Midnight Silver',
      array['electric', 'favorite'],
      (select id from public.entries where title = 'Bluebird'),
      (select revision from public.entries where title = 'Bluebird')
    )
  ),
  1,
  'The current revision can update a Vehicle atomically'
);

select is(
  (select revision from public.entries where title = 'Bluebird EV'),
  2,
  'Updating a Vehicle advances its Entry revision once'
);

select is(
  (
    select concat_ws('|', make, model, model_year::text, color)
    from public.vehicles_workspace()
    where title = 'Bluebird EV'
  ),
  'Tesla|Model Y|2021|Midnight Silver',
  'The Vehicles workspace returns updated structured facts'
);

select is(
  (
    select tag_names::text
    from public.vehicles_workspace()
    where title = 'Bluebird EV'
  ),
  '{Electric,favorite}',
  'A Vehicle update atomically replaces tags'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items('Midnight Silver')
    where item_kind = 'entity' and item_subtype = 'vehicle'
      and title = 'Bluebird EV'
  ),
  1,
  'Global search finds a Vehicle through its structured facts'
);

select is(
  (
    select count(*)::integer
    from public.save_vehicle_entry(
      'Stale overwrite', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC',
      'Changed', 'Changed', 2022, 'Changed', array[]::text[],
      (select id from public.entries where title = 'Bluebird EV'), 1
    )
  ),
  0,
  'A stale Vehicle update returns no row'
);

select is(
  (
    select vehicles.model
    from public.vehicles
    join public.entries on entries.id = vehicles.entry_id
    where entries.title = 'Bluebird EV'
  ),
  'Model Y',
  'A stale Vehicle update does not partially mutate specialized facts'
);

select set_config(
  'app.test_vehicle_entry_id',
  (select id::text from public.entries where title = 'Bluebird EV'),
  true
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000012', true);

select is(
  (select count(*)::integer from public.vehicles_workspace()),
  0,
  'Another owner sees none of the first owner''s Vehicles'
);

select is(
  (
    select count(*)::integer
    from public.save_vehicle_entry(
      'Cross-owner update', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC',
      null, null, null, null, array[]::text[],
      current_setting('app.test_vehicle_entry_id')::uuid, 2
    )
  ),
  0,
  'Another owner cannot update an inaccessible Vehicle'
);

select is(
  (
    select count(*)::integer
    from public.trash_vehicle_entry(
      current_setting('app.test_vehicle_entry_id')::uuid,
      2
    )
  ),
  0,
  'Another owner cannot move an inaccessible Vehicle to Trash'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.trash_vehicle_entry(
      (select id from public.entries where title = 'Bluebird EV'),
      2
    )
  ),
  1,
  'The current owner can revision-safely move a Vehicle to Trash'
);

select is(
  (select count(*)::integer from public.vehicles_workspace() where title = 'Bluebird EV'),
  0,
  'A trashed Vehicle disappears from the active Vehicles workspace'
);

select is(
  (select wiki_item_subtype from public.trash_workspace() where title = 'Bluebird EV'),
  'vehicle',
  'A trashed Vehicle appears in the shared recoverable Trash archive'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      (select id from public.entries where title = 'Bluebird EV'),
      (select revision from public.entries where title = 'Bluebird EV'),
      (select deleted_at from public.entries where title = 'Bluebird EV')
    )
  ),
  1,
  'The shared Trash contract restores a Vehicle without losing its facts'
);

select is(
  (
    select count(*)::integer
    from public.timeline_workspace_with_organization()
    where title = 'Bluebird EV'
      and track_system_key = 'vehicles'
      and timeline_kind = 'stage'
  ),
  1,
  'A restored Vehicle reappears on the Vehicles Timeline track'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.vehicles_workspace()),
  0,
  'An unauthenticated caller receives no Vehicles data'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.vehicles_workspace(integer,integer)',
    'execute'
  ),
  'Authenticated users can execute the Vehicles workspace'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.vehicles_workspace(integer,integer)',
    'execute'
  ),
  'Anonymous users cannot execute the Vehicles workspace'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_vehicle_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],uuid,integer)',
    'execute'
  ),
  'Authenticated users can execute the Vehicle mutation contract'
);

select ok(
  not has_function_privilege(
    'public',
    'public.save_vehicle_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],uuid,integer)',
    'execute'
  ),
  'PUBLIC cannot execute the Vehicle mutation contract'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.trash_vehicle_entry(uuid,integer)',
    'execute'
  ),
  'Authenticated users can execute the Vehicle Trash contract'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.trash_vehicle_entry(uuid,integer)',
    'execute'
  ),
  'Anonymous users cannot execute the Vehicle Trash contract'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.vehicles_workspace(integer,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Vehicles workspace uses an empty search path'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.save_vehicle_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],uuid,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Vehicle mutation contract uses an empty search path'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_vehicle_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[],uuid,integer)'::regprocedure
  ),
  false,
  'The Vehicle mutation contract remains security invoker'
);

select is(
  (
    select count(*)::integer
    from pg_indexes
    where schemaname = 'public'
      and indexname in ('entries_owner_vehicle_occurrence_idx', 'vehicles_owner_updated_idx')
  ),
  2,
  'Vehicles browsing has both supporting indexes'
);

select * from finish();
rollback;
