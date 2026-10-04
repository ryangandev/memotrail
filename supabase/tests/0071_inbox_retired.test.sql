begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000171','inbox-retired-owner@memotrail.local');

select is(
  (select column_default from information_schema.columns
   where table_schema='public' and table_name='entries' and column_name='inbox_status'),
  '''organized''::text',
  'New Entries default to Library'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000171',true);

insert into public.entries(id,owner_id,body,inbox_status,date_precision) values
  ('99710000-0000-4000-8000-000000000001',auth.uid(),'Saved by a client that still knows Inbox.','unreviewed','unknown');
select is(
  (select inbox_status from public.entries where id='99710000-0000-4000-8000-000000000001'),
  'organized',
  'A Capture saved to Inbox by an older client lands in Library'
);

update public.entries set inbox_status='unreviewed'
where id='99710000-0000-4000-8000-000000000001';
select is(
  (select inbox_status from public.entries where id='99710000-0000-4000-8000-000000000001'),
  'organized',
  'An Entry cannot be moved back to Inbox'
);

select throws_ok(
  $$select public.save_home_entry_with_geoapify(
    '{"title":"Harbor flat","tagNames":[]}'::jsonb,
    '{"entryId":"99710000-0000-4000-8000-000000000001","revision":2}'::jsonb,
    '{}'::jsonb
  )$$,
  '22023',
  'capture_handoff_retired',
  'A Home can no longer start from a Capture'
);
select throws_ok(
  $$select * from public.save_vehicle_with_location(
    '{"title":"Blue hatchback","tagNames":[]}'::jsonb,
    '{"entryId":"99710000-0000-4000-8000-000000000001","revision":2}'::jsonb,
    null
  )$$,
  '22023',
  'capture_handoff_retired',
  'A Vehicle can no longer start from a Capture'
);

reset role;
alter table public.entries disable trigger keep_entries_in_library;
select throws_ok(
  $$update public.entries set inbox_status='unreviewed'
    where id='99710000-0000-4000-8000-000000000001'$$,
  '23514',
  null,
  'Only Library is a valid Entry state'
);
alter table public.entries enable trigger keep_entries_in_library;

select is(
  (select count(*) from public.entry_versions where snapshot->>'inbox_status'='unreviewed'),
  0::bigint,
  'No history version can restore an Entry to Inbox'
);
select ok(
  not has_function_privilege('authenticated','public.keep_entries_in_library()','execute'),
  'The Library trigger function is not callable by clients'
);
select hasnt_function('public','capture_extraction_source','Capture handoff lookup is retired');
select hasnt_function('public','extract_capture_to_goal','Want to Do no longer starts from a Capture');
select hasnt_function('public','extract_capture_to_home','A Home no longer starts from a Capture');
select hasnt_function('public','extract_capture_to_vehicle','A Vehicle no longer starts from a Capture');

select * from finish();
rollback;
