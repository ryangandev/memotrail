begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000122','locations-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000123','locations-other@memotrail.local');

insert into public.places(id,owner_id,name,address,notes) values (
  '99000000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000122',
  'Corner café',
  'Near the old theater',
  'Sunday mornings.'
);

select is(
  (
    select count(*)
    from public.entries
    where id='99000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'A Place does not create a duplicate canonical Entry'
);

select is(
  (
    select count(*)
    from public.locations
    where id='99000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'A Place does not automatically create a Location'
);

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
  (select count(*) from public.places_workspace(50,0)),
  1::bigint,
  'Places remain available in their standalone Focused View'
);

select is(
  (
    select linked_entry_count || ':' || home_count
    from public.places_workspace(50,0)
    where place_id='99000000-0000-4000-8000-000000000001'
  ),
  '0:0',
  'Standalone Places expose no cross-Focused-View relationships'
);

select is(
  (
    select count(*)
    from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)
    where canonical_item_id='99000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'Places do not appear as duplicate Library items'
);

select is(
  (
    select count(*)
    from public.search_wiki_items('Pine Street')
    where entry_id='99000000-0000-4000-8000-000000000003'
  ),
  1::bigint,
  'Linked Location details contribute searchable Wiki Item context'
);

select is(
  (
    select count(*)
    from public.save_place(
      'Updated café','Near the theater',null,null,null,null,null,'Still personal.',
      array[]::uuid[],'99000000-0000-4000-8000-000000000001',1
    )
  ),
  1::bigint,
  'A Place can be edited independently'
);

select throws_ok(
  $$select * from public.save_place(
    'Invalid linked Place',null,null,null,null,null,null,null,
    array['99000000-0000-4000-8000-000000000003']::uuid[],null,null
  )$$,
  '22023',
  'place_relationships_removed',
  'Place writers reject cross-Focused-View relationships'
);

select is(
  (
    select count(*)
    from public.trash_place('99000000-0000-4000-8000-000000000001',2)
  ),
  1::bigint,
  'An independent Place can move to Trash without unlinking other records'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000123',true);
select is(
  (select count(*) from public.locations),
  0::bigint,
  'Location RLS remains owner scoped'
);
select is(
  (select count(*) from public.places_workspace(50,0)),
  0::bigint,
  'Standalone Place browsing remains owner scoped'
);

reset role;
select * from finish();
rollback;
