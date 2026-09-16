begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000119','canonical-entities-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000120','canonical-entities-other@memotrail.local');

insert into public.people(id,owner_id,name,relationship_label,notes) values (
  '98800000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000119',
  'Avery',
  'Friend',
  'Met at the marina.'
);

insert into public.places(id,owner_id,name,address,city,region,country,notes) values (
  '98800000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000119',
  'Berkeley Marina',
  '201 University Avenue',
  'Berkeley',
  'California',
  'USA',
  'Sailing lessons.'
);

select is(
  (
    select entry.item_kind || ':' || entry.item_subtype || ':' || entry.title
    from public.people as person
    join public.entries as entry on entry.id=person.id and entry.owner_id=person.owner_id
    where person.id='98800000-0000-4000-8000-000000000001'
  ),
  'entity:person:Avery',
  'A Person is created with one canonical Entity Wiki Item'
);

select is(
  (
    select entry.item_kind || ':' || entry.item_subtype || ':' || entry.title
    from public.places as place
    join public.entries as entry on entry.id=place.id and entry.owner_id=place.owner_id
    where place.id='98800000-0000-4000-8000-000000000002'
  ),
  'entity:place:Berkeley Marina',
  'A Place is created with one canonical Entity Wiki Item'
);

select is(
  (select id from public.people where id='98800000-0000-4000-8000-000000000001'),
  '98800000-0000-4000-8000-000000000001'::uuid,
  'The canonical and specialized Person records share one identity'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000119',true);

select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  2::bigint,
  'The Life Wiki returns each specialized Entity exactly once'
);

select is(
  (select count(*) from public.search_entries_with_occurrence('',array['standard'])),
  0::bigint,
  'Legacy Standard filtering does not classify canonical Entities as Writing'
);

select is(
  (
    select canonical_item_id
    from public.wiki_items_workspace('',array[]::text[],array['person'],50,0)
  ),
  (select id from public.people where id='98800000-0000-4000-8000-000000000001'),
  'The Life Wiki exposes the shared Person identity'
);

select is(
  (
    select count(*)
    from public.save_person(
      'Avery Chen','Close friend','Sailing together.',array[]::uuid[],
      '98800000-0000-4000-8000-000000000001',1
    )
  ),
  1::bigint,
  'The existing Person writer updates the Entity atomically'
);

select is(
  (
    select entry.title || ':' || entry.body || ':' || entry.revision
    from public.people as person
    join public.entries as entry on entry.id=person.id and entry.owner_id=person.owner_id
    where person.id='98800000-0000-4000-8000-000000000001'
  ),
  'Avery Chen:Sailing together.:2',
  'Person edits synchronize title, notes, and optimistic revision'
);

select is(
  (
    select count(*)
    from public.save_place(
      'Berkeley Marina','201 University Avenue','Berkeley','California','USA',
      37.865900,-122.313000,'Evening sails.',array[]::uuid[],
      '98800000-0000-4000-8000-000000000002',1
    )
  ),
  1::bigint,
  'The existing Place writer updates the Entity atomically'
);

select is(
  (
    select entry.title || ':' || entry.body || ':' || entry.revision
    from public.places as place
    join public.entries as entry on entry.id=place.id and entry.owner_id=place.owner_id
    where place.id='98800000-0000-4000-8000-000000000002'
  ),
  'Berkeley Marina:Evening sails.:2',
  'Place edits synchronize title, notes, and optimistic revision'
);

select is(
  (
    select entry_id
    from public.search_entries_with_occurrence(
      '201 University Avenue',array['place'],array[]::text[],array[]::text[],
      null,null,50,0
    )
  ),
  (select id from public.places where id='98800000-0000-4000-8000-000000000002'),
  'Canonical Place search includes specialized address fields'
);

select is(
  (
    select count(*)
    from public.trash_person('98800000-0000-4000-8000-000000000001',2)
  ),
  1::bigint,
  'An unlinked Person moves to Trash'
);

select ok(
  (
    select person.deleted_at is not null
      and entry.deleted_at=person.deleted_at
      and entry.revision=person.revision
    from public.people as person
    join public.entries as entry on entry.id=person.id and entry.owner_id=person.owner_id
    where person.id='98800000-0000-4000-8000-000000000001'
  ),
  'Person Trash state and revision synchronize to the canonical item'
);

select is(
  (
    select count(*)
    from public.trash_workspace(50,0)
    where item_kind='person' and item_id='98800000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Trash shows the specialized Person once'
);

select is(
  (
    select count(*)
    from public.trash_workspace(50,0)
    where item_kind='entry'
      and item_id=(
        select id from public.people
        where id='98800000-0000-4000-8000-000000000001'
      )
  ),
  0::bigint,
  'Trash hides the synchronized base Entry duplicate'
);

select is(
  (
    select count(*)
    from public.restore_trash_item(
      'person','98800000-0000-4000-8000-000000000001',3,
      (select deleted_at from public.people where id='98800000-0000-4000-8000-000000000001')
    )
  ),
  1::bigint,
  'Restoring a Person restores its canonical item in the same transaction'
);

select ok(
  (
    select person.deleted_at is null
      and entry.deleted_at is null
      and entry.revision=person.revision
    from public.people as person
    join public.entries as entry on entry.id=person.id and entry.owner_id=person.owner_id
    where person.id='98800000-0000-4000-8000-000000000001'
  ),
  'Restored Person and canonical item remain synchronized'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000120',true);
select is(
  (select count(*) from public.wiki_items_workspace('',array[]::text[],array[]::text[],50,0)),
  0::bigint,
  'Canonical Entity browsing remains owner scoped'
);

reset role;
select ok(
  not has_function_privilege(
    'anon','public.wiki_items_workspace(text,text[],text[],integer,integer)','execute'
  ),
  'Anonymous Life Wiki browsing remains denied'
);

select * from finish();
rollback;
