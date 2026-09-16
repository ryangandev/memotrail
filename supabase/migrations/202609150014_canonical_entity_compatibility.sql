-- Keep legacy filters and destructive workflows stable after People and Places
-- receive canonical Entity Wiki Item identities.

-- The legacy Standard filter predates semantic item Kinds. Preserve its old
-- meaning for older clients instead of leaking canonical Entity rows into it.
do $$
declare
  definition text;
  old_filter text := E'        or entries.entry_type = any(normalized_entry_types)\n        or entries.item_kind = any(normalized_entry_types)';
  new_filter text := E'        or (\n          entries.entry_type = any(normalized_entry_types)\n          and not (entries.entry_type = ''standard'' and entries.item_kind = ''entity'')\n        )\n        or entries.item_kind = any(normalized_entry_types)';
begin
  select pg_get_functiondef(procedure.oid)
  into strict definition
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'search_entries_ordered';

  if (length(definition) - length(replace(definition, old_filter, '')))
    <> length(old_filter)
  then
    raise exception 'Expected exactly one canonical Entity legacy filter replacement';
  end if;

  execute replace(definition, old_filter, new_filter);
end;
$$;

comment on function public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text) is
  'Owner-scoped Wiki Item search. p_entry_types accepts item Kind, subtype, or legacy entry_type values; legacy Standard excludes canonical Entities.';

-- Empty Trash snapshots the underlying tables directly. Apply the same
-- canonical identity de-duplication as trash_workspace so a Person or Place is
-- deleted once through its specialized record, whose trigger removes its Entry.
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
        select 1
        from public.people as person
        where person.id = entry.id
          and person.owner_id = entry.owner_id
      )
      and not exists (
        select 1
        from public.places as place
        where place.id = entry.id
          and place.owner_id = entry.owner_id
      )

    union all

    select 'attachment', attachment.id, attachment.deleted_at, null::integer
    from public.attachments as attachment
    join public.entries as entry
      on entry.id = attachment.entry_id
      and entry.owner_id = attachment.owner_id
    where attachment.owner_id = auth.uid()
      and attachment.deleted_at is not null
      and entry.deleted_at is null

    union all

    select 'habit', habit.id, habit.deleted_at, habit.revision
    from public.habits as habit
    where habit.owner_id = auth.uid()
      and habit.deleted_at is not null

    union all

    select 'place', place.id, place.deleted_at, place.revision
    from public.places as place
    where place.owner_id = auth.uid()
      and place.deleted_at is not null

    union all

    select 'person', person.id, person.deleted_at, person.revision
    from public.people as person
    where person.owner_id = auth.uid()
      and person.deleted_at is not null

    union all

    select 'collection', collection.id, collection.archived_at, collection.revision
    from public.collections as collection
    where collection.owner_id = auth.uid()
      and collection.archived_at is not null
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

revoke all on function public.prepare_empty_trash() from public, anon;
grant execute on function public.prepare_empty_trash() to authenticated;

comment on function public.prepare_empty_trash() is
  'Read-only exact owner-scoped manifest across all Trash pages. Canonical Person and Place Entries are represented once by their specialized records.';
