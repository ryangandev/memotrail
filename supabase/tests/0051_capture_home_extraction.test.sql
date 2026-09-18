begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000111','capture-home-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000112','capture-home-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,inbox_status,date_precision,occurred_timezone
) values (
  '98400000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000111',
  'Moved to Oakland',
  'The apartment near the lake.',
  'unreviewed',
  'unknown',
  'America/Los_Angeles'
);

insert into public.collections(id,owner_id,name) values
  ('98400000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000111','California');
insert into public.tags(id,owner_id,name) values
  ('98400000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000111','Moving');
insert into public.entry_collections(entry_id,collection_id,owner_id) values
  ('98400000-0000-4000-8000-000000000001','98400000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000111');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('98400000-0000-4000-8000-000000000001','98400000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000111');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000111',true);

select is(
  public.capture_extraction_source('98400000-0000-4000-8000-000000000001')->>'title',
  'Moved to Oakland',
  'The dedicated form can load the owned raw Capture'
);
select is(
  public.capture_extraction_source('98400000-0000-4000-8000-000000000001')->'collection_names'->>0,
  'California',
  'The extraction source includes active Collections'
);
select is(
  public.capture_extraction_source('98400000-0000-4000-8000-000000000001')->'tag_names'->>0,
  'Moving',
  'The extraction source includes tags'
);

select ok(
  (select home_entry_id is not null from public.extract_capture_to_home(
    '98400000-0000-4000-8000-000000000001',1,
    'Lake Merritt apartment','The apartment near the lake.',
    '2024-05-01 07:00:00+00',null,'month',null,'America/Los_Angeles',
    null,'Lake Merritt apartment','123 Grand Ave','Oakland','California','US',
    37.8116,-122.2646,null,'A new job',null,
    array['California'],array['Moving']
  )),
  'Extraction creates a Home through the specialized contract'
);

select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98400000-0000-4000-8000-000000000001'),
  'capture:source_capture:organized',
  'The original Capture is preserved and leaves Inbox as provenance'
);
select is(
  (select item_kind || ':' || item_subtype
   from public.entries
   where id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98400000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'entity:home',
  'The durable target is a Home Entity'
);
select is(
  (select title || ':' || body from public.entries
   where id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98400000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'Lake Merritt apartment:The apartment near the lake.',
  'The specialized form controls the Home content'
);
select is(
  (select locations.name || ':' || locations.city || ':' || homes.move_in_reason
   from public.homes
   join public.locations on locations.id=homes.place_id and locations.owner_id=homes.owner_id
   where homes.entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98400000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'Lake Merritt apartment:Oakland:A new job',
  'Home and Location-specific facts are saved'
);
select is(
  (select count(*) from public.entry_links
   where owner_id='10000000-0000-0000-0000-000000000111'
     and (source_entry_id='98400000-0000-4000-8000-000000000001'
       or target_entry_id='98400000-0000-4000-8000-000000000001')
     and relationship in ('derived','derived_from')),
  2::bigint,
  'Both the Capture and Home can discover their provenance'
);
select ok(
  public.capture_extraction_source('98400000-0000-4000-8000-000000000001') is null,
  'An organized source is no longer offered as a new handoff'
);

select ok(
  (select home_entry_id is not null from public.extract_capture_to_home(
    '98400000-0000-4000-8000-000000000001',1,
    'Lake Merritt apartment','The apartment near the lake.',
    '2024-05-01 07:00:00+00',null,'month',null,'America/Los_Angeles',
    null,'Lake Merritt apartment','123 Grand Ave','Oakland','California','US',
    37.8116,-122.2646,null,'A new job',null,
    array['California'],array['Moving']
  )),
  'A lost-response retry finds the existing Home'
);
select is(
  (select count(*) from public.homes where owner_id='10000000-0000-0000-0000-000000000111'),
  1::bigint,
  'Retrying cannot duplicate the Home'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000112',true);
select is(
  (select count(*) from public.extract_capture_to_home(
    '98400000-0000-4000-8000-000000000001',1,
    'Foreign Home','No access',null,null,'unknown',null,'UTC',
    null,'Foreign Place',null,null,null,null,null,null,null,null,null,'{}','{}'
  )),
  0::bigint,
  'Another owner cannot extract from the Capture'
);

reset role;
select ok(
  not has_function_privilege('anon','public.capture_extraction_source(uuid)','execute'),
  'Anonymous source loading is denied'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.extract_capture_to_home(uuid,integer,text,text,timestamp with time zone,timestamp with time zone,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[])',
    'execute'
  ),
  'Anonymous Home extraction is denied'
);

select * from finish();
rollback;
