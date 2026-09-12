begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000091','goal-links-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000092','goal-links-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',true);
insert into public.entries(id,owner_id,title) values
 ('20000000-0000-0000-0000-000000000091',auth.uid(),'Hidden progress'),
 ('20000000-0000-0000-0000-000000000092',auth.uid(),'Visible progress');
create function pg_temp.save_goal(links uuid[], id uuid default null, revision integer default null)
returns uuid language sql as $$
 select entry_id from public.save_goal_entry('Patient learning','Original intention','long_term','active',null,'{}','{}',links,id,revision);
$$;
create temporary table fixture as select pg_temp.save_goal(array[
 '20000000-0000-0000-0000-000000000091'::uuid,'20000000-0000-0000-0000-000000000092'::uuid]) id;
insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
 select id,'20000000-0000-0000-0000-000000000091',auth.uid(),'achievement' from fixture;
update public.entries set deleted_at=now() where id='20000000-0000-0000-0000-000000000091';
select is(jsonb_array_length(related_entries),1,'Workspace hides trashed targets') from public.goals_workspace();
select is(pg_temp.save_goal(array['20000000-0000-0000-0000-000000000092'::uuid],id,1),id,'Saving visible links succeeds') from fixture;
select is(count(*),2::bigint,'Both related links survive an unrelated save') from public.entry_links where source_entry_id=(select id from fixture) and relationship='related';
select ok(exists(select 1 from public.entry_versions v,jsonb_array_elements(v.snapshot->'links') link
 where v.entry_id=(select id from fixture) and link->>'target_entry_id'='20000000-0000-0000-0000-000000000091'),'History keeps the original hidden target');
select is(pg_temp.save_goal('{}',id,2),id,'Explicit removal of active targets succeeds') from fixture;
select is(count(*),1::bigint,'Only the hidden related link remains') from public.entry_links where source_entry_id=(select id from fixture) and relationship='related';
select is(count(*),1::bigint,'Achievement links remain outside editable-related replacement') from public.entry_links where source_entry_id=(select id from fixture) and relationship='achievement';
select is(pg_temp.save_goal('{}',id,1),null::uuid,'Stale save cannot unlink hidden progress') from fixture;
select throws_ok($$select pg_temp.save_goal(array['20000000-0000-0000-0000-000000000091'::uuid],id,3) from fixture$$,'22023','invalid_related_entries','New submitted links to Trash are still rejected');
select is(revision,3,'Invalid target rolls back the entire Goal update') from public.entries where id=(select id from fixture);
select is(count(*),2::bigint,'Rejected target creates no history revision') from public.entry_versions where entry_id=(select id from fixture);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',true);
select is(pg_temp.save_goal('{}',id,3),null::uuid,'Other account cannot change Goal links') from fixture;
select is(count(*),0::bigint,'Other account cannot see hidden targets') from public.entry_links;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',true);
select * from public.restore_trash_item('entry','20000000-0000-0000-0000-000000000091',
 (select revision from public.entries where id='20000000-0000-0000-0000-000000000091'),
 (select deleted_at from public.entries where id='20000000-0000-0000-0000-000000000091'));
select is(jsonb_array_length(related_entries),2,'Restoration reveals both preserved relationship kinds') from public.goals_workspace();
select is(pg_temp.save_goal('{}',id,3),id,'Restored related links can be explicitly removed') from fixture;
select is(count(*),0::bigint,'Active related link removal is not blocked by preservation') from public.entry_links where source_entry_id=(select id from fixture) and relationship='related';
select is(count(*),1::bigint,'Non-related achievement still survives explicit unlink') from public.entry_links where source_entry_id=(select id from fixture) and relationship='achievement';
reset role;
select * from finish();
rollback;
