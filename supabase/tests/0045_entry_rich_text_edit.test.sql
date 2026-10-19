begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000095','rich-entry-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000096','rich-entry-other@memotrail.local');
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_timezone,metadata) values
  ('96000000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000095','Rich Entry','Original words','entry','entry','unknown','UTC',
   '{"body_rich":{"version":1,"text":"Original words","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Original words","marks":[{"type":"bold"}]}]}]}}}');

create function pg_temp.rich_review(rev integer, body text, rich jsonb) returns bigint language sql as $$
  select count(*) from public.save_entry(
    '96000000-0000-4000-8000-000000000001',rev,'Rich Entry',body, rich,
    null,null,'UTC',null,'unknown','{}',null, null, false, false);
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);

select is(
  pg_temp.rich_review(1,'Updated words',
    '{"version":1,"text":"Updated words","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Updated words","marks":[{"type":"italic"}]}]}]}}'),
  1::bigint,
  'Rich review updates writing and formatting atomically'
);
select is((select body from public.entries where id='96000000-0000-4000-8000-000000000001'),'Updated words','Plaintext stays canonical');
select is((select metadata->'body_rich'->'document'->'content'->0->'content'->0->'marks'->0->>'type' from public.entries where id='96000000-0000-4000-8000-000000000001'),'italic','Rich formatting is stored in metadata');
select is((select revision from public.entries where id='96000000-0000-4000-8000-000000000001'),2,'One rich save advances one revision');

select throws_ok(
  $$select pg_temp.rich_review(2,'Mismatch','{"version":1,"text":"Different","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Different"}]}]}}')$$,
  '22023','invalid_rich_text','Rich text must match canonical plaintext'
);
select is((select revision from public.entries where id='96000000-0000-4000-8000-000000000001'),2,'Invalid rich text changes nothing');
select is(pg_temp.rich_review(2,'Plain again',null),1::bigint,'Rich formatting can be removed explicitly');
select ok(not (select metadata ? 'body_rich' from public.entries where id='96000000-0000-4000-8000-000000000001'),'Clearing formatting removes only the rich text key');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',true);
select is(pg_temp.rich_review(3,'Foreign edit',null),0::bigint,'Another owner cannot edit rich text');
reset role;

select ok(
  not has_function_privilege('anon','public.save_entry(uuid,integer,text,text,jsonb,timestamptz,timestamptz,text,text,text,text[],jsonb,jsonb,boolean,boolean)','execute'),
  'Anonymous rich review denied'
);
select * from finish();
rollback;
