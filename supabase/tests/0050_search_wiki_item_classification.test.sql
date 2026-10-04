begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000111','semantic-search-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000112','semantic-search-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision) values
  ('98300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000111','Morning pages','A quiet record.','entry','entry','organized','unknown'),
  ('98300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000111','A good day','I felt happy.','entry','entry','organized','unknown'),
  ('98300000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000111','A long story','A deliberately authored narrative.','entry','entry','organized','unknown'),
  ('98300000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000112','Foreign reflection','Private.','entry','entry','organized','unknown');

insert into public.tags(id,owner_id,name) values
  ('98300000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000111','Reflection'),
  ('98300000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000111','Memory'),
  ('98300000-0000-4000-8000-000000000013','10000000-0000-0000-0000-000000000111','Story'),
  ('98300000-0000-4000-8000-000000000014','10000000-0000-0000-0000-000000000112','Reflection');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('98300000-0000-4000-8000-000000000001','98300000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000111'),
  ('98300000-0000-4000-8000-000000000002','98300000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000111'),
  ('98300000-0000-4000-8000-000000000003','98300000-0000-4000-8000-000000000013','10000000-0000-0000-0000-000000000111'),
  ('98300000-0000-4000-8000-000000000004','98300000-0000-4000-8000-000000000014','10000000-0000-0000-0000-000000000112');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status) values
  ('98300000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000111','Harbor flat','Lived by the marina.','entity','home','organized');
insert into public.homes(entry_id,owner_id) values
  ('98300000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000111');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000111',true);

select is(
  (select count(*) from public.search_wiki_items('',array['entry'])),
  3::bigint,
  'Entry filtering returns every ordinary Entry'
);
select is(
  (select title from public.search_wiki_items('',array[]::text[],array['Memory'])),
  'A good day',
  'Tag filtering finds a Memory Entry'
);
select is(
  (select title from public.search_wiki_items('happy',array['entry'])),
  'A good day',
  'Entry filtering and keyword search find the dated memory'
);
select is(
  (select count(*) from public.search_wiki_items('',array[]::text[],array['Story'])),
  1::bigint,
  'Story is searchable as a tag'
);
select is(
  (select title from public.search_wiki_items('reflection')),
  'Morning pages',
  'Keyword search indexes descriptive tags'
);
select is(
  public.archive_wiki_search_evidence(array['marina'],array['entity'])->'entries'->0->>'title',
  'Harbor flat',
  'AI Entity evidence includes matching Entities'
);
select ok(
  not (public.archive_wiki_search_evidence(array['marina'],array['entity']) ? 'places'),
  'AI evidence has no authored Place source'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000112',true);
select is(
  (select count(*) from public.search_wiki_items('',array['entry'])),
  1::bigint,
  'Entry search remains owner scoped'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.search_wiki_items(text,text[],text[],date,date,integer,integer,text)',
    'execute'
  ),
  'Anonymous semantic search is denied'
);

select * from finish();
rollback;
