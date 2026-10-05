begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000125','specialized-locations@memotrail.local');

create function pg_temp.provider(provider_id text, formatted text)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'kind','provider','provider','geoapify',
    'providerLocationId',provider_id,
    'formattedAddress',formatted,
    'address','10 Pine Street','city','Philadelphia','region','Pennsylvania',
    'postalCode',null,'country','United States','countryCode','us',
    'latitude',39.9526,'longitude',-75.1652,'timezone','America/New_York',
    'resultType','building','confidence',0.99,'matchType','full_match',
    'dataSource','openstreetmap'
  );
$$;

create function pg_temp.save_first_time(p_id uuid, p_revision integer, p_title text, p_body text, p_location jsonb)
returns table(entry_id uuid, revision integer)
language sql
as $$
  select * from public.save_entry(
    p_id, p_revision, p_title, p_body, null, null, null, 'UTC', null, 'unknown', '{}',
    p_location, null, '{"shape":"moment","lane":"other","isFirstTime":true}'
  );
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000125',true);

select is(
  (select count(*) from pg_temp.save_first_time(
    '99620000-0000-4000-8000-000000000001', null, 'First hike', 'A memory',
    pg_temp.provider('specialized-pine-10','10 Pine Street, Philadelphia')
  )),
  1::bigint,
  'A First Time and provider Location save together'
);

select is(
  (select count(*) from public.save_vehicle_with_location(
    jsonb_build_object(
      'title','Blue Civic','body','A memory','datePrecision','unknown',
      'tagNames',jsonb_build_array()
    ),
    pg_temp.provider('specialized-pine-10','10 Pine Street, Philadelphia')
  )),
  1::bigint,
  'A Vehicle independently saves the same provider result'
);

select is(
  (select count(distinct link.location_id)
   from public.entry_locations as link
   join public.entries as entry on entry.id=link.entry_id
   where entry.title in ('First hike','Blue Civic')
     and link.relationship='primary'),
  2::bigint,
  'The specialized Items own different Location snapshots'
);

select is(
  (select count(*)
   from public.locations
   where provider_location_id='specialized-pine-10'
     and bound_entry_id in (
       select id from public.entries where title in ('First hike','Blue Civic')
     )),
  2::bigint,
  'Each same-address snapshot is bound to its own specialized Item'
);

select is(
  (select count(*) from pg_temp.save_first_time(
    (select id from public.entries where title='First hike'),
    (select revision from public.entries where title='First hike'),
    'First hike', 'A changed memory',
    pg_temp.provider('specialized-market-1','Market Street, Philadelphia')
  )),
  1::bigint,
  'Changing one First Time creates and links a replacement snapshot'
);

select is(
  (
    select location.provider_location_id
    from public.entry_locations as link
    join public.entries as entry on entry.id=link.entry_id
    join public.locations as location on location.id=link.location_id
    where entry.title='Blue Civic' and link.relationship='primary'
  ),
  'specialized-pine-10',
  'The Vehicle retains its independent original snapshot'
);

set constraints all immediate;
set constraints all deferred;
select is(
  (select count(*) from public.locations
   where bound_entry_id=(select id from public.entries where title='First hike')),
  1::bigint,
  'The First Time drops its replaced snapshot'
);

select is(
  (select count(*) from public.save_vehicle_with_location(
    jsonb_build_object(
      'title','Blue Civic','body','A later memory','datePrecision','unknown',
      'tagNames',jsonb_build_array(),
      'id',(select id from public.entries where title='Blue Civic'),
      'revision',(select revision from public.entries where title='Blue Civic')
    ),
    null
  )),
  1::bigint,
  'Removing a Vehicle Location saves atomically with its record'
);

select is(
  (select count(*) from public.entry_locations as link
   join public.entries as entry on entry.id=link.entry_id
   where entry.title='Blue Civic' and link.relationship='primary'),
  0::bigint,
  'Removing the active association clears the Vehicle primary link'
);

set constraints all immediate;
set constraints all deferred;
select is(
  (select count(*) from public.locations
   where bound_entry_id=(select id from public.entries where title='Blue Civic')),
  0::bigint,
  'The removed Vehicle snapshot is dropped'
);

select throws_ok(
  $sql$
    select * from pg_temp.save_first_time(
      '99620000-0000-4000-8000-000000000002', null, 'Should roll back', '',
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
