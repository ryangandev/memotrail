begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000107','goal-extraction-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000108','goal-extraction-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,metadata,source_language,item_kind,item_subtype,inbox_status
) values (
  '98100000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000107',
  'Learn to sail',
  'I want to spend more time on the water.',
  '{"body_rich":{"version":1,"text":"I want to spend more time on the water.","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"I want to spend more time on the water."}]}]}},"private_draft":"do not copy"}',
  'en',
  'writing',
  'idea',
  'organized'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000107',true);

select is(
  (select goal_entry_id from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000001',1,
    '98100000-0000-4000-8000-000000000002',
    'Learn to sail','long_term','active','2030-06-15'
  )),
  '98100000-0000-4000-8000-000000000002'::uuid,
  'Extracting creates the caller-identified Goal'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || revision
   from public.entries where id='98100000-0000-4000-8000-000000000001'),
  'writing:idea:1',
  'The source keeps its Kind, subtype, and revision'
);
select is(
  (select title || ':' || item_kind || ':' || item_subtype
   from public.entries where id='98100000-0000-4000-8000-000000000002'),
  'Learn to sail:goal:goal',
  'The target is a distinct Goal Wiki Item'
);
select is(
  (select body from public.entries where id='98100000-0000-4000-8000-000000000002'),
  'I want to spend more time on the water.',
  'The Goal starts with the source writing as editable context'
);
select ok(
  (select metadata ? 'body_rich' and not metadata ? 'private_draft'
   from public.entries where id='98100000-0000-4000-8000-000000000002'),
  'Only portable rich-text metadata is copied to the Goal'
);
select is(
  (select horizon || ':' || status || ':' || target_date
   from public.goals where entry_id='98100000-0000-4000-8000-000000000002'),
  'long_term:active:2030-06-15',
  'Goal-specific fields are saved on the Goal entity'
);
select is(
  (select count(*) from public.entry_links
   where owner_id='10000000-0000-0000-0000-000000000107'
     and ((source_entry_id='98100000-0000-4000-8000-000000000001' and target_entry_id='98100000-0000-4000-8000-000000000002' and relationship='derived')
       or (source_entry_id='98100000-0000-4000-8000-000000000002' and target_entry_id='98100000-0000-4000-8000-000000000001' and relationship='derived_from'))),
  2::bigint,
  'Source and Goal can both discover their provenance relationship'
);

select is(
  (select goal_entry_id from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000001',1,
    '98100000-0000-4000-8000-000000000002',
    'Learn to sail','long_term','active','2030-06-15'
  )),
  '98100000-0000-4000-8000-000000000002'::uuid,
  'A lost-response retry returns the existing Goal'
);
select is(
  (select count(*) from public.entries where id='98100000-0000-4000-8000-000000000002'),
  1::bigint,
  'A retry cannot duplicate the Goal'
);
select is(
  (select count(*) from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000001',1,
    '98100000-0000-4000-8000-000000000002',
    'Changed payload','someday','considering',null
  )),
  0::bigint,
  'The same request id cannot confirm a different payload'
);
select throws_ok(
  $$select * from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000001',0,
    '98100000-0000-4000-8000-000000000003',
    'Stale source','someday','considering',null
  )$$,
  '22023',
  'invalid_goal_extraction',
  'An invalid source revision is rejected before creating a Goal'
);
select is(
  (select count(*) from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000002',1,
    '98100000-0000-4000-8000-000000000004',
    'Goal from Goal','someday','considering',null
  )),
  0::bigint,
  'A Goal cannot be extracted from another Goal'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000108',true);
select is(
  (select count(*) from public.extract_goal_from_item(
    '98100000-0000-4000-8000-000000000001',1,
    '98100000-0000-4000-8000-000000000005',
    'Foreign source','someday','considering',null
  )),
  0::bigint,
  'Another owner cannot extract from the source'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date)',
    'execute'
  ),
  'Anonymous Goal extraction is denied'
);

select * from finish();
rollback;
