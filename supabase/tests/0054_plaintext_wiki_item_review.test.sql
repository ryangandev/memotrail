begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000117','plaintext-review-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000118','plaintext-review-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,metadata,entry_type,inbox_status,date_precision,occurred_timezone
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
  'standard','unreviewed','unknown','UTC'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000117',true);

select is(
  (select revision from public.review_wiki_item_with_photo_place(
    '98700000-0000-4000-8000-000000000001',1,
    'Morning pages','Edited on iPhone.','writing','journal',
    null,'UTC','{}',array['Morning'],true,null,null,'unknown',null
  )),
  2,
  'A plaintext client classifies and reviews a raw Capture'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98700000-0000-4000-8000-000000000001'),
  'writing:journal:organized',
  'The semantic Kind and subtype are saved atomically'
);
select is(
  (select metadata->'body_rich'->>'text'
   from public.entries where id='98700000-0000-4000-8000-000000000001'),
  'A quiet start.',
  'Rich metadata is preserved for a plaintext client even when plaintext changes'
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

select throws_ok(
  $$select * from public.review_wiki_item_with_photo_place(
    '98700000-0000-4000-8000-000000000001',2,
    'Morning pages','Try to change Kind','event','memory',
    null,'UTC','{}','{}',true,null,null,'unknown',null
  )$$,
  '22023',
  'invalid_item_kind_transition',
  'A plaintext client cannot mutate an established Kind'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000118',true);
select is(
  (select count(*) from public.review_wiki_item_with_photo_place(
    '98700000-0000-4000-8000-000000000001',2,
    'Foreign','No access','writing','journal',
    null,'UTC','{}','{}',true,null,null,'unknown',null
  )),
  0::bigint,
  'Another owner cannot review the Wiki Item'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamp with time zone,text,text[],text[],boolean,timestamp with time zone,text,text,jsonb)',
    'execute'
  ),
  'Anonymous plaintext semantic review is denied'
);

select * from finish();
rollback;
