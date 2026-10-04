begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000105','capture-review-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000106','capture-review-other@memotrail.local');

insert into public.entries(id,owner_id,title,body,inbox_status,date_precision,occurred_timezone) values
  ('98000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000105','Morning pages','A quiet start.','unreviewed','unknown','UTC'),
  ('98000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000105','A bright day','I felt happy today.','unreviewed','unknown','UTC'),
  ('98000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000105','Draft chapter','A longer arc.','unreviewed','unknown','UTC');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000105',true);

select is(
  (select revision from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000001',1,'Morning pages','A quiet start.','entry','entry',
    null,'UTC','{}',false,null,null,'unknown',null,null
  )),
  2,
  'Saving an Inbox Capture classifies it atomically as Writing'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98000000-0000-4000-8000-000000000001'),
  'entry:entry:unreviewed',
  'A classified Writing can remain in Inbox until Done'
);

select throws_ok(
  $$select * from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000001',2,'Morning pages','A quiet start.','entry','first_time',
    null,'UTC','{}',true,null,null,'unknown',null,null
  )$$,
  '22023',
  'invalid_item_classification',
  'Inbox review cannot turn an Entry into a First Time'
);

select is(
  (select revision from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000001',2,'Morning pages','A quiet start.','entry','entry',
    null,'UTC','{}',true,null,null,'unknown',null,null
  )),
  3,
  'A Writing may change to a compatible Writing subtype and finish review'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98000000-0000-4000-8000-000000000001'),
  'entry:entry:organized',
  'Done preserves Kind while applying the compatible subtype'
);

select is(
  (select revision from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000002',1,'A bright day','I felt happy today.','entry','entry',
    null,'UTC','{}',true,null,null,'unknown',null,null
  )),
  2,
  'A raw Capture can be finalized directly as a Memory Event'
);
select is(
  (select item_kind || ':' || item_subtype
   from public.entries where id='98000000-0000-4000-8000-000000000002'),
  'entry:entry',
  'A Memory uses the canonical Event model'
);
select is(
  (select item_kind || ':' || item_subtype
   from jsonb_populate_record(null::public.entries,public.editable_entry('98000000-0000-4000-8000-000000000002'))),
  'entry:entry',
  'Organized Memory Events remain editable through the shared editor'
);

select is(
  (select revision from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000003',1,'Draft chapter','A longer arc.','entry','entry',
    null,'UTC','{}',true,null,null,'unknown',null,null
  )),
  2,
  'A raw Capture can be finalized as an explicit Story Chapter'
);
select is(
  (select item_kind || ':' || item_subtype
   from public.entries where id='98000000-0000-4000-8000-000000000003'),
  'entry:entry',
  'A Story remains distinct from a dated Entity or Event'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000106',true);
select is(
  (select count(*) from public.review_wiki_item_with_photo_place_rich(
    '98000000-0000-4000-8000-000000000002',2,'Foreign','Foreign','entry','entry',
    null,'UTC','{}',true,null,null,'unknown',null,null
  )),
  0::bigint,
  'Another owner cannot review or reclassify a Wiki Item'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],boolean,timestamptz,text,text,jsonb,jsonb)',
    'execute'
  ),
  'Anonymous Wiki Item review is denied'
);

select * from finish();
rollback;
