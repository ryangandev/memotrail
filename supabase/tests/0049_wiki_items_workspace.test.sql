begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000109','wiki-workspace-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000110','wiki-workspace-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype) values
  ('98200000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000109','Morning reflection','Learned to pause.','entry','entry'),
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','Learn Spanish','Practice every day.','goal','goal'),
  ('98200000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000110','Foreign item','Hidden.','entry','entry'),
  ('98200000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000109','  ','A tagged capture without a title.','entry','entry'),
  ('98200000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000109',' ','Another capture with a blank title.','entry','entry');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone) values
  ('98200000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000109',null,'A quick capture to read later.','entry','entry','2026-10-18T19:00:00Z','day','America/Los_Angeles');
insert into public.tags(id,owner_id,name) values
  ('98200000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000109','sorted');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('98200000-0000-4000-8000-000000000006','98200000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000109');
insert into public.goals(entry_id,owner_id,status) values
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','active');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109','Harbor flat','Lived near the marina.','entity','home');
insert into public.homes(entry_id,owner_id) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000109',true);

select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  6::bigint,
  'The Life Wiki page combines canonical Entries, Entities, and Goals'
);
select is(
  (select max(total_count) from public.wiki_items_workspace('',array[]::text[],array[]::text[],2,0)),
  6::bigint,
  'Pagination counts every Library item'
);
select is(
  (select count(*) from public.wiki_items_workspace('read later',array[]::text[],array[]::text[],50,0)),
  1::bigint,
  'Library keyword search includes new Captures'
);
-- Clients name an untitled Entry by its date, so the workspace returns what they need for it.
select results_eq(
  $$select title, excerpt, occurred_start, date_precision, occurred_timezone
    from public.wiki_items_workspace('read later',array[]::text[],array[]::text[],50,0)$$,
  $$values (''::text, 'A quick capture to read later.'::text, '2026-10-18T19:00:00Z'::timestamptz, 'day'::text, 'America/Los_Angeles'::text)$$,
  'An untitled Entry keeps a blank title and carries its date'
);
select is(
  (select title from public.wiki_items_workspace('blank title',array[]::text[],array[]::text[],50,0)),
  '',
  'A blank title is not replaced by the writing'
);
-- The Web deployed before migration 202610180087 still calls the six-argument
-- workspace until the Web that names untitled Entries by date replaces it.
select is(
  (select pronargdefaults::integer from pg_proc
   where oid = to_regprocedure('public.wiki_items_workspace(text,text[],text[],integer,integer,boolean)')),
  0,
  'The earlier six-argument workspace requires every argument, so PostgREST never finds two matches'
);
select is(
  (select title from public.wiki_items_workspace('read later',array[]::text[],array[]::text[],50,0,false)),
  'A quick capture to read later.',
  'The earlier workspace keeps its earlier title for the Web deployed before the change'
);
select is(
  (select array_agg(item_id::text order by item_id) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0,true)),
  array['98200000-0000-4000-8000-000000000005','98200000-0000-4000-8000-000000000007'],
  'The earlier workspace still lists Entries with neither a title nor a tag'
);
select is(
  (select max(total_count) from public.wiki_items_workspace('',array[]::text[],array[]::text[],1,0,true)),
  2::bigint,
  'The earlier workspace still counts only matching Entries'
);
select throws_ok(
  $$select * from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0,null)$$,
  '22023',
  'invalid_wiki_items_page',
  'The earlier workspace still requires its switch'
);
select is(
  (select count(*) from public.wiki_items_workspace('',array['entity'],array[]::text[],50,0)),
  1::bigint,
  'Kind filtering includes canonical Entities'
);
select is(
  (select title from public.wiki_items_workspace('',array[]::text[],array['home'],50,0)),
  'Harbor flat',
  'Subtype filtering selects one Entity preset'
);
select is(
  (select item_kind || ':' || item_subtype from public.wiki_items_workspace('marina',array[]::text[],array[]::text[],50,0)),
  'entity:home',
  'Keyword lookup searches Entity writing'
);

select throws_ok(
  $$select * from public.wiki_items_workspace('',array['invalid'],array[]::text[],50,0)$$,
  '22023',
  'invalid_wiki_items_page',
  'Unsupported Kind filters are rejected'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000110',true);
select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  1::bigint,
  'The unified workspace remains owner scoped'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.wiki_items_workspace(text,text[],text[],integer,integer)',
    'execute'
  ),
  'Anonymous Life Wiki browsing is denied'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.wiki_items_workspace(text,text[],text[],integer,integer,boolean)',
    'execute'
  ),
  'Anonymous browsing through the earlier workspace is denied'
);

select * from finish();
rollback;
