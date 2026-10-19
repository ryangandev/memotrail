begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Functions no client called, and the review chain the Entry editor replaced.
select hasnt_function('public','save_home_entry','The test-only Home save is gone');
select hasnt_function('public','save_vehicle_entry','The test-only Vehicle save is gone');
select hasnt_function('public','save_timeline_entry','The test-only Timeline save is gone');
select hasnt_function('public','mark_goal_achieved_with_first_time','The unused Goal achievement path is gone');
select hasnt_function('public','library_text_matches','The unused Library matcher is gone');
select hasnt_function('public','save_location','The standalone Location save is gone');
select hasnt_function('public','save_home_entry_with_geoapify','Homes save their Location like Vehicles');
select hasnt_function('public','resolve_home_location_copy_on_write','Homes no longer take address fields');
select hasnt_function('public','review_wiki_item_with_location_rich','The Inbox-era review is replaced by save_entry');
select hasnt_function('public','review_wiki_item_with_photo_place_core','The nested photo review step is gone');
select hasnt_function('public','review_wiki_item_with_occurrence_rich','The nested writing review step is gone');
select ok(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'save_entry' and 'p_item_kind' = any(p.proargnames)
  ), 'The Entry editor passes no classification');

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000174','leftovers-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000175','leftovers-other@memotrail.local');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_timezone) values
  ('99740000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000174','Walk','Words','entry','entry','unknown','UTC'),
  ('99740000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000174','Corner flat','Words','entry','chapter','unknown','UTC');

select throws_ok(
  $$update public.entries set item_subtype = 'source_capture' where id = '99740000-0000-4000-8000-000000000001'$$,
  '23514', null, 'An Entry can no longer be marked as a source capture');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000174',true);

select is(
  (select count(*) from public.save_entry('99740000-0000-4000-8000-000000000002',1,'Corner flat','Edited',null,
    null,null,'UTC',null,'unknown','{}',null,null, true, false)),
  1::bigint,
  'The Entry editor saves a Chapter through the same path'
);
select is(
  (select item_subtype from public.entries where id = '99740000-0000-4000-8000-000000000002'),
  'chapter',
  'Saving with the Chapter mark keeps the Chapter'
);
select is(
  (select revision from public.save_entry('99740000-0000-4000-8000-000000000001',1,'Walk','Edited',null,
    null,null,'UTC',null,'unknown','{}',
    jsonb_build_object('kind','provider','provider','geoapify','providerLocationId','corner',
      'formattedAddress','1 Corner Street','latitude',1.5,'longitude',2.5),
    null, false, false)),
  2,
  'The Entry editor saves the writing and its primary Location together'
);
select is(
  public.entry_detail('99740000-0000-4000-8000-000000000001')->'locations'->0->>'formatted_address',
  '1 Corner Street',
  'The Item page reads the Entry''s Locations'
);
select is(
  public.entry_detail('99740000-0000-4000-8000-000000000001')->'locations'->0->>'relationship',
  'primary',
  'The Item page reads how each Location relates to the Entry'
);
select ok(not (public.entry_detail('99740000-0000-4000-8000-000000000001') ? 'places'),
  'The Item page no longer reads places');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000175',true);
select is((select count(*) from public.entry_locations),0::bigint,'Another owner sees no Location links');
select is((select count(*) from public.locations),0::bigint,'Another owner sees no Locations');
reset role;
select set_config('request.jwt.claim.sub','',true);

select ok(not has_function_privilege('anon','public.replace_primary_location(uuid,jsonb)','execute'),
  'Signed-out visitors cannot link Locations');
select ok(not has_function_privilege('authenticated','public.claim_location_for_entry()','execute'),
  'Clients cannot call the Location claim trigger function');

select * from finish();
rollback;
