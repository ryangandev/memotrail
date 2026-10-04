begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000091','goal-links-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000092','goal-links-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',true);
insert into public.entries(id,owner_id,title) values
 ('20000000-0000-0000-0000-000000000091',auth.uid(),'First Time milestone'),
 ('20000000-0000-0000-0000-000000000092',auth.uid(),'Earlier related note');
create function pg_temp.save_goal(id uuid default null, revision integer default null)
returns uuid language sql as $$
 select entry_id from public.save_goal_entry('Patient learning','Original intention','active',null,'{}',id,revision);
$$;
create temporary table fixture as select pg_temp.save_goal() id;
-- Synthetic protected links: an achievement and an earlier related link.
reset role;
insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
 select id,'20000000-0000-0000-0000-000000000091'::uuid,'10000000-0000-0000-0000-000000000091'::uuid,'achievement' from fixture
 union all
 select id,'20000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000091','related' from fixture;
set local role authenticated;
select is(jsonb_array_length(related_entries),1,'Workspace lists the achievement but not earlier related links') from public.goals_workspace();
select is(related_entries->0->>'relationship','achievement','The listed link is the achievement') from public.goals_workspace();
select is(pg_temp.save_goal(id,1),id,'Saving a Goal succeeds') from fixture;
select is(count(*),1::bigint,'Saving keeps earlier related links in the data') from public.entry_links where source_entry_id=(select id from fixture) and relationship='related';
select is(count(*),1::bigint,'Saving keeps the achievement link') from public.entry_links where source_entry_id=(select id from fixture) and relationship='achievement';
select ok(exists(select 1 from public.entry_versions v,jsonb_array_elements(v.snapshot->'links') link
 where v.entry_id=(select id from fixture) and link->>'target_entry_id'='20000000-0000-0000-0000-000000000092'),'History keeps the earlier related link');
update public.entries set deleted_at=now() where id='20000000-0000-0000-0000-000000000091';
select is(jsonb_array_length(related_entries),0,'Workspace hides trashed targets') from public.goals_workspace();
select is(pg_temp.save_goal(id,1),null::uuid,'Stale save is refused') from fixture;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',true);
select is(pg_temp.save_goal(id,2),null::uuid,'Other account cannot change the Goal') from fixture;
select is(count(*),0::bigint,'Other account cannot see Goal links') from public.entry_links;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',true);
select * from public.restore_trash_item('entry','20000000-0000-0000-0000-000000000091',
 (select revision from public.entries where id='20000000-0000-0000-0000-000000000091'),
 (select deleted_at from public.entries where id='20000000-0000-0000-0000-000000000091'));
select is(jsonb_array_length(related_entries),1,'Restoration reveals the achievement again') from public.goals_workspace();
reset role;
select * from finish();
rollback;
