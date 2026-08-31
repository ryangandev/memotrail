begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

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
  (select count(*)::integer from public.entries),
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

select * from finish();

rollback;
