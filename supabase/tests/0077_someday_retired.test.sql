begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Someday items became ordinary Entries tagged `someday`, so nothing Goal-specific remains.
select hasnt_table('public','goals','The Goal table is gone');
select hasnt_function('public','save_goal_entry','The Goal save is gone');
select hasnt_function('public','extract_goal_from_item','Adding an item to Someday is gone');
select hasnt_function('public','achieve_goal_with_occurrence','Marking a Someday item done is gone');
select hasnt_function('public','trash_goal_entry','The Goal Trash action is gone');
select hasnt_function('public','goals_workspace','The Someday workspace is gone');
select hasnt_index('public','entries','entries_owner_goal_updated_idx','The Goal index is gone');
select is(public.default_item_subtype('goal'),null::text,'Goal is no longer a Kind with a default subtype');
select is(public.default_item_subtype('entry'),'entry','An Entry keeps its default subtype');
select ok(not ('goals' = any(public.export_dataset_names())),'Export no longer reads a Goal dataset');
select ok('entries' = any(public.export_dataset_names()),'Export still reads Entries');

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000177','someday-retired-owner@memotrail.local');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision) values
  ('99770000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000177','Walk','Words','entry','entry','unknown'),
  ('99770000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000177','Elsewhere','Words','entry','entry','unknown');

select throws_ok(
  $$insert into public.entries(owner_id,title,item_kind,item_subtype)
    values('10000000-0000-0000-0000-000000000177','Learn Spanish','goal','goal')$$,
  '23514',
  null,
  'An Entry can no longer be a Goal'
);
select throws_ok(
  $$update public.entries set item_kind = 'goal', item_subtype = 'goal'
    where id = '99770000-0000-4000-8000-000000000001'$$,
  '23514',
  null,
  'An Entry cannot be turned into a Goal'
);

-- The only links left are the Exploration ones.
select throws_ok(
  $$insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
    values('99770000-0000-4000-8000-000000000001','99770000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000177','achievement')$$,
  '23514',
  null,
  'An achievement link cannot be stored'
);
select throws_ok(
  $$insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
    values('99770000-0000-4000-8000-000000000001','99770000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000177','derived')$$,
  '23514',
  null,
  'An extraction link cannot be stored'
);
select lives_ok(
  $$insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
    values('99770000-0000-4000-8000-000000000001','99770000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000177','exploration_source')$$,
  'An Exploration link can still be stored'
);

-- Search and the Library no longer know Someday as a Kind, and still find its Entries by tag.
insert into public.tags(id,owner_id,name) values
  ('99770000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000177','someday');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
  ('99770000-0000-4000-8000-000000000001','99770000-0000-4000-8000-000000000101','10000000-0000-0000-0000-000000000177');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000177',true);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('',array[]::text[],array['someday'])),
  array['99770000-0000-4000-8000-000000000001'::uuid],
  'A converted Someday Entry is found by its tag'
);
select is(
  (select count(*) from public.search_wiki_items('Walk',array['goal'])),
  0::bigint,
  'Filtering by the retired Goal Kind finds nothing'
);
select is(
  (select jsonb_array_length(public.archive_wiki_search_evidence(array['Walk'])->'entries')),
  1,
  'Search evidence still reads Entries without the Goal table'
);
select throws_ok(
  $$select * from public.wiki_items_workspace('',array['goal'],array[]::text[],50,0)$$,
  '22023',
  'invalid_wiki_items_page',
  'The Library page no longer filters by Goal'
);

select * from finish();
rollback;
