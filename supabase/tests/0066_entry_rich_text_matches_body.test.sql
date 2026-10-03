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
create function pg_temp.versions(p_id uuid) returns bigint language sql stable as $$
  select count(*) from public.entry_versions where entry_id = p_id;
$$;
create function pg_temp.provider() returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','provider','provider','geoapify',
    'providerLocationId','rich-text-home','name','10 Pine Street','formattedAddress','10 Pine Street',
    'address','10 Pine Street','city','Philadelphia','region','Pennsylvania','country','United States',
    'countryCode','us','latitude',39.95,'longitude',-75.16,'timezone','America/New_York');
$$;

-- Every focused plaintext writer, including the Location and organization variants.
create temporary table writers(kind text primary key, id uuid);
grant all on writers to authenticated;
create function pg_temp.save(p_kind text, p_id uuid, p_body text) returns uuid language plpgsql as $$
declare
  result uuid;
  current_revision integer := (select revision from public.entries where id = p_id);
  track uuid := (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'other_events');
  input jsonb := jsonb_build_object('title','Rich ' || p_kind,'body',p_body,
    'datePrecision','unknown',
    'collectionNames','[]'::jsonb,'tagNames','[]'::jsonb,'id',p_id,'revision',current_revision);
begin
  if p_kind = 'goal' then
    select entry_id into result from public.save_goal_entry(
      'Rich goal',p_body,'long_term','active',null,'{}','{}','{}',p_id,current_revision);
  elsif p_kind = 'moment' then
    select entry_id into result from public.save_timeline_entry_with_organization(
      track,'event','Rich moment',p_body,null,null,'unknown',null,'UTC','{}','{}',p_id,current_revision);
  elsif p_kind = 'period' then
    select entry_id into result from public.save_timeline_entry_with_occurrence(
      track,'stage','Rich period',p_body,null,null,'unknown',null,'UTC',p_id,current_revision);
  elsif p_kind = 'first_time' then
    select entry_id into result from public.save_first_time_with_occurrence(
      'Rich first time',p_body,null,'unknown',null,null,'{}','{}',p_id,current_revision,null);
  elsif p_kind = 'first_time_location' then
    select entry_id into result from public.save_first_time_with_location(input,null);
  elsif p_kind = 'home' then
    select entry_id into result from public.save_home_entry_with_occurrence(
      'Rich home',p_body,null,null,'unknown',null,'UTC',null,null,null,null,null,null,null,null,
      null,null,null,'{}','{}',p_id,current_revision);
  elsif p_kind = 'home_geoapify' then
    result := (public.save_home_entry_with_geoapify(input || '{"occurredTimezone":"UTC"}',null,
      pg_temp.provider())->>'entry_id')::uuid;
  elsif p_kind = 'vehicle' then
    select entry_id into result from public.save_vehicle_entry_with_occurrence(
      'Rich vehicle',p_body,null,null,'unknown',null,'UTC','Honda','Civic',2018,'Blue','{}','{}',
      p_id,current_revision);
  elsif p_kind = 'vehicle_location' then
    select entry_id into result from public.save_vehicle_with_location(input,null,null);
  end if;
  return result;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000141',true);

-- The reported path: a linked Goal copies an Item's formatting, then its focused editor
-- replaces the writing.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision,metadata)
values ('96600000-0000-4000-8000-000000000001',auth.uid(),'Marathon plan','Run zebrafinch marathon',
  'entry','entry','organized','unknown',jsonb_build_object('body_rich',pg_temp.rich('Run zebrafinch marathon')));
select is(
  (select goal_entry_id from public.extract_goal_from_item('96600000-0000-4000-8000-000000000001',1,
    '96600000-0000-4000-8000-000000000002','Marathon goal','short_term','active',null)),
  '96600000-0000-4000-8000-000000000002'::uuid,
  'A formatted Item creates a linked Goal'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000002'),'Run zebrafinch marathon',
  'The linked Goal copies formatting that matches its writing');
select is(
  (select revision from public.save_goal_entry('Renamed goal','Run zebrafinch marathon','short_term','active',
    null,'{}','{}','{}','96600000-0000-4000-8000-000000000002',1)),
  2,
  'A Goal save with unchanged writing advances one revision'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000002'),'Run zebrafinch marathon',
  'A Goal save with unchanged writing keeps its formatting');
select is(pg_temp.versions('96600000-0000-4000-8000-000000000002'),1::bigint,
  'Keeping formatting adds no history version of its own');
select is(
  (select revision from public.save_goal_entry('Renamed goal','Run a half marathon','short_term','active',
    null,'{}','{}','{}','96600000-0000-4000-8000-000000000002',2)),
  3,
  'A Goal save with new writing advances one revision'
);
select is((select body from public.entries where id = '96600000-0000-4000-8000-000000000002'),
  'Run a half marathon','The Goal stores the new writing');
select ok(not (select metadata ? 'body_rich' from public.entries where id = '96600000-0000-4000-8000-000000000002'),
  'The Goal drops formatting for writing it no longer has');
select is(pg_temp.versions('96600000-0000-4000-8000-000000000002'),2::bigint,
  'Dropping formatting adds no history version of its own');
select is(
  (select snapshot->'metadata'->'body_rich'->>'text' from public.entry_versions
   where entry_id = '96600000-0000-4000-8000-000000000002' and version = 2),
  'Run zebrafinch marathon',
  'History keeps the formatting the Goal had before the edit'
);
select is(
  (select count(*) from public.search_wiki_items('zebrafinch') where entry_id = '96600000-0000-4000-8000-000000000002'),
  0::bigint,
  'Search no longer finds the Goal by writing it removed'
);
select is(
  (select count(*) from public.search_wiki_items('zebrafinch') where entry_id = '96600000-0000-4000-8000-000000000001'),
  1::bigint,
  'The source Item still matches its own writing'
);
select is(
  (select count(*) from public.search_wiki_items('half marathon') where entry_id = '96600000-0000-4000-8000-000000000002'),
  1::bigint,
  'Search finds the Goal by its new writing'
);

-- Restoring replays a snapshot's metadata through the same rule.
select is(public.restore_entry_version('96600000-0000-4000-8000-000000000002',2,3),4,
  'Restoring the formatted version succeeds');
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000002'),'Run zebrafinch marathon',
  'Restoring a version restores formatting that matches its writing');
reset role;
update public.entry_versions
set snapshot = jsonb_set(snapshot,'{metadata,body_rich}',pg_temp.rich('Run zebrafinch marathon'))
where entry_id = '96600000-0000-4000-8000-000000000002' and version = 3;
set local role authenticated;
select is(public.restore_entry_version('96600000-0000-4000-8000-000000000002',3,4),5,
  'Restoring a version with outdated formatting succeeds');
select is((select body from public.entries where id = '96600000-0000-4000-8000-000000000002'),
  'Run a half marathon','The restored writing is canonical');
select ok(not (select metadata ? 'body_rich' from public.entries where id = '96600000-0000-4000-8000-000000000002'),
  'Restoring never revives formatting for different writing');

-- Each focused writer keeps matching formatting and drops it once the writing changes.
insert into writers
select kind, pg_temp.save(kind,null,'Original words')
from unnest(array['goal','moment','period','first_time','first_time_location','home','home_geoapify',
  'vehicle','vehicle_location']) as kind;
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

-- Review RPCs still set, keep, and clear formatting.
insert into public.entries(id,owner_id,title,body,item_kind,item_subtype,inbox_status,date_precision,occurred_timezone,metadata)
values ('96600000-0000-4000-8000-000000000005',auth.uid(),'Review','Review words','entry','entry',
  'organized','unknown','UTC',jsonb_build_object('body_rich',pg_temp.rich('Review words')));
select is(
  (select revision from public.review_wiki_item_with_photo_place('96600000-0000-4000-8000-000000000005',1,
    'Reviewed','Review words','entry','entry',null,'UTC','{}','{}',false,null,null,'unknown',null)),
  2,
  'A plaintext review with unchanged writing succeeds'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000005'),'Review words',
  'A plaintext review keeps formatting it cannot author while the writing is unchanged');
select is(
  (select revision from public.review_wiki_item_with_photo_place_rich('96600000-0000-4000-8000-000000000005',2,
    'Reviewed','Formatted words','entry','entry',null,'UTC','{}','{}',false,null,null,'unknown',null,
    pg_temp.rich('Formatted words'))),
  3,
  'A rich review saves new writing with its formatting'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000005'),'Formatted words',
  'A rich review stores formatting for its new writing');
select is(
  (select revision from public.review_wiki_item_with_location_rich('96600000-0000-4000-8000-000000000005',3,
    'Reviewed','Located words','entry','entry',null,'UTC','{}','{}',false,null,null,'unknown',null,null,
    pg_temp.rich('Located words'))),
  4,
  'A Location review saves new writing with its formatting'
);
select is(pg_temp.rich_text('96600000-0000-4000-8000-000000000005'),'Located words',
  'A Location review stores formatting for its new writing');
select is(
  (select revision from public.review_wiki_item_with_photo_place('96600000-0000-4000-8000-000000000005',4,
    'Reviewed','Plain edit','entry','entry',null,'UTC','{}','{}',false,null,null,'unknown',null)),
  5,
  'A plaintext review with new writing succeeds'
);
select ok(not (select metadata ? 'body_rich' from public.entries where id = '96600000-0000-4000-8000-000000000005'),
  'A plaintext review drops formatting for writing it replaced');

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
