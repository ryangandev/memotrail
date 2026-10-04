begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

create or replace function pg_temp.capture_sqlstate(statement text)
returns text
language plpgsql
as $$
begin
  execute statement;
  return null;
exception
  when others then
    return sqlstate;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-0000-0000-000000000013',
  'authenticated', 'authenticated', 'goals-other@memotrail.local', '',
  timezone('utc', now()), '{"provider":"google","providers":["google"]}'::jsonb,
  '{"full_name":"Goals Other User"}'::jsonb, timezone('utc', now()),
  timezone('utc', now()), '', '', '', ''
)
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.goals_workspace()),
  0,
  'The Goals workspace starts empty for the owner'
);

select is(
  pg_temp.capture_sqlstate($$select * from public.goals_workspace(0, 0)$$),
  '22023',
  'The Goals workspace rejects an invalid page'
);

insert into public.entries (title, body, owner_id, item_kind, item_subtype, inbox_status)
values (
  'Learning journal',
  'Notes from language practice.',
  '10000000-0000-0000-0000-000000000001',
  'entry','entry',
  'organized'
);

select lives_ok(
  $$
    select *
    from public.save_goal_entry(
      'Learn Japanese',
      'Build a patient daily practice.',
      'active',
      '2028-12-31',
      array['Language', 'growth', 'LANGUAGE'],
      null,
      null
    )
  $$,
  'An owner can create an organized Goal'
);

select is(
  (select item_kind from public.entries where title = 'Learn Japanese'),
  'goal',
  'A Goal is stored as a specialized Entry'
);

select is(
  (select inbox_status from public.entries where title = 'Learn Japanese'),
  'organized',
  'Direct Goal creation produces an organized Entry'
);

select is(
  (
    select concat_ws('|', goals.status, goals.target_date::text)
    from public.goals
    join public.entries on entries.id = goals.entry_id
    where entries.title = 'Learn Japanese'
  ),
  'active|2028-12-31',
  'Goal status and optional target date are preserved'
);

select is(
  (
    select concat_ws('|', occurred_start::text, occurred_end::text, date_precision)
    from public.entries
    where title = 'Learn Japanese'
  ),
  'unknown',
  'A target date does not invent an Entry occurrence date'
);

select is(
  (select tag_names::text from public.goals_workspace() where title = 'Learn Japanese'),
  '{growth,Language}',
  'Goal tags are normalized and de-duplicated case-insensitively'
);

select is(
  (
    select count(*)::integer
    from public.entry_links
    join public.entries on entries.id = entry_links.source_entry_id
    where entries.title = 'Learn Japanese'
  ),
  0,
  'Saving a Goal creates no related links'
);

select is(
  (select status from public.goals_workspace() where title = 'Learn Japanese'),
  'active',
  'The Goals workspace returns the Goal state'
);

select is(
  (select total_count from public.goals_workspace() limit 1),
  1::bigint,
  'The Goals workspace reports its total result count'
);

select lives_ok(
  $$
    select *
    from public.save_goal_entry(
      'Visit Iceland', '', 'active', null, array['Travel'], null, null
    )
  $$,
  'A Goal may omit its description and target date'
);

select lives_ok(
  $$
    select *
    from public.save_goal_entry(
      'Pause running', 'Rest without pressure.', 'let_go', null, array[]::text[], null, null
    )
  $$,
  'A Goal may be saved as let go'
);

select is(
  (select title from public.goals_workspace(1, 0)),
  'Learn Japanese',
  'Dated active Goals sort first'
);

select is(
  (select title from public.goals_workspace(1, 1)),
  'Visit Iceland',
  'Undated active Goals sort before let-go Goals'
);

select is(
  (select total_count from public.goals_workspace(1, 2)),
  3::bigint,
  'A paginated Goal row retains the complete count'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('', '', 'active', null, '{}', null, null)$$
  ),
  '22023',
  'Goal creation rejects an empty title'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('Bad', '', 'considering', null, '{}', null, null)$$
  ),
  '22023',
  'Goal creation rejects the retired Considering state'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('Bad', '', 'done', null, '{}', null, null)$$
  ),
  '22023',
  'Goal creation rejects a task-style unsupported status'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('Bad', '', 'active', null, array[''], null, null)$$
  ),
  '22023',
  'Goal creation rejects blank tags'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('Bad', '', 'active', 'infinity', '{}', null, null)$$
  ),
  '22023',
  'Goal creation rejects an unbounded target date'
);

select is(
  pg_temp.capture_sqlstate(
    $$select * from public.save_goal_entry('Bad', '', null, null, '{}', null, null)$$
  ),
  '22023',
  'Goal creation requires a state'
);

select is(
  (
    select count(*)::integer
    from public.save_goal_entry(
      'Not a Goal', '', 'active', null, '{}',
      (select id from public.entries where title = 'Learning journal'), 1
    )
  ),
  0,
  'Saving a Goal cannot rewrite another kind of Entry'
);

select lives_ok(
  format(
    $$select * from public.save_goal_entry(
      'Learn Japanese well', 'Updated reflection.', 'let_go', null, array['language'], %L::uuid, 1
    )$$,
    (select id from public.entries where title = 'Learn Japanese')
  ),
  'A Goal can be revision-safely edited'
);

select is(
  (select revision from public.entries where title = 'Learn Japanese well'),
  2,
  'Editing a Goal increments its Entry revision'
);

select is(
  (
    select snapshot -> 'goal' ->> 'status'
    from public.entry_versions
    join public.entries on entries.id = entry_versions.entry_id
    where entries.title = 'Learn Japanese well' and entry_versions.version = 1
  ),
  'active',
  'Goal history preserves the prior status'
);

select ok(
  (
    select not (snapshot -> 'goal' ? 'horizon')
    from public.entry_versions
    join public.entries on entries.id = entry_versions.entry_id
    where entries.title = 'Learn Japanese well' and entry_versions.version = 1
  ),
  'Goal history no longer records a horizon'
);

select is(
  (select status from public.goals_workspace() where title = 'Learn Japanese well'),
  'let_go',
  'An edited Goal keeps its new state'
);

select is(
  (
    select count(*)::integer
    from public.save_goal_entry(
      'Stale', '', 'active', null, '{}',
      (select id from public.entries where title = 'Learn Japanese well'), 1
    )
  ),
  0,
  'A stale Goal edit returns no row'
);

select is(
  (
    select title
    from public.search_wiki_items('Japanese', array['goal'], '{}', null, null, 20, 0)
    where title = 'Learn Japanese well'
  ),
  'Learn Japanese well',
  'Global search finds a Goal'
);

select is(
  (
    select title
    from public.search_wiki_items('2028-12-31', array['goal'], '{}', null, null, 20, 0)
    where title = 'Learn Japanese well'
  ),
  null,
  'Clearing a target date removes its structured search value'
);

select is(
  (
    select count(*)::integer
    from public.mark_goal_achieved_with_first_time(
      (select id from public.entries where title = 'Visit Iceland'),
      1, '2026-09-03T19:00:00Z', 'day', 'First Iceland trip', 'America/Los_Angeles'
    )
  ),
  1,
  'A Goal can atomically create an achieved First Time'
);

select is(
  (
    select goals.status
    from public.goals
    join public.entries on entries.id = goals.entry_id
    where entries.title = 'Visit Iceland' and entries.item_kind = 'goal'
  ),
  'achieved',
  'The achievement action marks the Goal achieved'
);

select is(
  (
    select revision
    from public.entries
    where title = 'Visit Iceland' and item_kind = 'goal'
  ),
  2,
  'The achievement action revision-safely updates the Goal'
);

select is(
  (
    select body
    from public.entries
    where title = 'Visit Iceland' and item_kind = 'entry' and item_subtype = 'first_time'
  ),
  '',
  'The created First Time does not copy the Goal description'
);

select is(
  (
    select concat_ws('|', item_kind, item_subtype, inbox_status, date_precision, occurred_label)
    from public.entries
    where title = 'Visit Iceland' and item_kind = 'entry' and item_subtype = 'first_time'
  ),
  'entry|first_time|organized|day|First Iceland trip',
  'The created First Time preserves organized occurrence context'
);

select is(
  (
    select relationship
    from public.entry_links
    join public.entries as source on source.id = entry_links.source_entry_id
    where source.title = 'Visit Iceland' and relationship = 'achievement'
  ),
  'achievement',
  'The achieved Goal links to its First Time'
);

select is(
  (
    select snapshot -> 'goal' ->> 'status'
    from public.entry_versions
    join public.entries on entries.id = entry_versions.entry_id
    where entries.title = 'Visit Iceland' and entry_versions.version = 1
  ),
  'active',
  'The achievement action preserves the previous Goal status in history'
);

select is(
  (
    select count(*)::integer
    from public.mark_goal_achieved_with_first_time(
      (select id from public.entries where title = 'Visit Iceland' and item_kind = 'goal'),
      1, '2026-09-04T19:00:00Z', 'day', null, 'America/Los_Angeles'
    )
  ),
  0,
  'A stale achievement action cannot create another First Time'
);

select is(
  pg_temp.capture_sqlstate(
    format(
      $$select * from public.mark_goal_achieved_with_first_time(
        %L::uuid, 2, '2026-09-03T19:00:00Z', 'unknown', null, 'America/Los_Angeles'
      )$$,
      (select id from public.entries where title = 'Visit Iceland' and item_kind = 'goal')
    )
  ),
  '22023',
  'The achievement action rejects unknown completion precision'
);

select is(
  pg_temp.capture_sqlstate(
    format(
      $$select * from public.mark_goal_achieved_with_first_time(
        %L::uuid, 2, '2026-09-03T19:00:00Z', 'day', null, 'Not/A-Timezone'
      )$$,
      (select id from public.entries where title = 'Visit Iceland' and item_kind = 'goal')
    )
  ),
  '22023',
  'The achievement action rejects an invalid timezone'
);

select is(
  (
    select count(*)::integer
    from public.trash_goal_entry(
      (select id from public.entries where title = 'Pause running'),
      1
    )
  ),
  1,
  'A current Goal can move to recoverable Trash'
);

select is(
  (select wiki_item_kind from public.trash_workspace() where title = 'Pause running'),
  'goal',
  'The shared Trash workspace preserves the Goal type'
);

select is(
  (select count(*)::integer from public.goals_workspace() where title = 'Pause running'),
  0,
  'A trashed Goal leaves the active workspace'
);

select is(
  (
    select count(*)::integer
    from public.restore_trash_item(
      'entry',
      (select id from public.entries where title = 'Pause running'),
      (select revision from public.entries where title = 'Pause running'),
      (select deleted_at from public.entries where title = 'Pause running')
    )
  ),
  1,
  'A Goal can be restored through the shared Trash contract'
);

select is(
  (select status from public.goals_workspace() where title = 'Pause running'),
  'let_go',
  'Restoration preserves Goal structure'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000013', true);

select is(
  (select count(*)::integer from public.goals_workspace()),
  0,
  'Another owner cannot browse private Goals'
);

select is(
  (
    select count(*)::integer
    from public.trash_goal_entry(
      (select id from public.entries where title = 'Learn Japanese well'),
      2
    )
  ),
  0,
  'Another owner cannot trash a private Goal'
);

reset role;

select function_returns(
  'public', 'goals_workspace', array['integer', 'integer'], 'setof record',
  'The Goals workspace function remains available'
);

select function_returns(
  'public', 'trash_goal_entry', array['uuid', 'integer'], 'setof record',
  'The Goal Trash function remains available'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.goals_workspace(integer,integer)'::regprocedure),
  false,
  'The Goals workspace uses invoker rights'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.save_goal_entry(text,text,text,date,text[],uuid,integer)'::regprocedure),
  true,
  'The owner-checked Goal save boundary writes tags through the shared writer'
);

select is(
  to_regprocedure('public.save_goal_entry(text,text,text,text,date,text[],uuid[],uuid,integer)'),
  null,
  'The Goal save with horizons and related Items is retired'
);

select hasnt_column('public', 'goals', 'horizon', 'Goals have no horizon');

select col_default_is('public', 'goals', 'status', 'active'::text, 'New Goals start as wanted');

select throws_ok(
  $$insert into public.goals (entry_id, owner_id, status)
    select id, owner_id, 'paused' from public.entries where title = 'Learning journal'$$,
  '23514',
  null,
  'The retired Paused state is refused'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.mark_goal_achieved_with_first_time(uuid,integer,timestamptz,text,text,text)'::regprocedure),
  false,
  'The Goal achievement action uses invoker rights'
);

select is(
  (select proconfig from pg_proc where oid = 'public.goals_workspace(integer,integer)'::regprocedure),
  array['search_path=""']::text[],
  'The Goals workspace has an empty search path'
);

select ok(
  has_function_privilege('authenticated', 'public.goals_workspace(integer,integer)', 'EXECUTE'),
  'Authenticated users can execute the Goals workspace'
);

select ok(
  not has_function_privilege('anon', 'public.goals_workspace(integer,integer)', 'EXECUTE')
    and not has_function_privilege('public', 'public.goals_workspace(integer,integer)', 'EXECUTE'),
  'Anonymous and PUBLIC roles cannot execute the Goals workspace'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.mark_goal_achieved_with_first_time(uuid,integer,timestamptz,text,text,text)',
    'EXECUTE'
  ),
  'Authenticated users can execute the Goal achievement action'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.mark_goal_achieved_with_first_time(uuid,integer,timestamptz,text,text,text)',
    'EXECUTE'
  ),
  'Anonymous users cannot execute the Goal achievement action'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'entries_owner_goal_updated_idx'
  ),
  'Goals browsing has an Entry index'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'goals_owner_status_target_idx'
  ),
  'Goal state browsing has a supporting index'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'entry_links_owner_source_relationship_idx'
  ),
  'Related Goal Entry links have a supporting index'
);

select * from finish();
rollback;
