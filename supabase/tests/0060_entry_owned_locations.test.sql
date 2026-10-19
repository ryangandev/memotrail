begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select hasnt_table('public', 'places', 'Authored Place table is removed');
select hasnt_table('public', 'place_versions', 'Place history table is removed');
select hasnt_function('public', 'places_workspace', array['integer','integer'], 'Place browsing RPC is removed');
select hasnt_function('public', 'trash_place', array['uuid','integer'], 'Place Trash RPC is removed');
select ok('locations' = any(public.export_dataset_names()), 'Location snapshots remain exportable');
select ok(not ('places' = any(public.export_dataset_names())), 'Authored Places are absent from new exports');

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000122','locations-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000123','locations-other@memotrail.local');

insert into public.locations(
  id,owner_id,formatted_address,address,city,region,country,latitude,longitude,
  provider,provider_location_id
) values (
  '99000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000122',
  '10 Pine Street, Philadelphia, Pennsylvania, USA',
  '10 Pine Street',
  'Philadelphia',
  'Pennsylvania',
  'USA',
  39.952600,
  -75.165200,
  'test-provider',
  'home-location-1'
);

insert into public.entries(
  id,owner_id,title,body,item_kind,item_subtype,date_precision
) values (
  '99000000-0000-4000-8000-000000000003',
  '10000000-0000-0000-0000-000000000122',
  'Pine Street home',
  'A remembered residence.',
  'entry',
  'chapter',
  'unknown'
);
insert into public.entry_locations(entry_id,location_id,owner_id,relationship) values (
  '99000000-0000-4000-8000-000000000003',
  '99000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000122',
  'primary'
);

select is(
  (
    select bound_entry_id
    from public.locations
    where id='99000000-0000-4000-8000-000000000002'
  ),
  '99000000-0000-4000-8000-000000000003'::uuid,
  'Linking a Location binds it to its Entry'
);

select throws_ok(
  $$insert into public.entry_locations(entry_id,location_id,owner_id,relationship) values (
    '99000000-0000-4000-8000-000000000003',
    '99000000-0000-4000-8000-000000000002',
    '10000000-0000-0000-0000-000000000122',
    'home'
  )$$,
  '23514',
  null,
  'Links are primary or photo Locations only'
);

select hasnt_table('public', 'homes', 'A Chapter''s Location is its primary Location link, with no Home record');
select hasnt_table('public', 'entry_places', 'Entry Location links live in entry_locations');
select hasnt_column('public', 'locations', 'name', 'Locations have no separate name');
select hasnt_column('public', 'locations', 'notes', 'Locations have no notes');
select hasnt_column('public', 'locations', 'deleted_at', 'Locations are never soft-deleted');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000122',true);

select is(
  (
    select count(*)
    from public.search_wiki_items('Pine Street')
    where entry_id='99000000-0000-4000-8000-000000000003'
  ),
  1::bigint,
  'Linked Location details contribute searchable Wiki Item context'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000123',true);
select is(
  (select count(*) from public.locations),
  0::bigint,
  'Location RLS remains owner scoped'
);
reset role;
select * from finish();
rollback;
