begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000109','wiki-workspace-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000110','wiki-workspace-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status) values
  ('98200000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000109','Morning reflection','Learned to pause.','entry','entry','organized'),
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','Learn Spanish','Practice every day.','goal','goal','organized'),
  ('98200000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000110','Foreign item','Hidden.','entry','entry','organized'),
  ('98200000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000109','Inbox-only thought','Only saved to Inbox so far.','entry','entry','unreviewed');
insert into public.goals(entry_id,owner_id,horizon,status) values
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','long_term','active');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109','Harbor flat','Lived near the marina.','entity','home','organized');
insert into public.homes(entry_id,owner_id) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000109',true);

select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  3::bigint,
  'The Life Wiki page combines canonical Entries, Entities, and Goals'
);
select is(
  (select max(total_count) from public.wiki_items_workspace('',array[]::text[],array[]::text[],2,0)),
  3::bigint,
  'Pagination counts only organized Library items'
);
select is(
  (select count(*) from public.wiki_items_workspace('Inbox-only',array[]::text[],array[]::text[],50,0)),
  0::bigint,
  'Library keyword search excludes unreviewed Inbox captures'
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
select is(
  (select record_source from public.wiki_items_workspace('pause',array[]::text[],array[]::text[],50,0)),
  'entry',
  'Keyword lookup searches canonical Wiki Item writing'
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

select * from finish();
rollback;
