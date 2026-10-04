begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000113','capture-vehicle-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000114','capture-vehicle-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,inbox_status,date_precision
) values (
  '98500000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000113',
  'My first EV',
  'Quiet drives around the bay.',
  'unreviewed',
  'unknown'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000113',true);

select ok(
  (select vehicle_entry_id is not null from public.extract_capture_to_vehicle(
    '98500000-0000-4000-8000-000000000001',1,
    'Pearl','Quiet drives around the bay.',
    '2025-06-01 07:00:00+00',null,'month',null,'America/Los_Angeles',
    'Toyota','RAV4',2025,'White Pearl',array['EV']
  )),
  'Extraction creates a Vehicle through the specialized contract'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98500000-0000-4000-8000-000000000001'),
  'entry:source_capture:organized',
  'The original Capture is preserved as provenance'
);
select is(
  (select item_kind || ':' || item_subtype
   from public.entries
   where id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98500000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'entity:vehicle',
  'The durable target is a Vehicle Entity'
);
select is(
  (select make || ':' || model || ':' || model_year || ':' || color
   from public.vehicles
   where entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98500000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'Toyota:RAV4:2025:White Pearl',
  'Vehicle-specific facts are saved'
);
select is(
  (select count(*) from public.entry_links
   where owner_id='10000000-0000-0000-0000-000000000113'
     and (source_entry_id='98500000-0000-4000-8000-000000000001'
       or target_entry_id='98500000-0000-4000-8000-000000000001')
     and relationship in ('derived','derived_from')),
  2::bigint,
  'Both the Capture and Vehicle can discover their provenance'
);
select ok(
  (select vehicle_entry_id is not null from public.extract_capture_to_vehicle(
    '98500000-0000-4000-8000-000000000001',1,
    'Pearl','Quiet drives around the bay.',
    '2025-06-01 07:00:00+00',null,'month',null,'America/Los_Angeles',
    'Toyota','RAV4',2025,'White Pearl',array['EV']
  )),
  'A lost-response retry finds the existing Vehicle'
);
select is(
  (select count(*) from public.vehicles where owner_id='10000000-0000-0000-0000-000000000113'),
  1::bigint,
  'Retrying cannot duplicate the Vehicle'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000114',true);
select is(
  (select count(*) from public.extract_capture_to_vehicle(
    '98500000-0000-4000-8000-000000000001',1,
    'Foreign Vehicle','No access',null,null,'unknown',null,'UTC',
    null,null,null,null,'{}'
  )),
  0::bigint,
  'Another owner cannot extract from the Capture'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.extract_capture_to_vehicle(uuid,integer,text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text[])',
    'execute'
  ),
  'Anonymous Vehicle extraction is denied'
);

select * from finish();
rollback;
