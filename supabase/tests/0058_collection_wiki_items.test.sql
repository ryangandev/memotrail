begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000122','collection-wiki@memotrail.local');

insert into public.collections(id,owner_id,name) values (
  '98910000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000122',
  'Harbor memories'
);

insert into public.people(id,owner_id,name,notes) values (
  '98910000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000122',
  'Marina',
  'Friend from the harbor.'
);

insert into public.entry_collections(owner_id,entry_id,collection_id)
select
  person.owner_id,
  person.id,
  '98910000-0000-4000-8000-000000000001'::uuid
from public.people as person
where person.id = '98910000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000122',true);

select is(
  (
    select concat_ws('|',item_kind,item_subtype,record_source,record_id::text)
    from public.collection_wiki_items('98910000-0000-4000-8000-000000000001')
  ),
  'entity|person|person|98910000-0000-4000-8000-000000000002',
  'A Collection exposes canonical semantics and the specialized Person routing identity'
);

select is(
  (
    select entry_id
    from public.collection_wiki_items('98910000-0000-4000-8000-000000000001')
  ),
  (
    select id
    from public.people
    where id = '98910000-0000-4000-8000-000000000002'
  ),
  'A Collection uses the same canonical and specialized Person identity'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.collection_wiki_items(uuid,integer,integer)',
    'execute'
  ),
  'Anonymous Collection browsing is denied'
);

select * from finish();
rollback;
