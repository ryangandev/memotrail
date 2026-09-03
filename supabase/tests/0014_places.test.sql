begin;

create extension if not exists pgtap with schema extensions;

select plan(73);

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

select has_table('public', 'place_versions', 'Place history exists');
select has_column('public', 'places', 'revision', 'Places have optimistic revisions');
select has_column('public', 'places', 'deleted_at', 'Places support recoverable Trash');
select has_function(
  'public', 'places_workspace', array['integer', 'integer'],
  'The Places workspace exists'
);
select has_function(
  'public', 'save_place',
  array['text', 'text', 'text', 'text', 'text', 'numeric', 'numeric', 'text', 'uuid[]', 'uuid', 'integer'],
  'The Place save mutation exists'
);
select has_function(
  'public', 'trash_place', array['uuid', 'integer'],
  'The Place Trash mutation exists'
);
select has_function('public', 'archive_place_version', array[]::text[], 'The Place history trigger exists');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-0000-0000-000000000014',
  'authenticated', 'authenticated', 'places-other@memotrail.local', '',
  timezone('utc', now()), '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Places Other User"}'::jsonb, timezone('utc', now()),
  timezone('utc', now()), '', '', '', ''
)
on conflict (id) do nothing;

insert into public.entries (
  id, owner_id, title, body, entry_type, inbox_status, occurred_start,
  date_precision, occurred_timezone
)
values
  (
    '81000000-0000-4000-8000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Park journal', 'Walks and changing seasons.', 'standard', 'organized',
    '2026-06-01T19:00:00Z', 'day', 'America/Los_Angeles'
  ),
  (
    '81000000-0000-4000-8000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Apartment chapter', 'A small first home.', 'home', 'organized',
    '2020-01-01T20:00:00Z', 'year', 'America/Los_Angeles'
  ),
  (
    '81000000-0000-4000-8000-000000000003',
    '10000000-0000-0000-0000-000000000014',
    'Other journal', 'Private place.', 'standard', 'organized',
    null, 'unknown', null
  );

insert into public.attachments (
  id, owner_id, entry_id, object_path, original_filename, mime_type, byte_size
)
values (
  '82000000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000001/81000000-0000-4000-8000-000000000001/park.jpg',
  'park.jpg', 'image/jpeg', 2048
);

insert into public.places (
  id, owner_id, name, city, region, country, notes
)
values
  (
    '83000000-0000-4000-8000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Old Apartment', 'Philadelphia', 'Pennsylvania', 'United States', 'First lease.'
  ),
  (
    '83000000-0000-4000-8000-000000000003',
    '10000000-0000-0000-0000-000000000014',
    'Other Place', 'Private City', null, null, null
  );

update public.places
set notes = 'Other private history.'
where id = '83000000-0000-4000-8000-000000000003';

insert into public.homes (
  entry_id, owner_id, place_id, move_in_reason
)
values (
  '81000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  '83000000-0000-4000-8000-000000000002',
  'First place of my own.'
);

insert into public.entry_places (
  entry_id, place_id, owner_id, relationship
)
values (
  '81000000-0000-4000-8000-000000000002',
  '83000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  'home'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$
    select * from public.save_place(
      'Golden Gate Park', '501 Stanyan Street', 'San Francisco', 'California',
      'United States', 37.769400, -122.486200, 'A place for long walks.',
      array['81000000-0000-4000-8000-000000000001'::uuid], null, null
    )
  $$,
  'An owner can create a Map-ready Place linked to an Entry'
);

select is(
  (select revision from public.places where name = 'Golden Gate Park'),
  1,
  'A new Place starts at revision one'
);

select is(
  (
    select concat_ws('|', name, address, city, region, country, notes)
    from public.places_workspace()
    where name = 'Golden Gate Park'
  ),
  'Golden Gate Park|501 Stanyan Street|San Francisco|California|United States|A place for long walks.',
  'The Places workspace preserves complete location details'
);

select is(
  (
    select concat(latitude::text, ',', longitude::text)
    from public.places_workspace()
    where name = 'Golden Gate Park'
  ),
  '37.769400,-122.486200',
  'The Places workspace preserves Map-ready coordinates'
);

select is(
  (select linked_entry_count from public.places_workspace() where name = 'Golden Gate Park'),
  1::bigint,
  'The Places workspace reports its active linked Entry count'
);

select is(
  (select home_count from public.places_workspace() where name = 'Golden Gate Park'),
  0::bigint,
  'A regular linked Entry does not count as a Home'
);

select is(
  (
    select linked_entries -> 0 ->> 'title'
    from public.places_workspace()
    where name = 'Golden Gate Park'
  ),
  'Park journal',
  'The Places workspace returns linked Entry context'
);

select is(
  (
    select linked_entries -> 0 ->> 'relationship'
    from public.places_workspace()
    where name = 'Golden Gate Park'
  ),
  'related',
  'Editable Place links preserve their relationship'
);

select is(
  (
    select linked_entries -> 0 -> 'attachments' -> 0 ->> 'object_path'
    from public.places_workspace()
    where name = 'Golden Gate Park'
  ),
  '10000000-0000-0000-0000-000000000001/81000000-0000-4000-8000-000000000001/park.jpg',
  'Linked Entry context preserves private attachment metadata'
);

select is(
  (select total_count from public.places_workspace(1, 0) limit 1),
  2::bigint,
  'Paginated Places preserve the complete owner-scoped count'
);

select is(
  pg_temp.capture_sqlstate('select * from public.places_workspace(0, 0)'),
  '22023',
  'The Places workspace rejects an invalid limit'
);

select is(
  pg_temp.capture_sqlstate('select * from public.places_workspace(20, -1)'),
  '22023',
  'The Places workspace rejects an invalid offset'
);

select is(
  (select home_count from public.places_workspace() where name = 'Old Apartment'),
  1::bigint,
  'A Home-created Place appears in the reusable Places workspace'
);

select is(
  (
    select linked_entries -> 0 ->> 'relationship'
    from public.places_workspace()
    where name = 'Old Apartment'
  ),
  'home',
  'A Home-created Place retains its protected Home relationship'
);

select lives_ok(
  $$
    select * from public.save_place(
      'Old Apartment', null, 'Philadelphia', 'Pennsylvania', 'United States',
      null, null, 'The first lease, remembered.',
      array['81000000-0000-4000-8000-000000000002'::uuid],
      '83000000-0000-4000-8000-000000000002', 1
    )
  $$,
  'A Home-created Place can be revision-safely enriched'
);

select is(
  (
    select count(*)::integer
    from public.entry_places
    where place_id = '83000000-0000-4000-8000-000000000002'
  ),
  1,
  'Editing a Home-created Place does not duplicate its relationship'
);

select is(
  (
    select relationship
    from public.entry_places
    where place_id = '83000000-0000-4000-8000-000000000002'
  ),
  'home',
  'Editing a Place never replaces its Home relationship'
);

select is(
  (
    select count(*)::integer
    from public.trash_place('83000000-0000-4000-8000-000000000002', 2)
  ),
  0,
  'A linked Home Place cannot be moved to Trash'
);

select lives_ok(
  format(
    $$select * from public.save_place(
      'Golden Gate Park and Presidio', '501 Stanyan Street', 'San Francisco',
      'California', 'United States', 37.769400, -122.486200,
      'Two neighboring places in one memory.',
      array['81000000-0000-4000-8000-000000000001'::uuid], %L, 1
    )$$,
    (select id from public.places where name = 'Golden Gate Park')
  ),
  'A current Place can be revision-safely edited'
);

select is(
  (select revision from public.places where name = 'Golden Gate Park and Presidio'),
  2,
  'Editing a Place advances its revision'
);

select is(
  (
    select snapshot #>> '{place,name}'
    from public.place_versions
    where place_id = (select id from public.places where name = 'Golden Gate Park and Presidio')
      and version = 1
  ),
  'Golden Gate Park',
  'Editing a Place preserves its prior details in history'
);

select is(
  (
    select snapshot #>> '{entry_links,0,entry_id}'
    from public.place_versions
    where place_id = (select id from public.places where name = 'Golden Gate Park and Presidio')
      and version = 1
  ),
  '81000000-0000-4000-8000-000000000001',
  'Place history preserves the previous linked Entry set'
);

select is(
  (
    select count(*)::integer
    from public.save_place(
      'Stale overwrite', null, null, null, null, null, null, null, '{}',
      (select id from public.places where name = 'Golden Gate Park and Presidio'), 1
    )
  ),
  0,
  'A stale Place revision cannot overwrite newer content'
);

select is(
  (select name from public.places where name = 'Golden Gate Park and Presidio'),
  'Golden Gate Park and Presidio',
  'A rejected stale edit leaves Place content unchanged'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place('', null, null, null, null, null, null, null, '{}', null, null)$$
  ),
  '22023',
  'Place creation rejects an empty name'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place('Bad', null, null, null, null, 1, null, null, '{}', null, null)$$
  ),
  '22023',
  'Place creation rejects partial coordinates'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place('Bad', null, null, null, null, 91, 0, null, '{}', null, null)$$
  ),
  '22023',
  'Place creation rejects out-of-range coordinates'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place(
      'Bad', null, null, null, null, null, null, null,
      array['ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid], null, null
    )$$
  ),
  '22023',
  'Place creation rejects a missing related Entry'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place('Bad', null, null, null, null, null, null, null, '{}', null, 1)$$
  ),
  '22023',
  'A new Place rejects an unexpected revision'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_place(
      'Bad', null, null, null, null, null, null, null, '{}',
      '83000000-0000-4000-8000-000000000002', null
    )$$
  ),
  '22023',
  'An existing Place requires an expected revision'
);

select is(
  (
    select count(*)::integer
    from public.save_place(
      'Private overwrite', null, null, null, null, null, null, null, '{}',
      '83000000-0000-4000-8000-000000000003', 2
    )
  ),
  0,
  'An owner cannot edit another owner''s Place'
);

select is(
  (select count(*)::integer from public.places_workspace() where name = 'Other Place'),
  0,
  'The Places workspace hides another owner''s Place'
);

select is(
  (
    select count(*)::integer
    from public.place_versions
    where place_id = '83000000-0000-4000-8000-000000000003'
  ),
  0,
  'Row Level Security hides another owner''s Place history'
);

select lives_ok(
  format(
    $$select * from public.save_place(
      'Golden Gate Park and Presidio', '501 Stanyan Street', 'San Francisco',
      'California', 'United States', 37.769400, -122.486200,
      'Two neighboring places in one memory.', '{}', %L, 2
    )$$,
    (select id from public.places where name = 'Golden Gate Park and Presidio')
  ),
  'An owner can unlink editable Place relationships'
);

select is(
  (
    select count(*)::integer
    from public.entry_places
    where place_id = (select id from public.places where name = 'Golden Gate Park and Presidio')
  ),
  0,
  'Replacing editable relationships can leave a Place unlinked'
);

select is(
  (
    select count(*)::integer
    from public.trash_place(
      (select id from public.places where name = 'Golden Gate Park and Presidio'), 3
    )
  ),
  1,
  'An unlinked Place can move to recoverable Trash'
);

select is(
  (select count(*)::integer from public.places_workspace() where name = 'Golden Gate Park and Presidio'),
  0,
  'A trashed Place leaves the active workspace'
);

select is(
  (
    select item_kind
    from public.trash_workspace()
    where title = 'Golden Gate Park and Presidio'
  ),
  'place',
  'The shared Trash workspace identifies a removed Place'
);

select is(
  (
    select detail
    from public.trash_workspace()
    where title = 'Golden Gate Park and Presidio'
  ),
  '501 Stanyan Street, San Francisco, California, United States',
  'Trash preserves useful Place location context'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      99,
      (select deleted_at from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  0,
  'A stale Place revision cannot restore Trash'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      4,
      (select deleted_at + interval '1 second' from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  0,
  'A changed Place deletion timestamp cannot restore Trash'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      4,
      (select deleted_at from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  1,
  'A Place restores through the shared optimistic Trash contract'
);

select is(
  (select revision from public.places where name = 'Golden Gate Park and Presidio'),
  5,
  'Restoring a Place advances its revision'
);

select ok(
  exists (
    select 1
    from public.place_versions
    where place_id = (select id from public.places where name = 'Golden Gate Park and Presidio')
      and (snapshot #>> '{place,deleted_at}') is not null
  ),
  'Restoring a Place preserves its deleted state in history'
);

select is(
  (
    select count(*)::integer
    from public.trash_place(
      (select id from public.places where name = 'Golden Gate Park and Presidio'), 5
    )
  ),
  1,
  'A restored Place can move to Trash again'
);

select is(
  (
    select count(*)::integer
    from public.trash_item_storage_paths(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      6,
      (select deleted_at from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  0,
  'A Place has no direct private Storage objects to remove'
);

select is(
  (
    select count(*)::integer
    from public.delete_trash_item_forever(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      5,
      (select deleted_at from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  0,
  'A stale Place revision cannot permanently delete Trash'
);

select is(
  (
    select count(*)::integer
    from public.delete_trash_item_forever(
      'place',
      (select id from public.places where name = 'Golden Gate Park and Presidio'),
      6,
      (select deleted_at from public.places where name = 'Golden Gate Park and Presidio')
    )
  ),
  1,
  'A matching Place can be permanently deleted after explicit confirmation'
);

select is(
  (select count(*)::integer from public.places where name = 'Golden Gate Park and Presidio'),
  0,
  'Permanent deletion removes the Place'
);

select is(
  (
    select count(*)::integer
    from public.place_versions
    where place_id not in (select id from public.places)
  ),
  0,
  'Permanent Place deletion removes its version history under the deletion policy'
);

reset role;

select function_returns(
  'public', 'places_workspace', array['integer', 'integer'], 'setof record',
  'The Places workspace function remains available'
);

select function_returns(
  'public', 'trash_place', array['uuid', 'integer'], 'setof record',
  'The Place Trash function remains available'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.places_workspace(integer,integer)'::regprocedure),
  false,
  'The Places workspace uses invoker rights'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)'::regprocedure
  ),
  false,
  'The Place save function uses invoker rights'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.trash_place(uuid,integer)'::regprocedure),
  false,
  'The Place Trash function uses invoker rights'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.archive_place_version()'::regprocedure),
  true,
  'Place history uses a hardened security-definer trigger boundary'
);

select is(
  (select proconfig from pg_proc where oid = 'public.places_workspace(integer,integer)'::regprocedure),
  array['search_path=""']::text[],
  'The Places workspace has an empty search path'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'The Place save function has an empty search path'
);

select is(
  (select proconfig from pg_proc where oid = 'public.trash_place(uuid,integer)'::regprocedure),
  array['search_path=""']::text[],
  'The Place Trash function has an empty search path'
);

select is(
  (select proconfig from pg_proc where oid = 'public.archive_place_version()'::regprocedure),
  array['search_path=""']::text[],
  'The Place history trigger has an empty search path'
);

select ok(
  has_function_privilege('authenticated', 'public.places_workspace(integer,integer)', 'EXECUTE')
    and has_function_privilege(
      'authenticated',
      'public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)',
      'EXECUTE'
    )
    and has_function_privilege('authenticated', 'public.trash_place(uuid,integer)', 'EXECUTE'),
  'Authenticated users can execute every Place contract function'
);

select ok(
  not has_function_privilege('anon', 'public.places_workspace(integer,integer)', 'EXECUTE')
    and not has_function_privilege(
      'anon',
      'public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)',
      'EXECUTE'
    )
    and not has_function_privilege('anon', 'public.trash_place(uuid,integer)', 'EXECUTE'),
  'Anonymous users cannot execute Place contract functions'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.place_versions'::regclass),
  true,
  'Place history has Row Level Security enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'place_versions'
      and policyname = 'Users can view their own place history'
  ),
  'Place history has an owner-scoped read policy'
);

select is(
  (
    select array_agg(privilege_type::text order by privilege_type)::text[]
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'place_versions'
  ),
  array['SELECT']::text[],
  'Authenticated users receive read-only access to Place history'
);

select is(
  (
    select count(*)::integer
    from pg_indexes
    where schemaname = 'public'
      and indexname in (
        'places_owner_active_updated_idx',
        'places_owner_active_coordinates_idx',
        'entry_places_owner_place_relationship_idx',
        'place_versions_owner_place_version_idx'
      )
  ),
  4,
  'Places browsing, Map coordinates, links, and history have supporting indexes'
);

select * from finish();
rollback;
