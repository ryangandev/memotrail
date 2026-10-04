begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000124','entry-owned-locations@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,item_kind,item_subtype,date_precision
) values
  ('99100000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000124','First memory','One','entry','entry','unknown'),
  ('99100000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000124','Second memory','Two','entry','entry','unknown');

create function pg_temp.provider(provider_id text, formatted text, latitude numeric, longitude numeric)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'kind','provider','provider','geoapify',
    'providerLocationId',provider_id,
    'formattedAddress',formatted,
    'address','10 Pine Street','city','Philadelphia','region','Pennsylvania',
    'postalCode','19107','country','United States','countryCode','us',
    'latitude',latitude,'longitude',longitude,
    'timezone','America/New_York','resultType','building',
    'confidence',0.98,'matchType','full_match','dataSource','openstreetmap'
  );
$$;

create function pg_temp.review(entry_id uuid, expected_revision integer, location jsonb)
returns bigint
language sql
as $$
  select count(*) from public.save_entry(
    entry_id,expected_revision,
    (select title from public.entries where id=entry_id),
    (select body from public.entries where id=entry_id),null,null,
    null,'UTC',null,'unknown',array[]::text[],location,null, null);
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000124',true);

select is(
  pg_temp.review(
    '99100000-0000-4000-8000-000000000002',1,
    pg_temp.provider('geoapify-pine-10','10 Pine Street, Philadelphia, PA 19107, USA',39.9526,-75.1652)
  ),
  1::bigint,
  'The first Entry saves a provider Location atomically'
);

select is(
  pg_temp.review(
    '99100000-0000-4000-8000-000000000003',1,
    pg_temp.provider('geoapify-pine-10','10 Pine Street, Philadelphia, PA 19107, USA',39.9526,-75.1652)
  ),
  1::bigint,
  'The second Entry independently saves the same provider result'
);

select is(
  (select count(*) from public.locations where provider_location_id='geoapify-pine-10'),
  2::bigint,
  'Provider identity is provenance and does not deduplicate Entry snapshots'
);

select is(
  (select count(distinct location_id) from public.entry_locations where entry_id in ('99100000-0000-4000-8000-000000000002','99100000-0000-4000-8000-000000000003')),
  2::bigint,
  'The two Entries have different Location identities'
);

select is(
  (select count(*) from public.locations where bound_entry_id in ('99100000-0000-4000-8000-000000000002','99100000-0000-4000-8000-000000000003')),
  2::bigint,
  'Each snapshot records its owning Entry'
);

select is(
  (select count(*) from public.locations where formatted_address='10 Pine Street, Philadelphia, PA 19107, USA'),
  2::bigint,
  'Each snapshot keeps the provider address'
);

select throws_ok(
  $$
    insert into public.entry_locations(entry_id,location_id,owner_id,relationship)
    select
      '99100000-0000-4000-8000-000000000003',location_id,
      '10000000-0000-0000-0000-000000000124','primary'
    from public.entry_locations
    where entry_id='99100000-0000-4000-8000-000000000002'
      and relationship='primary'
  $$,
  '23505','location_belongs_to_another_entry',
  'A snapshot cannot be attached to a different Entry'
);

select is(
  pg_temp.review(
    '99100000-0000-4000-8000-000000000002',
    (select revision from public.entries where id='99100000-0000-4000-8000-000000000002'),
    pg_temp.provider('geoapify-pine-20','20 Pine Street, Philadelphia, PA 19107, USA',39.951,-75.162)
  ),
  1::bigint,
  'Changing one Entry creates and links a replacement snapshot'
);

select is(
  (
    select location.provider_location_id
    from public.entry_locations as link
    join public.locations as location on location.id=link.location_id
    where link.entry_id='99100000-0000-4000-8000-000000000003'
      and link.relationship='primary'
  ),
  'geoapify-pine-10',
  'Changing one Entry leaves the other Entry snapshot unchanged'
);

-- Unlinked Locations are dropped at commit.
set constraints all immediate;
set constraints all deferred;
select is(
  (select count(*) from public.locations where bound_entry_id='99100000-0000-4000-8000-000000000002'),
  1::bigint,
  'The replaced snapshot is dropped once nothing links to it'
);

select is(
  pg_temp.review(
    '99100000-0000-4000-8000-000000000002',1,
    pg_temp.provider('geoapify-stale-result','Stale result, Philadelphia',39.95,-75.16)
  ),
  0::bigint,
  'A stale Entry revision cannot save a different Location'
);

select is(
  (select count(*) from public.locations where provider_location_id='geoapify-stale-result'),
  0::bigint,
  'A stale Entry revision leaves no unattached Location'
);

select ok(
  to_regprocedure('public.search_locations(text,integer)') is null,
  'The saved Location search RPC no longer exists'
);

select is(
  (
    select primary_location->>'formatted_address'
    from (select public.editable_entry('99100000-0000-4000-8000-000000000002') as item) source,
      lateral (select source.item->'primary_location' as primary_location) location
  ),
  '20 Pine Street, Philadelphia, PA 19107, USA',
  'The generic editor loads the current Entry-owned snapshot'
);

create function pg_temp.save_precision_home(entry_id uuid, expected_revision integer)
returns jsonb
language sql
as $$
  select to_jsonb(saved) from public.save_home_with_location(
    jsonb_build_object(
      'title', 'High-precision Home',
      'body', '',
      'datePrecision', 'unknown',
      'occurredTimezone', 'UTC',
      'tagNames', jsonb_build_array(),
      'id', entry_id,
      'revision', expected_revision
    ),
    pg_temp.provider(
      'geoapify-high-precision-home',
      '10 Pine Street, Philadelphia, PA 19107, USA',
      39.95261234, -75.16529876
    )
  ) as saved;
$$;

create temporary table precision_home as
select pg_temp.save_precision_home(null, null) as saved;
set constraints all immediate;

select is(
  (select count(*) from public.locations where provider_location_id='geoapify-high-precision-home'),
  1::bigint,
  'A high-precision Home provider result creates only one Location snapshot'
);
select is(
  (select latitude from public.locations where provider_location_id='geoapify-high-precision-home'),
  39.952612::numeric,
  'A Home snapshot stores the rounded latitude without changing provider input'
);
select is(
  (
    select location.bound_entry_id
    from public.locations as location
    where location.provider_location_id='geoapify-high-precision-home'
  ),
  (select (saved->>'entry_id')::uuid from precision_home),
  'The high-precision provider snapshot belongs to its Home'
);

set constraints all deferred;
select ok(
  pg_temp.save_precision_home(
    (select (saved->>'entry_id')::uuid from precision_home),
    (select (saved->>'revision')::integer from precision_home)
  ) is not null,
  'An existing Home can save a high-precision provider Location again'
);
set constraints all immediate;
select is(
  (select count(*) from public.locations where provider_location_id='geoapify-high-precision-home' and bound_entry_id is not null),
  1::bigint,
  'Resaving replaces the Home snapshot instead of keeping both'
);

reset role;

delete from public.entries
where id='99100000-0000-4000-8000-000000000003';

select is(
  (select count(*) from public.locations where bound_entry_id='99100000-0000-4000-8000-000000000003'),
  0::bigint,
  'Permanently deleting an Entry cascades all of its Location snapshots'
);

select * from finish();
rollback;
