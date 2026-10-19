begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000183','library-order-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000184','library-order-other@memotrail.local');

-- Each Entry was last changed in a different order from when it happened, so an order by
-- edit time and an order by life date disagree everywhere.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,is_first_time,date_precision,occurred_start,occurred_end,occurred_label,occurred_timezone,updated_at) values
  ('98300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000183','Final round','Four interviews.','entry','entry',false,'day','2026-10-17T12:00:00Z',null,null,'UTC','2026-01-01T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000183','Cooking for twelve','Dumplings.','entry','entry',true,'exact','2026-10-14T19:30:00Z',null,null,'UTC','2026-10-18T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000183','2026 job search','Leaving consulting.','entry','chapter',false,'month','2026-01-01T12:00:00Z',null,null,'UTC','2026-10-19T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000183','A year in Philadelphia','Classes.','entry','entry',false,'year','2024-01-01T12:00:00Z',null,null,'UTC','2025-06-01T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000183','Learning to climb','Bouldering.','entry','entry',false,'approximate','2025-09-01T12:00:00Z',null,'Fall 2025','UTC','2024-02-01T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000183','Childhood summer','At the lake.','entry','entry',false,'age',null,null,'When I was 12','UTC','2026-10-10T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000183','Someday note','No date.','entry','entry',false,'unknown',null,null,null,'UTC','2026-03-01T00:00:00Z'),
  ('98300000-0000-4000-8000-000000000008','10000000-0000-0000-0000-000000000184','Foreign','Hidden.','entry','entry',false,'day','2027-01-01T12:00:00Z',null,null,'UTC','2027-01-01T00:00:00Z');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000183',true);

select results_eq(
  $$select title from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)$$,
  $$values
    ('Final round'::text), ('Cooking for twelve'), ('2026 job search'),
    ('Learning to climb'), ('A year in Philadelphia'),
    ('Childhood summer'), ('Someday note')$$,
  'Library lists Entries by the date they happened, newest first, and undated ones last, the most recently changed first'
);

select results_eq(
  $$select title from public.wiki_items_workspace('',array[]::text[],array[]::text[],3,3)$$,
  $$values ('Learning to climb'::text), ('A year in Philadelphia'), ('Childhood summer')$$,
  'A later Library page continues the same order'
);

select results_eq(
  $$select title from public.wiki_items_workspace('',array[]::text[],array['chapter'],50,0)$$,
  $$values ('2026 job search'::text)$$,
  'A Chapter is listed where it began'
);

-- An edit changes when an Entry was last touched, not where Library lists it.
reset role;
update public.entries set body = 'Classes and long walks.'
  where id = '98300000-0000-4000-8000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000183',true);
select is(
  (select title from public.wiki_items_workspace('',array[]::text[],array[]::text[],1,0)),
  'Final round',
  'Editing an older Entry does not move it to the top'
);

-- Library's filters search with the "newest" order, which keeps the same life-date order.
select results_eq(
  $$select title from public.search_wiki_items(
      p_item_classifications => array['entry'], p_order => 'newest', p_limit => 50
    )$$,
  $$values
    ('Final round'::text), ('Cooking for twelve'), ('Learning to climb'),
    ('A year in Philadelphia'), ('Childhood summer'), ('Someday note')$$,
  'Filtered search ordered by newest lists dated Entries first and undated ones last'
);
select results_eq(
  $$select title from public.search_wiki_items(
      p_item_classifications => array['first_time', 'chapter'], p_order => 'newest', p_limit => 50
    )$$,
  $$values ('Cooking for twelve'::text), ('2026 job search')$$,
  'Chapters and First Times filtered together keep the life-date order'
);
select results_eq(
  $$select title from public.search_wiki_items(
      p_item_classifications => array['entry'], p_order => 'oldest', p_limit => 50
    )$$,
  $$values
    ('A year in Philadelphia'::text), ('Learning to climb'), ('Cooking for twelve'),
    ('Final round'), ('Childhood summer'), ('Someday note')$$,
  'The oldest order is unchanged: earliest first, undated last'
);
select is(
  (select title from public.search_wiki_items(p_query => 'interviews', p_limit => 1)),
  'Final round',
  'Relevance still ranks keyword matches'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000184',true);
select results_eq(
  $$select title from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)$$,
  $$values ('Foreign'::text)$$,
  'Library stays owner scoped'
);

reset role;
select has_function(
  'public', 'wiki_items_workspace',
  array['text','text[]','text[]','integer','integer'],
  'iOS still calls the five-argument Library workspace'
);
select has_function(
  'public', 'search_wiki_items',
  array['text','text[]','text[]','date','date','integer','integer','text','real[]','text','real'],
  'Search keeps its arguments'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.wiki_items_workspace(text,text[],text[],integer,integer)',
    'execute'
  ),
  'Anonymous Library browsing is still denied'
);

select * from finish();
rollback;
