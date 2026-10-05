begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000117','plaintext-review-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000118','plaintext-review-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,metadata,date_precision,occurred_timezone
) values (
  '98700000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000117',
  'Morning pages',
  'A quiet start.',
  jsonb_build_object(
    'body_rich',
    jsonb_build_object(
      'version','1',
      'text','A quiet start.',
      'document',jsonb_build_object('type','doc','content',jsonb_build_array())
    )
  ),
  'unknown','UTC'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000117',true);

select is(
  (select revision from public.save_entry(
    '98700000-0000-4000-8000-000000000001',1,
    'Morning pages','Edited without formatting.', null,
    null,null,'UTC',null,'unknown',array['Morning'],null, null, null)),
  2,
  'An edit without formatting saves the Entry'
);
select ok(
  not (select metadata ? 'body_rich'
   from public.entries where id='98700000-0000-4000-8000-000000000001'),
  'An edit without formatting drops formatting for the writing it replaced'
);
select is(
  (select count(*)
   from public.entry_tags as membership
   join public.tags as tag
     on tag.id=membership.tag_id and tag.owner_id=membership.owner_id
   where membership.entry_id='98700000-0000-4000-8000-000000000001'
     and tag.name='Morning'),
  1::bigint,
  'Organization is saved through the same transaction'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000118',true);
select is(
  (select count(*) from public.save_entry(
    '98700000-0000-4000-8000-000000000001',2,
    'Foreign','No access', null,
    null,null,'UTC',null,'unknown','{}',null, null, null)),
  0::bigint,
  'Another owner cannot review the Wiki Item'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.save_entry(uuid,integer,text,text,jsonb,timestamptz,timestamptz,text,text,text,text[],jsonb,jsonb,jsonb)',
    'execute'
  ),
  'Anonymous review is denied'
);

select * from finish();
rollback;
