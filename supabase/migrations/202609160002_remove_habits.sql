-- Habits were deferred from the product before launch. Remove their empty
-- persistence model instead of carrying a dormant feature through Life Wiki.

-- Home no longer publishes retired Habit counters. Rebuild the function
-- because PostgreSQL cannot change a table-returning function's row type with
-- CREATE OR REPLACE.
do $$
declare
  definition text;
  habit_columns text := ', active_habit_count bigint, due_habit_count bigint, completed_habit_count bigint, skipped_habit_count bigint';
  habit_stats text := E'  habit_rows as (\n    select *\n    from public.habits_workspace(p_local_date)\n  ),\n  habit_stats as (\n    select\n      count(*) as active_habit_count,\n      count(*) filter (where local_status <> ''not_scheduled'') as due_habit_count,\n      count(*) filter (where local_status = ''completed'') as completed_habit_count,\n      count(*) filter (where local_status = ''skipped'') as skipped_habit_count\n    from habit_rows\n  ),';
  habit_values text := E'    habit_stats.active_habit_count,\n    habit_stats.due_habit_count,\n    habit_stats.completed_habit_count,\n    habit_stats.skipped_habit_count,\n';
begin
  select pg_get_functiondef('public.home_workspace(date,text,integer)'::regprocedure)
  into definition;
  if strpos(definition, habit_columns) = 0
    or strpos(definition, habit_stats) = 0
    or strpos(definition, habit_values) = 0
    or strpos(definition, E'\n  cross join habit_stats') = 0
  then
    raise exception 'Expected the complete Home Habit contract';
  end if;
  definition := replace(definition, habit_columns, '');
  definition := replace(definition, habit_stats, '');
  definition := replace(definition, habit_values, '');
  definition := replace(definition, E'\n  cross join habit_stats', '');
  execute 'drop function public.home_workspace(date,text,integer)';
  execute definition;
end;
$$;

revoke all on function public.home_workspace(date,text,integer) from public,anon;
grant execute on function public.home_workspace(date,text,integer) to authenticated;

-- AI archive search no longer exposes a Habit switch or a null Habit payload.
do $$
declare
  definition text;
  habit_evidence text := E',''habits'',case when p_include_habits and coalesce(cardinality(p_entry_types),0)=0 and coalesce(cardinality(p_collection_names),0)=0 and coalesce(cardinality(p_tag_names),0)=0 then public.archive_habit_evidence(p_date_from,p_date_to,p_as_of) else null end';
begin
  select pg_get_functiondef('public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date)'::regprocedure)
  into definition;
  if strpos(definition, ', p_include_habits boolean DEFAULT false') = 0
    or strpos(definition, habit_evidence) = 0
  then
    raise exception 'Expected the complete AI Habit evidence contract';
  end if;
  definition := replace(definition, ', p_include_habits boolean DEFAULT false', '');
  definition := replace(definition, habit_evidence, '');
  execute 'drop function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date)';
  execute definition;
end;
$$;

revoke all on function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date) from public,anon;
grant execute on function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,text,date) to authenticated;

-- Library keyword search now covers the two canonical directory presets.
create or replace function public.search_library_entities(
  p_query text,
  p_limit integer default 20,
  p_offset integer default 0,
  p_kinds text[] default array['person','place']::text[]
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  result jsonb;
begin
  if length(q) > 200
    or p_limit is null or p_limit < 1 or p_limit > 50
    or p_offset is null or p_offset < 0 or p_offset > 10000
    or p_kinds is null or cardinality(p_kinds) < 1 or cardinality(p_kinds) > 2
    or not (p_kinds <@ array['person','place']::text[])
  then
    raise exception using errcode = '22023', message = 'invalid_library_search';
  end if;

  with candidates as (
    select
      person.id,
      'person'::text as kind,
      person.name,
      coalesce(person.notes, '') as notes,
      coalesce(person.relationship_label, '') as details
    from public.people as person
    where person.owner_id = auth.uid()
      and person.deleted_at is null
      and 'person' = any(p_kinds)

    union all

    select
      place.id,
      'place',
      place.name,
      coalesce(place.notes, ''),
      concat_ws(
        ' ', place.address, place.city, place.region, place.country,
        place.latitude::text, place.longitude::text
      )
    from public.places as place
    where place.owner_id = auth.uid()
      and place.deleted_at is null
      and 'place' = any(p_kinds)
  ),
  matched as (
    select
      id,
      kind,
      name,
      left(concat_ws(' · ', nullif(details, ''), nullif(notes, '')), 280) as excerpt,
      array_remove(array[
        case when public.library_text_matches(name, q) then 'Name' end,
        case when public.library_text_matches(notes, q) then 'Notes' end,
        case when public.library_text_matches(details, q) then 'Details' end
      ], null) as match_reasons,
      case
        when lower(name) = lower(q) then 0
        when strpos(lower(name), lower(q)) > 0 then 1
        else 2
      end as rank
    from candidates
    where public.library_text_matches(concat_ws(' ', name, notes, details), q)
  )
  select jsonb_build_object(
    'total_count', (select count(*) from matched),
    'items', coalesce((
      select jsonb_agg(to_jsonb(page) - 'rank' order by page.rank, lower(page.name), page.kind, page.id)
      from (
        select * from matched
        order by rank, lower(name), kind, id
        limit p_limit offset p_offset
      ) as page
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$$;

-- Remove Habit rows from Trash without changing the rest of its pagination
-- contract while Web and iOS move to semantic item Kind fields.
do $$
declare
  definition text;
  old_rows text := E'\n    union all\n\n    select\n      ''habit''::text,\n      habits.id,\n      habits.name,\n      case\n        when habits.tracking_mode = ''measure'' then\n          concat(habits.measurement_unit, '' · target '', habits.target_value::text)\n        else ''Check Habit''\n      end,\n      habits.deleted_at,\n      habits.deleted_at + interval ''30 days'',\n      habits.revision,\n      null::text,\n      null::uuid,\n      array[]::text[]\n    from public.habits\n    where habits.owner_id = auth.uid()\n      and habits.deleted_at is not null';
begin
  select pg_get_functiondef('public.trash_workspace(integer,integer)'::regprocedure)
  into definition;
  if (length(definition) - length(replace(definition, old_rows, ''))) <> length(old_rows) then
    raise exception 'Expected exactly one Trash Habit branch';
  end if;
  execute replace(definition, old_rows, '');
end;
$$;

create or replace function public.prepare_empty_trash()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  with candidates as (
    select 'entry'::text as item_kind, entry.id as item_id, entry.deleted_at, entry.revision
    from public.entries as entry
    where entry.owner_id = auth.uid()
      and entry.deleted_at is not null
      and not exists (
        select 1 from public.people as person
        where person.id = entry.id and person.owner_id = entry.owner_id
      )
      and not exists (
        select 1 from public.places as place
        where place.id = entry.id and place.owner_id = entry.owner_id
      )

    union all

    select 'attachment', attachment.id, attachment.deleted_at, null::integer
    from public.attachments as attachment
    join public.entries as entry
      on entry.id = attachment.entry_id and entry.owner_id = attachment.owner_id
    where attachment.owner_id = auth.uid()
      and attachment.deleted_at is not null
      and entry.deleted_at is null

    union all

    select 'place', place.id, place.deleted_at, place.revision
    from public.places as place
    where place.owner_id = auth.uid() and place.deleted_at is not null

    union all

    select 'person', person.id, person.deleted_at, person.revision
    from public.people as person
    where person.owner_id = auth.uid() and person.deleted_at is not null

    union all

    select 'collection', collection.id, collection.archived_at, collection.revision
    from public.collections as collection
    where collection.owner_id = auth.uid() and collection.archived_at is not null
  ),
  bounded as (
    select *
    from candidates
    order by
      case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
      item_kind,
      item_id
    limit 10001
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(bounded)
      order by
        case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
        item_kind,
        item_id
    ),
    '[]'::jsonb
  )
  into result
  from bounded;

  if jsonb_array_length(result) > 10000 then
    raise exception using errcode = '54000', message = 'trash_snapshot_too_large';
  end if;

  return result;
end;
$$;

create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','entry_versions','collections','tags','entry_collections','entry_tags',
    'places','people','entry_places','entry_people','timeline_tracks','timeline_items','homes','vehicles','goals',
    'attachments','entry_links','person_versions','place_versions','ai_preferences','ai_usage','ai_suggestions',
    'ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$$;

-- Remove dormant Habit branches from the generic Trash mutations before the
-- underlying tables disappear.
do $$
declare
  definition text;
  habit_branch text;
begin
  select pg_get_functiondef(
    'public.restore_trash_item_without_photo_history(text,uuid,integer,timestamptz)'::regprocedure
  ) into definition;
  habit_branch := E'  if p_item_kind = ''habit'' then\n    if p_expected_revision is null or p_expected_revision < 1 then\n      raise exception using errcode = ''22023'', message = ''invalid_trash_revision'';\n    end if;\n\n    return query\n    update public.habits\n    set deleted_at = null\n    where habits.id = p_item_id\n      and habits.owner_id = trash_owner_id\n      and habits.revision = p_expected_revision\n      and habits.deleted_at = p_expected_deleted_at\n    returning ''habit''::text, habits.id, habits.revision;\n    return;\n  end if;\n\n';
  if strpos(definition, habit_branch) = 0 then
    raise exception 'Expected the Trash restore Habit branch';
  end if;
  execute replace(definition, habit_branch, '');

  select pg_get_functiondef(
    'public.delete_trash_item_forever(text,uuid,integer,timestamptz)'::regprocedure
  ) into definition;
  habit_branch := E'  if p_item_kind = ''habit'' then\n    if p_expected_revision is null or p_expected_revision < 1 then\n      raise exception using errcode = ''22023'', message = ''invalid_trash_revision'';\n    end if;\n\n    if not exists (\n      select 1\n      from public.habits\n      where habits.id = p_item_id\n        and habits.owner_id = trash_owner_id\n        and habits.revision = p_expected_revision\n        and habits.deleted_at = p_expected_deleted_at\n    ) then\n      return;\n    end if;\n\n    delete from public.habit_occurrences\n    where habit_occurrences.habit_id = p_item_id\n      and habit_occurrences.owner_id = trash_owner_id;\n\n    return query\n    delete from public.habits\n    where habits.id = p_item_id\n      and habits.owner_id = trash_owner_id\n      and habits.revision = p_expected_revision\n      and habits.deleted_at = p_expected_deleted_at\n    returning ''habit''::text, habits.id;\n    return;\n  end if;\n\n';
  if strpos(definition, habit_branch) = 0 then
    raise exception 'Expected the permanent delete Habit branch';
  end if;
  execute replace(definition, habit_branch, '');

  select pg_get_functiondef(
    'public.trash_item_storage_paths(text,uuid,integer,timestamptz)'::regprocedure
  ) into definition;
  if strpos(definition, 'if p_item_kind in (''habit'',''place'',''person'',''collection'')') = 0 then
    raise exception 'Expected the Trash storage Habit branch';
  end if;
  execute replace(
    definition,
    'if p_item_kind in (''habit'',''place'',''person'',''collection'')',
    'if p_item_kind in (''place'',''person'',''collection'')'
  );
end;
$$;

drop function if exists public.archive_habit_evidence(date,date,date);
drop function if exists public.habit_entry_choices(uuid,date,text,integer);
drop function if exists public.habit_year_calendar(uuid,integer,date);
drop function if exists public.habits_workspace(date);
drop function if exists public.record_habit_occurrence(uuid,date,text,numeric,text,uuid,integer);
drop function if exists public.save_habit_check_in(uuid,date,text,numeric,text,uuid,integer);
drop function if exists public.save_habit(uuid,integer,text,text,text,numeric,jsonb,date,date);
drop function if exists public.trash_habit(uuid,integer);
drop function if exists public.habit_scheduled_day_count(jsonb,date,date,date,date);
drop function if exists public.habit_is_scheduled(jsonb,date,date,date);
drop function if exists public.habit_schedule_is_valid(jsonb);

drop table public.habit_occurrence_versions cascade;
drop table public.habit_occurrences cascade;
drop table public.habit_versions cascade;
drop table public.habits cascade;

drop function if exists public.archive_habit_occurrence_version();
drop function if exists public.archive_habit_version();

comment on function public.home_workspace(date,text,integer) is
  'Returns an owner-scoped Home snapshot with archive counts, current stages, and recent Wiki Items.';
comment on function public.search_library_entities(text,integer,integer,text[]) is
  'Searches the owner scoped Person and Place entity directories.';
