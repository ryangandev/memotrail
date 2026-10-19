begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000109','wiki-workspace-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000110','wiki-workspace-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype) values
  ('98200000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000109','Morning reflection','Learned to pause.','entry','entry'),
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','Learn Spanish','Practice every day.','entry','entry'),
  ('98200000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000110','Foreign item','Hidden.','entry','entry'),
  ('98200000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000109','  ','A tagged capture without a title.','entry','entry'),
  ('98200000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000109',' ','Another capture with a blank title.','entry','entry');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone) values
  ('98200000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000109',null,'A quick capture to read later.','entry','entry','2026-10-18T19:00:00Z','day','America/Los_Angeles');
insert into public.tags(id,owner_id,name) values
  ('98200000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000109','sorted');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('98200000-0000-4000-8000-000000000006','98200000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000109');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109','Harbor flat','Lived near the marina.','entry','chapter');
update public.entries set is_first_time = true where id = '98200000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000109',true);

select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  6::bigint,
  'The Life Wiki page lists every Entry, Chapters included'
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
select hasnt_function(
  'public', 'wiki_items_workspace',
  array['text','text[]','text[]','integer','integer','boolean'],
  'The earlier six-argument workspace is retired'
);
select is(
  (select is_first_time from public.wiki_items_workspace('Spanish',array[]::text[],array[]::text[],50,0)),
  true,
  'Library rows carry the First Time mark'
);
select is(
  (select count(*) from public.wiki_items_workspace('',array['entry'],array[]::text[],50,0)),
  6::bigint,
  'Kind filtering names the one Entry Kind'
);
select throws_ok(
  $$select * from public.wiki_items_workspace('',array['entity'],array[]::text[],50,0)$$,
  '22023',
  'invalid_wiki_items_page',
  'The Entity Kind is no longer a filter'
);
select is(
  (select title from public.wiki_items_workspace('',array[]::text[],array['chapter'],50,0)),
  'Harbor flat',
  'Subtype filtering selects Chapters'
);
select is(
  (select item_kind || ':' || item_subtype from public.wiki_items_workspace('marina',array[]::text[],array[]::text[],50,0)),
  'entry:chapter',
  'Keyword lookup searches Chapter writing'
);

select throws_ok(
  $$select * from public.wiki_items_workspace('',array['invalid'],array[]::text[],50,0)$$,
  '22023',
  'invalid_wiki_items_page',
  'Unsupported Kind filters are rejected'
);
select throws_ok(
  $$select * from public.wiki_items_workspace('',array['goal'],array[]::text[],50,0)$$,
  '22023',
  'invalid_wiki_items_page',
  'Someday is no longer a Kind to filter by'
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

select * from finish();
rollback;
