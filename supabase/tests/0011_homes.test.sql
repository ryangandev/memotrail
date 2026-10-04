begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

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
  '10000000-0000-0000-0000-000000000011',
  'authenticated',
  'authenticated',
  'homes-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Homes Other User"}'::jsonb,
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
  (select count(*)::integer from public.homes_workspace()),
  0,
  'The Homes workspace starts empty for the owner'
);

select is(
  pg_temp.capture_sqlstate($$select * from public.homes_workspace(0, 0)$$),
  '22023',
  'The Homes workspace rejects an invalid page'
);

select lives_ok(
  $$
    select *
    from public.save_home_with_location(
      jsonb_build_object(
        'title', 'California apartment',
        'body', 'A sunny place near the coast.',
        'occurredStart', '2025-06-01T19:00:00Z',
        'occurredEnd', null,
        'datePrecision', 'month',
        'occurredLabel', 'Since June 2025',
        'occurredTimezone', 'America/Los_Angeles',
        'moveInReason', 'Moved for a new chapter.',
        'moveOutReason', null,
        'tagNames', jsonb_build_array('California', 'home', 'HOME'),
        'id', null,
        'revision', null
      ),
      jsonb_build_object(
        'kind', 'provider',
        'provider', 'geoapify',
        'providerLocationId', 'palm-street',
        'formattedAddress', '123 Palm Street, Los Angeles, California, United States',
        'address', '123 Palm Street',
        'city', 'Los Angeles',
        'region', 'California',
        'country', 'United States',
        'latitude', 34.052235,
        'longitude', -118.243683
      )
    )
  $$,
  'An owner can create an open-ended Home with a new Location'
);

select is(
  (
    select item_subtype
    from public.entries
    where title = 'California apartment'
      and item_kind = 'entity' and item_subtype = 'home'
  ),
  'home',
  'A Home is stored as a specialized Home Entity'
);

select is(
  (
    select locations.bound_entry_id
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    join public.locations on locations.id = entry_locations.location_id
    where entries.title = 'California apartment'
  ),
  (select id from public.entries where title = 'California apartment'),
  'The Home owns its Location'
);

select is(
  (
    select concat_ws('|', locations.formatted_address, locations.address, locations.city, locations.region, locations.country)
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    join public.locations on locations.id = entry_locations.location_id
    where entries.title = 'California apartment'
  ),
  '123 Palm Street, Los Angeles, California, United States|123 Palm Street|Los Angeles|California|United States',
  'The Location keeps the chosen address'
);

select is(
  (
    select concat(locations.latitude::text, ',', locations.longitude::text)
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    join public.locations on locations.id = entry_locations.location_id
    where entries.title = 'California apartment'
  ),
  '34.052235,-118.243683',
  'The Location keeps its coordinates'
);

select is(
  (
    select homes.move_in_reason
    from public.homes
    join public.entries on entries.id = homes.entry_id
    where entries.title = 'California apartment'
  ),
  'Moved for a new chapter.',
  'The Home preserves a move-in reason'
);

select is(
  (
    select entry_locations.relationship
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    where entries.title = 'California apartment'
  ),
  'primary',
  'The Home links its Location as its primary Location'
);

select is(
  (
    select concat(timeline_tracks.system_key, '|', timeline_items.timeline_kind)
    from public.timeline_items
    join public.timeline_tracks on timeline_tracks.id = timeline_items.track_id
    join public.entries on entries.id = timeline_items.entry_id
    where entries.title = 'California apartment'
  ),
  'homes|stage',
  'The Home appears as a Stage on the Homes Timeline track'
);

select is(
  (
    select tag_names::text
    from public.homes_workspace()
    where title = 'California apartment'
  ),
  '{California,home}',
  'Home tags are normalized and de-duplicated case-insensitively'
);

select is(
  (select count(*)::integer from public.homes_workspace()),
  1,
  'The new Home appears in the active workspace'
);

select is(
  (select total_count from public.homes_workspace() limit 1),
  1::bigint,
  'The Homes workspace reports its total result count'
);

reset role;

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'entry-media',
  '10000000-0000-0000-0000-000000000001/homes/entry-photo.jpg',
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
  '10000000-0000-0000-0000-000000000001/homes/entry-photo.jpg',
  'entry-photo.jpg',
  'image/jpeg',
  1234
from public.entries
where entries.title = 'California apartment'
  and entries.item_kind = 'entity' and entries.item_subtype = 'home';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select jsonb_array_length(attachments)
    from public.homes_workspace()
    where title = 'California apartment'
  ),
  1,
  'The Homes workspace includes active private attachment metadata'
);

-- The save returns the Location it linked, so the editor can show it before a refresh.
select ok(
  set_config('app.test_typed_home_location_id', (
    select location_id::text
    from public.save_home_with_location(
      jsonb_build_object(
        'title', 'Philadelphia rowhome',
        'body', 'The East Coast chapter.',
        'occurredStart', '2012-08-01T16:00:00Z',
        'occurredEnd', '2025-05-31T16:00:00Z',
        'datePrecision', 'approximate',
        'occurredLabel', 'Ages 12 to 25',
        'occurredTimezone', 'America/New_York',
        'moveInReason', 'Moved with family.',
        'moveOutReason', 'Moved to California.',
        'tagNames', jsonb_build_array('Philadelphia'),
        'id', null,
        'revision', null
      ),
      jsonb_build_object('kind', 'manual', 'city', ' Philadelphia ', 'region', 'Pennsylvania', 'country', 'United States')
    )
  ), true) <> '',
  'An owner can create a completed Home with a typed address'
);

select is(
  (
    select concat_ws('|', locations.formatted_address, locations.city, locations.coordinate_source, locations.latitude::text)
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    join public.locations on locations.id = entry_locations.location_id
    where entries.title = 'Philadelphia rowhome'
      and entry_locations.location_id::text = current_setting('app.test_typed_home_location_id')
  ),
  'Philadelphia, Pennsylvania, United States|Philadelphia|manual',
  'A typed address is saved without coordinates'
);

select is(
  pg_temp.capture_sqlstate($$
    select * from public.save_home_with_location(
      jsonb_build_object('title', 'Blank address', 'body', '', 'datePrecision', 'unknown', 'tagNames', jsonb_build_array()),
      jsonb_build_object('kind', 'manual', 'city', ' ')
    )
  $$),
  '22023',
  'A typed address needs at least one part'
);

select is(
  (select title from public.homes_workspace(1, 0)),
  'California apartment',
  'The active Home sorts before completed Homes'
);

select is(
  (select title from public.homes_workspace(1, 1)),
  'Philadelphia rowhome',
  'Homes pagination preserves deterministic range ordering'
);

select is(
  (select total_count from public.homes_workspace(1, 1)),
  2::bigint,
  'A paginated Homes row still reports the complete count'
);

select is(
  (
    select (occurred_end - occurred_start)::text
    from public.homes_workspace()
    where title = 'Philadelphia rowhome'
  ),
  '4686 days',
  'A completed Home preserves a duration-ready occurrence range'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry_with_occurrence(
        ' ', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home requires a title'
);

savepoint optional_home_location;
select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry_with_occurrence(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null, null, array[]::text[], null, null
      )
    $$
  ),
  null::text,
  'A Home can be saved without a Location'
);
rollback to savepoint optional_home_location;

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry_with_occurrence(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'Not/AZone', null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home rejects an invalid occurrence timezone'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry_with_occurrence(
        'Home', '', '2020-01-02T00:00:00Z', '2020-01-01T00:00:00Z', 'range', null, 'UTC', null, null, array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home end cannot precede its start'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry_with_occurrence(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null, 'Already left', array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A move-out reason requires a move-out date'
);

select is(
  (
    select count(*)::integer
    from public.save_home_with_location(
      jsonb_build_object(
        'title', 'California apartment',
        'body', 'A sunny place near the coast.',
        'occurredStart', '2025-06-01T19:00:00Z',
        'occurredEnd', null,
        'datePrecision', 'month',
        'occurredLabel', 'Since June 2025',
        'occurredTimezone', 'America/Los_Angeles',
        'moveInReason', 'Moved for a new chapter.',
        'moveOutReason', null,
        'tagNames', jsonb_build_array('California', 'home'),
        'id', (select id from public.entries where title = 'California apartment'),
        'revision', (select revision from public.entries where title = 'California apartment')
      ),
      (
        select jsonb_build_object('kind', 'existing', 'id', locations.id, 'revision', locations.revision)
        from public.entry_locations
        join public.entries on entries.id = entry_locations.entry_id
        join public.locations on locations.id = entry_locations.location_id
        where entries.title = 'California apartment'
      )
    )
  ),
  1,
  'Saving a Home with its current Location succeeds'
);

select is(
  (select count(*)::integer from public.locations),
  2,
  'Saving an unchanged Location keeps the same snapshot'
);

select is(
  (
    select count(*)::integer
    from public.save_home_with_location(
      jsonb_build_object(
        'title', 'California home',
        'body', 'A quieter home near work.',
        'occurredStart', '2025-06-01T19:00:00Z',
        'occurredEnd', '2026-08-31T19:00:00Z',
        'datePrecision', 'month',
        'occurredLabel', 'June 2025 to August 2026',
        'occurredTimezone', 'America/Los_Angeles',
        'moveInReason', 'Moved for a new chapter.',
        'moveOutReason', 'Needed more space.',
        'tagNames', jsonb_build_array('California', 'favorite'),
        'id', (select id from public.entries where title = 'California apartment'),
        'revision', (select revision from public.entries where title = 'California apartment')
      ),
      jsonb_build_object(
        'kind', 'provider',
        'provider', 'geoapify',
        'providerLocationId', 'elm-street',
        'formattedAddress', '456 Elm Street, San Francisco, California, United States',
        'address', '456 Elm Street',
        'city', 'San Francisco',
        'region', 'California',
        'country', 'United States',
        'latitude', 37.774929,
        'longitude', -122.419418
      )
    )
  ),
  1,
  'The current revision can update a Home atomically'
);

select is(
  (select revision from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
  3,
  'Each Home update advances its Entry revision once'
);

select is(
  (
    select move_out_reason
    from public.homes_workspace()
    where title = 'California home'
  ),
  'Needed more space.',
  'The Homes workspace returns the updated move details'
);

select is(
  (
    select string_agg(concat_ws('|', locations.address, locations.city), ',')
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    join public.locations on locations.id = entry_locations.location_id
    where entries.title = 'California home'
  ),
  '456 Elm Street|San Francisco',
  'A new Location replaces the Home''s earlier one'
);

select is(
  (
    select tag_names::text
    from public.homes_workspace()
    where title = 'California home'
  ),
  '{California,favorite}',
  'A Home update atomically replaces tags'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items('Elm Street')
    where item_kind = 'entity' and item_subtype = 'home'
      and title = 'California home'
  ),
  1,
  'Global search finds a Home through its structured Location fields'
);

select is(
  (
    select count(*)::integer
    from public.save_home_with_location(
      jsonb_build_object(
        'title', 'Stale overwrite', 'body', '', 'occurredStart', '2025-06-01T19:00:00Z',
        'occurredEnd', null, 'datePrecision', 'month', 'occurredLabel', null,
        'occurredTimezone', 'America/Los_Angeles', 'moveInReason', null, 'moveOutReason', null,
        'tagNames', jsonb_build_array(),
        'id', (select id from public.entries where title = 'California home'), 'revision', 1
      ),
      jsonb_build_object(
        'kind', 'provider', 'provider', 'geoapify', 'providerLocationId', 'stale-street',
        'formattedAddress', 'Stale Street', 'latitude', 1, 'longitude', 1
      )
    )
  ),
  0,
  'A stale Home update returns no row'
);

-- Replaced Locations are dropped when the transaction commits.
set constraints all immediate;
set constraints all deferred;

select is(
  (
    select string_agg(locations.formatted_address, ',' order by locations.formatted_address desc)
    from public.locations
    where locations.owner_id = '10000000-0000-0000-0000-000000000001'
  ),
  'Philadelphia, Pennsylvania, United States,456 Elm Street, San Francisco, California, United States',
  'A stale Home update creates and links no Location'
);

select set_config(
  'app.test_home_entry_id',
  (select id::text from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
  true
);
select set_config(
  'app.test_home_location_id',
  (
    select entry_locations.location_id::text
    from public.entry_locations
    join public.entries on entries.id = entry_locations.entry_id
    where entries.title = 'California home'
  ),
  true
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000011', true);

select is(
  (select count(*)::integer from public.homes_workspace()),
  0,
  'Another owner sees none of the first owner''s Homes'
);

select is(
  pg_temp.capture_sqlstate(format(
    $$
      select * from public.save_home_with_location(
        jsonb_build_object(
          'title', 'Cross-owner place', 'body', '', 'occurredStart', '2020-01-01T00:00:00Z',
          'occurredEnd', null, 'datePrecision', 'year', 'occurredLabel', null,
          'occurredTimezone', 'UTC', 'tagNames', jsonb_build_array(), 'id', null, 'revision', null
        ),
        jsonb_build_object('kind', 'existing', 'id', %L, 'revision', 1)
      )
    $$,
    current_setting('app.test_home_location_id')
  )),
  '40001',
  'Another owner cannot link a Home to an inaccessible Location'
);

select is(
  (
    select count(*)::integer
    from public.save_home_entry_with_occurrence(
      'Cross-owner update', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null, null, array[]::text[],
      current_setting('app.test_home_entry_id')::uuid, 3
    )
  ),
  0,
  'Another owner cannot update an inaccessible Home'
);

select is(
  (
    select count(*)::integer
    from public.trash_home_entry(
      current_setting('app.test_home_entry_id')::uuid,
      3
    )
  ),
  0,
  'Another owner cannot move an inaccessible Home to Trash'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.trash_home_entry(
      (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
      3
    )
  ),
  1,
  'The current owner can revision-safely move a Home to Trash'
);

select is(
  (
    select count(*)::integer
    from public.homes_workspace()
    where title = 'California home'
  ),
  0,
  'A trashed Home disappears from the active Homes workspace'
);

select is(
  (
    select wiki_item_subtype
    from public.trash_workspace()
    where title = 'California home'
  ),
  'home',
  'A trashed Home keeps its Entity subtype in the recoverable Trash archive'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
      (select revision from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
      (select deleted_at from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
    )
  ),
  1,
  'The shared Trash contract restores a Home without losing its relationships'
);

select is(
  (
    select count(*)::integer
    from public.timeline_workspace_with_organization()
    where title = 'California home'
      and track_system_key = 'homes'
      and timeline_kind = 'stage'
  ),
  1,
  'A restored Home reappears on the Homes Timeline track'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.homes_workspace()),
  0,
  'An unauthenticated caller receives no Homes data'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.homes_workspace(integer,integer)',
    'execute'
  ),
  'Authenticated users can execute the Homes workspace'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.homes_workspace(integer,integer)',
    'execute'
  ),
  'Anonymous users cannot execute the Homes workspace'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text[],uuid,integer)',
    'execute'
  ),
  'Authenticated users can execute the Home mutation contract'
);

select ok(
  not has_function_privilege(
    'public',
    'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text[],uuid,integer)',
    'execute'
  ),
  'PUBLIC cannot execute the Home mutation contract'
);

select ok(
  has_function_privilege('authenticated', 'public.save_home_with_location(jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.save_home_with_location(jsonb,jsonb)', 'execute'),
  'Only signed-in users can save a Home with its Location'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.homes_workspace(integer,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Homes workspace uses an empty search path'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text[],uuid,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Home mutation contract uses an empty search path'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_home_entry_with_occurrence(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text[],uuid,integer)'::regprocedure
  ),
  false,
  'The Home mutation contract remains security invoker'
);

select is(
  (
    select count(*)::integer
    from pg_indexes
    where schemaname = 'public'
      and indexname in ('entries_owner_home_occurrence_idx', 'homes_owner_updated_idx')
  ),
  2,
  'Homes browsing has both supporting indexes'
);

select * from finish();
rollback;
