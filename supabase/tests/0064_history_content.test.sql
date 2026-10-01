begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Timestamps must differ even inside this test's single transaction.
create function pg_temp.save_home(p_id uuid default null, p_revision integer default null,
  p_title text default 'History flat', p_reason text default 'Study')
returns uuid language sql as $$
  select entry_id from public.save_home_entry_with_occurrence(
    p_title, 'Home memories', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC',
    (select place_id from public.homes where entry_id = p_id), 'Maple Street',
    '10 Maple Street', 'Philadelphia', 'Pennsylvania', 'United States',
    39.95, -75.16, null, p_reason, null, '{}', '{}', p_id, p_revision
  );
$$;
create function pg_temp.save_vehicle(p_id uuid default null, p_revision integer default null,
  p_title text default 'History Civic', p_color text default 'Blue')
returns uuid language sql as $$
  select entry_id from public.save_vehicle_entry_with_occurrence(
    p_title, 'Vehicle memories', '2021-04-12T12:00:00Z', null, 'day', null, 'UTC',
    'Honda', 'Civic', 2018, p_color, '{}', '{}', p_id, p_revision
  );
$$;
create function pg_temp.differences(p_id uuid, p_version integer)
returns text[] language sql as $$
  select coalesce(array_agg(key order by key), '{}'::text[])
  from public.entry_history(p_id) as history,
    jsonb_each(history->'current') as current
  where key in ('title', 'places', 'timeline_items', 'home', 'vehicle')
    and value is distinct from (
      select version->'snapshot'->key
      from jsonb_array_elements(history->'versions') as version
      where (version->>'version')::integer = p_version
    );
$$;
create temporary table fixtures(kind text, id uuid);
grant all on fixtures to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
insert into fixtures(kind, id) values ('home', pg_temp.save_home()), ('vehicle', pg_temp.save_vehicle());
reset role;
update public.entry_places set created_at = '2000-01-01' where entry_id in (select id from fixtures);
update public.timeline_items set created_at = '2000-01-01' where entry_id in (select id from fixtures);
update public.homes set created_at = '2000-01-01' where entry_id in (select id from fixtures);
update public.vehicles set created_at = '2000-01-01' where entry_id in (select id from fixtures);
-- Bypass only the timestamp trigger to install an old update time as a fixture.
alter table public.homes disable trigger homes_set_updated_at;
update public.homes set updated_at = '2000-01-01' where entry_id in (select id from fixtures);
alter table public.homes enable trigger homes_set_updated_at;
alter table public.vehicles disable trigger vehicles_set_updated_at;
update public.vehicles set updated_at = '2000-01-01' where entry_id in (select id from fixtures);
alter table public.vehicles enable trigger vehicles_set_updated_at;
set local role authenticated;
select pg_temp.save_home(id, 1, 'History flat', 'Work') from fixtures where kind = 'home';
select pg_temp.save_vehicle(id, 1, 'History Civic', 'Red') from fixtures where kind = 'vehicle';
select is((select created_at from public.entry_places where entry_id = (select id from fixtures where kind = 'home') and relationship = 'home'),
  '2000-01-01'::timestamptz, 'Unchanged Home Location membership retains created_at');
select is((select created_at from public.timeline_items where entry_id = (select id from fixtures where kind = 'home')),
  '2000-01-01'::timestamptz, 'Unchanged Home Timeline placement retains created_at');
select is((select created_at from public.timeline_items where entry_id = (select id from fixtures where kind = 'vehicle')),
  '2000-01-01'::timestamptz, 'Unchanged Vehicle Timeline placement retains created_at');
select is(pg_temp.differences((select id from fixtures where kind = 'home'), 1),
  array['home'], 'Changing only a move-in reason changes only Home details');
select is(pg_temp.differences((select id from fixtures where kind = 'vehicle'), 1),
  array['vehicle'], 'Changing only color changes only Vehicle details');
select ok((select updated_at > '2000-01-01'::timestamptz from public.homes where entry_id = (select id from fixtures where kind = 'home')),
  'A real Home detail change advances updated_at');
select ok((select updated_at > '2000-01-01'::timestamptz from public.vehicles where entry_id = (select id from fixtures where kind = 'vehicle')),
  'A real Vehicle detail change advances updated_at');
reset role;
alter table public.homes disable trigger homes_set_updated_at;
update public.homes set updated_at = '2000-01-02' where entry_id in (select id from fixtures);
alter table public.homes enable trigger homes_set_updated_at;
alter table public.vehicles disable trigger vehicles_set_updated_at;
update public.vehicles set updated_at = '2000-01-02' where entry_id in (select id from fixtures);
alter table public.vehicles enable trigger vehicles_set_updated_at;
set local role authenticated;
select pg_temp.save_home(id, 2, 'Renamed flat', 'Work') from fixtures where kind = 'home';
select pg_temp.save_vehicle(id, 2, 'Renamed Civic', 'Red') from fixtures where kind = 'vehicle';
select is((select updated_at from public.homes where entry_id = (select id from fixtures where kind = 'home')),
  '2000-01-02'::timestamptz, 'Title-only saves leave Home detail updated_at untouched');
select is((select updated_at from public.vehicles where entry_id = (select id from fixtures where kind = 'vehicle')),
  '2000-01-02'::timestamptz, 'Title-only saves leave Vehicle detail updated_at untouched');
select is(pg_temp.differences((select id from fixtures where kind = 'home'), 2),
  array['title'], 'Title-only Home history has no false detail or relationship differences');
select is(pg_temp.differences((select id from fixtures where kind = 'vehicle'), 2),
  array['title'], 'Title-only Vehicle history has no false detail or relationship differences');
reset role;
-- Add volatile fields to emulate immutable snapshots saved before normalization.
update public.entry_versions as version
set snapshot = jsonb_set(jsonb_set(jsonb_set(version.snapshot,
  '{home}', version.snapshot->'home' || '{"created_at":"1999-01-01","updated_at":"1999-01-01"}'::jsonb),
  '{places}', (select jsonb_agg(value || '{"created_at":"1999-01-01","updated_at":"1999-01-01"}'::jsonb) from jsonb_array_elements(version.snapshot->'places'))),
  '{timeline_items}', (select jsonb_agg(value || '{"created_at":"1999-01-01","updated_at":"1999-01-01"}'::jsonb) from jsonb_array_elements(version.snapshot->'timeline_items')))
where version.entry_id = (select id from fixtures where kind = 'home') and version.version = 2;
set local role authenticated;
select is(pg_temp.differences((select id from fixtures where kind = 'home'), 2), array['title'],
  'Legacy snapshots are normalized at read time');
select ok(not ((select public.entry_history(id)->'current'->'home' from fixtures where kind = 'home') ?| array['created_at','updated_at']),
  'Live Home snapshots exclude bookkeeping');
select ok(not ((select public.entry_history(id)->'versions'->0->'snapshot'->'home' from fixtures where kind = 'home') ?| array['created_at','updated_at']),
  'Read RPC strips bookkeeping from stored Home snapshots');
select is((select public.restore_entry_version(id, 2, 3) from fixtures where kind = 'home'), 4,
  'Legacy Home snapshots still restore');
select is((select title from public.entries where id = (select id from fixtures where kind = 'home')), 'History flat', 'Legacy Home title restores');
select is((select public.restore_entry_version(id, 1, 3) from fixtures where kind = 'vehicle'), 4,
  'New normalized Vehicle snapshots still restore');
select is((select color from public.vehicles where entry_id = (select id from fixtures where kind = 'vehicle')), 'Blue', 'Normalized Vehicle details restore');
reset role;
select is((select snapshot->'home'->>'created_at' from public.entry_versions where entry_id = (select id from fixtures where kind = 'home') and version = 2),
  '1999-01-01', 'Reading and restoring history do not rewrite old snapshots');
select ok(not ((select snapshot->'vehicle' from public.entry_versions where entry_id = (select id from fixtures where kind = 'vehicle') and version = 1) ?| array['created_at','updated_at']),
  'New stored snapshots are normalized too');
-- Audit every whole-row field without dropping domain metadata or restore IDs.
create temporary table normalization(raw jsonb, expected jsonb);
grant select on normalization to authenticated;
insert into normalization values (
  '{"title":"A memory","revision":7,"history_schema":3,"created_at":"entry date","deleted_at":null,"metadata":{"created_at":"authored date"},"people":[{"person_id":"person","relationship":"related","name":"Friend","created_at":"old","updated_at":"old"}],"places":[{"place_id":"location","relationship":"home","name":"Maple","created_at":"old"}],"timeline_items":[{"track_id":"track","timeline_kind":"stage","sort_order":7,"created_at":"old"}],"links":[{"target_entry_id":"target","relationship":"related","created_at":"old"}],"attachments":[{"id":"second","variant":"original","object_path":"photo.jpg","metadata":{"created_at":"EXIF date"},"created_at":"old","deleted_at":null},{"id":"first","created_at":"old","updated_at":"old"}],"home":{"entry_id":"home","place_id":"location","move_in_reason":"Study","created_at":"old","updated_at":"old"},"vehicle":{"entry_id":"vehicle","color":"Blue","created_at":"old","updated_at":"old"},"goal":{"entry_id":"goal","status":"active","target_date":"2027-01-01","created_at":"old","updated_at":"old"},"place":{"id":"location","latitude":39.95,"created_at":"old","updated_at":"old"}}'::jsonb,
  '{"title":"A memory","revision":7,"history_schema":3,"created_at":"entry date","deleted_at":null,"metadata":{"created_at":"authored date"},"people":[{"person_id":"person","relationship":"related","name":"Friend"}],"places":[{"place_id":"location","relationship":"home","name":"Maple"}],"timeline_items":[{"track_id":"track","timeline_kind":"stage","sort_order":7}],"links":[{"target_entry_id":"target","relationship":"related"}],"attachments":[{"id":"second","variant":"original","object_path":"photo.jpg","metadata":{"created_at":"EXIF date"}},{"id":"first"}],"home":{"entry_id":"home","place_id":"location","move_in_reason":"Study"},"vehicle":{"entry_id":"vehicle","color":"Blue"},"goal":{"entry_id":"goal","status":"active","target_date":"2027-01-01"},"place":{"id":"location","latitude":39.95}}'::jsonb
);
select is(public.normalize_entry_history_snapshot(raw)->field, expected->field,
  'Normalization preserves content and identity for ' || field)
from normalization cross join unnest(array['people','places','timeline_items','links','attachments','home','vehicle','goal','place','metadata','revision','deleted_at']) as field;
select is(public.normalize_entry_history_snapshot(public.normalize_entry_history_snapshot(raw)),
  public.normalize_entry_history_snapshot(raw), 'Normalization is idempotent') from normalization;
select is(public.normalize_entry_history_snapshot('{"home":null,"people":[],"title":"Legacy"}'::jsonb),
  '{"home":null,"people":[],"title":"Legacy"}'::jsonb, 'Missing, null, and empty legacy fields retain their meaning');
-- Exercise the read RPC with all historical whole-row fields, including ones
-- absent from a focused Home, without altering the immutable snapshot on read.
update public.entry_versions set snapshot = (select raw from normalization)
where entry_id = (select id from fixtures where kind = 'home') and version = 2;
set local role authenticated;
select is((select public.entry_history(id)->'versions'->1->'snapshot' from fixtures where kind = 'home'),
  (select expected from normalization), 'Read RPC normalizes every legacy relationship and detail field');
reset role;
select is((select snapshot from public.entry_versions where entry_id = (select id from fixtures where kind = 'home') and version = 2),
  (select raw from normalization), 'Read normalization leaves the entire historical row immutable');
select ok(not has_function_privilege('authenticated','public.normalize_entry_history_snapshot(jsonb)','execute'),
  'Normalizer stays internal to the history contract');
select ok(not has_function_privilege('anon','public.entry_history(uuid,integer,integer)','execute'),
  'History read still denies anonymous access');
select * from finish();
rollback;
