begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000103','life-wiki-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000104','life-wiki-other@memotrail.local');

select has_column('public','entries','item_kind','Entries expose a structural Wiki Item kind');
select has_column('public','entries','item_subtype','Entries expose a compatible preset subtype');

insert into public.entries(id,owner_id,body,entry_type,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000103','A raw thought','standard','unreviewed','unknown'),
  ('97000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000103','An older organized note','standard','organized','unknown'),
  ('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103','Home facts','home','organized','unknown'),
  ('97000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000103','A first','first_time','organized','unknown');

select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000001'),
  'capture:quick_capture',
  'An older unreviewed Standard insert becomes a raw Capture'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000002'),
  'writing:note',
  'An older organized Standard insert remains Writing'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000003'),
  'entity:home',
  'A Home is classified as an Entity rather than a Chapter'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000004'),
  'event:first_time',
  'A First Time is classified as an Event'
);

insert into public.homes(entry_id,owner_id)
values('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000103',true);

update public.entries
set inbox_status='organized'
where id='97000000-0000-4000-8000-000000000001';
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000001'),
  'writing:note',
  'An older Done action finalizes a simple Capture as Writing'
);

insert into public.entries(id,owner_id,title,body,entry_type,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000010',auth.uid(),'A very good day','I felt happy today.','standard','unreviewed','unknown');

select is(
  (select item_kind || ':' || item_subtype
   from public.organize_capture('97000000-0000-4000-8000-000000000010',1,'event','memory')),
  'event:memory',
  'A raw Capture can be finalized as an Event'
);
select is(
  (select entry_type from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'life_stage',
  'The compatibility Entry type follows the new Event identity'
);

update public.entries
set item_subtype='milestone'
where id='97000000-0000-4000-8000-000000000010';
select is(
  public.restore_entry_version('97000000-0000-4000-8000-000000000010',2,3),
  4,
  'History restoration succeeds after an Event subtype change'
);
select is(
  (select item_subtype from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'memory',
  'History restoration restores semantic subtype instead of only the legacy type'
);

insert into public.entries(id,owner_id,body,entry_type,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000020',auth.uid(),'Bought a white RAV4 and felt excited.','standard','unreviewed','unknown');

create temporary table extracted_item as
select * from public.extract_capture_item(
  '97000000-0000-4000-8000-000000000020',
  1,
  'event',
  'memory',
  'The day I bought my RAV4',
  'A happy afternoon at the dealership.',
  null,
  null,
  'unknown',
  null,
  'America/Los_Angeles'
);

select is((select capture_revision from extracted_item),2,'Extraction advances the source Capture revision');
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='97000000-0000-4000-8000-000000000020'),
  'capture:source_capture:organized',
  'Extraction preserves the original as organized provenance'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id=(select item_id from extracted_item)),
  'event:memory',
  'Extraction creates a distinct typed Wiki Item'
);
select is(
  (select relationship from public.entry_links
   where source_entry_id='97000000-0000-4000-8000-000000000020'
     and target_entry_id=(select item_id from extracted_item)),
  'derived',
  'Extraction links the result to its source without changing source identity'
);

select throws_ok(
  $$select * from public.organize_capture('97000000-0000-4000-8000-000000000020',2,'entity','vehicle')$$,
  '22023',
  'invalid_capture_organization',
  'Entity creation cannot bypass its specialized editor'
);

insert into public.entries(id,owner_id,body,entry_type,item_kind,item_subtype,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000030',auth.uid(),'A longer narrative','standard','story','chapter','organized','unknown');
select is(
  (select entry_type || ':' || item_kind || ':' || item_subtype
   from public.entries where id='97000000-0000-4000-8000-000000000030'),
  'standard:story:chapter',
  'Stories remain distinct even while older clients see a compatible Standard Entry'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000104',true);
select is(
  (select count(*) from public.organize_capture('97000000-0000-4000-8000-000000000020',2,'writing','note')),
  0::bigint,
  'Another owner cannot organize a Capture'
);
select is(
  (select count(*) from public.extract_capture_item(
    '97000000-0000-4000-8000-000000000020',2,'event','memory','Foreign','Foreign',null,null,'unknown',null,'UTC'
  )),
  0::bigint,
  'Another owner cannot extract from a Capture'
);

reset role;
select ok(
  not has_function_privilege('anon','public.organize_capture(uuid,integer,text,text)','execute'),
  'Anonymous Capture organization is denied'
);
select ok(
  not has_function_privilege('anon','public.extract_capture_item(uuid,integer,text,text,text,text,timestamptz,timestamptz,text,text,text)','execute'),
  'Anonymous Capture extraction is denied'
);

select * from finish();
rollback;
