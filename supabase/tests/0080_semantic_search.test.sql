begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- The semantic search index is owner-scoped, reachable only through security definer
-- functions, kept current by a trigger, and removed when the Entry or the setting goes.
insert into auth.users(id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000801', 'semantic-owner@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000802', 'semantic-other@memotrail.local', '{}');

insert into public.entries(id, owner_id, title, body, updated_at) values
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000801', 'Climbing gym', 'The guy who fixes bikes.', '2026-10-03T12:00:00Z'),
  ('80000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000801', null, '去年夏天在海边跑步。', '2026-10-02T12:00:00Z'),
  ('80000000-0000-4000-8000-000000000003', '10000000-0000-0000-0000-000000000801', 'In Trash', 'Old note.', '2026-10-04T12:00:00Z'),
  ('80000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000802', 'Someone else', 'Private to the other owner.', '2026-10-05T12:00:00Z');
update public.entries set deleted_at = '2026-10-10T00:00:00Z'
where id = '80000000-0000-4000-8000-000000000003';

create function pg_temp.unit_vector(p_hot integer) returns jsonb language sql as $$
  select jsonb_agg(case when position = p_hot then 1 else 0 end order by position)
  from generate_series(1, 1024) as position;
$$;
create function pg_temp.chunk(p_index integer, p_start integer, p_end integer, p_embedding jsonb)
returns jsonb language sql as $$
  select jsonb_build_object('index', p_index, 'start', p_start, 'end', p_end, 'embedding', p_embedding);
$$;
create function pg_temp.hash_of(p_entry uuid) returns text language sql security definer as $$
  select encode(source_hash, 'hex') from public.entry_search_index_state where entry_id = p_entry;
$$;

select is(
  (select count(*) from public.entries as item
   left join public.entry_search_index_state as state on state.entry_id = item.id
   where state.entry_id is null),
  0::bigint,
  'Every Entry, including Trash, has an index state row'
);
select is(
  (select status from public.entry_search_index_state
   where entry_id = '80000000-0000-4000-8000-000000000003'),
  'pending',
  'An Entry in Trash is still queued, so Restore needs no re-indexing'
);
select is(
  (select source_hash from public.entry_search_index_state
   where entry_id = '80000000-0000-4000-8000-000000000001'),
  public.entry_search_source_hash('Climbing gym', 'The guy who fixes bikes.'),
  'The queued hash covers the title and plaintext body'
);
select is(
  public.entry_search_source_hash('  Climbing gym ', 'x'),
  public.entry_search_source_hash('Climbing gym', 'x'),
  'The hash ignores title padding'
);

-- Not a title or body change, so the Entry stays as it was.
update public.entry_search_index_state set status = 'indexed', indexed_model = 'model-a'
where entry_id = '80000000-0000-4000-8000-000000000001';
update public.entries set occurred_label = 'Autumn'
where id = '80000000-0000-4000-8000-000000000001';
select is(
  (select status from public.entry_search_index_state
   where entry_id = '80000000-0000-4000-8000-000000000001'),
  'indexed',
  'Editing another column leaves an indexed Entry alone'
);
update public.entries set body = 'The guy who fixes bikes and brews tea.'
where id = '80000000-0000-4000-8000-000000000001';
select is(
  (select status || ':' || (source_hash = public.entry_search_source_hash('Climbing gym', 'The guy who fixes bikes and brews tea.'))::text
   from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000001'),
  'pending:true',
  'Editing the body makes the Entry due again with the new hash'
);
update public.entries set body = 'The guy who fixes bikes.'
where id = '80000000-0000-4000-8000-000000000001';
select is(
  (select status from public.entry_search_index_state
   where entry_id = '80000000-0000-4000-8000-000000000001'),
  'pending',
  'Restoring the old text is still a change to index'
);
update public.entry_search_index_state set indexed_model = null
where entry_id = '80000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);

select is(
  (select count(*) from public.claim_entry_search_index_jobs('model-a', 16)),
  3::bigint,
  'Claiming returns only the caller''s due Entries, Trash included'
);
select is(
  (select array_agg(entry_id order by entry_id) from public.claim_entry_search_index_jobs('model-a', 16)),
  null::uuid[],
  'A leased Entry is not claimed again while its lease lasts'
);
select throws_ok(
  $$select * from public.claim_entry_search_index_jobs('bad model', 4)$$,
  '22023', 'invalid_search_model', 'Claiming validates the model label'
);
select throws_ok(
  $$select * from public.claim_entry_search_index_jobs('model-a', 17)$$,
  '22023', 'invalid_search_limit', 'Claiming validates the batch size'
);

reset role;
update public.entry_search_index_state set leased_until = null
where owner_id = '10000000-0000-0000-0000-000000000801';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);

select is(
  (select array_agg(entry_id order by entry_id)
   from public.claim_entry_search_index_jobs('model-a', 2)),
  array['80000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000002']::uuid[],
  'Active Entries are claimed before Trash, newest writing first'
);

select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(0, 0, 5, jsonb_build_array(1, 2, 3)))),
  '22023', 'invalid_chunks', 'A vector of the wrong dimension is refused'
);
select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(0, 0, 5, (select jsonb_agg('x'::text) from generate_series(1, 1024))))),
  '22023', 'invalid_chunks', 'A vector with non-numbers is refused'
);
select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(0, 0, 5, (select jsonb_agg(1e300) from generate_series(1, 1024))))),
  '22023', 'invalid_chunks', 'A vector with absurd values is refused'
);
select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(0, 0, 5, (select jsonb_agg(0) from generate_series(1, 1024))))),
  '22023', 'invalid_chunks', 'A zero vector is refused'
);
select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(0, 0, 500, pg_temp.unit_vector(1)))),
  '22023', 'invalid_chunks', 'A range beyond the body is refused'
);
select throws_ok(
  format($$select public.store_entry_search_chunks(%L, %L, 'model-a', %L::jsonb)$$,
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    jsonb_build_array(pg_temp.chunk(1, 0, 5, pg_temp.unit_vector(1)))),
  '22023', 'invalid_chunks', 'Chunk indexes must run from zero without gaps'
);
select is(
  public.store_entry_search_chunks(
    '80000000-0000-4000-8000-000000000004',
    repeat('0', 64),
    'model-a',
    jsonb_build_array(pg_temp.chunk(0, 0, 5, pg_temp.unit_vector(1)))),
  false,
  'Another owner''s Entry cannot be indexed'
);

select is(
  public.store_entry_search_chunks(
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    'model-a',
    jsonb_build_array(
      pg_temp.chunk(0, 0, 10, pg_temp.unit_vector(1)),
      pg_temp.chunk(1, 8, 24, pg_temp.unit_vector(2)))),
  true,
  'Storing chunks for the current text succeeds'
);
reset role;
select is(
  (select status || ':' || indexed_model || ':' || (indexed_hash = source_hash)::text
   from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000001'),
  'indexed:model-a:true',
  'Storing marks the Entry indexed with the model and hash'
);
select is(
  (select count(*) from public.entry_search_chunks where entry_id = '80000000-0000-4000-8000-000000000001'),
  2::bigint,
  'Both chunks are stored'
);
select is(
  (select array_agg(chunk_index || ':' || char_start || '-' || char_end || ':' || model order by chunk_index)
   from public.entry_search_chunks where entry_id = '80000000-0000-4000-8000-000000000001'),
  array['0:0-10:model-a', '1:8-24:model-a'],
  'Chunks keep their code point range and model label'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select is(
  public.store_entry_search_chunks(
    '80000000-0000-4000-8000-000000000001',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000001'),
    'model-a',
    jsonb_build_array(pg_temp.chunk(0, 0, 24, pg_temp.unit_vector(3)))),
  true,
  'Storing again replaces the earlier chunks'
);
reset role;
select is(
  (select count(*) from public.entry_search_chunks where entry_id = '80000000-0000-4000-8000-000000000001'),
  1::bigint,
  'Re-indexing leaves only the new chunks'
);

-- An edit lands while the Entry is being embedded.
update public.entry_search_index_state set status = 'pending', leased_until = now() + interval '2 minutes'
where entry_id = '80000000-0000-4000-8000-000000000001';
select set_config('test.claimed_hash', pg_temp.hash_of('80000000-0000-4000-8000-000000000001'), true);
update public.entries set title = 'Climbing gym, Saturday'
where id = '80000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select is(
  public.store_entry_search_chunks(
    '80000000-0000-4000-8000-000000000001',
    current_setting('test.claimed_hash'),
    'model-a',
    jsonb_build_array(pg_temp.chunk(0, 0, 24, pg_temp.unit_vector(4)))),
  false,
  'Storing for text the Entry no longer has is refused'
);
reset role;
select is(
  (select status || ':' || (leased_until is null)::text
   from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000001'),
  'pending:true',
  'The edited Entry waits for the next drain with no lease'
);

-- A single-Entry failure backs off, and only for the hash it was about.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select throws_ok(
  format($$select public.fail_entry_search_index_job(%L, %L, 'Bad Error!')$$,
    '80000000-0000-4000-8000-000000000002',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000002')),
  '22023', 'invalid_search_error', 'A failure code is a short lowercase label'
);
select public.fail_entry_search_index_job(
  '80000000-0000-4000-8000-000000000002', repeat('0', 64), 'input_rejected');
reset role;
select is(
  (select status from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000002'),
  'pending',
  'A failure for another hash changes nothing'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select public.fail_entry_search_index_job(
  '80000000-0000-4000-8000-000000000002',
  pg_temp.hash_of('80000000-0000-4000-8000-000000000002'),
  'input_rejected');
reset role;
select is(
  (select status || ':' || attempts || ':' || last_error || ':' || (next_attempt_at > now())::text
   from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000002'),
  'failed:1:input_rejected:true',
  'A failure counts an attempt and delays the next one'
);

-- Status for the Library notice: active Entries still waiting.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select results_eq(
  $$select enabled, pending from public.search_index_status('model-a')$$,
  $$values (true, 2)$$,
  'Status counts active Entries that are not searchable by meaning yet'
);
select results_eq(
  $$select enabled, pending from public.search_index_status('model-b')$$,
  $$values (true, 2)$$,
  'Another model counts every active Entry again, ignoring Trash'
);

-- Search by meaning off: no meaning index is kept.
reset role;
update public.entry_search_index_state set status = 'indexed', indexed_model = 'model-a',
  indexed_hash = source_hash, next_attempt_at = now() - interval '1 minute'
where entry_id = '80000000-0000-4000-8000-000000000002';
insert into public.entry_search_chunks(entry_id, owner_id, chunk_index, source_hash, model, char_start, char_end, embedding)
select '80000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000801', 0, source_hash, 'model-a', 0, 10,
  (pg_temp.unit_vector(5)::text::extensions.vector(1024))::extensions.halfvec(1024)
from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000002';
insert into public.entry_search_chunks(entry_id, owner_id, chunk_index, source_hash, model, char_start, char_end, embedding)
select '80000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000802', 0, source_hash, 'model-a', 0, 10,
  (pg_temp.unit_vector(6)::text::extensions.vector(1024))::extensions.halfvec(1024)
from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000004';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
update public.profiles set semantic_search_enabled = false
where user_id = '10000000-0000-0000-0000-000000000801';
reset role;
select is(
  (select count(*) from public.entry_search_chunks where owner_id = '10000000-0000-0000-0000-000000000801'),
  0::bigint,
  'Turning the setting off deletes the owner''s vectors'
);
select is(
  (select count(*) from public.entry_search_chunks where owner_id = '10000000-0000-0000-0000-000000000802'),
  1::bigint,
  'Turning the setting off leaves other owners alone'
);
select is(
  (select array_agg(distinct status) from public.entry_search_index_state
   where owner_id = '10000000-0000-0000-0000-000000000801'),
  array['disabled'],
  'Every Entry of the owner is marked disabled'
);
update public.entries set body = 'Written while search by meaning was off.'
where id = '80000000-0000-4000-8000-000000000002';
insert into public.entries(id, owner_id, title, body) values
  ('80000000-0000-4000-8000-000000000005', '10000000-0000-0000-0000-000000000801', 'New while off', 'Body.');
select is(
  (select array_agg(status order by entry_id) from public.entry_search_index_state
   where entry_id in ('80000000-0000-4000-8000-000000000002', '80000000-0000-4000-8000-000000000005')),
  array['disabled', 'disabled'],
  'Edits and new Entries stay disabled while the setting is off'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select is(
  (select count(*) from public.claim_entry_search_index_jobs('model-a', 16)),
  0::bigint,
  'Nothing is claimed while the setting is off'
);
select is(
  public.store_entry_search_chunks(
    '80000000-0000-4000-8000-000000000005',
    pg_temp.hash_of('80000000-0000-4000-8000-000000000005'),
    'model-a',
    jsonb_build_array(pg_temp.chunk(0, 0, 5, pg_temp.unit_vector(7)))),
  false,
  'A drain that raced the switch cannot store vectors'
);
select results_eq(
  $$select enabled, pending from public.search_index_status('model-a')$$,
  $$values (false, 0)$$,
  'Status reports the setting off with nothing pending'
);
update public.profiles set semantic_search_enabled = true
where user_id = '10000000-0000-0000-0000-000000000801';
reset role;
select is(
  (select array_agg(distinct status) from public.entry_search_index_state
   where owner_id = '10000000-0000-0000-0000-000000000801'),
  array['pending'],
  'Turning the setting on queues every Entry again'
);

-- Access: the index is reachable only through the functions.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000801', true);
select throws_ok(
  $$select * from public.entry_search_chunks$$, '42501', null,
  'Signed-in users cannot read vectors directly'
);
select throws_ok(
  $$select * from public.entry_search_index_state$$, '42501', null,
  'Signed-in users cannot read index state directly'
);
select throws_ok(
  $$delete from public.entry_search_chunks$$, '42501', null,
  'Signed-in users cannot delete vectors directly'
);
select ok(
  has_function_privilege('authenticated', 'public.claim_entry_search_index_jobs(text, integer)', 'execute')
    and has_function_privilege('authenticated', 'public.store_entry_search_chunks(uuid, text, text, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.fail_entry_search_index_job(uuid, text, text)', 'execute')
    and has_function_privilege('authenticated', 'public.search_index_status(text)', 'execute'),
  'Signed-in users can run the indexing functions'
);
select ok(
  not has_function_privilege('anon', 'public.claim_entry_search_index_jobs(text, integer)', 'execute')
    and not has_function_privilege('anon', 'public.store_entry_search_chunks(uuid, text, text, jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.fail_entry_search_index_job(uuid, text, text)', 'execute')
    and not has_function_privilege('anon', 'public.search_index_status(text)', 'execute'),
  'Signed-out visitors cannot run any indexing function'
);
select ok(
  not has_function_privilege('authenticated', 'public.entry_search_source_hash(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.queue_entry_search_index()', 'execute')
    and not has_function_privilege('authenticated', 'public.apply_semantic_search_preference()', 'execute'),
  'The hash and the trigger functions are not callable by clients'
);
select ok(
  not has_table_privilege('anon', 'public.entry_search_chunks', 'select')
    and not has_table_privilege('service_role', 'public.entry_search_chunks', 'select')
    and not has_table_privilege('service_role', 'public.entry_search_index_state', 'select'),
  'Neither anon nor service_role is granted the index tables'
);

-- Lifecycle: Delete forever and export.
reset role;
insert into public.entry_search_chunks(entry_id, owner_id, chunk_index, source_hash, model, char_start, char_end, embedding)
select '80000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000802', 1, source_hash, 'model-a', 0, 10,
  (pg_temp.unit_vector(8)::text::extensions.vector(1024))::extensions.halfvec(1024)
from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000004';
delete from public.entries where id = '80000000-0000-4000-8000-000000000004';
select is(
  (select count(*) from public.entry_search_chunks where entry_id = '80000000-0000-4000-8000-000000000004')
    + (select count(*) from public.entry_search_index_state where entry_id = '80000000-0000-4000-8000-000000000004'),
  0::bigint,
  'Deleting an Entry forever removes its vectors and index state'
);
select ok(
  not exists (
    select 1 from public.export_dataset_names() as dataset(name)
    where name::text like 'entry_search%'
  ),
  'Export never includes the search index'
);

-- Hybrid search: keyword and meaning matches fused by rank in search_wiki_items.
insert into auth.users(id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000803', 'hybrid-owner@memotrail.local', '{}'),
  ('10000000-0000-0000-0000-000000000804', 'hybrid-other@memotrail.local', '{}');

insert into public.entries(id, owner_id, title, body, occurred_start, date_precision, updated_at) values
  ('81000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000803', 'Bike repair', 'Fixed the commuter bike.', '2026-06-01T12:00:00Z', 'day', '2026-10-01T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000803', 'The mechanic', 'The quiet man who tunes rims.', '2020-05-01T12:00:00Z', 'day', '2026-10-02T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000003', '10000000-0000-0000-0000-000000000803', 'Beach', 'Ran by the sea.', '2026-07-01T12:00:00Z', 'day', '2026-10-03T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000004', '10000000-0000-0000-0000-000000000803', 'In the bin', 'Thrown away note.', '2026-06-02T12:00:00Z', 'day', '2026-10-04T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000006', '10000000-0000-0000-0000-000000000803', 'Formatted note', 'Plain words only.', '2026-06-03T12:00:00Z', 'day', '2026-10-05T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000007', '10000000-0000-0000-0000-000000000803', 'Changed later', 'Spokes before the edit.', '2026-06-04T12:00:00Z', 'day', '2026-10-06T12:00:00Z'),
  ('81000000-0000-4000-8000-000000000008', '10000000-0000-0000-0000-000000000804', 'Not yours', 'Somebody else''s spokes.', '2026-06-05T12:00:00Z', 'day', '2026-10-07T12:00:00Z');
insert into public.entries(id, owner_id, title, body, item_subtype, date_precision, updated_at) values
  ('81000000-0000-4000-8000-000000000005', '10000000-0000-0000-0000-000000000803', 'Riding years', 'A stretch of getting around by wheel.', 'chapter', 'unknown', '2026-10-08T12:00:00Z');
update public.entries set deleted_at = '2026-10-10T00:00:00Z'
where id = '81000000-0000-4000-8000-000000000004';
update public.entries
set metadata = jsonb_build_object('body_rich', jsonb_build_object(
  'version', 1,
  'text', 'Plain words only.',
  'doc', jsonb_build_object('type', 'doc', 'content', jsonb_build_array(
    jsonb_build_object('type', 'paragraph', 'content', jsonb_build_array(
      jsonb_build_object('type', 'text', 'text', 'Plain words only.',
        'marks', jsonb_build_array(jsonb_build_object('type', 'bold'))))))
)))
where id = '81000000-0000-4000-8000-000000000006';

insert into public.tags(id, owner_id, name) values
  ('82000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000803', 'Neighbors'),
  ('82000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000803', 'Repairs');
insert into public.entry_tags(entry_id, tag_id, owner_id) values
  ('81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002', '10000000-0000-0000-0000-000000000803'),
  ('81000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000001', '10000000-0000-0000-0000-000000000803');

-- A unit vector of 1024 numbers with weight on up to two positions; the query is position 1.
create function pg_temp.axis(p_first integer, p_second integer default null, p_first_weight real default 1)
returns real[] language sql as $$
  select array_agg(
    case
      when position = p_first then p_first_weight
      when position = p_second then sqrt(1 - p_first_weight * p_first_weight)
      else 0
    end::real order by position)
  from generate_series(1, 1024) as position;
$$;
create function pg_temp.index_entry(p_entry uuid, p_embedding real[], p_end integer default 10, p_chunk integer default 0)
returns void language sql as $$
  insert into public.entry_search_index_state as state (entry_id, owner_id, source_hash)
  select id, owner_id, public.entry_search_source_hash(title, body) from public.entries where id = p_entry
  on conflict (entry_id) do nothing;
  update public.entry_search_index_state
  set status = 'indexed', indexed_model = 'model-h', indexed_hash = source_hash
  where entry_id = p_entry;
  insert into public.entry_search_chunks(entry_id, owner_id, chunk_index, source_hash, model, char_start, char_end, embedding)
  select p_entry, state.owner_id, p_chunk, state.source_hash, 'model-h', 0, p_end,
    (p_embedding::extensions.vector(1024))::extensions.halfvec(1024)
  from public.entry_search_index_state as state where state.entry_id = p_entry;
$$;

-- Similarity to the query: 1.0 for the Bike Entry, 0.8 for the mechanic and the Chapter,
-- 0.9 for the formatted note, and 0.0 for the beach.
select pg_temp.index_entry('81000000-0000-4000-8000-000000000001', pg_temp.axis(1));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000002', pg_temp.axis(1, 2, 0.8));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000002', pg_temp.axis(3), 18, 1);
select pg_temp.index_entry('81000000-0000-4000-8000-000000000003', pg_temp.axis(3));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000003', pg_temp.axis(6), 14, 1);
select pg_temp.index_entry('81000000-0000-4000-8000-000000000004', pg_temp.axis(1));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000005', pg_temp.axis(1, 4, 0.8));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000006', pg_temp.axis(1, 5, 0.9));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000007', pg_temp.axis(1));
select pg_temp.index_entry('81000000-0000-4000-8000-000000000008', pg_temp.axis(1));
-- A perfect chunk labelled with another model does not count for the formatted note.
select pg_temp.index_entry('81000000-0000-4000-8000-000000000006', pg_temp.axis(1), 10, 1);
update public.entry_search_chunks set model = 'model-z'
where entry_id = '81000000-0000-4000-8000-000000000006' and chunk_index = 1;
-- The edited Entry keeps its old chunk, but its text moved on.
update public.entries set body = 'Spokes after the edit.'
where id = '81000000-0000-4000-8000-000000000007';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000803', true);

select is(
  (select array_agg(entry_id order by entry_id) from public.search_wiki_items('spokes')),
  array['81000000-0000-4000-8000-000000000007']::uuid[],
  'Without a query vector the search is keyword-only'
);
select is(
  (select array_agg(entry_id order by entry_id) from public.search_wiki_items('spokes', p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000007']::uuid[],
  'A model label without a vector is still keyword-only'
);
select is(
  (select array_agg(entry_id order by entry_id) from public.search_wiki_items('spokes', p_query_embedding => pg_temp.axis(1))),
  array['81000000-0000-4000-8000-000000000007']::uuid[],
  'A vector without a model label is still keyword-only'
);
select is(
  (select array_agg(match_reasons[1] || ':' || coalesce(semantic_similarity::text, 'none')) from public.search_wiki_items('spokes')),
  array['Body:none'],
  'Keyword-only rows carry no meaning columns'
);
select is(
  (select array_agg(entry_id order by match_rank desc, entry_id)
   from public.search_wiki_items('bike', '{}', '{}', null, null, 50, 0, 'relevance', null, null, 0.5)),
  (select array_agg(entry_id order by match_rank desc, entry_id) from public.search_wiki_items('bike')),
  'A null vector returns the same rows in the same order as before'
);
select cmp_ok(
  (select match_rank from public.search_wiki_items('bike')), '>=', 4::double precision,
  'Keyword-only relevance keeps its original scale'
);
select is(
  (select count(*) from public.search_wiki_items('', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h', p_tag_names => array['Repairs'])),
  1::bigint,
  'A filter-only search ignores the vector'
);
select is(
  (select match_reasons from public.search_wiki_items('', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h', p_tag_names => array['Repairs'])),
  array['Filters'],
  'A filter-only search still reports Filters'
);

select is(
  (select array_agg(entry_id order by match_rank desc, entry_id)
   from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array[
    '81000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000006',
    '81000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000005'
  ]::uuid[],
  'An Entry matching by words and meaning ranks first, then the closest meanings'
);
select is(
  (select match_reasons from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000002'),
  array['Meaning'],
  'A semantic-only Entry appears with the Meaning reason alone'
);
select is(
  (select match_reasons from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000001'),
  array['Title', 'Body', 'Meaning'],
  'Meaning is appended last to the keyword reasons'
);
select is(
  (select semantic_char_start || '-' || semantic_char_end || ':' || semantic_chunk_count || ':' || round(semantic_similarity::numeric, 2)
   from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000002'),
  '0-10:2:0.80',
  'The best chunk, its range, and the chunk count come with the result'
);
select is(
  (select total_count from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h') limit 1),
  4::bigint,
  'The total counts the union of keyword and meaning matches'
);
select is(
  (select array_agg(entry_id order by entry_id)
   from public.search_wiki_items('bike', p_limit => 2, p_offset => 2, p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000005']::uuid[],
  'Pagination slices the fused order'
);
select is(
  (select array_agg(entry_id order by entry_id)
   from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h', p_semantic_min_similarity => 0.85)),
  array['81000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000006']::uuid[],
  'A higher floor drops weaker meaning matches'
);
select is(
  (select count(*) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000003'),
  0::bigint,
  'An Entry whose best chunk is below the floor never appears'
);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(7), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000001']::uuid[],
  'A far vector adds no meaning matches and keeps the keyword match'
);

select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_tag_names => array['Neighbors'], p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000002']::uuid[],
  'A tag filter keeps a meaning match with that tag and drops the rest'
);
select is(
  (select count(*) from public.search_wiki_items('bike', p_tag_names => array['Nobody'], p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  0::bigint,
  'A tag filter with no members excludes every semantic candidate'
);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_item_classifications => array['chapter'], p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000005']::uuid[],
  'The Chapter filter keeps only a Chapter among the meaning matches'
);
select is(
  (select array_agg(entry_id order by entry_id) from public.search_wiki_items('bike', p_item_classifications => array['entry'], p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000006']::uuid[],
  'The Entry filter leaves the Chapter out of the meaning matches'
);
select is(
  (select array_agg(entry_id order by entry_id) from public.search_wiki_items('bike', p_date_from => '2026-01-01', p_date_to => '2026-12-31', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000006']::uuid[],
  'A date filter excludes a meaning match from another year'
);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_date_from => '2020-01-01', p_date_to => '2020-12-31', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000002']::uuid[],
  'A date filter keeps a meaning match inside the range'
);

select is(
  (select count(*) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000004'),
  0::bigint,
  'An Entry in Trash never appears, whatever its vector'
);
select is(
  (select count(*) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000008'),
  0::bigint,
  'Another owner''s vectors never produce a match'
);
select is(
  (select count(*) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')
   where entry_id = '81000000-0000-4000-8000-000000000007'),
  0::bigint,
  'A chunk indexed from older text does not match an edited Entry'
);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-other')),
  array['81000000-0000-4000-8000-000000000001']::uuid[],
  'Vectors of another model never match'
);
select is(
  (select round(similarity::numeric, 2) from public.semantic_entry_matches(pg_temp.axis(1), 'model-h', 0.5)
   where entry_id = '81000000-0000-4000-8000-000000000006'),
  0.90,
  'A chunk labelled with another model does not count toward an Entry'
);

select is(
  (select count(*) from public.search_wiki_items('paragraph')), 0::bigint,
  'Rich text node names are not searchable (issue 42)'
);
select is(
  (select count(*) from public.search_wiki_items('bold')), 0::bigint,
  'Rich text mark names are not searchable (issue 42)'
);
select is(
  (select count(*) from public.search_wiki_items('doc')), 0::bigint,
  'Rich text structure words are not searchable (issue 42)'
);
select is(
  (select match_reasons from public.search_wiki_items('plain words')),
  array['Body'],
  'A formatted Entry is still found by its writing'
);

select throws_ok(
  $$select * from public.semantic_entry_matches(array[1, 2, 3]::real[], 'model-h', 0.5)$$,
  '22023', 'invalid_query_embedding', 'A query vector of the wrong size is refused'
);
select throws_ok(
  format($$select * from public.semantic_entry_matches(%L::real[], 'model-h', 0.5)$$, (select array_agg(0::real) from generate_series(1, 1024))),
  '22023', 'invalid_query_embedding', 'A zero query vector is refused'
);
select throws_ok(
  $$select * from public.search_wiki_items('bike', p_query_embedding => array[1]::real[], p_embedding_model => 'model-h')$$,
  '22023', 'invalid_query_embedding', 'Search refuses a malformed query vector'
);
select throws_ok(
  $$select * from public.semantic_entry_matches(pg_temp.axis(1), 'bad model', 0.5)$$,
  '22023', 'invalid_search_model', 'The model label is validated'
);

select ok(
  has_function_privilege('authenticated', 'public.semantic_entry_matches(real[], text, real)', 'execute')
    and not has_function_privilege('anon', 'public.semantic_entry_matches(real[], text, real)', 'execute'),
  'Only signed-in users can run the meaning match'
);
select ok(
  has_function_privilege('authenticated', 'public.search_wiki_items(text, text[], text[], date, date, integer, integer, text, real[], text, real)', 'execute')
    and not has_function_privilege('anon', 'public.search_wiki_items(text, text[], text[], date, date, integer, integer, text, real[], text, real)', 'execute'),
  'Only signed-in users can run the merged search'
);
select is(
  (select jsonb_array_length(public.archive_wiki_search_evidence(array['bike'])->'entries')),
  1,
  'Archive evidence keeps resolving the search'
);

-- Another owner sees none of these vectors.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000804', true);
select is(
  (select array_agg(entry_id) from public.semantic_entry_matches(pg_temp.axis(1), 'model-h', 0.5)),
  array['81000000-0000-4000-8000-000000000008']::uuid[],
  'Each owner matches only their own vectors'
);

-- With the setting off, vectors are ignored even if some remain.
reset role;
update public.profiles set semantic_search_enabled = false
where user_id = '10000000-0000-0000-0000-000000000803';
select pg_temp.index_entry('81000000-0000-4000-8000-000000000002', pg_temp.axis(1), 10, 2);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000803', true);
select is(
  (select count(*) from public.semantic_entry_matches(pg_temp.axis(1), 'model-h', 0.5)),
  0::bigint,
  'The meaning match is empty while the setting is off'
);
select is(
  (select array_agg(entry_id) from public.search_wiki_items('bike', p_query_embedding => pg_temp.axis(1), p_embedding_model => 'model-h')),
  array['81000000-0000-4000-8000-000000000001']::uuid[],
  'Search falls back to keywords while the setting is off'
);
reset role;

select * from finish();
rollback;
