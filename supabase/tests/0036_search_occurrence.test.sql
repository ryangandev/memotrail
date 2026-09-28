begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select is(public.wiki_item_occurrence_window('2017-01-01Z',null,'year','UTC','entry','entry')::text,'[2017-01-01,2018-01-01)','Year covers all possible days');
select is(public.wiki_item_occurrence_window('2024-02-01Z',null,'month','UTC','entry','entry')::text,'[2024-02-01,2024-03-01)','Month includes leap day');
select is(public.wiki_item_occurrence_window('2017-07-10T00:15:00Z',null,'exact','America/Los_Angeles','entry','entry')::text,'[2017-07-09,2017-07-10)','Exact time uses recorded calendar zone');
select is(public.wiki_item_occurrence_window('2017-07-10Z',null,'day','UTC','entry','entry')::text,'[2017-07-10,2017-07-11)','Day is inclusive');
select is(public.wiki_item_occurrence_window('2017-01-01Z','2019-02-03Z','range','UTC','entry','entry')::text,'[2017-01-01,2019-02-04)','Closed range includes its final day');
select is(public.wiki_item_occurrence_window('2017-01-01Z',null,'range','UTC','entry','entry')::text,'[2017-01-01,)','Explicit open range continues');
select is(public.wiki_item_occurrence_window('2017-01-01Z',null,'day','UTC','entity','home')::text,'[2017-01-01,)','Current Home remains ongoing');
select is(public.wiki_item_occurrence_window('2017-01-01Z',null,'day','UTC','entity','vehicle')::text,'[2017-01-01,)','Current Vehicle remains ongoing');
select is(public.wiki_item_occurrence_window('2017-01-01Z','2020-01-01Z','year','UTC','entry','period')::text,'[2017-01-01,2021-01-01)','Partial stage end covers its recorded year');
select is(public.wiki_item_occurrence_window(null,null,'age','UTC','entry','entry'),null::daterange,'Description-only age has no guessed anchor');
select is(public.wiki_item_occurrence_window(null,null,'approximate','UTC','entry','entry'),null::daterange,'Description-only approximate period has no guessed anchor');
select is(public.wiki_item_occurrence_window('2017-01-01Z',null,'unknown','UTC','entry','entry'),null::daterange,'Unknown never exposes a stale anchor');
select is(public.wiki_item_occurrence_window('2017-01-01Z','2017-02-01Z','approximate','UTC','entry','entry')::text,'[2017-01-01,2017-02-02)','Known approximate bounds overlap normally');
select is(public.entry_occurrence_date_text('2017-01-01Z','year','UTC'),'2017','Year indexing never invents January or a day');
select is(public.entry_occurrence_date_text('2017-07-01Z','month','UTC'),'2017-07 July      2017','Month indexing never invents a day');
select is(public.entry_occurrence_date_text('2017-01-01Z','unknown','UTC'),null::text,'Unknown indexing never exposes stale anchor');

insert into auth.users(id,email,raw_user_meta_data) values('10000000-0000-0000-0000-000000000099','search-precision-other@memotrail.local','{}');
insert into public.entries(id,owner_id,title,body,date_precision,occurred_start,occurred_end,occurred_timezone,item_kind,item_subtype) values
 ('96000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000001','Precision year','','year','2017-01-01Z',null,'UTC','entry','entry'),
 ('96000000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000001','Precision month','','month','2017-07-01Z',null,'UTC','entry','entry'),
 ('96000000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000001','Precision range','','range','2016-01-01Z','2019-02-03Z','UTC','entry','entry'),
 ('96000000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000001','Precision unknown','','unknown',null,null,'UTC','entry','entry'),
 ('96000000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000001','Precision stage','','year','2015-01-01Z','2020-01-01Z','UTC','entry','period'),
 ('96000000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000099','Precision foreign','','year','2017-01-01Z',null,'UTC','entry','entry');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.search_wiki_items('Precision','{}','{}','{}','2017-07-10','2017-07-10')),4::bigint,'Canonical search includes overlapping partial dates and ranges');
select is((select count(*) from public.search_wiki_items('Precision','{}','{}','{}','2017-07-10','2017-07-10')),4::bigint,'Canonical search retains overlap and owner isolation');
select is((select date_precision from public.search_wiki_items('Precision year')),'year','New result explicitly carries precision');
select is((select array_agg(entry_id order by ordinality) from public.search_wiki_items('Precision') with ordinality), (select array_agg(entry_id order by ordinality) from public.search_wiki_items('Precision') with ordinality),'New projection preserves relevance ordering');
select is((select occurred_end from public.search_wiki_items('Precision range')),'2019-02-03Z'::timestamptz,'New result preserves range end');
select is((select count(*) from public.search_wiki_items('Precision','{}','{}','{}','2017-07-10','2017-07-10',1,1)),1::bigint,'Pagination still limits a page');
select is((select total_count from public.search_wiki_items('Precision','{}','{}','{}','2017-07-10','2017-07-10',1,1)),4::bigint,'Pagination retains full matching count');
select is((select count(*) from public.search_wiki_items('Precision unknown')),1::bigint,'Unanchored writing remains searchable without dates');
select is((select count(*) from public.search_wiki_items('Precision unknown','{}','{}','{}','2017-01-01',null)),0::bigint,'Date filters never infer dates from creation time');
select is((select count(*) from public.search_wiki_items('2017-01-01') where entry_id='96000000-0000-4000-8000-000000000001'),0::bigint,'A fake full date is not indexed for year-only memory');
select is((select count(*) from public.search_wiki_items('2017-07-01') where entry_id='96000000-0000-4000-8000-000000000002'),0::bigint,'A fake day is not indexed for month-only memory');
select is((select count(*) from public.search_wiki_items('2019-02-03') where entry_id='96000000-0000-4000-8000-000000000003'),1::bigint,'The actual range end is searchable');
select is(jsonb_array_length(public.archive_wiki_search_evidence(array['Precision'],'{}','{}','{}','2017-07-10','2017-07-10')->'entries'),4,'AI evidence shares the same date window');
select throws_ok($$select * from public.search_wiki_items('Precision','{}','{}','{}','infinity',null)$$,'22023','invalid_date_range','Nonfinite bounds are rejected');
update public.entries set deleted_at=now() where id='96000000-0000-4000-8000-000000000001';
select is((select count(*) from public.search_wiki_items('Precision year')),0::bigint,'Trash is excluded by new projection');
reset role;
select ok(not has_function_privilege('anon','public.search_wiki_items(text,text[],text[],text[],date,date,integer,integer,text)','execute'),'Anonymous canonical search is denied');
select * from finish();
rollback;
