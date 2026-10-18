begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Importing from another app: job and item tables are readable but not writable by clients,
-- every write checks the owner, an imported Entry is an ordinary Entry created through
-- save_entry, and importing the same file again changes nothing.
insert into auth.users(id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000771', 'import-owner@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000772', 'import-other@memotrail.local', '{}');

-- Runs one job up to the point where its items can be imported.
create function pg_temp.start_job(p_items jsonb, p_excluded jsonb default '[]')
returns uuid language plpgsql as $$
declare
  started uuid;
begin
  select created.job_id into started from public.create_import_job('markdown', 'notes.zip', 1000) as created;
  perform public.update_import_job(started, array['uploading'], 'scanning', '{}');
  perform public.add_import_items(started, p_items);
  perform public.update_import_job(started, array['scanning'], 'preview_ready', '{}');
  perform public.confirm_import_job(started, '{}', p_excluded);
  perform public.acquire_import_lease(started, 60);
  return started;
end;
$$;

-- Imports one item of a job at day precision and returns the outcome.
create function pg_temp.import_one(
  p_job uuid, p_key text, p_entry uuid, p_hash text,
  p_title text, p_body text, p_tags text[] default '{}'
)
returns text language plpgsql as $$
declare
  outcome text;
begin
  select imported.outcome into outcome
  from public.import_entry(
    p_job,
    (select item.id from public.import_items as item where item.job_id = p_job and item.source_key = p_key),
    p_entry, p_hash, p_title, p_body, null,
    '2024-05-12T07:00:00Z', null, 'America/Los_Angeles', null, 'day', p_tags, null, '2024-05-12T07:00:00Z', null
  ) as imported;
  return outcome;
end;
$$;

select ok(
  (select relrowsecurity from pg_class where oid = 'public.import_jobs'::regclass)
    and (select relrowsecurity from pg_class where oid = 'public.import_items'::regclass)
    and (select relrowsecurity from pg_class where oid = 'public.entry_import_origins'::regclass),
  'Row-level security is enabled on every import table'
);
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('import_jobs', 'import_items', 'entry_import_origins')
      and (grantee in ('anon', 'PUBLIC') or (grantee = 'authenticated' and privilege_type <> 'SELECT'))
  ),
  'Clients can only read the import tables'
);
select ok(
  not has_function_privilege('anon', 'public.create_import_job(text,text,bigint)', 'execute')
    and has_function_privilege('authenticated', 'public.create_import_job(text,text,bigint)', 'execute')
    and not has_function_privilege('authenticated', 'public.end_import_job(uuid,text,text)', 'execute'),
  'Clients call the import functions but not the internal job ender'
);
select is(
  (select file_size_limit from storage.buckets where id = 'import-staging'),
  null::bigint,
  'The staging bucket leaves the size limit to the project, and Web enforces its own'
);
select is(
  (select public from storage.buckets where id = 'import-staging'),
  false,
  'The staging bucket is private'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000771', true);

select throws_ok(
  $$insert into public.import_jobs(owner_id, source) values ('10000000-0000-0000-0000-000000000771', 'markdown')$$,
  '42501', null, 'A client cannot write a job directly'
);
select throws_ok(
  $$select payload from public.import_items$$,
  '42501', null, 'A client cannot read the parsed text of an item'
);
select throws_ok(
  $$select * from public.create_import_job('evernote', 'notes.zip', 1000)$$,
  '22023', 'invalid_import_job', 'An unknown source is refused'
);

-- Job 1: scanned, previewed, confirmed with one folder unchecked, and imported.
create temp table job1 as
  select created.job_id, created.staging_path from public.create_import_job('markdown', 'notes.zip', 1000) as created;
select is(
  (select staging_path from job1),
  '10000000-0000-0000-0000-000000000771/' || (select job_id from job1)::text || '/source.zip',
  'The staged ZIP lives in the owner''s folder under the job'
);
select throws_ok(
  $$select * from public.create_import_job('markdown', 'second.zip', 1000)$$,
  '23505', 'import_job_active', 'A second active import is refused'
);
select is(
  public.update_import_job((select job_id from job1), array['scanning'], 'preview_ready', '{}'),
  null::text,
  'A job that is not in the expected step is left alone'
);

select lives_ok(
  $$insert into storage.objects(bucket_id, name, owner_id)
    values ('import-staging', (select staging_path from job1), '10000000-0000-0000-0000-000000000771')$$,
  'The owner can stage the ZIP of an upload in progress'
);
select throws_ok(
  $$insert into storage.objects(bucket_id, name, owner_id)
    values ('import-staging', '10000000-0000-0000-0000-000000000771/other/source.zip', '10000000-0000-0000-0000-000000000771')$$,
  '42501', null, 'Staging refuses a path no upload is waiting for'
);
select throws_ok(
  $$insert into storage.objects(bucket_id, name, owner_id)
    values ('import-staging', '10000000-0000-0000-0000-000000000772/x/source.zip', '10000000-0000-0000-0000-000000000771')$$,
  '42501', null, 'Staging refuses another person''s folder'
);
select is(
  public.update_import_job((select job_id from job1), array['uploading'], 'scanning', '{"file_bytes": 1234}'),
  'scanning',
  'An uploaded job moves to scanning'
);
select throws_ok(
  $$select public.add_import_items('00000000-0000-0000-0000-000000000000', '[]')$$,
  '22023', 'import_job_not_scanning', 'Items are only added to a job being scanned'
);
select is(
  public.add_import_items((select job_id from job1), $$[
    {"source_key": "paris", "folder_path": ["Travel"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000001", "payload": {"title": "Paris"}, "media": {"photos": []}},
    {"source_key": "rome", "folder_path": ["Travel", "Rome"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000002", "payload": {"title": "Rome"}},
    {"source_key": "photo", "folder_path": ["Home"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000003", "payload": {"title": null}, "media": {"photos": [{"key": "a", "status": "pending"}]}},
    {"source_key": "empty", "folder_path": ["Home"], "status": "skipped", "reason": "empty"},
    {"source_key": "paris", "folder_path": ["Travel"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000009", "payload": {"title": "Paris again"}}
  ]$$),
  4,
  'A key repeated inside a file is kept once'
);
select is(
  public.update_import_job((select job_id from job1), array['scanning'], 'preview_ready', '{"totals": {"entries": 3}}'),
  'preview_ready',
  'A scanned job is ready for the preview'
);
select results_eq(
  $$select unchanged, changed from public.import_job_overlap((select job_id from job1))$$,
  $$values (0::bigint, 0::bigint)$$,
  'Nothing is imported yet'
);
select is(
  public.confirm_import_job((select job_id from job1), '{"timezone": "America/Los_Angeles"}', '[["Travel", "Rome"]]'),
  2::bigint,
  'Confirming removes the unchecked folder and counts what is left to import'
);
select is(
  (select count(*) from public.import_items where job_id = (select job_id from job1) and source_key = 'rome'),
  0::bigint,
  'An unchecked item is not kept'
);

-- The lease keeps two runs apart.
create temp table lease1 as select public.acquire_import_lease((select job_id from job1), 60) as token;
select isnt((select token from lease1), null::uuid, 'The first run takes the lease');
select is(
  public.acquire_import_lease((select job_id from job1), 60),
  null::uuid,
  'A second run cannot take it'
);
select throws_ok(
  $$select * from public.claim_import_items((select job_id from job1), gen_random_uuid(), 10, 60)$$,
  '55P03', 'import_lease_lost', 'A run without the lease cannot claim items'
);
select is(
  (select count(*) from public.claim_import_items((select job_id from job1), (select token from lease1), 10, 60)),
  2::bigint,
  'A run claims the pending items'
);

select is(
  pg_temp.import_one((select job_id from job1), 'paris', 'a7700000-0000-4000-8000-000000000001',
    repeat('0', 63) || '1', 'Paris', 'We walked along the river.', array['Trip', 'trip', 'Imported from a folder']),
  'created',
  'An item becomes an Entry'
);
select results_eq(
  $$select title, body, date_precision, occurred_timezone, revision, item_kind
    from public.entries where id = 'a7700000-0000-4000-8000-000000000001'$$,
  $$values ('Paris'::text, 'We walked along the river.'::text, 'day'::text, 'America/Los_Angeles'::text, 1, 'entry'::text)$$,
  'The Entry is an ordinary Entry with the source date at its precision'
);
select is(
  (select array_agg(lower(tag.name) order by lower(tag.name))
   from public.entry_tags as link join public.tags as tag on tag.id = link.tag_id
   where link.entry_id = 'a7700000-0000-4000-8000-000000000001'),
  array['imported from a folder', 'trip'],
  'Tags are created once, ignoring case'
);
select results_eq(
  $$select source, source_key, content_hash, imported_revision
    from public.entry_import_origins where entry_id = 'a7700000-0000-4000-8000-000000000001'$$,
  $$values ('markdown'::text, 'paris'::text, repeat('0', 63) || '1', 1)$$,
  'The origin records the source, key, hash, and revision'
);
select is(
  (select status from public.import_items where source_key = 'paris'),
  'imported',
  'An item without photos is finished with its Entry'
);
select is(
  pg_temp.import_one((select job_id from job1), 'photo', 'a7700000-0000-4000-8000-000000000003',
    repeat('0', 63) || '3', null, ''),
  'created',
  'An Entry of photos only is created, as a photo capture is'
);
select results_eq(
  $$select title, body from public.entries where id = 'a7700000-0000-4000-8000-000000000003'$$,
  $$values (null::text, ''::text)$$,
  'It has no title and no words'
);
select is(
  (select status from public.import_items where source_key = 'photo'),
  'photos_pending',
  'An item with photos waits for them after its Entry exists'
);
select lives_ok(
  $$select public.finish_import_item(
      (select id from public.import_items where source_key = 'photo'),
      'imported', null, false, '{"photos": [{"key": "a", "status": "done"}]}')$$,
  'Photos finish the item'
);
select is(
  public.finish_import_job((select job_id from job1)),
  'completed',
  'The job completes when every item is done'
);
reset role;
select is(
  (select count(*) from public.import_items where job_id = (select job_id from job1) and payload is not null),
  0::bigint,
  'A finished job keeps none of the parsed text'
);
set local role authenticated;
select is(
  public.import_job_progress((select job_id from job1)) #>> '{photos,imported}',
  '1',
  'Progress counts imported photos'
);

-- Job 2: the same file again.
create temp table job2 as select pg_temp.start_job($$[
  {"source_key": "paris", "folder_path": ["Travel"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000001", "payload": {"title": "Paris"}},
  {"source_key": "photo", "folder_path": ["Home"], "content_hash": "00000000000000000000000000000000000000000000000000000000000000ff", "payload": {"title": null}}
]$$) as id;
select results_eq(
  $$select unchanged, changed from public.import_job_overlap((select id from job2))$$,
  $$values (1::bigint, 1::bigint)$$,
  'The preview counts items already imported and items that changed in the source'
);
select is(
  pg_temp.import_one((select id from job2), 'paris', 'a7700000-0000-4000-8000-000000000001',
    repeat('0', 63) || '1', 'Paris', 'We walked along the river.'),
  'unchanged',
  'Importing the same item again does nothing'
);
select is(
  pg_temp.import_one((select id from job2), 'photo', 'a7700000-0000-4000-8000-000000000003',
    repeat('0', 62) || 'ff', 'Now with a title', 'and words'),
  'changed_in_source',
  'An item that changed in the source is reported, not applied'
);
select is(
  (select title from public.entries where id = 'a7700000-0000-4000-8000-000000000003'),
  null::text,
  'The imported Entry is left as it was'
);
select is(
  (select count(*) from public.entries where owner_id = '10000000-0000-0000-0000-000000000771'),
  2::bigint,
  'No Entry was added by the second import'
);
select is(public.finish_import_job((select id from job2)), 'completed', 'The second job completes');

-- Trash and Delete forever are respected.
update public.entries set deleted_at = clock_timestamp() where id = 'a7700000-0000-4000-8000-000000000001';
create temp table job3 as select pg_temp.start_job($$[
  {"source_key": "paris", "folder_path": ["Travel"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000001", "payload": {"title": "Paris"}},
  {"source_key": "gone", "folder_path": ["Home"], "content_hash": "0000000000000000000000000000000000000000000000000000000000000004", "payload": {"title": "Gone"}}
]$$) as id;
select is(
  pg_temp.import_one((select id from job3), 'paris', 'a7700000-0000-4000-8000-000000000001',
    repeat('0', 63) || '1', 'Paris', 'We walked along the river.'),
  'unchanged',
  'An Entry in Trash counts as already imported'
);
select is(
  (select reason from public.import_items where job_id = (select id from job3) and source_key = 'paris'),
  'in_trash',
  'and says it is in Trash'
);
delete from public.entries where id = 'a7700000-0000-4000-8000-000000000001';
select is(
  pg_temp.import_one((select id from job3), 'gone', 'a7700000-0000-4000-8000-000000000001',
    repeat('0', 63) || '4', 'Back again', 'text'),
  'deleted_earlier',
  'An Entry deleted forever is not brought back'
);
select is(
  (select count(*) from public.entries where id = 'a7700000-0000-4000-8000-000000000001'),
  0::bigint,
  'and stays deleted'
);
select throws_ok(
  $$select pg_temp.import_one((select id from job3), 'paris', 'a7700000-0000-4000-8000-000000000009',
      repeat('0', 63) || '1', null, '')$$,
  '22023', 'empty_entry', 'An item with no words and no photos is refused'
);
select is(public.finish_import_job((select id from job3)), 'completed', 'The third job completes');

-- Job 4: an Entry made by import, edited, and undone.
create temp table job4 as select pg_temp.start_job($$[
  {"source_key": "one", "folder_path": [], "content_hash": "0000000000000000000000000000000000000000000000000000000000000005", "payload": {}},
  {"source_key": "two", "folder_path": [], "content_hash": "0000000000000000000000000000000000000000000000000000000000000006", "payload": {}}
]$$) as id;
select is(
  pg_temp.import_one((select id from job4), 'one', 'a7700000-0000-4000-8000-000000000011', repeat('0', 63) || '5', 'One', 'first'),
  'created', 'First item imported'
);
select is(
  pg_temp.import_one((select id from job4), 'two', 'a7700000-0000-4000-8000-000000000012', repeat('0', 63) || '6', 'Two', 'second'),
  'created', 'Second item imported'
);
select is(public.finish_import_job((select id from job4)), 'completed', 'The job completes');
update public.entries set title = 'Two, edited' where id = 'a7700000-0000-4000-8000-000000000012';
select results_eq(
  $$select trashed, edited from public.trash_import_job((select id from job4))$$,
  $$values (1, 1)$$,
  'Undo moves untouched Entries to Trash and leaves edited ones'
);
select is(
  (select count(*) from public.entries where id in ('a7700000-0000-4000-8000-000000000011') and deleted_at is not null),
  1::bigint,
  'The untouched Entry is in Trash, where it can be restored'
);

-- Cleanup lists the staged ZIPs of finished jobs.
select is(
  (select count(*) from public.expire_import_jobs()),
  4::bigint,
  'Every finished job with a staged ZIP is listed for removal'
);
select is(
  (select count(*) from public.expire_import_jobs() where staging_path = (select staging_path from job1)),
  1::bigint,
  'with its path'
);
select is(
  public.complete_import_staging_cleanup(array[(select job_id from job1)]),
  1,
  'Confirming removal clears the path'
);
select is(
  (select count(*) from public.expire_import_jobs()),
  3::bigint,
  'and that job is not listed again'
);

-- Another person sees and changes nothing.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000772', true);
select is((select count(*) from public.import_jobs), 0::bigint, 'Another person sees no jobs');
select is((select count(*) from public.import_items), 0::bigint, 'or items');
select is((select count(*) from public.entry_import_origins), 0::bigint, 'or origins');
select is((select count(*) from storage.objects where bucket_id = 'import-staging'), 0::bigint, 'or staged files');
select is(
  public.update_import_job((select id from job4), array['running', 'completed'], 'failed', '{}'),
  null::text,
  'Another person cannot change a job'
);
select is(public.cancel_import_job((select id from job4)), false, 'or cancel it');
select throws_ok(
  $$select * from public.trash_import_job((select id from job4))$$,
  '22023', 'import_job_not_undoable', 'or undo it'
);
select is(public.import_job_progress((select id from job4)), null::jsonb, 'or read its progress');

select * from finish();
rollback;
