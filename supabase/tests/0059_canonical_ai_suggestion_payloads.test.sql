begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into public.entries(id, owner_id, title, body)
values (
  '99000000-0000-4000-8000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Suggestion source',
  'A thought waiting to be organized.'
);

insert into public.ai_suggestions(
  id,
  owner_id,
  entry_id,
  entry_revision,
  request_scope,
  suggestions,
  status
)
values (
  '99000000-0000-4000-8000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  '99000000-0000-4000-8000-000000000001',
  1,
  'classification_tagging',
  '{"tags":["Thought"]}',
  'proposed'
);

select ok(
  not (select suggestions ? 'entryType' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  'Canonical suggestion omits the legacy entryType key'
);

select is(
  (select suggestions #>> '{tags,0}' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  'Thought',
  'Canonical suggestion keeps optional tags'
);

select is(
  (select suggestions ? 'classification' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  false,
  'Canonical suggestion does not prescribe an Entry type'
);

select throws_ok(
  $$update public.ai_suggestions set suggestions = '{"entryType":"standard"}' where id = '99000000-0000-4000-8000-000000000002'$$,
  '23514',
  'new row for relation "ai_suggestions" violates check constraint "ai_suggestions_entry_payload_check"',
  'Legacy suggestion payloads are rejected'
);

select throws_ok(
  $$update public.ai_suggestions set suggestions = '{"classification":{"itemKind":"entry","itemSubtype":"entry"}}' where id = '99000000-0000-4000-8000-000000000002'$$,
  '23514',
  'new row for relation "ai_suggestions" violates check constraint "ai_suggestions_entry_payload_check"',
  'AI classification payloads are rejected'
);

select * from finish();
rollback;
