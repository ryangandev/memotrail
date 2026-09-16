begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000111','semantic-search-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000112','semantic-search-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,entry_type,item_kind,item_subtype,inbox_status,date_precision) values
  ('98300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000111','Morning pages','A quiet record.','standard','writing','reflection','organized','unknown'),
  ('98300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000111','A good day','I felt happy.','life_stage','event','memory','organized','unknown'),
  ('98300000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000111','A long story','A deliberately authored narrative.','standard','story','chapter','organized','unknown'),
  ('98300000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000112','Foreign reflection','Private.','standard','writing','reflection','organized','unknown');

insert into public.people(id,owner_id,name,notes) values
  ('98300000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000111','Marina mentor','Helped at the marina.');
insert into public.places(id,owner_id,name,notes) values
  ('98300000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000111','Marina dock','A favorite marina.');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000111',true);

select is(
  (select count(*) from public.search_entries_with_occurrence('',array['writing'])),
  1::bigint,
  'Kind filtering returns every matching Writing subtype'
);
select is(
  (select title from public.search_entries_with_occurrence('',array['memory'])),
  'A good day',
  'Subtype filtering finds a Memory stored under the life_stage compatibility type'
);
select is(
  (select title from public.search_entries_with_occurrence('',array['event'])),
  'A good day',
  'Kind filtering finds the Event without relying on its legacy type'
);
select is(
  (select count(*) from public.search_entries_with_occurrence('',array['standard'])),
  2::bigint,
  'Older clients can still filter by the legacy Standard type'
);
select is(
  (select title from public.search_entries_with_occurrence('reflection')),
  'Morning pages',
  'Keyword search indexes semantic subtypes'
);
select is(
  jsonb_array_length(public.archive_search_evidence(array['marina'],array['entity'])->'people'),
  1,
  'AI Entity evidence includes matching People'
);
select is(
  jsonb_array_length(public.archive_search_evidence(array['marina'],array['entity'])->'places'),
  1,
  'AI Entity evidence includes matching Places'
);
select is(
  jsonb_array_length(public.archive_search_evidence(array['marina'],array['person'])->'places'),
  0,
  'A Person subtype filter does not leak Place evidence'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000112',true);
select is(
  (select count(*) from public.search_entries_with_occurrence('',array['writing'])),
  1::bigint,
  'Semantic search remains owner scoped'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text)',
    'execute'
  ),
  'Anonymous semantic search is denied'
);

select * from finish();
rollback;
