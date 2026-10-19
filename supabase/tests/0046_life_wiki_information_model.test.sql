begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000103','life-wiki-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000104','life-wiki-other@memotrail.local');

select has_column('public','entries','item_kind','Entries keep one Kind');
select has_column('public','entries','item_subtype','Entries are either ordinary or a Chapter');
select hasnt_column('public','entries','entry_type','Entries no longer expose the transitional Entry type');

insert into public.entries(id,owner_id,body,item_kind,item_subtype,date_precision) values
  ('97000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000103','A raw thought','entry','entry','unknown'),
  ('97000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000103','An organized note','entry','entry','unknown'),
  ('97000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000103','Home facts','entry','chapter','unknown');

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
  'entry:chapter',
  'A Chapter is an Entry with the chapter subtype'
);
select throws_ok(
  $$update public.entries set item_subtype = 'first_time' where id = '97000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'A First Time is a mark on an Entry, not a separate form'
);

select throws_ok(
  $$update public.entries set item_kind = 'entity' where id = '97000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'The Entity Kind is retired'
);
select throws_ok(
  $$update public.entries set item_subtype = 'home' where id = '97000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'A Home is a Chapter, not a separate form'
);

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

insert into public.entries(id,owner_id,body,item_kind,item_subtype,date_precision) values
  ('97000000-0000-4000-8000-000000000030',auth.uid(),'A longer narrative','entry','entry','unknown');
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
