begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

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
  'search-other@memotrail.local',
  '',
  timezone('utc', now()),
  '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Search Other User"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  item_kind,
  item_subtype,
  occurred_start,
  occurred_timezone,
  metadata,
  deleted_at
)
values
  (
    '50000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'First time skiing',
    'A cold and brilliant day in the mountains.',
    'entry','entry',
    '2026-07-04T02:00:00Z',
    'America/Los_Angeles',
    '{"weather":"snowy"}'::jsonb,
    null
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '今天学到的事情',
    '为什么塑料牙套可以慢慢移动坚硬的牙齿',
    'entry','entry',
    '2025-05-04T08:00:00Z',
    'Asia/Shanghai',
    '{}'::jsonb,
    null
  ),
  (
    '50000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    'My first car',
    'A practical daily driver.',
    'entity',
    'vehicle',
    '2020-03-12T12:00:00Z',
    'America/New_York',
    '{}'::jsonb,
    null
  ),
  (
    '50000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    'Deleted skiing note',
    'This should stay in Trash.',
    'entry','entry',
    '2024-01-01T12:00:00Z',
    'UTC',
    '{}'::jsonb,
    timezone('utc', now())
  ),
  (
    '50000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000003',
    'Private skiing note',
    'A different owner must never see this.',
    'entry','entry',
    '2026-07-03T18:30:00Z',
    'UTC',
    '{}'::jsonb,
    null
  )
on conflict (id) do nothing;

insert into public.tags (id, owner_id, name)
values
  (
    '30000000-0000-0000-0000-000000000010',
    '10000000-0000-0000-0000-000000000001',
    'snow'
  ),
  (
    '30000000-0000-0000-0000-000000000011',
    '10000000-0000-0000-0000-000000000001',
    'orthodontics'
  )
on conflict (id) do nothing;

insert into public.entry_tags (entry_id, tag_id, owner_id)
values
  (
    '50000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000010',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000011',
    '10000000-0000-0000-0000-000000000001'
  )
on conflict do nothing;

insert into public.vehicles (entry_id, owner_id, make, model, model_year, color)
values (
  '50000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000001',
  'Tesla',
  'Model 3',
  2020,
  'Blue'
)
on conflict (entry_id) do nothing;

insert into public.milestones (entry_id, owner_id, shape, lane, is_first_time)
values (
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'moment',
  'other',
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$ select * from public.search_wiki_items(p_query => 'skiing') $$,
  'An authenticated owner can search Entries'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(p_query => 'First time skiing')
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  1,
  'Keyword search matches an Entry title'
);

select ok(
  (
    select match_reasons @> array['Title']::text[]
    from public.search_wiki_items(p_query => 'First time skiing')
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  'Search explains a title match'
);

select ok(
  (
    select match_reasons @> array['Body']::text[]
    from public.search_wiki_items(p_query => 'brilliant day')
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  'Search matches and explains body text'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(p_query => '牙套')
    where entry_id = '50000000-0000-0000-0000-000000000002'
  ),
  1,
  'Substring matching supports Chinese text without whitespace tokenization'
);

select ok(
  (
    select match_reasons @> array['Tag']::text[]
    from public.search_wiki_items(p_query => 'snow')
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  'Search matches and explains a tag'
);

select ok(
  (
    select match_reasons @> array['Date']::text[]
    from public.search_wiki_items(p_query => '2026-07-03')
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  'Search matches an occurrence date in the Entry''s preserved timezone'
);

select is(
  public.entry_local_timestamp('2026-07-04T02:00:00Z', 'Not/A_Timezone'),
  '2026-07-04 02:00:00'::timestamp,
  'Invalid legacy occurrence timezones safely fall back to UTC'
);

select ok(
  (
    select match_reasons @> array['Details']::text[]
    from public.search_wiki_items(p_query => 'Tesla')
    where entry_id = '50000000-0000-0000-0000-000000000003'
  ),
  'Search matches and explains structured Entry details'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(
      p_query => '',
      p_tag_names => array['SNOW']
    )
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  1,
  'A tag filter works without a keyword query'
);

select is(
  (
    select match_reasons
    from public.search_wiki_items(
      p_query => '',
      p_tag_names => array['SNOW']
    )
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  array['Filters']::text[],
  'Filter-only results explain why they matched'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(
      p_query => '',
      p_item_classifications => array['FIRST_TIME']
    )
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  1,
  'Entry Type filters are case-insensitive'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(
      p_query => '',
      p_tag_names => array['ORTHODONTICS']
    )
    where entry_id = '50000000-0000-0000-0000-000000000002'
  ),
  1,
  'Tag filters are case-insensitive'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(
      p_query => '',
      p_date_from => '2026-01-01',
      p_date_to => '2026-12-31'
    )
    where entry_id = '50000000-0000-0000-0000-000000000001'
  ),
  1,
  'Date filters include an Entry inside the selected range'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(p_query => 'Deleted skiing note')
  ),
  0,
  'Search excludes Entries in Trash'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items(p_query => 'Private skiing note')
  ),
  0,
  'Search never returns another owner''s Entry'
);

select is(
  (
    select count(*)::integer
    from public.search_wiki_items()
  ),
  0,
  'An empty search without filters returns no rows'
);

select lives_ok(
  $$ select * from public.search_wiki_items(p_query => ''' OR true --') $$,
  'Punctuation is treated as search input instead of executable SQL'
);

select is(
  pg_temp.capture_sqlstate(
    $$ select * from public.search_wiki_items(p_query => repeat('x', 201)) $$
  ),
  '22023',
  'Overlong search input is rejected'
);

reset role;
set local role anon;

select is(
  pg_temp.capture_sqlstate(
    $$ select * from public.search_wiki_items(p_query => 'skiing') $$
  ),
  '42501',
  'Unauthenticated users cannot execute Entry search'
);

select * from finish();

rollback;
