begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000121','canonical-search@memotrail.local');

insert into public.people(id,owner_id,name,notes) values
  ('98900000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000121','Marina','Met at the harbor');
insert into public.places(id,owner_id,name,address) values
  ('98900000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000121','Harbor','Pier 7');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000121',true);

select is(
  (
    select concat_ws('|',item_kind,item_subtype,record_source,record_id::text)
    from public.search_wiki_items('Marina')
  ),
  'entity|person|person|98900000-0000-4000-8000-000000000001',
  'Canonical search returns Person semantic and specialized routing identities'
);

select is(
  (
    select concat_ws('|',item_kind,item_subtype,record_source,record_id::text)
    from public.search_wiki_items('Pier 7')
  ),
  'entity|place|place|98900000-0000-4000-8000-000000000002',
  'Canonical search indexes Place details and returns its specialized routing identity'
);

select is(
  (select count(*) from public.search_wiki_items('',array['entity'])),
  2::bigint,
  'Entity Kind filtering returns canonical People and Places once'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.search_wiki_items(text,text[],text[],text[],date,date,integer,integer,text)',
    'execute'
  ),
  'Anonymous canonical search is denied'
);

select * from finish();
rollback;
