begin;

create extension if not exists pgtap with schema extensions;

select plan(59);

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
    from public.save_home_entry(
      'California apartment',
      'A sunny place near the coast.',
      '2025-06-01T19:00:00Z',
      null,
      'month',
      'Since June 2025',
      'America/Los_Angeles',
      null,
      'California apartment',
      '123 Palm Street',
      'Los Angeles',
      'California',
      'United States',
      34.052235,
      -118.243683,
      'Near the coast.',
      'Moved for a new chapter.',
      null,
      array['Homes', 'Reflection', 'homes'],
      array['California', 'home', 'HOME'],
      null,
      null
    )
  $$,
  'An owner can create an open-ended Home with a new Place'
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
    select inbox_status
    from public.entries
    where title = 'California apartment'
      and item_kind = 'entity' and item_subtype = 'home'
  ),
  'organized',
  'Direct Home creation produces an organized Entry'
);

select ok(
  (
    select homes.place_id is not null
    from public.homes
    join public.entries on entries.id = homes.entry_id
    where entries.title = 'California apartment'
  ),
  'The Home owns an Entry-specific Location relationship'
);

select is(
  (
    select concat_ws('|', locations.name, locations.address, locations.city, locations.region, locations.country)
    from public.homes
    join public.entries on entries.id = homes.entry_id
    join public.locations on locations.id = homes.place_id
    where entries.title = 'California apartment'
  ),
  '123 Palm Street, Los Angeles, California, United States|123 Palm Street|Los Angeles|California|United States',
  'The Location derives its label from normalized address fields'
);

select is(
  (
    select concat(locations.latitude::text, ',', locations.longitude::text)
    from public.homes
    join public.entries on entries.id = homes.entry_id
    join public.locations on locations.id = homes.place_id
    where entries.title = 'California apartment'
  ),
  '34.052235,-118.243683',
  'The Location preserves optional coordinates'
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
    select entry_places.relationship
    from public.entry_places
    join public.entries on entries.id = entry_places.entry_id
    where entries.title = 'California apartment'
  ),
  'home',
  'The Home is linked to its Entry-owned Location through the compatibility relationship'
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
    select collection_names::text
    from public.homes_workspace()
    where title = 'California apartment'
  ),
  '{homes,Reflection}',
  'Home Collections are normalized and de-duplicated case-insensitively'
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

insert into public.locations (
  id,
  owner_id,
  name,
  city,
  region,
  country
)
values (
  '50000000-0000-0000-0000-000000000011',
  '10000000-0000-0000-0000-000000000001',
  'Philadelphia rowhome',
  'Philadelphia',
  'Pennsylvania',
  'United States'
);

select lives_ok(
  $$
    select *
    from public.save_home_entry(
      'Philadelphia rowhome',
      'The East Coast chapter.',
      '2012-08-01T16:00:00Z',
      '2025-05-31T16:00:00Z',
      'approximate',
      'Ages 12 to 25',
      'America/New_York',
      '50000000-0000-0000-0000-000000000011',
      'Philadelphia rowhome',
      null,
      'Philadelphia',
      'Pennsylvania',
      'United States',
      null,
      null,
      null,
      'Moved with family.',
      'Moved to California.',
      array['Homes'],
      array['Philadelphia'],
      null,
      null
    )
  $$,
  'An owner can create a completed Home using an existing Place'
);

select is(
  (select count(*)::integer from public.locations),
  2,
  'Saving an unchanged Entry-owned Location keeps the same snapshot'
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
      select * from public.save_home_entry(
        ' ', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null,
        'Place', null, null, null, null, null, null, null, null, null,
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home requires a title'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null,
        ' ', null, null, null, null, null, null, null, null, null,
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home requires a Place name'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'Not/AZone', null,
        'Place', null, null, null, null, null, null, null, null, null,
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home rejects an invalid occurrence timezone'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry(
        'Home', '', '2020-01-02T00:00:00Z', '2020-01-01T00:00:00Z', 'range', null, 'UTC', null,
        'Place', null, null, null, null, null, null, null, null, null,
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A Home end cannot precede its start'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null,
        'Place', null, null, null, null, 34, null, null, null, null,
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'Home coordinates must be supplied as a complete pair'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      select * from public.save_home_entry(
        'Home', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null,
        'Place', null, null, null, null, null, null, null, null, 'Already left',
        array[]::text[], array[]::text[], null, null
      )
    $$
  ),
  '22023',
  'A move-out reason requires a move-out date'
);

select is(
  (
    select count(*)::integer
    from public.save_home_entry(
      'California home',
      'A quieter home near work.',
      '2025-06-01T19:00:00Z',
      '2026-08-31T19:00:00Z',
      'month',
      'June 2025 to August 2026',
      'America/Los_Angeles',
      (
        select homes.place_id
        from public.homes
        join public.entries on entries.id = homes.entry_id
        where entries.title = 'California apartment'
      ),
      'California home',
      '456 Elm Street',
      'San Francisco',
      'California',
      'United States',
      37.774929,
      -122.419418,
      'Walkable and quiet.',
      'Moved for a new chapter.',
      'Needed more space.',
      array['Homes', 'Milestones'],
      array['California', 'favorite'],
      (select id from public.entries where title = 'California apartment' and item_kind = 'entity' and item_subtype = 'home'),
      (select revision from public.entries where title = 'California apartment' and item_kind = 'entity' and item_subtype = 'home')
    )
  ),
  1,
  'The current revision can update a Home atomically'
);

select is(
  (select revision from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
  2,
  'Updating a Home advances its Entry revision once'
);

select is(
  (
    select snapshot ->> 'title'
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
      and version = 1
  ),
  'California apartment',
  'Home history preserves the previous Entry content'
);

select is(
  (
    select snapshot #>> '{home,move_in_reason}'
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
      and version = 1
  ),
  'Moved for a new chapter.',
  'Home history preserves the previous specialized Home fields'
);

select is(
  (
    select snapshot #>> '{place,address}'
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
      and version = 1
  ),
  '123 Palm Street',
  'Home history preserves the previous Place fields'
);

select is(
  (
    select snapshot #>> '{timeline,track_system_key}'
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
      and version = 1
  ),
  'homes',
  'Home history preserves its previous Timeline relationship'
);

select is(
  (
    select concat_ws('|', address, city, move_out_reason)
    from public.homes_workspace()
    where title = 'California home'
  ),
  '456 Elm Street|San Francisco|Needed more space.',
  'The Homes workspace returns the updated Location and move details'
);

select is(
  (
    select concat(collection_names::text, '|', tag_names::text)
    from public.homes_workspace()
    where title = 'California home'
  ),
  '{homes,Milestones}|{California,favorite}',
  'A Home update atomically replaces Collections and tags'
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
    from public.save_home_entry(
      'Stale overwrite', '', '2025-06-01T19:00:00Z', null, 'month', null,
      'America/Los_Angeles',
      (select homes.place_id from public.homes join public.entries on entries.id = homes.entry_id where entries.title = 'California home'),
      'Changed by stale write', null, null, null, null, null, null, null, null, null,
      array[]::text[], array[]::text[],
      (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'), 1
    )
  ),
  0,
  'A stale Home update returns no row'
);

select is(
  (
    select locations.name
    from public.homes
    join public.entries on entries.id = homes.entry_id
    join public.locations on locations.id = homes.place_id
    where entries.title = 'California home'
  ),
  '456 Elm Street, San Francisco, California, United States',
  'A stale Home update does not partially replace its Location snapshot'
);

select set_config(
  'app.test_home_entry_id',
  (select id::text from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home'),
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
  (
    select count(*)::integer
    from public.save_home_entry(
      'Cross-owner place', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC',
      '50000000-0000-0000-0000-000000000011',
      'Other place', null, null, null, null, null, null, null, null, null,
      array[]::text[], array[]::text[], null, null
    )
  ),
  0,
  'Another owner cannot create a Home with an inaccessible Place'
);

select is(
  (
    select count(*)::integer
    from public.save_home_entry(
      'Cross-owner update', '', '2020-01-01T00:00:00Z', null, 'year', null, 'UTC', null,
      'Other place', null, null, null, null, null, null, null, null, null,
      array[]::text[], array[]::text[],
      current_setting('app.test_home_entry_id')::uuid, 2
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
      2
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
      2
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
    select snapshot #>> '{place,city}'
    from public.entry_versions
    where entry_id = (select id from public.entries where title = 'California home' and item_kind = 'entity' and item_subtype = 'home')
      and version = 2
  ),
  'San Francisco',
  'Moving a Home to Trash preserves its current specialized state in history'
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
    'public.save_home_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)',
    'execute'
  ),
  'Authenticated users can execute the Home mutation contract'
);

select ok(
  not has_function_privilege(
    'public',
    'public.save_home_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)',
    'execute'
  ),
  'PUBLIC cannot execute the Home mutation contract'
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
    where oid = 'public.save_home_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Home mutation contract uses an empty search path'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_home_entry(text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[],uuid,integer)'::regprocedure
  ),
  false,
  'The Home mutation contract remains security invoker'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.archive_entry_version()'::regprocedure
  ),
  true,
  'Entry history remains a hardened security-definer trigger boundary'
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
