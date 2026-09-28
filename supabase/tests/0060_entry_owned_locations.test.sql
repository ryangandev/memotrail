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
  id,owner_id,name,formatted_address,address,city,region,country,latitude,longitude,notes,
  provider,provider_location_id
) values (
  '99000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000122',
  'Home location',
  '10 Pine Street, Philadelphia, Pennsylvania, USA',
  '10 Pine Street',
  'Philadelphia',
  'Pennsylvania',
  'USA',
  39.952600,
  -75.165200,
  'Private geographic context.',
  'test-provider',
  'home-location-1'
);

insert into public.entries(
  id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision
) values (
  '99000000-0000-4000-8000-000000000003',
  '10000000-0000-0000-0000-000000000122',
  'Pine Street home',
  'A remembered residence.',
  'entity',
  'home',
  'organized',
  'unknown'
);
insert into public.homes(entry_id,owner_id,place_id) values (
  '99000000-0000-4000-8000-000000000003',
  '10000000-0000-0000-0000-000000000122',
  '99000000-0000-4000-8000-000000000002'
);
insert into public.entry_places(entry_id,place_id,owner_id,relationship) values (
  '99000000-0000-4000-8000-000000000003',
  '99000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000122',
  'home'
);

select is(
  (
    select location_id
    from public.entry_locations
    where entry_id='99000000-0000-4000-8000-000000000003'
  ),
  '99000000-0000-4000-8000-000000000002'::uuid,
  'The canonical relationship view exposes a Location identity'
);

select is(
  (
    select c.confrelid::regclass::text
    from pg_constraint as c
    where c.conname='homes_location_id_owner_id_fkey'
  ),
  'locations',
  'Homes reference Locations rather than Places'
);

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
