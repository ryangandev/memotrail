begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000125','specialized-locations@memotrail.local');

insert into public.locations(
  id,owner_id,name,formatted_address,latitude,longitude
) values (
  '99200000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000125',
  'Shared Location', '10 Pine Street, Philadelphia', 39.9526, -75.1652
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000125',true);

select is(
  (select count(*) from public.save_first_time_with_location(
    jsonb_build_object(
      'title','First hike','body','A memory','datePrecision','unknown',
      'collectionNames',jsonb_build_array(),'tagNames',jsonb_build_array()
    ),
    jsonb_build_object(
      'kind','existing','id','99200000-0000-4000-8000-000000000001',
      'revision',1
    )
  )),
  1::bigint,
  'A First Time and an existing Location save together'
);

select is(
  (select count(*) from public.save_vehicle_with_location(
    jsonb_build_object(
      'title','Blue Civic','body','A memory','datePrecision','unknown',
      'collectionNames',jsonb_build_array(),'tagNames',jsonb_build_array()
    ),
    null,
    jsonb_build_object(
      'kind','existing','id','99200000-0000-4000-8000-000000000001',
      'revision',1
    )
  )),
  1::bigint,
  'A Vehicle can reuse the same Location'
);

select is(
  (select count(*)
   from public.entry_places as link
   where link.place_id = '99200000-0000-4000-8000-000000000001'
     and link.relationship = 'primary'),
  2::bigint,
  'Both specialized Items initially share the Location'
);

select is(
  (select count(*) from public.save_first_time_with_location(
    jsonb_build_object(
      'title','First hike','body','A changed memory',
      'datePrecision','unknown',
      'collectionNames',jsonb_build_array(),'tagNames',jsonb_build_array(),
      'id',(select id from public.entries where title='First hike'),
      'revision',(select revision from public.entries where title='First hike')
    ),
    jsonb_build_object(
      'kind','provider','provider','geoapify',
      'providerLocationId','specialized-market-1',
      'name','Market Street','formattedAddress','Market Street, Philadelphia',
      'address','Market Street','city','Philadelphia','region','Pennsylvania',
      'postalCode',null,'country','United States','countryCode','us',
      'latitude',39.95,'longitude',-75.16,'timezone','America/New_York',
      'resultType','street','confidence',0.9,'matchType','full_match',
      'dataSource','openstreetmap'
    )
  )),
  1::bigint,
  'Changing one First Time resolves a provider Location and relinks only it'
);

select is(
  (select link.place_id
   from public.entry_places as link
   join public.entries as entry on entry.id = link.entry_id
   where entry.title = 'Blue Civic' and link.relationship = 'primary'),
  '99200000-0000-4000-8000-000000000001'::uuid,
  'The Vehicle retains the original shared Location'
);

select is(
  (select location.name from public.locations as location
   where location.id='99200000-0000-4000-8000-000000000001'),
  'Shared Location',
  'The shared geographic facts remain unchanged'
);

select is(
  (select count(*) from public.save_vehicle_with_location(
    jsonb_build_object(
      'title','Blue Civic','body','A later memory','datePrecision','unknown',
      'collectionNames',jsonb_build_array(),'tagNames',jsonb_build_array(),
      'id',(select id from public.entries where title='Blue Civic'),
      'revision',(select revision from public.entries where title='Blue Civic')
    ),
    null,
    null
  )),
  1::bigint,
  'Removing a Vehicle Location saves atomically with its record'
);

select is(
  (select count(*) from public.entry_places as link
   join public.entries as entry on entry.id=link.entry_id
   where entry.title='Blue Civic' and link.relationship='primary'),
  0::bigint,
  'Removing one association does not delete the Location'
);

select is(
  (select count(*) from public.entry_places as link
   join public.entries as entry on entry.id=link.entry_id
   where entry.title='First hike' and link.relationship='primary'),
  1::bigint,
  'The other specialized Item keeps its provider Location'
);

select throws_ok(
  $sql$
    select * from public.save_first_time_with_location(
      jsonb_build_object(
        'title','Should roll back','body','','datePrecision','unknown',
        'collectionNames',jsonb_build_array(),'tagNames',jsonb_build_array()
      ),
      jsonb_build_object(
        'kind','existing','id','99200000-0000-4000-8000-000000000099',
        'revision',1
      )
    )
  $sql$,
  '40001',
  'primary_location_changed',
  'A stale or inaccessible Location rejects the whole specialized save'
);

select is(
  (select count(*) from public.entries where title='Should roll back'),
  0::bigint,
  'A failed Location association does not leave an orphan Wiki Item'
);

select * from finish();
rollback;
