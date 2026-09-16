begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000093','goal-extraction-owner@memotrail.local','{}'),
  ('10000000-0000-0000-0000-000000000094','goal-extraction-other@memotrail.local','{}');

insert into public.entries(
  id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision,occurred_label,metadata
) values (
  '20000000-0000-0000-0000-000000000093',
  '10000000-0000-0000-0000-000000000093',
  'An idea',
  E'  Original\nwriting  ',
  'writing',
  'idea',
  'unreviewed',
  'age',
  '17岁',
  '{"original":true,"body_rich":{"version":1,"text":"  Original\nwriting  ","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"  Original\nwriting  "}]}]}}}'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);

select is(
  (select goal_entry_id from public.extract_goal_from_item(
    '20000000-0000-0000-0000-000000000093',
    1,
    '20000000-0000-0000-0000-000000000096',
    'An idea',
    'someday',
    'considering',
    null
  )),
  '20000000-0000-0000-0000-000000000096'::uuid,
  'Extraction creates a separately identified Goal'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || revision
   from public.entries where id='20000000-0000-0000-0000-000000000093'),
  'writing:idea:1',
  'The source keeps its writing identity and revision'
);
select is(
  (select body from public.entries where id='20000000-0000-0000-0000-000000000093'),
  E'  Original\nwriting  ',
  'The source keeps its exact writing'
);
select is(
  (select inbox_status from public.entries where id='20000000-0000-0000-0000-000000000093'),
  'unreviewed',
  'Extraction does not silently file the source Capture'
);
select is(
  (select occurred_label from public.entries where id='20000000-0000-0000-0000-000000000093'),
  '17岁',
  'Extraction does not rewrite source occurrence context'
);
select is(
  (select item_kind || ':' || item_subtype from public.entries where id='20000000-0000-0000-0000-000000000096'),
  'goal:goal',
  'The extracted item has canonical Goal identity'
);
select is(
  (select horizon || ':' || status from public.goals where entry_id='20000000-0000-0000-0000-000000000096'),
  'someday:considering',
  'Goal-specific facts live in the Goal record'
);
select is(
  (select count(*) from public.entry_links
   where owner_id='10000000-0000-0000-0000-000000000093'
     and ((source_entry_id='20000000-0000-0000-0000-000000000093'
       and target_entry_id='20000000-0000-0000-0000-000000000096'
       and relationship='derived')
      or (source_entry_id='20000000-0000-0000-0000-000000000096'
       and target_entry_id='20000000-0000-0000-0000-000000000093'
       and relationship='derived_from'))),
  2::bigint,
  'Both items retain navigable provenance'
);
select ok(
  (select metadata ? 'body_rich' and not metadata ? 'original'
   from public.entries where id='20000000-0000-0000-0000-000000000096'),
  'Only portable rich writing metadata is copied to the Goal'
);
select is(
  (select goal_entry_id from public.extract_goal_from_item(
    '20000000-0000-0000-0000-000000000093',1,
    '20000000-0000-0000-0000-000000000096',
    'An idea','someday','considering',null
  )),
  '20000000-0000-0000-0000-000000000096'::uuid,
  'A lost-response retry returns the same Goal'
);
select is(
  (select count(*) from public.entries where id='20000000-0000-0000-0000-000000000096'),
  1::bigint,
  'A retry cannot duplicate the Goal'
);
select is(
  (select count(*) from public.extract_goal_from_item(
    '20000000-0000-0000-0000-000000000093',1,
    '20000000-0000-0000-0000-000000000096',
    'Changed intention','someday','active',null
  )),
  0::bigint,
  'A reused request id cannot confirm a different payload'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000094',true);
select is(
  (select count(*) from public.extract_goal_from_item(
    '20000000-0000-0000-0000-000000000093',1,
    '20000000-0000-0000-0000-000000000097',
    'Other user','someday','considering',null
  )),
  0::bigint,
  'Another account cannot extract from the source'
);

reset role;
select hasnt_function(
  'public',
  'convert_entry_to_goal',
  array['uuid','integer','text','text','text','date'],
  'The in-place conversion contract is removed'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date)',
    'execute'
  ),
  'Authenticated clients may extract a separate linked Goal'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date)',
    'execute'
  ),
  'Anonymous extraction is denied'
);

select * from finish();
rollback;
