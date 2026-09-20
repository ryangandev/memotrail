begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000124','location-cow@memotrail.local');

insert into public.locations(
  id,owner_id,name,formatted_address,address,city,region,country,latitude,longitude
) values (
  '99100000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000124',
  'Shared Location',
  '10 Pine Street, Philadelphia, Pennsylvania, USA',
  '10 Pine Street',
  'Philadelphia',
  'Pennsylvania',
  'USA',
  39.952600,
  -75.165200
);

insert into public.entries(
  id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision
) values
  (
    '99100000-0000-4000-8000-000000000002',
    '10000000-0000-0000-0000-000000000124',
    'First memory','One','writing','note','organized','unknown'
  ),
  (
    '99100000-0000-4000-8000-000000000003',
    '10000000-0000-0000-0000-000000000124',
    'Second memory','Two','writing','note','organized','unknown'
  );

insert into public.entry_places(entry_id,place_id,owner_id,relationship) values
  (
    '99100000-0000-4000-8000-000000000002',
    '99100000-0000-4000-8000-000000000001',
    '10000000-0000-0000-0000-000000000124',
    'primary'
  ),
  (
    '99100000-0000-4000-8000-000000000003',
    '99100000-0000-4000-8000-000000000001',
    '10000000-0000-0000-0000-000000000124',
    'primary'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000124',true);

select is(
  (
    select count(*)
    from public.review_wiki_item_with_location_rich(
      '99100000-0000-4000-8000-000000000002',1,
      'First memory','One','writing','note',null,'UTC',
      array[]::text[],array[]::text[],false,null,null,'unknown',null,
      jsonb_build_object(
        'kind','provider',
        'provider','geoapify',
        'providerLocationId','geoapify-pine-20',
        'name','20 Pine Street',
        'formattedAddress','20 Pine Street, Philadelphia, PA 19107, USA',
        'address','20 Pine Street',
        'city','Philadelphia',
        'region','Pennsylvania',
        'postalCode','19107',
        'country','United States',
        'countryCode','us',
        'latitude',39.951,
        'longitude',-75.162,
        'timezone','America/New_York',
        'resultType','building',
        'confidence',0.98,
        'matchType','full_match',
        'dataSource','openstreetmap'
      ),
      null
    )
  ),
  1::bigint,
  'A provider Location can replace one Entry primary Location atomically'
);

select is(
  (
    select place_id
    from public.entry_places
    where entry_id='99100000-0000-4000-8000-000000000003'
      and relationship='primary'
  ),
  '99100000-0000-4000-8000-000000000001'::uuid,
  'The other Entry keeps the original shared Location'
);

select is(
  (
    select name
    from public.locations
    where id='99100000-0000-4000-8000-000000000001'
  ),
  'Shared Location',
  'The original shared Location remains unchanged'
);

select is(
  (
    select count(*)
    from public.locations
    where owner_id='10000000-0000-0000-0000-000000000124'
      and provider='geoapify'
      and provider_location_id='geoapify-pine-20'
  ),
  1::bigint,
  'Provider identity is stored once for owner-scoped reuse'
);

select is(
  (
    select count(*)
    from public.review_wiki_item_with_location_rich(
      '99100000-0000-4000-8000-000000000002',1,
      'Stale memory','One','writing','note',null,'UTC',
      array[]::text[],array[]::text[],false,null,null,'unknown',null,
      jsonb_build_object(
        'kind','provider','provider','geoapify',
        'providerLocationId','geoapify-stale-result',
        'name','Stale result','formattedAddress','Stale result, Philadelphia',
        'address','Stale result','city','Philadelphia','region',null,
        'postalCode',null,'country',null,'countryCode',null,
        'latitude',39.95,'longitude',-75.16,'timezone',null,
        'resultType',null,'confidence',null,'matchType',null,'dataSource',null
      ),
      null
    )
  ),
  0::bigint,
  'A stale Entry revision cannot save a different Location'
);

select is(
  (
    select count(*)
    from public.locations
    where owner_id='10000000-0000-0000-0000-000000000124'
      and provider_location_id='geoapify-stale-result'
  ),
  0::bigint,
  'A stale Entry revision does not leave an unattached provider Location'
);

select is(
  (
    select primary_location->>'name'
    from (select public.editable_entry('99100000-0000-4000-8000-000000000002') as item) source,
      lateral (select source.item->'primary_location' as primary_location) location
  ),
  '20 Pine Street',
  'The generic editor loads the current primary Location'
);

select is(
  (select count(*) from public.search_locations('Pine',7)),
  2::bigint,
  'Saved Location search covers names and formatted addresses'
);

select is(
  (
    select count(*)
    from public.save_home_entry_with_occurrence(
      'Forked Home','Home memory',null,null,'unknown',null,'UTC',
      '99100000-0000-4000-8000-000000000001',
      'My Pine Street home','10 Pine Street','Philadelphia','Pennsylvania','USA',
      39.952600,-75.165200,'Only this Home uses this note',null,null,
      array[]::text[],array[]::text[],null,null
    )
  ),
  1::bigint,
  'Editing shared Location facts through Home creates a Home successfully'
);

select isnt(
  (
    select home.place_id
    from public.homes as home
    join public.entries as entry on entry.id = home.entry_id
    where entry.title = 'Forked Home'
      and entry.owner_id = '10000000-0000-0000-0000-000000000124'
  ),
  '99100000-0000-4000-8000-000000000001'::uuid,
  'A Home edit forks a new Location rather than mutating the shared one'
);

select is(
  (
    select name || ':' || coalesce(notes, '')
    from public.locations
    where id='99100000-0000-4000-8000-000000000001'
  ),
  'Shared Location:',
  'Home copy-on-write leaves the shared Location facts untouched'
);

-- save_location is internal to the privileged photo-review writer.
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000124',true);

select isnt(
  (
    select place_id
    from public.save_location(
      'Photo-derived address','12 Pine Street','Philadelphia',
      'Pennsylvania','USA',39.9526,-75.1652,null,
      array['99100000-0000-4000-8000-000000000002']::uuid[],
      '99100000-0000-4000-8000-000000000001',1
    )
  ),
  '99100000-0000-4000-8000-000000000001'::uuid,
  'Photo-derived Location edits fork instead of mutating a shared row'
);

select is(
  (
    select name from public.locations
    where id='99100000-0000-4000-8000-000000000001'
  ),
  'Shared Location',
  'Photo-derived edits leave the original Location unchanged'
);

set local role authenticated;

select is(
  (
    select count(*)
    from public.save_home_entry_with_occurrence(
      'Provider Home','Located by address search',null,null,'unknown',null,'UTC',
      public.resolve_geoapify_location(jsonb_build_object(
        'kind','provider','provider','geoapify',
        'providerLocationId','geoapify-home-city-hall',
        'name','City Hall','formattedAddress','City Hall, Philadelphia, PA, USA',
        'address','City Hall','city','Philadelphia','region','Pennsylvania',
        'postalCode','19107','country','United States','countryCode','us',
        'latitude',39.952,'longitude',-75.163,
        'timezone','America/New_York','resultType','amenity',
        'confidence',0.95,'matchType','full_match','dataSource','openstreetmap'
      )),
      'City Hall','City Hall','Philadelphia','Pennsylvania','United States',
      39.952,-75.163,null,null,null,
      array[]::text[],array[]::text[],null,null
    )
  ),
  1::bigint,
  'A Home can save a provider-backed Location through the existing writer'
);

select is(
  (
    select location.provider_location_id
    from public.homes as home
    join public.entries as entry on entry.id = home.entry_id
    join public.locations as location on location.id = home.place_id
    where entry.title = 'Provider Home'
      and entry.owner_id = '10000000-0000-0000-0000-000000000124'
  ),
  'geoapify-home-city-hall',
  'The Home keeps the Geoapify identity and structured Location data'
);

select ok(
  not has_table_privilege('authenticated','public.locations','update'),
  'Authenticated clients cannot mutate Location facts through the table API'
);

reset role;

select * from finish();
rollback;
