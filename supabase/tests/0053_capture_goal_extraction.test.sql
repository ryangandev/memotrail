begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000115','capture-goal-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000116','capture-goal-other@memotrail.local');

insert into public.entries(
  id,owner_id,title,body,entry_type,inbox_status,date_precision
) values
  (
    '98600000-0000-4000-8000-000000000001',
    '10000000-0000-0000-0000-000000000115',
    'Learn to sail',
    'A wish I want to make concrete.',
    'standard',
    'unreviewed',
    'unknown'
  ),
  (
    '98600000-0000-4000-8000-000000000002',
    '10000000-0000-0000-0000-000000000115',
    'Why the ocean matters',
    'A related note.',
    'standard',
    'organized',
    'unknown'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000115',true);

select ok(
  (select goal_entry_id is not null from public.extract_capture_to_goal(
    '98600000-0000-4000-8000-000000000001',1,
    'Learn to sail','A wish I want to make concrete.',
    'long_term','active','2028-06-01',array['Life plans'],array['Ocean'],
    array['98600000-0000-4000-8000-000000000002'::uuid]
  )),
  'Extraction creates a Goal through the specialized contract'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || inbox_status
   from public.entries where id='98600000-0000-4000-8000-000000000001'),
  'capture:source_capture:organized',
  'The original Capture is preserved as provenance'
);
select is(
  (select item_kind || ':' || item_subtype || ':' || entry_type
   from public.entries
   where id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98600000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'goal:goal:goal',
  'The durable target is a Goal'
);
select is(
  (select horizon || ':' || status || ':' || target_date::text
   from public.goals
   where entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98600000-0000-4000-8000-000000000001'
       and relationship='derived'
   )),
  'long_term:active:2028-06-01',
  'Goal-specific intent fields are saved'
);
select is(
  (select count(*)
   from public.entry_collections as membership
   join public.collections as collection
     on collection.id = membership.collection_id
     and collection.owner_id = membership.owner_id
   where membership.entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98600000-0000-4000-8000-000000000001'
       and relationship='derived'
   ) and collection.name='Life plans'),
  1::bigint,
  'Goal Collections are saved'
);
select is(
  (select count(*)
   from public.entry_tags as membership
   join public.tags as tag
     on tag.id = membership.tag_id
     and tag.owner_id = membership.owner_id
   where membership.entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98600000-0000-4000-8000-000000000001'
       and relationship='derived'
   ) and tag.name='Ocean'),
  1::bigint,
  'Goal tags are saved'
);
select is(
  (select count(*) from public.entry_links
   where source_entry_id = (
     select target_entry_id from public.entry_links
     where source_entry_id='98600000-0000-4000-8000-000000000001'
       and relationship='derived'
   )
     and target_entry_id='98600000-0000-4000-8000-000000000002'
     and relationship='related'),
  1::bigint,
  'Related Entries are saved independently from provenance'
);
select is(
  (select count(*) from public.entry_links
   where owner_id='10000000-0000-0000-0000-000000000115'
     and (source_entry_id='98600000-0000-4000-8000-000000000001'
       or target_entry_id='98600000-0000-4000-8000-000000000001')
     and relationship in ('derived','derived_from')),
  2::bigint,
  'Both the Capture and Goal can discover their provenance'
);
select ok(
  (select goal_entry_id is not null from public.extract_capture_to_goal(
    '98600000-0000-4000-8000-000000000001',1,
    'Learn to sail','A wish I want to make concrete.',
    'long_term','active','2028-06-01',array['Life plans'],array['Ocean'],
    array['98600000-0000-4000-8000-000000000002'::uuid]
  )),
  'A lost-response retry finds the existing Goal'
);
select is(
  (select count(*) from public.goals where owner_id='10000000-0000-0000-0000-000000000115'),
  1::bigint,
  'Retrying cannot duplicate the Goal'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000116',true);
select is(
  (select count(*) from public.extract_capture_to_goal(
    '98600000-0000-4000-8000-000000000001',1,
    'Foreign Goal','No access','someday','considering',null,'{}','{}','{}'
  )),
  0::bigint,
  'Another owner cannot extract from the Capture'
);

reset role;
select ok(
  not has_function_privilege(
    'anon',
    'public.extract_capture_to_goal(uuid,integer,text,text,text,text,date,text[],text[],uuid[])',
    'execute'
  ),
  'Anonymous Goal extraction is denied'
);

select * from finish();
rollback;
