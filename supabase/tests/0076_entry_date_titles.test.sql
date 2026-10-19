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
  ('99870000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000187',null,'First solo hike.','entry','entry','day','2024-06-01T12:00:00Z','UTC','2026-10-03T12:00:00Z');
update public.entries set item_subtype='chapter' where id='99870000-0000-4000-8000-000000000002';
update public.entries set is_first_time=true where id='99870000-0000-4000-8000-000000000003';

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
  'An untitled Chapter on Now keeps a blank title instead of none'
);
select results_eq(
  $$select title, date_precision, occurred_timezone from public.home_resurfaced_memory('2026-10-18','America/Los_Angeles')$$,
  $$values (''::text, 'day'::text, 'America/Los_Angeles'::text)$$,
  'A resurfaced memory keeps a blank title and its date'
);
select is(
  (select array_agg(title order by entry_id) from public.timeline_workspace()),
  array['',''],
  'Timeline Chapters and First Times carry blank stored titles, never a stand-in'
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

select * from finish();
rollback;
