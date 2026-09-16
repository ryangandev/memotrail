begin;
create extension if not exists pgtap with schema extensions;
select plan(23);
insert into public.timeline_tracks(id,owner_id,name,sort_order,system_key)
values('95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Track test',-100,'track-test');
insert into public.entries(id,owner_id,title) values
('95000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','Track memory');
insert into public.timeline_items(entry_id,track_id,owner_id,timeline_kind) values
('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','event');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((select entry_count from public.timeline_track_settings() where name='Track test'),1::bigint,'Linked Entry count');
select is((select name from public.timeline_track_settings(1,0)),'Track test','Sort order and page limit');
select ok(public.save_timeline_track('  新阶段  ',5,false) is not null,'Create custom track');
select is((select name from public.timeline_track_settings() where name='新阶段'),'新阶段','Trim bilingual name');
select is((select system_key from public.timeline_track_settings() where name='新阶段'),null::text,'Custom track cannot claim a system identity');
select throws_ok($$select public.save_timeline_track('track TEST',0,false)$$,'23505',null,'Case-insensitive duplicate rejected');
select is(public.save_timeline_track('Renamed track',-200,true,'95000000-0000-4000-8000-000000000001',1),'95000000-0000-4000-8000-000000000001'::uuid,'Rename, reorder and hide atomically');
select is((select revision from public.timeline_track_settings() where name='Renamed track'),2,'Revision advanced');
select is((select system_key from public.timeline_track_settings() where name='Renamed track'),'track-test','System identity survives renaming');
select is((select count(*) from public.timeline_items where track_id='95000000-0000-4000-8000-000000000001'),1::bigint,'Hiding preserves placements');
select is((select deleted_at from public.entries where id='95000000-0000-4000-8000-000000000002'),null::timestamptz,'Hiding never trashes content');
select is((select count(*) from public.timeline_workspace_with_organization(false) where track_id='95000000-0000-4000-8000-000000000001'),0::bigint,'Hidden track excluded from Timeline');
select is(public.save_timeline_track('Stale',0,false,'95000000-0000-4000-8000-000000000001',1),null::uuid,'Stale save does not overwrite');
select is(public.save_timeline_track('Renamed track',-200,false,'95000000-0000-4000-8000-000000000001',2),'95000000-0000-4000-8000-000000000001'::uuid,'Show track again');
select is((select count(*) from public.timeline_workspace_with_organization(false) where track_id='95000000-0000-4000-8000-000000000001'),1::bigint,'Existing moment returns');
select throws_ok($$select public.save_timeline_track(' ',0,false)$$,'22023','invalid_track_details','Blank name rejected');
select throws_ok($$select public.save_timeline_track('x',1000001,false)$$,'22023','invalid_track_details','Out-of-range order rejected');
select throws_ok($$select public.save_timeline_track('x',0,false,null,1)$$,'22023','invalid_revision','Creation revision rejected');
select throws_ok($$select public.timeline_track_settings(101,0)$$,'22023','invalid_track_page','Invalid page rejected');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000099',true);
select is((select count(*) from public.timeline_track_settings() where id='95000000-0000-4000-8000-000000000001'),0::bigint,'Other owner cannot read');
select is(public.save_timeline_track('Other owner',0,false,'95000000-0000-4000-8000-000000000001',3),null::uuid,'Other owner cannot edit');
reset role;
select ok(not has_function_privilege('anon','public.save_timeline_track(text,integer,boolean,uuid,integer)','execute'),'Anonymous mutation denied');
select ok(not has_function_privilege('anon','public.timeline_track_settings(integer,integer)','execute'),'Anonymous read denied');
select * from finish();
rollback;
