begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- A Chapter contains an Entry when the Chapter's days contain all of the Entry's days, each
-- read in its own recorded time zone. Nothing is stored, so every case below is a read.

insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000791','chapter-contents-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000792','chapter-contents-order@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000793','chapter-contents-other@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000794','chapter-contents-overlap@memotrail.local','{}');

-- One row per worked case: the Chapter, the Entry, and whether the Entry is inside.
create temporary table chapter_cases as
select row_number() over () as n, *
from (values
  ('Day chapter holds its first day', '2020-03-15T12:00Z'::timestamptz, '2021-06-30T12:00Z'::timestamptz, 'day', 'UTC', '2020-03-15T12:00Z'::timestamptz, null::timestamptz, 'day', 'UTC', true),
  ('Day chapter holds its last day', '2020-03-15T12:00Z', '2021-06-30T12:00Z', 'day', 'UTC', '2021-06-30T12:00Z', null, 'day', 'UTC', true),
  ('Day chapter excludes the day after', '2020-03-15T12:00Z', '2021-06-30T12:00Z', 'day', 'UTC', '2021-07-01T12:00Z', null, 'day', 'UTC', false),
  ('Month chapter holds the last day of its last month', '2020-03-01T00:00Z', '2021-06-01T00:00Z', 'month', 'UTC', '2021-06-30T12:00Z', null, 'day', 'UTC', true),
  ('Month chapter excludes the day before its first month', '2020-03-01T00:00Z', '2021-06-01T00:00Z', 'month', 'UTC', '2020-02-29T12:00Z', null, 'day', 'UTC', false),
  ('Month chapter holds a Month entry in its last month', '2020-03-01T00:00Z', '2021-06-01T00:00Z', 'month', 'UTC', '2021-06-01T00:00Z', null, 'month', 'UTC', true),
  ('Day chapter excludes a Month entry it covers only in part', '2021-06-10T12:00Z', '2021-08-01T12:00Z', 'day', 'UTC', '2021-06-01T00:00Z', null, 'month', 'UTC', false),
  ('Year chapter holds the last day of its last year', '2019-01-01T00:00Z', '2021-01-01T00:00Z', 'year', 'UTC', '2021-12-31T12:00Z', null, 'day', 'UTC', true),
  ('Year chapter holds a Year entry in its last year', '2019-01-01T00:00Z', '2021-01-01T00:00Z', 'year', 'UTC', '2021-01-01T00:00Z', null, 'year', 'UTC', true),
  ('Open chapter excludes a Year entry it covers only in part', '2021-03-01T12:00Z', null, 'day', 'UTC', '2021-01-01T00:00Z', null, 'year', 'UTC', false),
  ('Open chapter holds a later day', '2021-03-01T12:00Z', null, 'day', 'UTC', '2030-01-01T12:00Z', null, 'day', 'UTC', true),
  ('Open chapter holds an onward range that starts after it', '2014-01-01T12:00Z', null, 'day', 'UTC', '2015-01-01T12:00Z', null, 'range', 'UTC', true),
  ('Closed chapter excludes an onward range', '2013-01-01T00:00Z', '2017-01-01T00:00Z', 'year', 'UTC', '2015-01-01T12:00Z', null, 'range', 'UTC', false),
  ('Day chapter excludes a range that runs past its end', '2020-01-01T12:00Z', '2020-12-31T12:00Z', 'day', 'UTC', '2020-05-01T12:00Z', '2021-02-01T12:00Z', 'range', 'UTC', false),
  ('Day chapter holds a Not sure date by its rough day', '2020-01-01T12:00Z', '2020-12-31T12:00Z', 'day', 'UTC', '2020-04-01T12:00Z', null, 'approximate', 'UTC', true),
  ('Anchored chapter excludes an Unknown date', '2020-01-01T12:00Z', '2020-12-31T12:00Z', 'day', 'UTC', null, null, 'unknown', 'UTC', false),
  ('Anchored chapter excludes a Not sure date without a rough day', '2020-01-01T12:00Z', '2020-12-31T12:00Z', 'day', 'UTC', null, null, 'approximate', 'UTC', false),
  ('A Not sure chapter without a rough start holds nothing', null, null, 'approximate', 'UTC', '2020-04-01T12:00Z', null, 'day', 'UTC', false),
  ('An Unknown chapter holds nothing', null, null, 'unknown', 'UTC', '2020-04-01T12:00Z', null, 'day', 'UTC', false),
  ('Each side is read in its own time zone', '2020-03-14T20:00Z', null, 'day', 'Asia/Tokyo', '2020-03-15T04:00Z', null, 'day', 'America/Los_Angeles', false),
  ('A null Entry zone reads as UTC', '2020-03-15T12:00Z', null, 'day', 'UTC', '2020-03-15T12:00Z', null, 'day', null, true)
) as c(label, c_start, c_end, c_precision, c_zone, e_start, e_end, e_precision, e_zone, inside);

insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,occurred_label)
select ('79100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '10000000-0000-0000-0000-000000000791', 'Chapter ' || n, '', 'entry', 'chapter',
  c_start, c_end, c_precision, c_zone, case when c_precision = 'approximate' then 'college years' end
from chapter_cases;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,occurred_label)
select ('79200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '10000000-0000-0000-0000-000000000791', 'Entry ' || n, 'Words', 'entry', 'entry',
  e_start, e_end, e_precision, e_zone, case when e_precision = 'approximate' then 'spring' end
from chapter_cases;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000791',true);

select is(
  exists(
    select 1
    from public.chapter_entries(('79100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 100, 0) as member
    where member.entry_id = ('79200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
  ),
  inside,
  label
) from chapter_cases order by n;

-- Other kinds of items never count as inside.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,deleted_at) values
 ('79300000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000791','Wide chapter','','entry','chapter','2000-01-01T12:00Z','2030-01-01T12:00Z','day','UTC',null),
 ('79300000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000791','Trashed entry','Gone','entry','entry','2010-05-05T12:00Z',null,'day','UTC',now()),
 ('79300000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000791','Nested chapter','','entry','chapter','2010-01-01T12:00Z','2010-12-31T12:00Z','day','UTC',null),
 ('79300000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000793','Foreign entry','Private','entry','entry','2010-05-05T12:00Z',null,'day','UTC',null),
 ('79300000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000791','Inside entry','Words','entry','entry','2010-05-06T12:00Z',null,'day','UTC',null);

select is(
  (select array_agg(member.entry_id order by member.entry_id) filter (where member.entry_id::text like '7930%')
   from public.chapter_entries('79300000-0000-4000-8000-000000000001', 100, 0) as member),
  array['79300000-0000-4000-8000-000000000005']::uuid[],
  'Trash, other Chapters, and other owners are not inside a Chapter'
);

-- Entries are listed oldest first by the days they cover, then start, creation, and ID.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,created_at) values
 ('79400000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000792','Order chapter','','entry','chapter','2020-01-01T12:00Z','2020-12-31T12:00Z','day','UTC','2026-01-01'),
 ('79400000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000792','June day','x','entry','entry','2020-06-15T12:00Z',null,'day','UTC','2026-01-02'),
 ('79400000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000792','March month','x','entry','entry','2020-03-01T00:00Z',null,'month','UTC','2026-01-03'),
 ('79400000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000792','Whole year','x','entry','entry','2020-01-01T00:00Z',null,'year','UTC','2026-01-04'),
 ('79400000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000792','March first day','x','entry','entry','2020-03-01T12:00Z',null,'day','UTC','2026-01-05'),
 ('79400000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000792','Later same day','x','entry','entry','2020-03-01T12:00Z',null,'day','UTC','2026-01-06');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000792',true);
select is(
  (select array_agg(title order by ordinality)
   from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) with ordinality),
  array['Whole year','March month','March first day','Later same day','June day'],
  'Entries read oldest first, and a Month or Year sorts at the start of its period'
);
select is(
  (select max(total_count) from public.chapter_entries('79400000-0000-4000-8000-000000000001', 2, 0)),
  5::bigint,
  'The total counts every Entry inside, not the page'
);
select is(
  (select array_agg(title order by ordinality)
   from public.chapter_entries('79400000-0000-4000-8000-000000000001', 2, 2) with ordinality),
  array['March first day','Later same day'],
  'Limit and offset page through the Entries'
);
select is(
  (select count(*) from public.chapter_entries('79400000-0000-4000-8000-000000000001', 2, 4)),
  1::bigint,
  'The last page holds the remainder'
);
select is(
  (select occurred_label from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'Whole year'),
  null::text,
  'An Entry keeps its own precision for display'
);
select is(
  (select date_precision from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'March month'),
  'month',
  'A Month Entry is returned with its Month precision, never an invented day'
);

select throws_ok($$select * from public.chapter_entries(null, 50, 0)$$, '22023', 'invalid_chapter_page', 'A page needs a Chapter');
select throws_ok($$select * from public.chapter_entries('79400000-0000-4000-8000-000000000001', 0, 0)$$, '22023', 'invalid_chapter_page', 'A page needs at least one row');
select throws_ok($$select * from public.chapter_entries('79400000-0000-4000-8000-000000000001', 101, 0)$$, '22023', 'invalid_chapter_page', 'A page is bounded');
select throws_ok($$select * from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, -1)$$, '22023', 'invalid_chapter_page', 'An offset is not negative');
select throws_ok($$select * from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 100001)$$, '22023', 'invalid_chapter_page', 'An offset is bounded');

-- Tags and the cover photo come with each Entry.
reset role;
insert into public.tags(id,owner_id,name) values
 ('79500000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000792','beta'),
 ('79500000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000792','Alpha');
insert into public.entry_tags(entry_id,tag_id,owner_id) values
 ('79400000-0000-4000-8000-000000000002','79500000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000792'),
 ('79400000-0000-4000-8000-000000000002','79500000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000792');
insert into public.attachments(id,owner_id,entry_id,variant,object_path,original_filename,mime_type,byte_size,pixel_width,pixel_height,created_at,deleted_at) values
 ('79600000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000792','79400000-0000-4000-8000-000000000002','original','10000000-0000-0000-0000-000000000792/doc.pdf','doc.pdf','application/pdf',10,null,null,'2026-01-01',null),
 ('79600000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000792','79400000-0000-4000-8000-000000000002','original','10000000-0000-0000-0000-000000000792/removed.jpg','removed.jpg','image/jpeg',10,10,10,'2026-01-02',now()),
 ('79600000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000792','79400000-0000-4000-8000-000000000002','original','10000000-0000-0000-0000-000000000792/first.jpg','first.jpg','image/jpeg',100,640,480,'2026-01-03',null),
 ('79600000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000792','79400000-0000-4000-8000-000000000002','original','10000000-0000-0000-0000-000000000792/second.jpg','second.jpg','image/jpeg',100,640,480,'2026-01-04',null);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000792',true);
set local role authenticated;
select is(
  (select tag_names from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'June day'),
  array['Alpha','beta'],
  'Tag names read in case-insensitive order'
);
select is(
  (select cover_photo->>'attachment_id' from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'June day'),
  '79600000-0000-4000-8000-000000000003',
  'The cover is the first active original image'
);
select is(
  (select cover_photo->>'original_filename' from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'June day'),
  'first.jpg',
  'The cover carries the fields the Web signs'
);
select is(
  (select cover_photo from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'Whole year'),
  null::jsonb,
  'An Entry without a photo has no cover'
);
select is(
  (select excerpt from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0) where title = 'June day'),
  'x',
  'Each row carries a short excerpt of the writing'
);

-- Chapters that return nothing.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,occurred_label,deleted_at) values
 ('79700000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000792','Unanchored chapter','','entry','chapter',null,null,'approximate','UTC','college years',null),
 ('79700000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000792','Trashed chapter','','entry','chapter','2020-01-01T12:00Z','2020-12-31T12:00Z','day','UTC',null,now());
select is((select count(*) from public.chapter_entries('79700000-0000-4000-8000-000000000001', 50, 0)), 0::bigint, 'A Chapter with no calendar days contains nothing');
select is((select count(*) from public.chapter_entries('79700000-0000-4000-8000-000000000002', 50, 0)), 0::bigint, 'A Chapter in Trash contains nothing');
select is((select count(*) from public.chapter_entries('79400000-0000-4000-8000-000000000002', 50, 0)), 0::bigint, 'An ordinary Entry is not a Chapter');
select is((select count(*) from public.chapter_entries('79400000-0000-4000-8000-000000000099', 50, 0)), 0::bigint, 'A missing Chapter contains nothing');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000793',true);
select is((select count(*) from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0)), 0::bigint, 'Another owner reads no Chapter');
select set_config('request.jwt.claim.sub','',true);
select is((select count(*) from public.chapter_entries('79400000-0000-4000-8000-000000000001', 50, 0)), 0::bigint, 'A signed-out caller reads no Chapter');

-- Chapters that share any day with this one: nested, partly overlapping, and open.
reset role;
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,occurred_end,date_precision,occurred_timezone,deleted_at) values
 ('79800000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000794','Main chapter','','entry','chapter','2020-01-01T12:00Z','2020-12-31T12:00Z','day','UTC',null),
 ('79800000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000794','Nested inside','','entry','chapter','2020-03-01T12:00Z','2020-04-01T12:00Z','day','UTC',null),
 ('79800000-0000-4000-8000-000000000003','10000000-0000-0000-0000-000000000794','Starts before','','entry','chapter','2019-06-01T00:00Z','2020-06-01T00:00Z','month','UTC',null),
 ('79800000-0000-4000-8000-000000000004','10000000-0000-0000-0000-000000000794','Open from December','','entry','chapter','2020-12-31T12:00Z',null,'day','UTC',null),
 ('79800000-0000-4000-8000-000000000005','10000000-0000-0000-0000-000000000794','Ends the day before','','entry','chapter','2019-01-01T12:00Z','2019-12-31T12:00Z','day','UTC',null),
 ('79800000-0000-4000-8000-000000000006','10000000-0000-0000-0000-000000000794','Starts the day after','','entry','chapter','2021-01-01T12:00Z','2021-02-01T12:00Z','day','UTC',null),
 ('79800000-0000-4000-8000-000000000007','10000000-0000-0000-0000-000000000794','Trashed overlap','','entry','chapter','2020-05-01T12:00Z','2020-05-02T12:00Z','day','UTC',now()),
 ('79800000-0000-4000-8000-000000000008','10000000-0000-0000-0000-000000000793','Foreign overlap','','entry','chapter','2020-05-01T12:00Z','2020-05-02T12:00Z','day','UTC',null),
 ('79800000-0000-4000-8000-000000000009','10000000-0000-0000-0000-000000000794','Not sure overlap','','entry','chapter',null,null,'approximate','UTC',null);
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000794',true);
select is(
  (select array_agg(title order by ordinality) from public.chapter_overlaps('79800000-0000-4000-8000-000000000001') with ordinality),
  array['Starts before','Nested inside','Open from December'],
  'Nested, partly overlapping, and open Chapters are listed by start; touching, trashed, foreign, and undated ones are not'
);
select is(
  (select window_start || '/' || coalesce(window_end::text, 'open')
   from public.chapter_overlaps('79800000-0000-4000-8000-000000000001') where title = 'Starts before'),
  '2019-06-01/2020-07-01',
  'Overlaps report the days of each Chapter, with an exclusive end'
);
select is(
  (select coalesce(window_end::text, 'open') from public.chapter_overlaps('79800000-0000-4000-8000-000000000001') where title = 'Open from December'),
  'open',
  'An open Chapter has no end day'
);
select is((select count(*) from public.chapter_overlaps('79800000-0000-4000-8000-000000000001') where entry_id = '79800000-0000-4000-8000-000000000001'), 0::bigint, 'A Chapter is not listed as overlapping itself');
select is((select count(*) from public.chapter_overlaps('79800000-0000-4000-8000-000000000009')), 0::bigint, 'A Chapter with no calendar days overlaps nothing');
select is((select count(*) from public.chapter_overlaps('79800000-0000-4000-8000-000000000007')), 0::bigint, 'A Chapter in Trash overlaps nothing');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,occurred_start,date_precision,occurred_timezone) values ('79800000-0000-4000-8000-000000000010','10000000-0000-0000-0000-000000000794','Plain entry','x','entry','entry','2020-05-01T12:00Z','day','UTC');
select is((select count(*) from public.chapter_overlaps('79800000-0000-4000-8000-000000000010')), 0::bigint, 'An ordinary Entry has no overlaps');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000793',true);
select is((select count(*) from public.chapter_overlaps('79800000-0000-4000-8000-000000000001')), 0::bigint, 'Another owner reads no overlaps');

reset role;
select ok(not has_function_privilege('anon','public.chapter_entries(uuid,integer,integer)','execute'), 'Signed-out visitors cannot read a Chapter''s Entries');
select ok(not has_function_privilege('anon','public.chapter_overlaps(uuid)','execute'), 'Signed-out visitors cannot read overlapping Chapters');
select ok(not has_function_privilege('anon','public.chapter_window(timestamptz,timestamptz,text,text)','execute'), 'Signed-out visitors cannot call the Chapter window');
select ok(not has_function_privilege('anon','public.entry_date_window(timestamptz,timestamptz,text,text)','execute'), 'Signed-out visitors cannot call the Entry window');
select ok(has_function_privilege('authenticated','public.chapter_entries(uuid,integer,integer)','execute'), 'Signed-in users can read a Chapter''s Entries');
select * from finish();
rollback;
