begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values('10000000-0000-0000-0000-000000000099','evidence-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title,body,date_precision,occurred_start) values
 ('98000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Before the move','搬家前，我在思考为什么人需要不断学习。','day','2026-01-05T12:00Z'),
 ('98000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','After the move','Electric lighters use an electric arc.','day','2026-01-07T12:00Z'),
 ('98000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000001','An uncertain first','First time skiing at age 17.','age',null),
 ('98000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000099','Private other owner','Private electric lighters note.','day','2026-01-04T12:00Z');
insert into public.entries(id,owner_id,title,item_kind,item_subtype,date_precision,occurred_start) values
 ('98000000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000001','Living on Pine Street','entry','chapter','day','2026-01-06T12:00Z');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is(jsonb_array_length(public.archive_wiki_search_evidence(array['搬家前'])->'entries'),1,'Evidence excludes another owner');
select is(public.archive_wiki_search_evidence(array['First time skiing at age 17'])->'entries'->0->>'date_precision','age','Evidence retains uncertainty');
select is(public.archive_wiki_search_evidence(array['First time skiing at age 17'])->'entries'->0->'occurred_start','null'::jsonb,'Evidence never invents a date');
select ok(not (public.archive_wiki_search_evidence(array['搬家前'])->'entries'->0 ? 'attachments'),'Text evidence excludes media');
select is(jsonb_array_length(public.archive_wiki_search_evidence(array['不断学习'])->'entries'),1,'Chinese query evidence');
select ok(not (public.archive_wiki_search_evidence(array['electric arc']) ? 'people'),'People are absent from AI evidence');
select ok(not (public.archive_wiki_search_evidence(array['electric arc']) ? 'places'),'Authored Places are absent from AI evidence');
select is(public.archive_wiki_search_evidence('{}',array['chapter'])->'entries'->0->>'title','Living on Pine Street','The chapter classification finds a Chapter');
select is(public.archive_wiki_search_evidence('{}',array['chapter'])->'entries'->0->>'item_subtype','chapter','Evidence says an Entry is a Chapter');
select ok(not exists(select 1 from jsonb_array_elements(public.archive_wiki_search_evidence('{}',array['entry'])->'entries') e where e->>'item_subtype'<>'entry') and exists(select 1 from jsonb_array_elements(public.archive_wiki_search_evidence('{}',array['entry'])->'entries') e where e->>'title'='After the move'),'The entry classification finds ordinary Entries only');
select is(public.archive_wiki_search_evidence(array['After the move'])->'entries'->0->'is_first_time','false'::jsonb,'Evidence carries the First Time mark as a flag');
select ok(not (public.archive_wiki_search_evidence(array['After the move'])->'entries'->0 ? 'facts'),'Evidence has no typed facts object');
select ok(not (public.archive_wiki_search_evidence(array['After the move']) ? 'latest_home_reference'),'There is no Home boundary');
select ok(not (public.archive_wiki_search_evidence(array['After the move']) ? 'reference_window_applied'),'No date window is derived from a Home');
select is(public.archive_wiki_search_evidence('{}','{}','{}','2026-01-01','2026-01-31')->>'effective_date_to','2026-01-31','The requested end date is used as given');
select throws_ok($$select public.archive_wiki_search_evidence(array['a','b','c','d','e','f','g'])$$,'22023','invalid_evidence_request','Query fanout bounded');
select throws_ok($$select public.archive_wiki_search_evidence('{}','{}','{}','2026-02-01','2026-01-01')$$,'22023','invalid_evidence_request','Reversed date range denied');
select throws_ok($$select public.archive_wiki_search_evidence('{}','{}','{}',null,null,'invalid')$$,'22023','invalid_evidence_request','Sort contract validated');
reset role;
insert into public.entries(owner_id,title,body,item_kind,item_subtype,occurred_start)
 select '10000000-0000-0000-0000-000000000001','Chronological skiing evidence','Unique skiing stress fixture','entry','entry',('2000-01-01'::date+n)::timestamptz from generate_series(0,110) n;
update public.entries set is_first_time=true where body='Unique skiing stress fixture';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((public.archive_wiki_search_evidence(array['Unique skiing stress fixture'],array['first_time'],'{}',null,null,'oldest')->'entries'->0->>'occurred_start')::timestamptz,'2000-01-01'::timestamptz,'Earliest result is selected before limiting even with over 100 matches');
select is((public.archive_wiki_search_evidence(array['Unique skiing stress fixture'],array['first_time'])->>'query_truncated')::boolean,true,'Bounded query coverage is explicit');
select is(jsonb_array_length(public.archive_wiki_search_evidence(array['Unique skiing stress fixture'],array['first_time'])->'entries'),36,'Evidence payload source count bounded');
select is((select count(*) from public.search_wiki_items('Unique skiing stress fixture','{}','{}',null,null,25,0)),25::bigint,'Existing keyword RPC preserves its public contract');
reset role;
select hasnt_function('public','archive_entry_sources',array['uuid[]'],'Legacy source RPC is removed');
select ok(not has_function_privilege('anon','public.archive_wiki_search_evidence(text[],text[],text[],date,date,text)','execute'),'Anonymous evidence search denied');
select * from finish();
rollback;
