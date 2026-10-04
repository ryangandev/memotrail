begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000171','inbox-retired-owner@memotrail.local');

select hasnt_column('public','entries','inbox_status','Entries have no Inbox state');
select hasnt_index('public','entries','entries_owner_inbox_idx','The Inbox index is gone');
select hasnt_function('public','keep_entries_in_library','The Library trigger is gone with the column');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000171',true);

insert into public.entries(id,owner_id,body,date_precision) values
  ('99710000-0000-4000-8000-000000000001',auth.uid(),'Saved straight to Library.','unknown');
select is(
  (select count(*) from public.entries where id='99710000-0000-4000-8000-000000000001'),
  1::bigint,
  'A Capture saves straight to Library'
);
select throws_ok(
  $$insert into public.entries(owner_id,body,date_precision,inbox_status)
    values (auth.uid(),'From an old client.','unknown','unreviewed')$$,
  '42703',
  null,
  'A client that still sends an Inbox state is refused'
);

reset role;

select hasnt_function('public','capture_extraction_source','Capture handoff lookup is retired');
select hasnt_function('public','extract_capture_to_goal','Want to Do no longer starts from a Capture');
select hasnt_function('public','extract_capture_to_home','A Home no longer starts from a Capture');
select hasnt_function('public','extract_capture_to_vehicle','A Vehicle no longer starts from a Capture');
select hasnt_function('public','save_home_entry_with_geoapify',array['jsonb','jsonb','jsonb'],'Home saves take no Capture source');
select hasnt_function('public','save_vehicle_with_location',array['jsonb','jsonb','jsonb'],'Vehicle saves take no Capture source');
select has_function('public','save_home_entry_with_geoapify',array['jsonb','jsonb'],'Home saves take the record and its Location');
select has_function('public','save_vehicle_with_location',array['jsonb','jsonb'],'Vehicle saves take the record and its Location');
select hasnt_function('public','review_wiki_item_with_photo_place','The plain-text review without a Location is retired');
select hasnt_function('public','review_wiki_item_with_photo_place_rich','The rich-text review without a Location is retired');
select hasnt_function('public','trash_item_storage_paths','The per-record deletion manifest is retired');
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and 'p_mark_done' = any(p.proargnames)
  ),
  'No function takes a mark-done flag'
);
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and pg_get_function_result(p.oid) ~ '(inbox_status|inbox_count|record_source|record_id)'
  ),
  'No function returns an Inbox state or a record source'
);

select * from finish();
rollback;
