begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000109','wiki-workspace-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000110','wiki-workspace-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status) values
  ('98200000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000109','Morning reflection','Learned to pause.','writing','reflection','organized'),
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','Learn Spanish','Practice every day.','goal','goal','organized'),
  ('98200000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000110','Foreign item','Hidden.','writing','note','organized');
insert into public.goals(entry_id,owner_id,horizon,status) values
  ('98200000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000109','long_term','active');
insert into public.people(id,owner_id,name,relationship_label,notes) values
  ('98200000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000109','Avery','Friend','Met at the marina.');
insert into public.places(id,owner_id,name,city,country,notes) values
  ('98200000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000109','Ocean Beach','San Francisco','USA','Morning walks.');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000109',true);

select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  4::bigint,
  'The Life Wiki page combines Entries, People, and Places'
);
select is(
  (select max(total_count) from public.wiki_items_workspace('',array[]::text[],array[]::text[],2,0)),
  4::bigint,
  'Pagination reports the complete matching count'
);
select is(
  (select count(*) from public.wiki_items_workspace('',array['entity'],array[]::text[],50,0)),
  2::bigint,
  'Kind filtering includes Person and Place Entities'
);
select is(
  (select title from public.wiki_items_workspace('',array[]::text[],array['person'],50,0)),
  'Avery',
  'Subtype filtering selects one Entity preset'
);
select is(
  (select item_kind || ':' || item_subtype from public.wiki_items_workspace('marina',array[]::text[],array[]::text[],50,0)),
  'entity:person',
  'Keyword lookup searches specialized Entity details'
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
