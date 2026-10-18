begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- An untitled Entry is named by its date on the client, so every workspace returns
-- its stored title, blank when there is none, never a stand-in made from its writing.
insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000187','date-titles-owner@memotrail.local');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_start,occurred_timezone,created_at) values
  ('99870000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000187',null,'Rain all morning.','entry','entry','day','2025-10-18T19:00:00Z','America/Los_Angeles','2026-10-01T12:00:00Z'),
  ('99870000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000187','  ','Started at the bakery.','entry','entry','month','2026-09-01T12:00:00Z','UTC','2026-10-02T12:00:00Z'),
  ('99870000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000187',null,'First solo hike.','entry','entry','day','2024-06-01T12:00:00Z','UTC','2026-10-03T12:00:00Z'),
  ('99870000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000187','Hike more','','goal','goal','unknown',null,'UTC','2026-10-04T12:00:00Z');
insert into public.milestones(entry_id,owner_id,shape,lane,is_first_time) values
  ('99870000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000187','period','work_study',false),
  ('99870000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000187','moment','other',true);
insert into public.goals(entry_id,owner_id,status) values
  ('99870000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000187','achieved');
insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship) values
  ('99870000-0000-4000-8000-000000000004','99870000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000187','achievement');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000187',true);

select is(
  (select array_agg(item->>'title' order by item->>'entry_id')
   from public.home_workspace('2026-10-18','UTC',5), jsonb_array_elements(recent_entries) as item
   where item->>'item_kind' = 'entry'),
  array['','',''],
  'Recent Entries keep blank titles'
);
select is(
  (select now_items->0->>'title' from public.home_workspace('2026-10-18','UTC',5)),
  '',
  'An untitled Period on Now keeps a blank title instead of none'
);
select results_eq(
  $$select title, date_precision, occurred_timezone from public.home_resurfaced_memory('2026-10-18','America/Los_Angeles')$$,
  $$values (''::text, 'day'::text, 'America/Los_Angeles'::text)$$,
  'A resurfaced memory keeps a blank title and its date'
);
select is(
  (select array_agg(stored_title order by entry_id) from public.timeline_workspace()),
  array['',''],
  'Timeline milestones carry blank stored titles'
);
select is(
  (select array_agg(title order by entry_id) from public.timeline_workspace()),
  array['Started at the bakery.','First solo hike.'],
  'Timeline titles keep their earlier stand-in for the Web deployed before the change'
);
select ok(
  not has_function_privilege('anon','public.timeline_workspace()','execute')
    and has_function_privilege('authenticated','public.timeline_workspace()','execute'),
  'Recreating Timeline keeps its grants'
);
select is(
  (select title from public.first_times_workspace()),
  '',
  'An untitled First Time keeps a blank title instead of none'
);
select is(
  (select (related_entries->0) - array['id','body','item_kind','item_subtype','revision','updated_at']
   from public.goals_workspace()),
  jsonb_build_object(
    'title', '',
    'occurred_start', '2024-06-01T12:00:00+00:00',
    'occurred_end', null,
    'date_precision', 'day',
    'occurred_label', null,
    'occurred_timezone', 'UTC',
    'relationship', 'achievement'
  ),
  'A Someday item''s First Time carries what names it by its date'
);

select * from finish();
rollback;
