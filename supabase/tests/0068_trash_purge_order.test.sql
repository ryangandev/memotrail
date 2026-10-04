begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Delete forever removes the record first and records its Storage objects; clients
-- remove only recorded objects, and every restore needs its originals.
insert into auth.users(id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000681', 'purge-owner@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000682', 'purge-other@memotrail.local', '{}');

create temporary table fixtures(name text primary key, entry_id uuid, attachment_id uuid, path text);
grant select on fixtures to authenticated;

create function pg_temp.photo_entry(p_name text, p_object boolean default true)
returns void language plpgsql as $$
declare
  owner uuid := '10000000-0000-0000-0000-000000000681';
  entry uuid := gen_random_uuid();
  attachment uuid := gen_random_uuid();
  path text := owner::text || '/' || entry::text || '/' || attachment::text || '.jpg';
begin
  insert into public.entries(id, owner_id, title) values (entry, owner, 'Purge ' || p_name);
  insert into public.attachments(id, owner_id, entry_id, object_path, mime_type, byte_size)
  values (attachment, owner, entry, path, 'image/jpeg', 1000);
  if p_object then
    insert into storage.objects(bucket_id, name) values ('entry-media', path);
  end if;
  insert into fixtures values (p_name, entry, attachment, path);
end;
$$;

-- A generated preview path for a fixture's original.
create function pg_temp.preview(p_name text, p_hash text default 'd')
returns text language sql as $$
  select split_part(path, '/', 1) || '/' || entry_id::text || '/derived/' || attachment_id::text
    || '/v1/' || repeat(p_hash, 64) || '/display.webp'
  from fixtures where name = p_name;
$$;

create function pg_temp.trash_entry(p_name text)
returns void language sql as $$
  update public.entries set deleted_at = clock_timestamp()
  where id = (select entry_id from fixtures where name = p_name);
$$;

create function pg_temp.entry_params(p_name text, out kind text, out id uuid, out revision integer, out deleted timestamptz)
language sql as $$
  select 'entry', e.id, e.revision, e.deleted_at
  from public.entries e where e.id = (select entry_id from fixtures where name = p_name);
$$;

create function pg_temp.object_count(p_name text)
returns bigint language sql as $$
  select count(*) from storage.objects
  where bucket_id = 'entry-media'
    and split_part(name, '/', 2) = (select entry_id::text from fixtures where name = p_name);
$$;

select pg_temp.photo_entry('deleted');
insert into storage.objects(bucket_id, name) values ('entry-media', pg_temp.preview('deleted'));
select pg_temp.trash_entry('deleted');
select pg_temp.photo_entry('photo');
select pg_temp.photo_entry('missing entry', false);
select pg_temp.trash_entry('missing entry');
select pg_temp.photo_entry('missing photo', false);
select pg_temp.photo_entry('race');
insert into storage.objects(bucket_id, name) values ('entry-media', pg_temp.preview('race'));
select pg_temp.trash_entry('race');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000681', true);
select lives_ok(
  $$select public.trash_entry_attachment(attachment_id) from fixtures where name in ('photo', 'missing photo')$$,
  'Single photos move to Trash'
);


-- Storage refuses a client delete of any registered original, in Trash or not.
select set_config('storage.allow_delete_query', 'true', true);
with removed as (
  delete from storage.objects
  where bucket_id = 'entry-media' and name in (select path from fixtures where name in ('deleted', 'photo', 'race'))
  returning 1
)
select is(count(*), 0::bigint, 'A client cannot remove the original of a registered photo') from removed;
with removed as (
  delete from storage.objects where bucket_id = 'entry-media' and name = pg_temp.preview('race') returning 1
)
select is(count(*), 1::bigint, 'Generated previews stay removable caches') from removed;
select is(pg_temp.object_count('deleted'), 2::bigint, 'The Trash Entry keeps its original and preview');

-- Every restore path requires the originals it makes visible.
select throws_ok(
  $$select public.restore_trash_item(p.kind, p.id, p.revision, p.deleted) from pg_temp.entry_params('missing entry') p$$,
  'P0001', 'trash_media_unavailable', 'An Entry whose original is missing cannot be restored'
);
select isnt(deleted_at, null, 'The refused Entry stays in Trash')
from public.entries where id = (select entry_id from fixtures where name = 'missing entry');
select throws_ok(
  $$update public.entries set deleted_at = null where id = (select entry_id from fixtures where name = 'missing entry')$$,
  'P0001', 'trash_media_unavailable', 'A direct client restore is refused the same way'
);
create temporary table missing_photo_revision as
select revision from public.entries where id = (select entry_id from fixtures where name = 'missing photo');
select throws_ok(
  $$select public.restore_trash_item('attachment', f.attachment_id, null,
      (select deleted_at from public.attachments where id = f.attachment_id))
    from fixtures f where f.name = 'missing photo'$$,
  'P0001', 'trash_media_unavailable', 'A photo whose original is missing cannot be restored'
);
select is(
  (select revision from public.entries where id = (select entry_id from fixtures where name = 'missing photo')),
  (select revision from missing_photo_revision),
  'The refused photo restore leaves no revision behind'
);
select isnt(deleted_at, null, 'The refused photo stays in Trash')
from public.attachments where id = (select attachment_id from fixtures where name = 'missing photo');

-- Delete forever is the commit point: the record goes, and its objects are recorded.
select is(
  (select count(*) from pg_temp.entry_params('deleted') p
   cross join lateral public.delete_trash_item_forever(p.kind, p.id, p.revision, p.deleted)),
  1::bigint,
  'Delete forever succeeds while the original and a late preview still exist'
);
select is(
  (select count(*) from public.entries where id = (select entry_id from fixtures where name = 'deleted')),
  0::bigint,
  'The record is gone'
);
select is(
  (select count(*) from public.restore_trash_item('entry', (select entry_id from fixtures where name = 'deleted'), 2, now())),
  0::bigint,
  'Nothing deleted can be restored'
);
select is(
  (select array_agg(object_path order by object_path) from public.pending_media_purge_paths()),
  (select array_agg(path order by path) from (
    select path from fixtures where name = 'deleted'
    union all select pg_temp.preview('deleted')) as expected),
  'The original and its preview are recorded for removal'
);
select is(pg_temp.object_count('deleted'), 2::bigint, 'Storage still holds them until the client removes them');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000682', true);
select is((select count(*) from public.pending_media_purge_paths()), 0::bigint, 'Another owner sees no recorded paths');
select is(public.complete_media_purges(), 0, 'Another owner has nothing to complete');
select throws_ok($$select * from public.media_purges$$, '42501', null, 'Clients cannot read the record directly');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000681', true);

-- An interrupted removal stays recorded; each retry is idempotent.
select is(public.complete_media_purges(), 2, 'Completing before removal keeps both recorded');
select is(public.complete_media_purges(), 2, 'Retrying the confirmation changes nothing');
with removed as (
  delete from storage.objects where bucket_id = 'entry-media' and name = pg_temp.preview('deleted') returning 1
)
select is(count(*), 1::bigint, 'A recorded preview can be removed') from removed;
select is(public.complete_media_purges(), 1, 'A partial removal leaves the rest recorded');
select is(
  (select array_agg(object_path) from public.pending_media_purge_paths()),
  (select array_agg(path) from fixtures where name = 'deleted'),
  'The retry lists only what remains'
);
with removed as (
  delete from storage.objects where bucket_id = 'entry-media'
    and name in (select object_path from public.pending_media_purge_paths()) returning 1
)
select is(count(*), 1::bigint, 'The original can be removed once its record is gone') from removed;
select is(public.complete_media_purges(), 0, 'Removal completes');
select is(public.complete_media_purges(), 0, 'Completing again is harmless');
select is((select count(*) from public.pending_media_purge_paths()), 0::bigint, 'Nothing is left to remove');

reset role;
select throws_ok(
  format($$insert into storage.objects(bucket_id, name) values ('entry-media', %L)$$, pg_temp.preview('deleted', 'e')),
  '23503', 'media_source_removed', 'A late preview cannot be written after Delete forever'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000681', true);
select set_config('storage.allow_delete_query', 'true', true);

-- A single Trash photo follows the same order and leaves its Entry active.
select is(
  (select count(*) from fixtures f cross join lateral public.delete_trash_item_forever(
    'attachment', f.attachment_id, null, (select deleted_at from public.attachments where id = f.attachment_id))
   where f.name = 'photo'),
  1::bigint,
  'Delete forever removes a Trash photo record'
);
select is(
  (select array_agg(object_path) from public.pending_media_purge_paths()),
  (select array_agg(path) from fixtures where name = 'photo'),
  'Its original is recorded'
);
select is(
  (select deleted_at from public.entries where id = (select entry_id from fixtures where name = 'photo')),
  null,
  'Its Entry stays active'
);
with removed as (
  delete from storage.objects where bucket_id = 'entry-media'
    and name in (select object_path from public.pending_media_purge_paths()) returning 1
)
select is(count(*), 1::bigint, 'The recorded original is removable') from removed;
select is(public.complete_media_purges(), 0, 'The photo removal completes');

-- A path registered again is live media and is never removed.
reset role;
insert into public.media_purges(bucket_id, object_name, owner_id)
select 'entry-media', path, '10000000-0000-0000-0000-000000000681' from fixtures where name = 'race';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000681', true);
select is((select count(*) from public.pending_media_purge_paths()), 0::bigint, 'A registered path is never listed for removal');
select is(public.complete_media_purges(), 0, 'A registered path is forgotten instead');

-- Restore and Delete forever lock the same record, so the later one sees the change.
create temporary table race_params as select * from pg_temp.entry_params('race');
select is(
  (select count(*) from race_params p cross join lateral public.restore_trash_item(p.kind, p.id, p.revision, p.deleted)),
  1::bigint,
  'Another device restores first'
);
select is(
  (select count(*) from race_params p cross join lateral public.delete_trash_item_forever(p.kind, p.id, p.revision, p.deleted)),
  0::bigint,
  'The stale Delete forever no longer matches'
);
select is((select count(*) from public.pending_media_purge_paths()), 0::bigint, 'Nothing was recorded for removal');
select is(pg_temp.object_count('race'), 1::bigint, 'The restored Entry keeps its original');
select pg_temp.trash_entry('race');
drop table race_params;
create temporary table race_params as select * from pg_temp.entry_params('race');
select is(
  (select count(*) from race_params p cross join lateral public.delete_trash_item_forever(p.kind, p.id, p.revision, p.deleted)),
  1::bigint,
  'Delete forever wins when it locks first'
);
select is(
  (select count(*) from race_params p cross join lateral public.restore_trash_item(p.kind, p.id, p.revision, p.deleted)),
  0::bigint,
  'The later Restore finds nothing to restore'
);
select is(
  (select array_agg(object_path) from public.pending_media_purge_paths()),
  (select array_agg(path) from fixtures where name = 'race'),
  'The deleted Entry original is recorded instead'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.complete_media_purges()$$,
  '42501', 'authentication_required', 'Completing requires a signed-in owner'
);
set local role anon;
select throws_ok($$select * from public.pending_media_purge_paths()$$, '42501', null, 'Anonymous callers cannot list paths');
reset role;
select is(
  (select count(*) from public.media_purges where owner_id = '10000000-0000-0000-0000-000000000681'),
  1::bigint,
  'Only the unremoved race original remains recorded'
);

-- Account deletion keeps the earlier guard: nothing can remove previews afterwards.
insert into public.entries(id, owner_id, title) values
  ('68000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000682', 'Account');
insert into public.attachments(id, owner_id, entry_id, object_path, mime_type, byte_size) values
  ('68000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000682',
   '68000000-0000-4000-8000-000000000001',
   '10000000-0000-0000-0000-000000000682/68000000-0000-4000-8000-000000000001/68000000-0000-4000-8000-000000000002.jpg',
   'image/jpeg', 1000);
insert into storage.objects(bucket_id, name) values
  ('entry-media', '10000000-0000-0000-0000-000000000682/68000000-0000-4000-8000-000000000001/derived/68000000-0000-4000-8000-000000000002/v1/' || repeat('f', 64) || '/display.webp');
select throws_ok(
  $$delete from auth.users where id = '10000000-0000-0000-0000-000000000682'$$,
  '55000', 'media_cleanup_required', 'Account deletion still requires generated previews to be removed first'
);
delete from storage.objects
where bucket_id = 'entry-media'
  and split_part(name, '/', 1) = '10000000-0000-0000-0000-000000000682'
  and split_part(name, '/', 3) = 'derived';
select lives_ok(
  $$delete from auth.users where id = '10000000-0000-0000-0000-000000000682'$$,
  'Account deletion proceeds once its previews are removed'
);
select is(
  (select count(*) from public.media_purges where owner_id = '10000000-0000-0000-0000-000000000682'),
  0::bigint,
  'Account deletion records nothing for an owner who can no longer remove it'
);
select lives_ok(
  $$delete from auth.users where id = '10000000-0000-0000-0000-000000000681'$$,
  'An account with recorded paths can be deleted'
);
select is(
  (select count(*) from public.media_purges where owner_id = '10000000-0000-0000-0000-000000000681'),
  0::bigint,
  'Account deletion forgets its recorded paths'
);

select * from finish();
rollback;
