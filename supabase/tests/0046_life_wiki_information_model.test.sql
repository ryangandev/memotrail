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
  ('97000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000103','A raw thought','entry','entry','organized','unknown'),
  ('97000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000103','An organized note','entry','entry','organized','unknown'),
  ('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103','Home facts','entity','home','organized','unknown'),
  ('97000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000103','A first','entry','first_time','organized','unknown');

select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000001'),
  'entry:entry',
  'A raw thought is an Entry'
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

insert into public.entries(id,owner_id,title,body,date_precision) values
  ('97000000-0000-4000-8000-000000000010',auth.uid(),'A very good day','I felt happy today.','unknown');

select is(
  (select item_kind || ':' || item_subtype from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'entry:entry',
  'A Capture is saved as an Entry without a type selection'
);

update public.entries
set body='I felt very happy today.'
where id='97000000-0000-4000-8000-000000000010';
select is(
  public.restore_entry_version('97000000-0000-4000-8000-000000000010',1,2),
  3,
  'History restoration succeeds after editing an Entry'
);
select is(
  (select body from public.entries where id='97000000-0000-4000-8000-000000000010'),
  'I felt happy today.',
  'History restoration restores Entry content'
);

insert into public.entries(id,owner_id,body,item_kind,item_subtype,inbox_status,date_precision) values
  ('97000000-0000-4000-8000-000000000030',auth.uid(),'A longer narrative','entry','entry','organized','unknown');
select is(
  (select item_kind || ':' || item_subtype
   from public.entries where id='97000000-0000-4000-8000-000000000030'),
  'entry:entry',
  'A longer narrative remains an Entry without a Story type'
);

reset role;
select hasnt_function('public','organize_capture','Inbox organization is retired');
select hasnt_function('public','extract_capture_item','Inbox extraction is retired');

select * from finish();
rollback;
