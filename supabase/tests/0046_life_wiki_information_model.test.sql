begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000103','life-wiki-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000104','life-wiki-other@memotrail.local');

select has_column('public','entries','item_kind','Entries distinguish Entry from focused Entity and Goal records');
select has_column('public','entries','item_subtype','Entries retain only focused structural forms');
select hasnt_column('public','entries','entry_type','Entries no longer expose the transitional Entry type');

insert into public.entries(id,owner_id,body,item_kind,item_subtype,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000103','A raw thought','entry','entry','unreviewed','unknown'),
  ('97000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000103','An organized note','entry','entry','organized','unknown'),
  ('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103','Home facts','entity','home','organized','unknown'),
  ('97000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000103','A first','entry','first_time','organized','unknown');

select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000001'),
  'entry:entry',
  'A raw thought is an unreviewed Entry'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000002'),
  'entry:entry',
  'An organized note is an Entry'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000003'),
  'entity:home',
  'A Home keeps a focused Entity form'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000004'),
  'entry:first_time',
  'A First Time keeps a focused Entry form'
);

insert into public.homes(entry_id,owner_id)
values('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000103',true);

select is(
  (select item_kind || ':' || item_subtype
   from public.organize_capture('97000000-0000-4000-8000-000000000001',1,'entry','entry')),
  'entry:entry',
  'Inbox organization finishes an Entry without a type selection'
);

insert into public.entries(id,owner_id,title,body,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000010',auth.uid(),'A very good day','I felt happy today.','unreviewed','unknown');

select is(
  (select item_kind || ':' || item_subtype
   from public.organize_capture('97000000-0000-4000-8000-000000000010',1,'entry','entry')),
  'entry:entry',
  'A raw Capture can be finalized as an Entry'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'entry:entry',
  'The canonical Entry identity is persisted directly'
);

update public.entries
set body='I felt very happy today.'
where id='97000000-0000-4000-8000-000000000010';
select is(
  public.restore_entry_version('97000000-0000-4000-8000-000000000010',2,3),
  4,
  'History restoration succeeds after editing an Entry'
);
select is(
  (select body from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'I felt happy today.',
  'History restoration restores Entry content'
);

insert into public.entries(id,owner_id,body,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000020',auth.uid(),'Bought a white RAV4 and felt excited.','unreviewed','unknown');

create temporary table extracted_item as
select * from public.extract_capture_item(
  '97000000-0000-4000-8000-000000000020',
  1,
  'entry','entry',
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
  'entry:source_capture:organized',
  'Extraction preserves the original as organized provenance'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id=(select item_id from extracted_item)),
  'entry:entry',
  'Extraction creates a distinct Entry'
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

insert into public.entries(id,owner_id,body,item_kind,item_subtype,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000030',auth.uid(),'A longer narrative','entry','entry','organized','unknown');
select is(
  (select item_kind || ':' || item_subtype
   from public.entries where id='97000000-0000-4000-8000-000000000030'),
  'entry:entry',
  'A longer narrative remains an Entry without a Story type'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000104',true);
select is(
  (select count(*) from public.organize_capture('97000000-0000-4000-8000-000000000020',2,'entry','entry')),
  0::bigint,
  'Another owner cannot organize a Capture'
);
select is(
  (select count(*) from public.extract_capture_item(
    '97000000-0000-4000-8000-000000000020',2,'entry','entry','Foreign','Foreign',null,null,'unknown',null,'UTC'
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
