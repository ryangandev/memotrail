begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000121','canonical-search@memotrail.local');

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype) values
  ('98900000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000121','Marina','Lived by the harbor','entity','home');
insert into public.homes(entry_id,owner_id) values
  ('98900000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000121');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000121',true);

select is(
  (
    select concat_ws('|',item_kind,item_subtype,entry_id::text)
    from public.search_wiki_items('Marina')
  ),
  'entity|home|98900000-0000-4000-8000-000000000001',
  'Canonical search returns Entity semantic and routing identities'
);

select is(
  (select count(*) from public.search_wiki_items('',array['entity'])),
  1::bigint,
  'Entity Kind filtering returns canonical Entities'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.search_wiki_items(text,text[],text[],date,date,integer,integer,text)',
    'execute'
  ),
  'Anonymous canonical search is denied'
);

select * from finish();
rollback;
