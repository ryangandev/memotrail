begin;

create extension if not exists pgtap with schema extensions;

select plan(32);

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

create or replace function pg_temp.rows_affected(statement text)
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  execute statement;
  get diagnostics affected = row_count;
  return affected;
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
  'second-user@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Second Test User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

select ok(
  exists (
    select 1
    from public.profiles
    where user_id = '10000000-0000-0000-0000-000000000001'
  ),
  'A profile is created for each authenticated user'
);

select is(
  (
    select count(*)::integer
    from public.timeline_tracks
    where owner_id = '10000000-0000-0000-0000-000000000001'
  ),
  9,
  'New users receive the nine confirmed default timeline tracks'
);

select is(
  (select public from storage.buckets where id = 'entry-media'),
  false,
  'Entry media storage is private'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)::integer
    from public.entries
    where id = '40000000-0000-0000-0000-000000000001'
  ),
  1,
  'A user can read their own seeded Entry'
);

select lives_ok(
  $$
    insert into public.entries (id, owner_id, title, body)
    values (
      '40000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000001',
      'A private test Entry',
      'Only the owner should be able to read this.'
    )
  $$,
  'A user can insert their own Entry'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      insert into public.entries (owner_id, title)
      values (
        '10000000-0000-0000-0000-000000000002',
        'An Entry for another user'
      )
    $$
  ),
  '42501',
  'RLS rejects inserting an Entry for another user'
);

select lives_ok(
  $$
    update public.entries
    set title = 'A revised private test Entry'
    where id = '40000000-0000-0000-0000-000000000002'
  $$,
  'A user can update their own Entry'
);

select is(
  (
    select count(*)::integer
    from public.entry_versions
    where entry_id = '40000000-0000-0000-0000-000000000002'
  ),
  1,
  'Updating an Entry records immutable history'
);

select is(
  (
    select revision
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  2,
  'Updating an Entry advances its revision'
);

select lives_ok(
  $$
    select *
    from public.review_wiki_item_with_photo_place(
      '40000000-0000-0000-0000-000000000002',
      2,
      'First time skiing',
      'A cold and brilliant day.',
      'event',
      'first_time',
      '2026-07-03T18:30:00Z',
      'America/Los_Angeles',
      array['Travel', 'Learning', 'travel'],
      array['skiing', 'learning', 'Skiing'],
      false,
      null,
      null,
      'exact',
      null
    )
  $$,
  'An owner can atomically review an Entry with Collections and tags'
);

select is(
  (
    select revision
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  3,
  'Atomic review advances the Entry revision once'
);

select is(
  (
    select item_kind || ':' || item_subtype
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  'event:first_time',
  'Atomic review updates the canonical Wiki Item identity'
);

select is(
  (
    select count(*)::integer
    from public.entry_versions
    where entry_id = '40000000-0000-0000-0000-000000000002'
  ),
  2,
  'Atomic review preserves the previous Entry revision'
);

select is(
  (
    select count(*)::integer
    from public.entry_collections
    where entry_id = '40000000-0000-0000-0000-000000000002'
  ),
  2,
  'Atomic review de-duplicates and links Collections'
);

select is(
  (
    select count(*)::integer
    from public.entry_tags
    where entry_id = '40000000-0000-0000-0000-000000000002'
  ),
  2,
  'Atomic review de-duplicates and links tags'
);

select is(
  (
    select count(*)::integer
    from public.review_wiki_item_with_photo_place(
      '40000000-0000-0000-0000-000000000002',
      2,
      'Stale overwrite',
      '',
      'event',
      'first_time',
      '2026-07-03T18:30:00Z',
      'UTC',
      array['Wrong Collection'],
      array['wrong-tag'],
      true,
      null,
      null,
      'exact',
      null
    )
  ),
  0,
  'A stale review returns no row'
);

select is(
  (
    select title
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  'First time skiing',
  'A stale review does not partially change the Entry'
);

select is(
  (
    select count(*)::integer
    from public.review_wiki_item_with_photo_place(
      '40000000-0000-0000-0000-000000000002',
      3,
      'First time skiing',
      'A cold and brilliant day.',
      'event',
      'first_time',
      '2026-07-03T18:30:00Z',
      'America/Los_Angeles',
      array['Travel', 'Learning'],
      array['skiing', 'learning'],
      true,
      null,
      null,
      'exact',
      null
    )
  ),
  1,
  'The current revision can be explicitly marked Done'
);

select is(
  (
    select inbox_status
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  'organized',
  'Done marks the Entry organized'
);

select is(
  (
    select revision
    from public.entries
    where id = '40000000-0000-0000-0000-000000000002'
  ),
  4,
  'Done preserves history through one additional revision'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

select is(
  (
    select count(*)::integer
    from public.entries
    where owner_id = '10000000-0000-0000-0000-000000000001'
  ),
  0,
  'Another authenticated user cannot read the first user''s Entries'
);

select is(
  pg_temp.rows_affected(
    $$
      update public.entries
      set title = 'Changed by another user'
      where id = '40000000-0000-0000-0000-000000000002'
    $$
  ),
  0,
  'Another authenticated user cannot update the first user''s Entries'
);

select is(
  pg_temp.rows_affected(
    $$
      delete from public.entries
      where id = '40000000-0000-0000-0000-000000000002'
    $$
  ),
  0,
  'Another authenticated user cannot delete the first user''s Entries'
);

select is(
  (
    select count(*)::integer
    from public.review_wiki_item_with_photo_place(
      '40000000-0000-0000-0000-000000000001',
      1,
      'Changed by another user',
      '',
      'writing',
      'reflection',
      '2026-07-03T18:30:00Z',
      'UTC',
      '{}'::text[],
      '{}'::text[],
      false,
      null,
      null,
      'exact',
      null
    )
  ),
  0,
  'Another authenticated user cannot review the first user''s Entry'
);

select lives_ok(
  $$
    insert into public.collections (id, owner_id, name)
    values (
      '20000000-0000-0000-0000-000000000003',
      '10000000-0000-0000-0000-000000000002',
      'Second User Collection'
    )
  $$,
  'A second user can create their own Collection'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      insert into public.entry_collections (entry_id, collection_id, owner_id)
      values (
        '40000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000003',
        '10000000-0000-0000-0000-000000000002'
      )
    $$
  ),
  '23503',
  'Composite foreign keys reject cross-owner relationships'
);

reset role;
set local role anon;

select is(
  pg_temp.capture_sqlstate('select count(*) from public.entries'),
  '42501',
  'Unauthenticated users cannot read Entries'
);

select is(
  pg_temp.capture_sqlstate(
    $$
      insert into public.entries (owner_id, title)
      values (
        '10000000-0000-0000-0000-000000000001',
        'Anonymous Entry'
      )
    $$
  ),
  '42501',
  'Unauthenticated users cannot create Entries'
);

reset role;

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and privilege_type not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'Authenticated clients have no table privileges that bypass normal row mutations'
);

select is(
  (
    select array_agg(privilege_type::text order by privilege_type)::text[]
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'attachments'
  ),
  array['SELECT'],
  'Attachment metadata is read-only outside validated functions'
);

select is(
  (
    select array_agg(privilege_type::text order by privilege_type)::text[]
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'profiles'
  ),
  array['SELECT', 'UPDATE'],
  'Profiles expose only their intended authenticated privileges'
);

select is(
  (
    select array_agg(privilege_type::text order by privilege_type)::text[]
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'entries'
  ),
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'Entries retain the CRUD privileges enforced by Row Level Security'
);

select * from finish();

rollback;
