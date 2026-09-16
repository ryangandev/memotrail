begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000093','conversion-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000094','conversion-other@memotrail.local','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
insert into public.entries(id,owner_id,title,body,date_precision,occurred_label,metadata)
values ('20000000-0000-0000-0000-000000000093',auth.uid(),'An idea',E'  Original\nwriting  ','age','17岁','{"original":true}');
create temporary table original as select public.entry_history('20000000-0000-0000-0000-000000000093',20,0)->'current' as snapshot;
reset role;
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea','someday','considering',null),2,'Conversion increments revision once');
select is(entry_type,'goal','The original Entry becomes a Goal') from public.entries where id='20000000-0000-0000-0000-000000000093';
select is(body,E'  Original\nwriting  ','Conversion retains raw writing including whitespace') from public.entries where id='20000000-0000-0000-0000-000000000093';
select is(inbox_status,'unreviewed','Conversion does not file the Inbox item') from public.entries where id='20000000-0000-0000-0000-000000000093';
select is(occurred_label,'17岁','Age description is not replaced by a target date') from public.entries where id='20000000-0000-0000-0000-000000000093';
select is(metadata,'{"original":true}'::jsonb,'Original metadata survives') from public.entries where id='20000000-0000-0000-0000-000000000093';
select is(count(*),1::bigint,'No duplicate Entry is created') from public.entries where owner_id=auth.uid();
select is(count(*),0::bigint,'No implicit Bucket List membership is created') from public.entry_collections where owner_id=auth.uid();
select is(snapshot - array['embedding','search_document'],(select snapshot from original),'Prior history retains every publicly readable original field') from public.entry_versions where entry_id='20000000-0000-0000-0000-000000000093' and version=1;
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea','someday','considering',null),2,'Lost-response retry returns the confirmed revision');
select is(count(*),1::bigint,'Retry creates no additional history') from public.entry_versions where entry_id='20000000-0000-0000-0000-000000000093';
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'Changed intention','someday','active',null),null::integer,'Different stale payload cannot masquerade as an idempotent retry');
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',2,'An idea','someday','considering',null),null::integer,'An existing Goal is not converted again');
select throws_ok($$select public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',0,'An idea','someday','considering',null)$$,'22023','invalid_goal_conversion','Invalid revision is rejected');
select throws_ok($$select public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,' ','someday','considering',null)$$,'22023','invalid_goal_conversion','Missing title is rejected');
select throws_ok($$select public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea',null,'considering',null)$$,'22023','invalid_goal_conversion','Null horizon is rejected');
select throws_ok($$select public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea','someday',null,null)$$,'22023','invalid_goal_conversion','Null status is rejected');
select throws_ok($$select public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea','someday','considering','infinity')$$,'22023','invalid_goal_conversion','Infinite target date is rejected');
select is(public.restore_entry_version('20000000-0000-0000-0000-000000000093',1,2),3,'History restores the original Standard Entry');
select is(count(*),0::bigint,'Restoration removes the specialized Goal row') from public.goals where owner_id=auth.uid();
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',1,'An idea','someday','considering',null),null::integer,'Old retry cannot reconvert a restored Entry');
select is(public.restore_entry_version('20000000-0000-0000-0000-000000000093',2,3),4,'The prior Goal can also be restored');
select is(horizon,'someday','Goal details survive round-trip restoration') from public.goals where owner_id=auth.uid();
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000094',true);
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000093',4,'Other user','someday','considering',null),null::integer,'Cross-owner conversion is denied');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',true);
insert into public.entries(id,owner_id,title,entry_type,deleted_at) values
 ('20000000-0000-0000-0000-000000000094',auth.uid(),'Trashed idea','standard',now()),
 ('20000000-0000-0000-0000-000000000095',auth.uid(),'A First Time','first_time',null);
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000094',1,'Trashed idea','someday','considering',null),null::integer,'Trash must be restored before conversion');
select is(public.convert_entry_to_goal('20000000-0000-0000-0000-000000000095',1,'A First Time','someday','considering',null),null::integer,'Other specialized Types are not converted');
select ok(not has_function_privilege('anon','public.convert_entry_to_goal(uuid,integer,text,text,text,date)','execute'),'Anonymous conversion is denied');
select ok(not has_function_privilege('authenticated','public.convert_entry_to_goal(uuid,integer,text,text,text,date)','execute'),'Authenticated clients cannot use the deprecated conversion');
select * from finish();
rollback;
