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
  '{"classification":{"itemKind":"writing","itemSubtype":"note"}}',
  'proposed'
);

select ok(
  not (select suggestions ? 'entryType' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  'Canonical suggestion omits the legacy entryType key'
);

select is(
  (select suggestions #>> '{classification,itemKind}' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  'writing',
  'Canonical suggestion keeps item Kind'
);

select is(
  (select suggestions #>> '{classification,itemSubtype}' from public.ai_suggestions where id = '99000000-0000-4000-8000-000000000002'),
  'note',
  'Canonical suggestion keeps item type'
);

select throws_ok(
  $$update public.ai_suggestions set suggestions = '{"entryType":"standard"}' where id = '99000000-0000-4000-8000-000000000002'$$,
  '23514',
  'new row for relation "ai_suggestions" violates check constraint "ai_suggestions_canonical_payload_check"',
  'Legacy suggestion payloads are rejected'
);

select throws_ok(
  $$update public.ai_suggestions set suggestions = '{"classification":{"itemKind":"unknown","itemSubtype":"note"}}' where id = '99000000-0000-4000-8000-000000000002'$$,
  '23514',
  'new row for relation "ai_suggestions" violates check constraint "ai_suggestions_canonical_payload_check"',
  'Unknown canonical item Kinds are rejected'
);

select * from finish();
rollback;
