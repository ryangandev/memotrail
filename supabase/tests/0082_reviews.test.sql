begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Chapter and year reviews and Chapter suggestions: accounting, preferences, the periods a
-- review reads, the job steps, grounding at save and at every read, deletion, suggestions,
-- and notices. Today is 2026-10-18 throughout, passed in where a function needs it.

insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000821','reviews-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000822','reviews-other@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000823','reviews-consent@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000824','reviews-suggestions@memotrail.local','{}');

-- Schema, security, and export

select has_table('public','entry_reviews','Reviews are stored');
select has_table('public','entry_review_sources','The Entries a review read are stored');
select has_table('public','chapter_suggestions','Chapter suggestions are stored');
select has_table('public','chapter_suggestion_state','Suggestion scheduling is stored');
select has_table('public','review_notices','Resolved notices are stored');
select ok((select relrowsecurity from pg_class where oid='public.entry_reviews'::regclass),'Reviews have row level security');
select ok((select relrowsecurity from pg_class where oid='public.entry_review_sources'::regclass),'Review sources have row level security');
select ok((select relrowsecurity from pg_class where oid='public.chapter_suggestions'::regclass),'Suggestions have row level security');
select ok((select relrowsecurity from pg_class where oid='public.chapter_suggestion_state'::regclass),'Suggestion state has row level security');
select ok((select relrowsecurity from pg_class where oid='public.review_notices'::regclass),'Notices have row level security');
select ok(has_table_privilege('authenticated','public.entry_reviews','select'),'People read their reviews');
select ok(not has_table_privilege('authenticated','public.entry_reviews','insert'),'People cannot write reviews directly');
select ok(not has_table_privilege('authenticated','public.entry_reviews','update'),'People cannot edit reviews directly');
select ok(not has_table_privilege('authenticated','public.entry_reviews','delete'),'People cannot delete reviews directly');
select ok(not has_table_privilege('authenticated','public.entry_review_sources','insert'),'People cannot write review sources');
select ok(not has_table_privilege('authenticated','public.chapter_suggestions','update'),'People cannot edit suggestions directly');
select ok(not has_table_privilege('authenticated','public.chapter_suggestion_state','select'),'Suggestion state is not readable');
select ok(not has_table_privilege('authenticated','public.review_notices','insert'),'People cannot write notices directly');
select ok(not has_table_privilege('anon','public.entry_reviews','select'),'Signed-out visitors cannot read reviews');
select ok(not has_function_privilege('anon','public.claim_entry_review(text,uuid,integer,date,jsonb)','execute'),'Signed-out visitors cannot start a review');
select ok(not has_function_privilege('anon','public.chapter_review(uuid,date)','execute'),'Signed-out visitors cannot read a Chapter review');
select ok(not has_function_privilege('anon','public.year_review(integer,date)','execute'),'Signed-out visitors cannot read a year review');
select ok(not has_function_privilege('anon','public.review_settings()','execute'),'Signed-out visitors cannot read review settings');
select ok(not has_function_privilege('anon','public.save_review_preferences(boolean,boolean,text,integer)','execute'),'Signed-out visitors cannot save review settings');
select ok(not has_function_privilege('anon','public.claim_chapter_suggestion_run()','execute'),'Signed-out visitors cannot start a suggestion run');
select ok(not has_function_privilege('anon','public.review_notice(date)','execute'),'Signed-out visitors cannot read the notice');
select ok(not has_function_privilege('authenticated','public.reserve_ai_usage(uuid,text,text,bigint,bigint,bigint)','execute'),'People cannot reserve their own billing');
select ok(not has_function_privilege('authenticated','public.ai_budget_allows(uuid,bigint,bigint,bigint)','execute'),'People cannot probe budgets');
select ok(not has_function_privilege('authenticated','public.discard_ai_work_for_deleted_entry()','execute'),'The delete trigger is not callable');
select ok('entry_reviews' = any(public.export_dataset_names()),'Export includes reviews');
select ok('entry_review_sources' = any(public.export_dataset_names()),'Export includes review sources');
select ok('chapter_suggestions' = any(public.export_dataset_names()),'Export includes suggestions');
select ok(not ('review_notices' = any(public.export_dataset_names())),'Export leaves out notices');
select ok(not ('chapter_suggestion_state' = any(public.export_dataset_names())),'Export leaves out suggestion scheduling');
select ok('media_objects' = any(public.export_dataset_names()) and 'ai_usage' = any(public.export_dataset_names()),'Export keeps the earlier datasets');

-- Accounting

select is((select input_micros from public.ai_model_price('claude-sonnet-5-5')),2,'Sonnet 5.5 input price');
select is((select output_micros from public.ai_model_price('claude-sonnet-5-5')),10,'Sonnet 5.5 output price');
select is((select input_micros from public.ai_model_price('claude-haiku-4-5-20251001')),1,'Haiku 4.5 input price');
select is((select output_micros from public.ai_model_price('claude-haiku-4-5-20251001')),5,'Haiku 4.5 output price');
select is((select count(*) from public.ai_model_price('unknown')),0::bigint,'Unknown models have no price');

insert into public.ai_preferences(owner_id,reviews_enabled,chapter_suggestions_enabled,review_disclosure_version) values
 ('10000000-0000-0000-0000-000000000821',true,false,'2026-10-18'),
 ('10000000-0000-0000-0000-000000000824',false,true,'2026-10-18');
insert into public.ai_preferences(owner_id,enabled,classification,reviews_enabled) values
 ('10000000-0000-0000-0000-000000000822',true,true,false);

select is((select classification from public.ai_preferences where owner_id='10000000-0000-0000-0000-000000000821'),false,'A row made for reviews leaves the paused features off');
select is((select classification from public.ai_preferences where owner_id='10000000-0000-0000-0000-000000000822'),true,'A saved paused-feature value is kept');

set local role service_role;
select lives_ok($$select set_config('test.review_usage',public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','claude-sonnet-5-5',500000,25000000,3000000)::text,true)$$,'Reviews reserve without the paused-feature switch');
select is(public.finish_ai_usage(current_setting('test.review_usage')::uuid,'completed',1000,200,null),true,'A review request completes');
select is((select charged_micros from public.ai_usage where id=current_setting('test.review_usage')::uuid),4000::bigint,'Sonnet 5.5 costs 2 and 10 micros per token');
select lives_ok($$select set_config('test.haiku_usage',public.reserve_ai_usage('10000000-0000-0000-0000-000000000822','classification','claude-haiku-4-5-20251001',500,25000000)::text,true)$$,'A paused feature keeps its rule');
select is(public.finish_ai_usage(current_setting('test.haiku_usage')::uuid,'completed',100,10,null),true,'A Haiku request completes');
select is((select charged_micros from public.ai_usage where id=current_setting('test.haiku_usage')::uuid),150::bigint,'Haiku 4.5 costs 1 and 5 micros per token');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000822','review','claude-sonnet-5-5',1000,25000000)$$,'42501','ai_disabled','Reviews need their own switch, not the general one');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','chapter_suggestion','claude-sonnet-5-5',1000,25000000)$$,'42501','ai_disabled','Suggestions need their own switch');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','classification','claude-sonnet-5-5',1000,25000000)$$,'42501','ai_disabled','Paused features stay off for review users');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','claude-sonnet-5-5',2000001,25000000)$$,'22023','invalid_ai_reservation','A single reservation is capped at two dollars');
select lives_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','claude-sonnet-5-5',2000000,25000000,3000000)$$,'A reservation of exactly two dollars is allowed');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','unknown',1000,25000000)$$,'22023','invalid_ai_reservation','An unknown model cannot use wrong pricing');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','claude-sonnet-5-5',1000,1000000001)$$,'22023','invalid_ai_reservation','The server budget has a ceiling');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000821','review','claude-sonnet-5-5',1500000,25000000,3000000)$$,'P0001','ai_budget_exceeded','The per-user monthly budget is enforced');
select ok(not public.ai_budget_allows('10000000-0000-0000-0000-000000000821',1500000,25000000,3000000),'A job that would exceed the user budget does not start');
select ok(public.ai_budget_allows('10000000-0000-0000-0000-000000000821',900000,25000000,3000000),'A job that fits both budgets may start');
select ok(not public.ai_budget_allows('10000000-0000-0000-0000-000000000821',900000,2500000,3000000),'A job that would exceed the server budget does not start');
select ok(not public.ai_budget_allows('10000000-0000-0000-0000-000000000821',1,25000000),'Without a server value the saved budget applies');
reset role;

-- Last month's usage does not count against this month's server cap.
insert into public.ai_usage(owner_id,feature,model,status,reserved_micros,charged_micros,created_at) values
 ('10000000-0000-0000-0000-000000000822','review','claude-sonnet-5-5','completed',1000000,1000000,date_trunc('month', now() at time zone 'UTC') at time zone 'UTC' - interval '2 days');
update public.ai_preferences set reviews_enabled=true,review_disclosure_version='2026-10-18' where owner_id='10000000-0000-0000-0000-000000000822';
set local role service_role;
select lives_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000822','review','claude-sonnet-5-5',1000,2500000,3000000)$$,'A row from last month is outside the server cap');
select throws_ok($$select public.reserve_ai_usage('10000000-0000-0000-0000-000000000822','review','claude-sonnet-5-5',2000000,2000500,3000000)$$,'P0001','ai_budget_exceeded','This month counts against the server cap');
reset role;

-- Preferences

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000823',true);
select is((public.review_settings()->>'revision'),'0','Unsaved review settings have revision zero');
select is((public.review_settings()->>'reviewsEnabled'),'false','Reviews are off by default');
select throws_ok($$select public.save_review_preferences(true,false,null,0)$$,'22023','review_consent_required','Turning reviews on needs the disclosure');
select throws_ok($$select public.save_review_preferences(null,false,null,0)$$,'22023','invalid_review_preferences','Missing switches are rejected');
select throws_ok($$select public.save_review_preferences(true,false,'yesterday',0)$$,'22023','invalid_review_preferences','A malformed disclosure version is rejected');
select is(public.save_review_preferences(true,false,'2026-10-18',1),null::jsonb,'A stale revision is refused');
select is((public.save_review_preferences(true,false,'2026-10-18',0)->>'reviewsEnabled'),'true','Turning reviews on with the disclosure saves');
select is((public.review_settings()->>'disclosureVersion'),'2026-10-18','The accepted disclosure version is kept');
select is((public.review_settings()->>'revision'),'1','Saving advances the revision');
select is((select classification from public.ai_preferences where owner_id='10000000-0000-0000-0000-000000000823'),false,'Saving leaves the paused features off');
select is((public.save_review_preferences(true,true,null,1)->>'chapterSuggestionsEnabled'),'true','The recorded disclosure covers a second switch');
select is((public.save_review_preferences(false,false,null,2)->>'reviewsEnabled'),'false','Turning both off saves without a disclosure');
reset role;

-- Fixtures: Chapters and Entries

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,is_first_time) values
 -- A Chapter that ended, with six Entries inside it.
 ('82000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000821','Job search','The year I looked for work. Money was tight.','entry','chapter','2026-03-01T12:00Z','2026-06-20T12:00Z','day','UTC',false),
 ('82000000-0000-4000-8000-000000000011','10000000-0000-0000-0000-000000000821','First rejection','I felt anxious about the first interview today.','entry','entry','2026-03-05T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000012','10000000-0000-0000-0000-000000000821','Practice','Practiced questions with my brother. It was steadier.','entry','entry','2026-03-20T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000013','10000000-0000-0000-0000-000000000821','Second round','The second interview went better than I expected.','entry','entry','2026-04-10T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000014','10000000-0000-0000-0000-000000000821','First offer','My first ever offer arrived this morning.','entry','entry','2026-04-25T12:00Z',null,'day','UTC',true),
 ('82000000-0000-4000-8000-000000000015','10000000-0000-0000-0000-000000000821',null,'Waiting is the hardest part.','entry','entry','2026-05-15T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000016','10000000-0000-0000-0000-000000000821','Decision','I decided to accept the offer.','entry','entry','2026-06-01T12:00Z',null,'day','UTC',false),
 -- Not inside: before, after, a month the Chapter covers only in part, Unknown, Trash, and another owner.
 ('82000000-0000-4000-8000-000000000017','10000000-0000-0000-0000-000000000821','Before','Before it started.','entry','entry','2026-02-20T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000018','10000000-0000-0000-0000-000000000821','After','After it ended.','entry','entry','2026-07-01T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000019','10000000-0000-0000-0000-000000000821','Whole June','A month entry.','entry','entry','2026-06-01T00:00Z',null,'month','UTC',false),
 ('82000000-0000-4000-8000-00000000001a','10000000-0000-0000-0000-000000000821','Undated','Nobody knows when.','entry','entry',null,null,'unknown','UTC',false),
 ('82000000-0000-4000-8000-00000000001b','10000000-0000-0000-0000-000000000821','In Trash','Gone for now.','entry','entry','2026-04-02T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-00000000001c','10000000-0000-0000-0000-000000000822','Someone else','Private to the other owner.','entry','entry','2026-04-03T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-00000000001d','10000000-0000-0000-0000-000000000821','Nested','A Chapter inside the Chapter.','entry','chapter','2026-04-01T12:00Z','2026-04-30T12:00Z','day','UTC',false),
 -- A Chapter still going on, an undated Chapter, and a Chapter with too few Entries.
 ('82000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000821','Seattle','Moving to Seattle.','entry','chapter','2026-08-01T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000821','Mystery','No dates.','entry','chapter',null,null,'unknown','UTC',false),
 ('82000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000821','Small','Not much happened.','entry','chapter','2023-01-01T12:00Z','2023-02-28T12:00Z','day','UTC',false),
 ('82000000-0000-4000-8000-000000000041','10000000-0000-0000-0000-000000000821','Boxes','Packed the boxes.','entry','entry','2026-08-02T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000042','10000000-0000-0000-0000-000000000821','Drive','Drove across the country.','entry','entry','2026-08-10T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000043','10000000-0000-0000-0000-000000000821','Apartment','Found the apartment.','entry','entry','2026-08-20T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000044','10000000-0000-0000-0000-000000000821','Rain','It rains here all the time.','entry','entry','2026-09-01T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000045','10000000-0000-0000-0000-000000000821','Coffee','The coffee here is good.','entry','entry','2026-09-15T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000046','10000000-0000-0000-0000-000000000821','Friends','Met a few friends.','entry','entry','2026-10-01T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000051','10000000-0000-0000-0000-000000000821','Small one','One.','entry','entry','2023-01-10T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000052','10000000-0000-0000-0000-000000000821','Small two','Two.','entry','entry','2023-02-10T12:00Z',null,'day','UTC',false),
 -- 2025, with a Chapter across it.
 ('82000000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000821','Studying','School.','entry','chapter','2025-09-01T12:00Z','2026-02-28T12:00Z','day','UTC',false),
 ('82000000-0000-4000-8000-000000000031','10000000-0000-0000-0000-000000000821','January','January words.','entry','entry','2025-01-10T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000032','10000000-0000-0000-0000-000000000821','April','April words.','entry','entry','2025-04-10T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000033','10000000-0000-0000-0000-000000000821','April again','More April words.','entry','entry','2025-04-20T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000034','10000000-0000-0000-0000-000000000821','July','July words.','entry','entry','2025-07-04T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000035','10000000-0000-0000-0000-000000000821','December','December words.','entry','entry','2025-12-31T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000036','10000000-0000-0000-0000-000000000821','All of 2025','A whole year entry.','entry','entry','2025-01-01T00:00Z',null,'year','UTC',false),
 ('82000000-0000-4000-8000-000000000037','10000000-0000-0000-0000-000000000821','New Year trip','Across New Year.','entry','entry','2025-12-28T12:00Z','2026-01-03T12:00Z','range','UTC',false),
 ('82000000-0000-4000-8000-000000000038','10000000-0000-0000-0000-000000000821','2025 trash','Trashed.','entry','entry','2025-05-05T12:00Z',null,'day','UTC',false),
 ('82000000-0000-4000-8000-000000000039','10000000-0000-0000-0000-000000000821','2024','Last year before.','entry','entry','2024-05-05T12:00Z',null,'day','UTC',false);
update public.entries set deleted_at='2026-10-01T00:00:00Z' where id in ('82000000-0000-4000-8000-00000000001b','82000000-0000-4000-8000-000000000038');

insert into public.tags(id,owner_id,name) values
 ('82100000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000821','interviews'),
 ('82100000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000821','family');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
 ('82000000-0000-4000-8000-000000000011','82100000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000821'),
 ('82000000-0000-4000-8000-000000000012','82100000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000821'),
 ('82000000-0000-4000-8000-000000000013','82100000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000821'),
 ('82000000-0000-4000-8000-000000000012','82100000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000821');

-- Periods

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);

select is((select count(*) from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001')),7::bigint,'A Chapter review reads the Chapter and the six Entries inside it');
select is((select entry_id from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') limit 1),'82000000-0000-4000-8000-000000000001'::uuid,'The Chapter itself comes first');
select is((select is_subject from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') limit 1),true,'The Chapter is marked as the subject');
select set_eq(
  $$select entry_id from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') where not is_subject$$,
  $$select entry_id from public.chapter_entries('82000000-0000-4000-8000-000000000001',100,0)$$,
  'Membership is exactly what the Chapter page lists'
);
select is(
  (select array_agg(entry_id order by ordinality) from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') with ordinality where not is_subject),
  array['82000000-0000-4000-8000-000000000011','82000000-0000-4000-8000-000000000012','82000000-0000-4000-8000-000000000013','82000000-0000-4000-8000-000000000014','82000000-0000-4000-8000-000000000015','82000000-0000-4000-8000-000000000016']::uuid[],
  'Entries come oldest first'
);
select is((select body from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') limit 1),'The year I looked for work. Money was tight.','The Chapter note is returned whole');
select is((select tag_names from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') where entry_id='82000000-0000-4000-8000-000000000012'),array['family','interviews'],'Tags come with the Entry');
select is((select window_end from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000001') where entry_id='82000000-0000-4000-8000-000000000011'),'2026-03-06'::date,'The window end is the day after the last day');
select throws_ok($$select * from public.review_period_entries('chapter','82000000-0000-4000-8000-000000000003')$$,'22023','review_subject_unavailable','An undated Chapter has no period');
select throws_ok($$select * from public.review_period_entries('chapter','82000000-0000-4000-8000-00000000001a')$$,'22023','review_subject_unavailable','An Entry is not a Chapter');
select throws_ok($$select * from public.review_period_entries('chapter','82000000-0000-4000-8000-00000000001c')$$,'22023','review_subject_unavailable','Another owner has no period here');
select throws_ok($$select * from public.review_period_entries('decade',null,2020)$$,'22023','invalid_review_period','Only Chapters and years are periods');
select is((select count(*) from public.review_period_entries('year',null,2025)),6::bigint,'A year holds its Day Entries and its Year Entry');
select ok(not exists(select 1 from public.review_period_entries('year',null,2025) where entry_id='82000000-0000-4000-8000-000000000037'),'A range across New Year is in neither year');
select ok(not exists(select 1 from public.review_period_entries('year',null,2025) where entry_id in ('82000000-0000-4000-8000-000000000038','82000000-0000-4000-8000-000000000039','82000000-0000-4000-8000-00000000001a')),'Trash, other years, and Unknown are left out');
select ok(not exists(select 1 from public.review_period_entries('year',null,2025) where entry_id='82000000-0000-4000-8000-000000000005'),'A year review does not read Chapter writing');
select is((select count(*) from public.review_period_chapters(2025)),1::bigint,'The Chapters during a year are listed');
select is((select title from public.review_period_chapters(2025)),'Studying','A Chapter during the year comes by name');

select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->>'entryCount'),'6','Facts count the Entries inside');
select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->'firstTimes'->0->>'id'),'82000000-0000-4000-8000-000000000014','Facts list the First Times');
select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->'topTags'->0->>'name'),'interviews','Facts list the most used tag');
select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->'topTags'->0->>'count'),'3','Facts count the tag uses');
select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->'busiestMonth'->>'month'),'2026-03','Ties go to the earlier month');
select is((public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->>'firstWindowStart'),'2026-03-05','Facts give the first day');
select is(jsonb_array_length(public.review_period_facts('chapter','82000000-0000-4000-8000-000000000001')->'chapters'),0,'A Chapter review lists no other Chapters');
select is(jsonb_array_length(public.review_period_facts('year',null,2025)->'chapters'),1,'A year lists its Chapters');
select is((public.review_period_facts('year',null,2025)->'busiestMonth'->>'month'),'2025-04','A Year Entry does not count towards a month');

select is((select array_agg(review_year) from public.review_years('2026-10-18')),array[2025],'Only past years with at least five Entries are listed');
select is((select entry_count from public.review_years('2026-10-18')),6::bigint,'The year list counts the Entries');
select is((select review_generated_at from public.review_years('2026-10-18')),null::timestamptz,'No review has been made yet');
select is((select count(*) from public.review_years('2025-06-01')),0::bigint,'The current year is never listed');

select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18')->>'status','eligible','An ended Chapter with enough Entries is eligible');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18')->>'ongoing','false','An ended Chapter is not ongoing');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000001',null,'2026-06-20')->>'ongoing','true','A Chapter ending today is still going on');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000002',null,'2026-10-18')->>'status','eligible','A Chapter still going on can have a review so far');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000002',null,'2026-10-18')->>'ongoing','true','A Chapter without an end is ongoing');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000003',null,'2026-10-18')->>'status','unanchored','A Chapter without a calendar span is unanchored');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-000000000004',null,'2026-10-18')->>'status','too_few_entries','Two Entries are too few');
select is(public.review_eligibility('chapter','82000000-0000-4000-8000-00000000001c',null,'2026-10-18')->>'status','unavailable','Another owner is unavailable');
select is(public.review_eligibility('year',null,2025,'2026-10-18')->>'status','eligible','A past year is eligible');
select is(public.review_eligibility('year',null,2026,'2026-10-18')->>'status','not_over','The current year is not over');
select is(public.review_eligibility('year',null,2024,'2026-10-18')->>'status','too_few_entries','A year with one Entry is too few');
reset role;

-- Jobs

create function pg_temp.plan(p_hash text, p_ids uuid[], p_ongoing boolean default false, p_steps jsonb default null, p_version text default '2026-10-18') returns jsonb language sql as $$
  select jsonb_build_object(
    'disclosureVersion', p_version,
    'planHash', repeat(p_hash, 64),
    'mode', case when jsonb_array_length(coalesce(p_steps, '[{"index":0,"kind":"review"}]'::jsonb)) > 1 then 'segmented' else 'single' end,
    'entryIds', to_jsonb(p_ids),
    'sources', '[]'::jsonb,
    'entriesInPeriod', cardinality(p_ids),
    'trimmedEntries', 0,
    'language', 'en',
    'ongoing', p_ongoing,
    'steps', coalesce(p_steps, jsonb_build_array(jsonb_build_object('index', 0, 'kind', 'review', 'entryIds', to_jsonb(p_ids))))
  );
$$;
create function pg_temp.chapter_ids() returns uuid[] language sql as $$
  select array['82000000-0000-4000-8000-000000000011','82000000-0000-4000-8000-000000000012','82000000-0000-4000-8000-000000000013','82000000-0000-4000-8000-000000000014','82000000-0000-4000-8000-000000000015','82000000-0000-4000-8000-000000000016']::uuid[];
$$;
create function pg_temp.sources() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('entryId', id, 'revision', revision) order by id)
  from public.entries
  where id in (
    '82000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000011','82000000-0000-4000-8000-000000000012',
    '82000000-0000-4000-8000-000000000013','82000000-0000-4000-8000-000000000014','82000000-0000-4000-8000-000000000015',
    '82000000-0000-4000-8000-000000000016');
$$;
create function pg_temp.content(p_quote_text text default 'anxious about the first interview', p_cited text default '82000000-0000-4000-8000-000000000011') returns jsonb language sql as $$
  select jsonb_build_object(
    'summary', 'A tense few months that ended well.',
    'feelings', jsonb_build_object('overview', 'From worry to relief.', 'phases', jsonb_build_array(
      jsonb_build_object('feeling', 'Anxious, then steadier', 'description', 'It eased.', 'entryIds', jsonb_build_array(p_cited, '82000000-0000-4000-8000-000000000012'), 'windowStart', '2026-03-05', 'windowEnd', '2026-03-21'))),
    'themes', jsonb_build_array(jsonb_build_object('name', 'Interviews', 'description', 'They kept coming.', 'entryIds', jsonb_build_array(p_cited, '82000000-0000-4000-8000-000000000013'))),
    'quotes', jsonb_build_array(jsonb_build_object('entryId', '82000000-0000-4000-8000-000000000011', 'start', 10, 'end', 44, 'text', p_quote_text, 'why', 'It names the worry.'))
  );
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);

select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000003',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))$$,'22023','review_not_eligible','A Chapter without dates cannot be reviewed');
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000004',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))$$,'22023','review_not_eligible','A Chapter with too few Entries cannot be reviewed');
select throws_ok($$select public.claim_entry_review('year',null,2026,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))$$,'22023','review_not_eligible','The current year cannot be reviewed');
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids(),false,null,'2026-01-01'))$$,'42501','review_disclosure_outdated','An outdated disclosure is refused');
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18','{"steps":[]}')$$,'22023','invalid_review_plan','A malformed plan is refused');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000823',true);
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))$$,'42501','ai_disabled','Reviews must be on to start one');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);

select lives_ok($$select set_config('test.job',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))::text,true)$$,'An eligible Chapter starts a job');
select is((current_setting('test.job')::jsonb->>'total'),'1','A single-pass job has one step');
select is((select job_status from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),'generating','The job is generating');
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000002',null,'2026-10-18',pg_temp.plan('b',pg_temp.chapter_ids()))$$,'P0001','review_in_progress','One job at a time');
select is((public.claim_review_steps((current_setting('test.job')::jsonb->>'reviewId')::uuid,(current_setting('test.job')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[0]'::jsonb,'A step is handed out');
select is((public.claim_review_steps((current_setting('test.job')::jsonb->>'reviewId')::uuid,(current_setting('test.job')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[]'::jsonb,'A step is handed out once');
select is((public.claim_review_steps((current_setting('test.job')::jsonb->>'reviewId')::uuid,'2020-01-01T00:00Z',6)->>'status'),'stale','Another job start is stale');
select is((public.claim_review_steps(gen_random_uuid(),'2020-01-01T00:00Z',6)->>'status'),'stale','An unknown job is stale');

-- A quote that is not in the Entry cannot be saved, nor a citation outside the sources.
select throws_ok(format($$select public.store_entry_review(%L,%L,pg_temp.content('I never wrote this'),'claude-sonnet-5-5',6,pg_temp.sources())$$,current_setting('test.job')::jsonb->>'reviewId',current_setting('test.job')::jsonb->>'jobStartedAt'),'22023','review_quote_unverified','A quote that is not in the Entry is refused');
select throws_ok(format($$select public.store_entry_review(%L,%L,pg_temp.content('anxious about the first interview','82000000-0000-4000-8000-000000000017'),'claude-sonnet-5-5',6,pg_temp.sources())$$,current_setting('test.job')::jsonb->>'reviewId',current_setting('test.job')::jsonb->>'jobStartedAt'),'22023','invalid_review_content','A citation outside the sources is refused');
select throws_ok(format($$select public.store_entry_review(%L,%L,pg_temp.content(),'claude-sonnet-5-5',6,jsonb_build_array(jsonb_build_object('entryId','82000000-0000-4000-8000-000000000017','revision',1)))$$,current_setting('test.job')::jsonb->>'reviewId',current_setting('test.job')::jsonb->>'jobStartedAt'),'22023','invalid_review_content','A source outside the plan is refused');
select is(public.store_entry_review((current_setting('test.job')::jsonb->>'reviewId')::uuid,'2020-01-01T00:00Z',pg_temp.content(),'claude-sonnet-5-5',6,pg_temp.sources()),false,'A stale job stores nothing');
select throws_ok(format($$select public.store_entry_review(%L,%L,'{}','claude-sonnet-5-5',6,pg_temp.sources())$$,current_setting('test.job')::jsonb->>'reviewId',current_setting('test.job')::jsonb->>'jobStartedAt'),'22023','invalid_review_content','Content without the expected shape is refused');

-- The Entry text is checked at save, so editing it between the model's answer and the save fails.
reset role;
update public.entries set body='I felt nervous about the first interview today.' where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select throws_ok(format($$select public.store_entry_review(%L,%L,pg_temp.content(),'claude-sonnet-5-5',6,pg_temp.sources())$$,current_setting('test.job')::jsonb->>'reviewId',current_setting('test.job')::jsonb->>'jobStartedAt'),'22023','review_quote_unverified','An Entry edited after the model read it fails the check');
reset role;
update public.entries set body='I felt anxious about the first interview today.' where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);

select is(public.store_entry_review((current_setting('test.job')::jsonb->>'reviewId')::uuid,(current_setting('test.job')::jsonb->>'jobStartedAt')::timestamptz,pg_temp.content(),'claude-sonnet-5-5',6,pg_temp.sources()),true,'A grounded review is saved');
select is((select job_status from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),'idle','The job is finished');
select is((select job_state from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),null::jsonb,'The plan is cleared');
select is((select count(*) from public.entry_review_sources where review_id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),7::bigint,'Every Entry read is recorded as a source');
select is((select count(*) from public.entry_review_sources where review_id=(current_setting('test.job')::jsonb->>'reviewId')::uuid and content_hash is not null),7::bigint,'Sources keep the hash of what was read');
select is((select entries_read from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),6,'The number of Entries read is stored');
select is((select model from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),'claude-sonnet-5-5','The model is stored');
select is((select ongoing from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),false,'A review of an ended Chapter is not a review so far');
select is((select period_end from public.entry_reviews where id=(current_setting('test.job')::jsonb->>'reviewId')::uuid),'2026-06-21'::date,'The period end is stored');

-- Reading a review

select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'eligibility'->>'status','eligible','The read says whether a review can be made');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'quoteAvailable','[true]'::jsonb,'A quote is available while its words are in the Entry');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes','{"newEntries":0,"editedEntries":0,"trashedEntries":0}'::jsonb,'Nothing has changed since the review');
select is(jsonb_array_length(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'sources'),3,'Sources list only the cited Entries');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'facts'->>'entryCount','6','The read carries the live facts');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'settings'->>'reviewsEnabled','true','The read carries the switch');
select is(public.chapter_review('82000000-0000-4000-8000-000000000002','2026-10-18')->'review','null'::jsonb,'A Chapter without a review reads as none');
select is(public.year_review(2025,'2026-10-18')->'eligibility'->>'status','eligible','A year read says whether a review can be made');

reset role;
update public.entries set body='I felt calm about the first interview today.' where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'quoteAvailable','[false]'::jsonb,'Editing the words away hides the quote');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes'->>'editedEntries','1','The edited Entry is counted');
reset role;
update public.entries set body='I felt anxious about the first interview today.' where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'quoteAvailable','[true]'::jsonb,'Putting the words back shows the quote again');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes'->>'editedEntries','0','Restoring the same writing is not a change');

reset role;
update public.entries set deleted_at=now() where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'quoteAvailable','[false]'::jsonb,'Trash hides the quote');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes'->>'trashedEntries','1','The trashed source is counted');
select is((select (value->>'trashed')::boolean from jsonb_array_elements(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'sources') where value->>'entryId'='82000000-0000-4000-8000-000000000011'),true,'A trashed source is flagged');
reset role;
update public.entries set deleted_at=null where id='82000000-0000-4000-8000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'quoteAvailable','[true]'::jsonb,'Restore brings the quote back');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes','{"newEntries":0,"editedEntries":0,"trashedEntries":0}'::jsonb,'A Trash and Restore round trip changes nothing');

reset role;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone) values
 ('82000000-0000-4000-8000-000000000061','10000000-0000-0000-0000-000000000821','Late addition','Added later.','entry','entry','2026-05-20T12:00Z','day','UTC');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'changes'->>'newEntries','1','A new Entry is counted');
reset role;
delete from public.entries where id='82000000-0000-4000-8000-000000000061';

-- Try again, leases, and the daily limit

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
create function pg_temp.segmented(p_hash text) returns jsonb language sql as $$
  select pg_temp.plan(p_hash, pg_temp.chapter_ids(), false, jsonb_build_array(
    jsonb_build_object('index', 0, 'kind', 'map', 'entryIds', jsonb_build_array('82000000-0000-4000-8000-000000000011')),
    jsonb_build_object('index', 1, 'kind', 'map', 'entryIds', jsonb_build_array('82000000-0000-4000-8000-000000000012')),
    jsonb_build_object('index', 2, 'kind', 'reduce', 'entryIds', '[]'::jsonb)));
$$;
select lives_ok($$select set_config('test.job2',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.segmented('c'))::text,true)$$,'A new job replaces the review row for the same Chapter');
select is((select content is not null from public.entry_reviews where id=(current_setting('test.job2')::jsonb->>'reviewId')::uuid),true,'The previous review stays while a new one is made');
select is((public.claim_review_steps((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[0, 1]'::jsonb,'Map steps are handed out together and reduce waits');
select is(public.finish_review_step((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,0,'{"notes":"one"}'),true,'A map step finishes');
select is(public.finish_review_step((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,0,'{"notes":"again"}'),false,'A finished step cannot finish twice');
select is(public.finish_review_step((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,2,'{"notes":"early"}'),false,'A step that is not running cannot finish');
select is((public.claim_review_steps((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[]'::jsonb,'Reduce still waits for the other map step');
select is(public.finish_review_step((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,1,'{"notes":"two"}'),true,'The other map step finishes');
select is((public.claim_review_steps((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[2]'::jsonb,'Reduce is handed out when the maps are done');
select is((public.entry_review_status((current_setting('test.job2')::jsonb->>'reviewId')::uuid)->>'done'),'2','Status counts finished steps');
select is((public.entry_review_status((current_setting('test.job2')::jsonb->>'reviewId')::uuid)->>'total'),'3','Status counts all steps');

-- A lease that ends unfinished fails the job, and nothing is repeated on its own.
reset role;
update public.entry_reviews
set job_state=jsonb_set(job_state,'{steps}',(
  select jsonb_agg(case when s.value->>'status'='running' then s.value || '{"leasedUntil":"2020-01-01T00:00:00Z"}'::jsonb else s.value end order by s.ordinality)
  from jsonb_array_elements(job_state->'steps') with ordinality as s(value,ordinality)))
where id=(current_setting('test.job2')::jsonb->>'reviewId')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is((public.claim_review_steps((current_setting('test.job2')::jsonb->>'reviewId')::uuid,(current_setting('test.job2')::jsonb->>'jobStartedAt')::timestamptz,6)->>'status'),'interrupted','An expired lease interrupts the job');
select is((select job_status || ':' || job_error from public.entry_reviews where id=(current_setting('test.job2')::jsonb->>'reviewId')::uuid),'failed:generation_interrupted','The job fails with a reason');
select is((select value->>'status' from jsonb_array_elements((select job_state->'steps' from public.entry_reviews where id=(current_setting('test.job2')::jsonb->>'reviewId')::uuid)) where value->>'index'='2'),'uncertain','The step with an unknown outcome is marked');
select is((select content is not null from public.entry_reviews where id=(current_setting('test.job2')::jsonb->>'reviewId')::uuid),true,'A failed job keeps the previous review');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'review'->'job'->>'error','generation_interrupted','The read shows why it failed');

select lives_ok($$select set_config('test.job3',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.segmented('c'))::text,true)$$,'Try again with the same plan starts a job');
select is((current_setting('test.job3')::jsonb->>'done'),'2','Finished map steps are kept');
select is((public.claim_review_steps((current_setting('test.job3')::jsonb->>'reviewId')::uuid,(current_setting('test.job3')::jsonb->>'jobStartedAt')::timestamptz,6)->'claimed'),'[2]'::jsonb,'Only the unfinished step is handed out');
select is(public.fail_entry_review((current_setting('test.job3')::jsonb->>'reviewId')::uuid,(current_setting('test.job3')::jsonb->>'jobStartedAt')::timestamptz,'provider_error'),true,'A job can be failed');
select is(public.fail_entry_review((current_setting('test.job3')::jsonb->>'reviewId')::uuid,(current_setting('test.job3')::jsonb->>'jobStartedAt')::timestamptz,'provider_error'),false,'A failed job cannot fail again');
select throws_ok($$select public.fail_entry_review(gen_random_uuid(),now(),'Bad Code')$$,'22023','invalid_review_plan','An error code has a fixed shape');

reset role;
update public.entry_reviews set generation_count_day = 0;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select lives_ok($$select set_config('test.job4',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.segmented('d'))::text,true)$$,'A different plan starts over');
select is((current_setting('test.job4')::jsonb->>'done'),'0','A different plan reuses nothing');
select is(public.fail_entry_review((current_setting('test.job4')::jsonb->>'reviewId')::uuid,(current_setting('test.job4')::jsonb->>'jobStartedAt')::timestamptz,'provider_error'),true,'The job fails');
reset role;
update public.entry_reviews set generation_count_day = 3;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select throws_ok($$select public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.segmented('e'))$$,'P0001','review_limit_reached','A fourth generation in a day is refused');
select lives_ok($$select public.claim_entry_review('year',null,2025,'2026-10-18',pg_temp.plan('f',array['82000000-0000-4000-8000-000000000031']::uuid[]))$$,'The limit is per subject');
select is((select count(*) from public.entry_reviews),2::bigint,'A person sees only their own reviews');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000822',true);
select is((select count(*) from public.entry_reviews),0::bigint,'Another owner cannot read reviews');
select is((select count(*) from public.entry_review_sources),0::bigint,'Another owner cannot read review sources');
select is(public.chapter_review('82000000-0000-4000-8000-000000000001','2026-10-18')->'eligibility'->>'status','unavailable','Another owner cannot read the Chapter review');
select is(public.entry_review_status((select id from public.entry_reviews limit 1)),null::jsonb,'Another owner cannot poll a job');
select is(public.delete_entry_review((current_setting('test.job')::jsonb->>'reviewId')::uuid),false,'Another owner cannot delete a review');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);

-- A job that stopped moving reads as interrupted.
reset role;
update public.entry_reviews set job_status='generating', job_progressed_at=now() - interval '31 minutes', job_state=coalesce(job_state,'{"steps":[]}') where scope='year';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.entry_review_status((select id from public.entry_reviews where scope='year'))->>'status','failed','A stalled job reads as failed');
select is(public.entry_review_status((select id from public.entry_reviews where scope='year'))->>'error','generation_interrupted','A stalled job says it was interrupted');
reset role;
delete from public.entry_reviews where scope='year';

-- Reviews turned off while a job runs

update public.ai_preferences set reviews_enabled=false where owner_id='10000000-0000-0000-0000-000000000821';
select is((select count(*) from public.entry_reviews where owner_id='10000000-0000-0000-0000-000000000821'),0::bigint,'Turning reviews off deletes every saved review');
update public.ai_preferences set reviews_enabled=true where owner_id='10000000-0000-0000-0000-000000000821';

-- Delete forever

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select lives_ok($$select set_config('test.job5',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.plan('a',pg_temp.chapter_ids()))::text,true)$$,'A job starts again');
select is((select count(*) from public.claim_review_steps((current_setting('test.job5')::jsonb->>'reviewId')::uuid,(current_setting('test.job5')::jsonb->>'jobStartedAt')::timestamptz,6)),1::bigint,'Its step is handed out');
select is(public.store_entry_review((current_setting('test.job5')::jsonb->>'reviewId')::uuid,(current_setting('test.job5')::jsonb->>'jobStartedAt')::timestamptz,pg_temp.content(),'claude-sonnet-5-5',6,pg_temp.sources()),true,'The review is saved');
select is(public.create_export_snapshot('82900000-0000-4000-8000-000000000001')->'datasets'->>'entry_reviews','1','A complete export holds the review');
select is(public.create_export_snapshot('82900000-0000-4000-8000-000000000002')->'datasets'->>'entry_review_sources','7','A complete export holds what the review read');
reset role;

-- Trash changes nothing stored; Delete forever of a source deletes the review.
update public.entries set deleted_at=now() where id='82000000-0000-4000-8000-000000000015';
select is((select count(*) from public.entry_reviews where owner_id='10000000-0000-0000-0000-000000000821'),1::bigint,'Trash leaves the stored review');
select is((select count(*) from public.entry_review_sources where owner_id='10000000-0000-0000-0000-000000000821'),7::bigint,'Trash leaves the stored sources');
delete from public.entries where id='82000000-0000-4000-8000-000000000015';
select is((select count(*) from public.entry_reviews where owner_id='10000000-0000-0000-0000-000000000821'),0::bigint,'Deleting an Entry the review read, though uncited, deletes the review');
select is((select count(*) from public.entry_review_sources where owner_id='10000000-0000-0000-0000-000000000821'),0::bigint,'Its sources go too');

-- Delete forever of an Entry a running job was reading fails the job and clears its plan.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select lives_ok($$select set_config('test.job6',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000002',null,'2026-10-18',pg_temp.plan('a',array['82000000-0000-4000-8000-000000000041','82000000-0000-4000-8000-000000000042','82000000-0000-4000-8000-000000000043','82000000-0000-4000-8000-000000000044','82000000-0000-4000-8000-000000000045']::uuid[],true))::text,true)$$,'A job starts for the ongoing Chapter');
reset role;
delete from public.entries where id='82000000-0000-4000-8000-000000000044';
select is((select job_status || ':' || job_error from public.entry_reviews where id=(current_setting('test.job6')::jsonb->>'reviewId')::uuid),'failed:review_source_deleted','Delete forever during a job fails it');
select is((select job_state from public.entry_reviews where id=(current_setting('test.job6')::jsonb->>'reviewId')::uuid),null::jsonb,'The partial plan is discarded');
delete from public.entries where id='82000000-0000-4000-8000-000000000002';
select is((select count(*) from public.entry_reviews where chapter_id='82000000-0000-4000-8000-000000000002'),0::bigint,'Deleting the Chapter deletes its review row');

-- Deleting the Chapter deletes its review.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select lives_ok($$select set_config('test.job7',public.claim_entry_review('chapter','82000000-0000-4000-8000-000000000001',null,'2026-10-18',pg_temp.plan('a',array['82000000-0000-4000-8000-000000000011','82000000-0000-4000-8000-000000000012','82000000-0000-4000-8000-000000000013','82000000-0000-4000-8000-000000000014','82000000-0000-4000-8000-000000000016']::uuid[]))::text,true)$$,'A job starts for the first Chapter again');
select is((select count(*) from public.claim_review_steps((current_setting('test.job7')::jsonb->>'reviewId')::uuid,(current_setting('test.job7')::jsonb->>'jobStartedAt')::timestamptz,6)),1::bigint,'Its step is handed out');
select is(public.store_entry_review((current_setting('test.job7')::jsonb->>'reviewId')::uuid,(current_setting('test.job7')::jsonb->>'jobStartedAt')::timestamptz,pg_temp.content(),'claude-sonnet-5-5',5,pg_temp.sources() - 5 - 5),true,'A review made without one trimmed Entry is saved');
select is((select count(*) from public.entry_review_sources where review_id=(current_setting('test.job7')::jsonb->>'reviewId')::uuid),5::bigint,'Only the Entries read are sources');
select is(public.delete_entry_review((current_setting('test.job7')::jsonb->>'reviewId')::uuid),true,'A review can be deleted');
select is((select count(*) from public.entry_review_sources where review_id=(current_setting('test.job7')::jsonb->>'reviewId')::uuid),0::bigint,'Its sources are deleted with it');
select is(public.review_settings()->>'reviewCount','0','The review count follows');

-- An uncited Entry the review did not read leaves it alone.
reset role;

-- Account deletion removes everything
insert into auth.users(id,email,raw_user_meta_data) values ('10000000-0000-0000-0000-000000000825','reviews-gone@memotrail.local','{}');
insert into public.ai_preferences(owner_id,reviews_enabled,chapter_suggestions_enabled,review_disclosure_version) values ('10000000-0000-0000-0000-000000000825',true,true,'2026-10-18');
insert into public.chapter_suggestions(owner_id,name,rationale,start_date,start_precision,window_start) values ('10000000-0000-0000-0000-000000000825','Gone','Gone.','2026-01-01','month','2026-01-01');
insert into public.review_notices(owner_id,subject) values ('10000000-0000-0000-0000-000000000825','year:2025');
delete from auth.users where id='10000000-0000-0000-0000-000000000825';
select is((select count(*) from public.chapter_suggestions where owner_id='10000000-0000-0000-0000-000000000825'),0::bigint,'Deleting the account deletes suggestions');
select is((select count(*) from public.review_notices where owner_id='10000000-0000-0000-0000-000000000825'),0::bigint,'Deleting the account deletes notices');

-- Window overlap

select is(public.window_iou(daterange('2026-01-01','2026-03-01'),daterange('2026-01-01','2026-03-01'),'2026-10-18'),1::numeric,'The same stretch overlaps fully');
select is(public.window_iou(daterange('2026-01-01','2026-02-01'),daterange('2026-03-01','2026-04-01'),'2026-10-18'),0::numeric,'Separate stretches do not overlap');
select is(round(public.window_iou(daterange('2026-01-01','2026-03-01'),daterange('2026-02-01','2026-04-01'),'2026-10-18'),4),round(28.0/90.0,4),'Partial overlap is overlap over union in days');
select is(round(public.window_iou(daterange('2026-01-01',null),daterange('2026-01-01','2026-04-11'),'2026-04-10'),4),1::numeric,'An open end reads as running through today');
select is(public.window_iou(null,daterange('2026-01-01','2026-02-01'),'2026-10-18'),0::numeric,'A stretch without days overlaps nothing');
select is(public.window_iou(daterange('2026-01-01','2026-01-11'),daterange('2026-01-01','2026-01-21'),'2026-10-18'),0.5::numeric,'Half of the longer stretch is exactly half');

-- Suggestions

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone)
select ('82200000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '10000000-0000-0000-0000-000000000824','Climb ' || n,'Climbed again.','entry','entry',
  '2026-07-01T12:00Z'::timestamptz + (n * interval '6 days'),'day','UTC'
from generate_series(1,14) as n;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select is((public.claim_chapter_suggestion_run()->>'due'),'true','A first run is due when the switch is on');
select is((public.claim_chapter_suggestion_run()->>'due'),'false','A live lease blocks a second run');
select is(public.release_chapter_suggestion_run('2020-01-01T00:00Z'),false,'Only the current lease can be released');
reset role;
select ok((select leased_until is not null from public.chapter_suggestion_state where owner_id='10000000-0000-0000-0000-000000000824'),'The lease is recorded');
update public.chapter_suggestion_state set leased_until=null where owner_id='10000000-0000-0000-0000-000000000824';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select lives_ok($$select set_config('test.lease',(public.claim_chapter_suggestion_run()->>'leaseUntil'),true)$$,'A run can be claimed again once the lease is gone');
select is(public.release_chapter_suggestion_run(current_setting('test.lease')::timestamptz),true,'A failed run releases its lease');
select is(public.claim_chapter_suggestion_run()->>'due','true','A released run may be tried again');
reset role;
select set_config('test.lease',(select leased_until::text from public.chapter_suggestion_state where owner_id='10000000-0000-0000-0000-000000000824'),true);

create function pg_temp.suggestion(p_name text, p_start date, p_end date, p_ids uuid[]) returns jsonb language sql as $$
  select jsonb_build_object('name', p_name, 'rationale', 'You kept returning to the gym.', 'sourceEntryIds', to_jsonb(p_ids),
    'startDate', p_start, 'startPrecision', 'day', 'endDate', p_end, 'endPrecision', case when p_end is null then null else 'day' end,
    'windowStart', p_start, 'windowEnd', case when p_end is null then null else p_end + 1 end);
$$;
create function pg_temp.climb_ids() returns uuid[] language sql as $$
  select array_agg(('82200000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid) from generate_series(1,5) n;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select is(public.store_chapter_suggestions('2020-01-01T00:00Z','[]','claude-sonnet-5-5','2026-10-18'),null::integer,'A stale lease stores nothing');
select throws_ok($$select public.store_chapter_suggestions(current_setting('test.lease')::timestamptz,jsonb_build_array(pg_temp.suggestion('Bad',date '2026-07-01',null,array['82000000-0000-4000-8000-000000000011']::uuid[])),'claude-sonnet-5-5','2026-10-18')$$,'22023','invalid_chapter_suggestion','A suggestion cannot cite another owner''s Entry');
select throws_ok($$select public.store_chapter_suggestions(current_setting('test.lease')::timestamptz,'[{"name":""}]','claude-sonnet-5-5','2026-10-18')$$,'22023','invalid_chapter_suggestion','A malformed suggestion is refused');
select is(public.store_chapter_suggestions(current_setting('test.lease')::timestamptz,jsonb_build_array(pg_temp.suggestion('Climbing',date '2026-07-07',date '2026-09-20',pg_temp.climb_ids())),'claude-sonnet-5-5','2026-10-18'),1,'A valid suggestion is stored');
select is(public.claim_chapter_suggestion_run()->>'due','false','A recent run is not due again');
select is((select status from public.chapter_suggestions where name='Climbing'),'pending','It waits for the person');
select is(public.pending_chapter_suggestion('2026-10-18')->>'name','Climbing','The Timeline shows the pending suggestion');
select is(public.pending_chapter_suggestion('2026-10-18')->>'entryCount','5','It says how many Entries it is based on');
select is(jsonb_array_length(public.pending_chapter_suggestion('2026-10-18')->'entries'),5,'It lists the cited Entries');
select is(public.pending_chapter_suggestion('2026-10-18')->>'startPrecision','day','It carries the precision of its start');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is(public.pending_chapter_suggestion('2026-10-18'),null::jsonb,'Another owner sees no suggestion');
select is((select count(*) from public.chapter_suggestions),0::bigint,'Another owner cannot read suggestions');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);

-- Creating a Chapter by hand quietly retires a similar suggestion.
reset role;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone) values
 ('82300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000824','Climbing season','','entry','chapter','2026-07-05T12:00Z','2026-09-22T12:00Z','day','UTC');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select is(public.pending_chapter_suggestion('2026-10-18'),null::jsonb,'A Chapter covering the same stretch hides the suggestion');
select is((select status from public.chapter_suggestions where name='Climbing'),'pending','The suggestion stays pending, only hidden');
select is(public.confirm_chapter_suggestion((select id from public.chapter_suggestions where name='Climbing'),'82300000-0000-4000-8000-000000000001'),true,'A suggestion is confirmed with the Chapter that was added');
select is((select status || ':' || cardinality(source_entry_ids) || ':' || coalesce(rationale,'-') from public.chapter_suggestions where name='Climbing'),'confirmed:0:-','Confirming keeps the name only');
select is(public.confirm_chapter_suggestion((select id from public.chapter_suggestions where name='Climbing'),'82300000-0000-4000-8000-000000000001'),false,'A confirmed suggestion cannot be confirmed again');

-- Room, dismissal, and the three-pending limit
reset role;
update public.chapter_suggestion_state set last_run_at=now() - interval '40 days', last_entry_count=14, leased_until=null where owner_id='10000000-0000-0000-0000-000000000824';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select is(public.claim_chapter_suggestion_run()->>'due','false','Thirty days without fifteen new Entries is not due');
reset role;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone)
select ('82400000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'10000000-0000-0000-0000-000000000824','More ' || n,'More words.','entry','entry','2026-09-01T12:00Z'::timestamptz + (n * interval '1 day'),'day','UTC'
from generate_series(1,15) as n;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select lives_ok($$select set_config('test.lease',(public.claim_chapter_suggestion_run()->>'leaseUntil'),true)$$,'Thirty days and fifteen new Entries make a run due');
select is(public.store_chapter_suggestions(current_setting('test.lease')::timestamptz,jsonb_build_array(
  pg_temp.suggestion('Second',date '2026-01-01',date '2026-02-01',pg_temp.climb_ids()),
  pg_temp.suggestion('Third',date '2026-03-01',date '2026-04-01',pg_temp.climb_ids()),
  pg_temp.suggestion('Overlap',date '2026-07-05',date '2026-09-22',pg_temp.climb_ids())),'claude-sonnet-5-5','2026-10-18'),2,'A stretch already covered is not stored again');
select is(public.dismiss_chapter_suggestion((select id from public.chapter_suggestions where name='Second')),true,'A suggestion can be dismissed');
select is((select name is null and rationale is null and cardinality(source_entry_ids)=0 and window_start='2026-01-01' from public.chapter_suggestions where status='dismissed'),true,'Dismissing keeps only the dates');
select is(public.dismiss_chapter_suggestion((select id from public.chapter_suggestions where status='dismissed')),false,'A dismissed suggestion cannot be dismissed again');
reset role;
update public.chapter_suggestion_state set last_run_at=now() - interval '40 days', last_entry_count=0, leased_until=null where owner_id='10000000-0000-0000-0000-000000000824';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select lives_ok($$select set_config('test.lease',(public.claim_chapter_suggestion_run()->>'leaseUntil'),true)$$,'Another run is due');
select is(public.store_chapter_suggestions(current_setting('test.lease')::timestamptz,jsonb_build_array(pg_temp.suggestion('Again',date '2026-01-05',date '2026-01-28',pg_temp.climb_ids())),'claude-sonnet-5-5','2026-10-18'),0,'A dismissed stretch is never proposed again');
reset role;
select ok((select last_run_at > now() - interval '1 minute' from public.chapter_suggestion_state where owner_id='10000000-0000-0000-0000-000000000824'),'A run that stored nothing is still recorded');

-- Turning suggestions off deletes the pending ones and keeps dismissed and confirmed.
update public.chapter_suggestions set status='pending',name='Third again',rationale='Again.',source_entry_ids=array['82200000-0000-4000-8000-000000000001']::uuid[],resolved_at=null where name='Third';
select is((select count(*) from public.chapter_suggestions where owner_id='10000000-0000-0000-0000-000000000824' and status='pending'),1::bigint,'One suggestion is pending');
update public.ai_preferences set chapter_suggestions_enabled=false where owner_id='10000000-0000-0000-0000-000000000824';
select is((select count(*) from public.chapter_suggestions where owner_id='10000000-0000-0000-0000-000000000824' and status='pending'),0::bigint,'Turning suggestions off deletes the pending ones');
select is((select count(*) from public.chapter_suggestions where owner_id='10000000-0000-0000-0000-000000000824' and status in ('dismissed','confirmed')),2::bigint,'Dismissed and confirmed suggestions are kept');
update public.ai_preferences set chapter_suggestions_enabled=true where owner_id='10000000-0000-0000-0000-000000000824';

-- Delete forever of a cited Entry deletes the pending suggestion.
insert into public.chapter_suggestions(owner_id,name,rationale,source_entry_ids,start_date,start_precision,window_start)
values ('10000000-0000-0000-0000-000000000824','Cited','Cites one Entry.',array['82400000-0000-4000-8000-000000000001']::uuid[],'2026-09-01','day','2026-09-01');
delete from public.entries where id='82400000-0000-4000-8000-000000000001';
select is((select count(*) from public.chapter_suggestions where name='Cited'),0::bigint,'Delete forever of a cited Entry deletes the suggestion');
update public.ai_preferences set chapter_suggestions_enabled=false where owner_id='10000000-0000-0000-0000-000000000824';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000824',true);
select is(public.claim_chapter_suggestion_run()->>'due','false','Nothing is due while suggestions are off');
reset role;

-- Notices

insert into auth.users(id,email,raw_user_meta_data) values ('10000000-0000-0000-0000-000000000826','reviews-notice@memotrail.local','{}');
insert into public.ai_preferences(owner_id,reviews_enabled,review_disclosure_version) values ('10000000-0000-0000-0000-000000000826',true,'2026-10-18');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone) values
 ('82500000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000826','Autumn','','entry','chapter','2026-08-01T12:00Z','2026-09-15T12:00Z','day','UTC'),
 ('82500000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000826','Old one','','entry','chapter','2025-01-01T12:00Z','2025-03-01T12:00Z','day','UTC');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone)
select ('82500000-0000-4000-8000-' || lpad((10 + n)::text,12,'0'))::uuid,'10000000-0000-0000-0000-000000000826','Note ' || n,'Words.','entry','entry',
  '2026-08-05T12:00Z'::timestamptz + (n * interval '5 days'),'day','UTC'
from generate_series(1,6) as n;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone)
select ('82500000-0000-4000-8000-' || lpad((30 + n)::text,12,'0'))::uuid,'10000000-0000-0000-0000-000000000826','Last year ' || n,'Words.','entry','entry',
  '2025-02-05T12:00Z'::timestamptz + (n * interval '20 days'),'day','UTC'
from generate_series(1,6) as n;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000826',true);
select is(public.review_notice('2026-10-18')->>'subject','chapter:82500000-0000-4000-8000-000000000001','A Chapter that ended within sixty days is noticed');
select is(public.review_notice('2026-10-18')->>'title','Autumn','The notice names the Chapter');
select is(public.review_notice('2026-12-01')->>'subject',null,'A Chapter that ended long ago is not noticed');
select is(public.review_notice('2027-01-10')->>'subject','year:2026','In January the year that just ended is noticed');
select is(public.review_notice('2026-02-10')->>'subject','year:2025','The year window runs through March');
select is(public.review_notice('2026-04-01')->>'subject',null,'The year window closes after March');
select is(public.resolve_review_notice('year:2025'),true,'A notice can be resolved');
select is(public.review_notice('2026-02-10')->>'subject',null,'A resolved notice never returns');
select is(public.resolve_review_notice('year:2025'),true,'Resolving twice is harmless');
select throws_ok($$select public.resolve_review_notice('anything')$$,'22023','invalid_review_notice','A notice subject has a fixed shape');
select is(public.resolve_review_notice('chapter:82500000-0000-4000-8000-000000000001'),true,'A Chapter notice can be resolved');
select is(public.review_notice('2026-10-18')->>'subject',null,'A resolved Chapter notice never returns');
select is((select count(*) from public.review_notices),2::bigint,'A person sees their own resolved notices');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000821',true);
select is((select count(*) from public.review_notices),0::bigint,'Another owner cannot read notices');
select is(public.review_notice('2026-10-18'),null::jsonb,'Notices need reviews on');
reset role;

select * from finish();
rollback;
