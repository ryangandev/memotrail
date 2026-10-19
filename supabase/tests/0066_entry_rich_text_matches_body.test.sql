begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000141','rich-text-matches-body@memotrail.local');

-- The bold single-paragraph document Web and native Capture store for plain writing.
create function pg_temp.rich(p_text text) returns jsonb language sql immutable as $$
  select jsonb_build_object('version',1,'text',p_text,'document',jsonb_build_object(
    'type','doc','content',jsonb_build_array(jsonb_build_object('type','paragraph','content',
      jsonb_build_array(jsonb_build_object('type','text','text',p_text,
        'marks',jsonb_build_array(jsonb_build_object('type','bold'))))))));
$$;
create function pg_temp.rich_text(p_id uuid) returns text language sql stable as $$
  select metadata->'body_rich'->>'text' from public.entries where id = p_id;
$$;
create function pg_temp.provider() returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','provider','provider','geoapify',
    'providerLocationId','rich-text-home','formattedAddress','10 Pine Street',
    'address','10 Pine Street','city','Philadelphia','region','Pennsylvania','country','United States',
    'countryCode','us','latitude',39.95,'longitude',-75.16,'timezone','America/New_York');
$$;

-- Every writer of an Entry, including the Chapter and Location variants.
create temporary table writers(kind text primary key, id uuid);
grant all on writers to authenticated;
create function pg_temp.save(p_kind text, p_id uuid, p_body text) returns uuid language plpgsql as $$
declare
  result uuid;
  current_revision integer := (select revision from public.entries where id = p_id);
begin
  select entry_id into result from public.save_entry(
    coalesce(p_id, gen_random_uuid()), current_revision, 'Rich ' || p_kind, p_body,
    (select entries.metadata->'body_rich' from public.entries
     where entries.id = p_id and entries.metadata->'body_rich'->>'text' = p_body),
    null, null, 'UTC', null, 'unknown', '{}',
    case when p_kind like '%location' then pg_temp.provider() end, null,
    p_kind like 'chapter%', p_kind = 'first_time');
  return result;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000141',true);

-- Each writer keeps matching formatting and drops it once the writing changes.
insert into writers
select kind, pg_temp.save(kind,null,'Original words')
from unnest(array['chapter','chapter_location','first_time','plain']) as kind;
select isnt(id,null,kind || ' is created') from writers;
-- Record formatting the way Capture and Inbox review store it.
update public.entries
set metadata = metadata || jsonb_build_object('body_rich',pg_temp.rich(body),'kept','yes')
where id in (select id from writers);
select is(pg_temp.save(kind,id,'Original words'),id,kind || ' saves unchanged writing') from writers;
select is(pg_temp.rich_text(id),'Original words',kind || ' keeps formatting that matches its writing') from writers;
select is(pg_temp.save(kind,id,'Edited words'),id,kind || ' saves new writing') from writers;
select is((select body from public.entries where entries.id = writers.id),'Edited words',
  kind || ' stores the new writing') from writers;
select ok(not (select metadata ? 'body_rich' from public.entries where entries.id = writers.id),
  kind || ' drops formatting for writing it no longer has') from writers;
select is((select metadata->>'kept' from public.entries where entries.id = writers.id),'yes',
  kind || ' keeps unrelated metadata') from writers;

-- Direct Capture inserts and client updates follow the same rule.
insert into public.entries(id,owner_id,title,body,metadata) values
  ('96600000-0000-4000-8000-000000000003',auth.uid(),'Capture','Matching words',
    jsonb_build_object('body_rich',pg_temp.rich('Matching words'))),
  ('96600000-0000-4000-8000-000000000004',auth.uid(),'Capture','Different words',
    jsonb_build_object('body_rich',pg_temp.rich('Other words'),'client','web'));
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000003'),'Matching words',
  'A Capture keeps formatting that matches its writing');
select is((select metadata from public.entries where id = '96600000-0000-4000-8000-000000000004'),
  '{"client":"web"}'::jsonb,'A Capture cannot store formatting for different writing');
update public.entries set title = 'Retitled capture' where id = '96600000-0000-4000-8000-000000000003';
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000003'),'Matching words',
  'A direct update that keeps the writing keeps its formatting');
update public.entries set body = 'Changed directly' where id = '96600000-0000-4000-8000-000000000003';
select ok(not (select metadata ? 'body_rich' from public.entries where id = '96600000-0000-4000-8000-000000000003'),
  'A direct update that changes the writing drops its formatting');

-- Reviews set, keep, and clear formatting.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,date_precision,occurred_timezone,metadata)
values ('96600000-0000-4000-8000-000000000005',auth.uid(),'Review','Review words','entry','entry',
  'unknown','UTC',jsonb_build_object('body_rich',pg_temp.rich('Review words')));
select is(
  (select revision from public.save_entry('96600000-0000-4000-8000-000000000005',1,
    'Reviewed','Review words', pg_temp.rich('Review words'),null,null,'UTC',null,'unknown','{}',null, null, false, false)),
  2,
  'A review with unchanged writing succeeds'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000005'),'Review words',
  'A review with unchanged writing keeps its formatting');
select is(
  (select revision from public.save_entry('96600000-0000-4000-8000-000000000005',2,
    'Reviewed','Formatted words', pg_temp.rich('Formatted words'),null,null,'UTC',null,'unknown','{}',null, null, false, false)),
  3,
  'A rich review saves new writing with its formatting'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000005'),'Formatted words',
  'A rich review stores formatting for its new writing');
select is(
  (select revision from public.save_entry('96600000-0000-4000-8000-000000000005',3,
    'Reviewed','Plain edit', null,null,null,'UTC',null,'unknown','{}',null, null, false, false)),
  4,
  'A review without formatting saves new writing'
);
select ok(not (select metadata ? 'body_rich' from public.entries where id = '96600000-0000-4000-8000-000000000005'),
  'A review without formatting drops formatting for writing it replaced');

select is(
  (select count(*) from public.entries
   where owner_id = auth.uid() and metadata ? 'body_rich' and metadata->'body_rich'->>'text' is distinct from body),
  0::bigint,
  'No Entry keeps formatting for writing it no longer has'
);
reset role;

select has_trigger('public','entries','discard_stale_entry_rich_text','Entries enforce formatting consistency');
select ok(
  not has_function_privilege('authenticated','public.discard_stale_entry_rich_text()','execute'),
  'Clients cannot call the formatting trigger function'
);
select * from finish();
rollback;
