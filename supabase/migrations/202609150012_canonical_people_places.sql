-- Person and Place are Entity presets, not parallel top-level record systems.
-- Give every specialized row a canonical entries identity while preserving its
-- stable registry id for existing links and deep links.

create or replace function public.legacy_entry_type_for_item(
  p_item_kind text,
  p_item_subtype text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  case p_item_kind
    when 'capture', 'writing', 'story' then
      return 'standard';
    when 'event' then
      return case when p_item_subtype = 'first_time' then 'first_time' else 'life_stage' end;
    when 'entity' then
      if p_item_subtype in ('home', 'vehicle') then
        return p_item_subtype;
      end if;
      if p_item_subtype in ('person', 'place') then
        return 'standard';
      end if;
      raise exception using
        errcode = '22023',
        message = 'unsupported_entity_subtype';
    when 'goal' then
      return 'goal';
    else
      raise exception using
        errcode = '22023',
        message = 'invalid_item_kind';
  end case;
end;
$$;

alter table public.entries
  drop constraint entries_legacy_information_model_valid,
  add constraint entries_legacy_information_model_valid
    check (
      case entry_type
        when 'first_time' then item_kind = 'event' and item_subtype = 'first_time'
        when 'life_stage' then item_kind = 'event'
        when 'home' then item_kind = 'entity' and item_subtype = 'home'
        when 'vehicle' then item_kind = 'entity' and item_subtype = 'vehicle'
        when 'goal' then item_kind = 'goal'
        when 'standard' then
          item_kind in ('capture', 'writing', 'story')
          or (item_kind = 'entity' and item_subtype in ('person', 'place'))
        else false
      end
    );

alter table public.people
  add column entry_id uuid default extensions.gen_random_uuid();

alter table public.places
  add column entry_id uuid default extensions.gen_random_uuid();

-- Resolve even astronomically unlikely UUID collisions before adding the
-- canonical foreign keys. The loop is deterministic and bounded in practice.
do $$
declare
  changed_rows integer;
  place_changed_rows integer;
begin
  loop
    update public.people as person
    set entry_id = extensions.gen_random_uuid()
    where exists (
      select 1 from public.entries as entry where entry.id = person.entry_id
    )
      or exists (
        select 1 from public.places as place where place.entry_id = person.entry_id
      )
      or exists (
        select 1
        from public.people as duplicate
        where duplicate.entry_id = person.entry_id
          and duplicate.id < person.id
      );
    get diagnostics changed_rows = row_count;

    update public.places as place
    set entry_id = extensions.gen_random_uuid()
    where exists (
      select 1 from public.entries as entry where entry.id = place.entry_id
    )
      or exists (
        select 1
        from public.places as duplicate
        where duplicate.entry_id = place.entry_id
          and duplicate.id < place.id
      );
    get diagnostics place_changed_rows = row_count;
    changed_rows := changed_rows + place_changed_rows;

    exit when changed_rows = 0;
  end loop;
end;
$$;

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  entry_type,
  item_kind,
  item_subtype,
  inbox_status,
  date_precision,
  occurred_timezone,
  revision,
  created_at,
  updated_at,
  deleted_at
)
select
  person.entry_id,
  person.owner_id,
  person.name,
  coalesce(person.notes, ''),
  'standard',
  'entity',
  'person',
  'organized',
  'unknown',
  'UTC',
  person.revision,
  person.created_at,
  person.updated_at,
  person.deleted_at
from public.people as person;

insert into public.entries (
  id,
  owner_id,
  title,
  body,
  entry_type,
  item_kind,
  item_subtype,
  inbox_status,
  date_precision,
  occurred_timezone,
  revision,
  created_at,
  updated_at,
  deleted_at
)
select
  place.entry_id,
  place.owner_id,
  place.name,
  coalesce(place.notes, ''),
  'standard',
  'entity',
  'place',
  'organized',
  'unknown',
  'UTC',
  place.revision,
  place.created_at,
  place.updated_at,
  place.deleted_at
from public.places as place;

alter table public.people
  alter column entry_id set not null,
  add constraint people_entry_identity_unique unique (entry_id, owner_id),
  add constraint people_entry_identity_fk
    foreign key (entry_id, owner_id)
    references public.entries(id, owner_id)
    on delete restrict;

alter table public.places
  alter column entry_id set not null,
  add constraint places_entry_identity_unique unique (entry_id, owner_id),
  add constraint places_entry_identity_fk
    foreign key (entry_id, owner_id)
    references public.entries(id, owner_id)
    on delete restrict;

create unique index people_entry_identity_idx on public.people(entry_id);
create unique index places_entry_identity_idx on public.places(entry_id);

create function public.sync_person_wiki_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_entry_id uuid;
begin
  if tg_op = 'INSERT' then
    insert into public.entries (
      id, owner_id, title, body, entry_type, item_kind, item_subtype,
      inbox_status, date_precision, occurred_timezone, revision, created_at,
      updated_at, deleted_at
    ) values (
      new.entry_id, new.owner_id, new.name, coalesce(new.notes, ''),
      'standard', 'entity', 'person', 'organized', 'unknown', 'UTC',
      new.revision, new.created_at, new.updated_at, new.deleted_at
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    update public.entries as entry
    set
      title = new.name,
      body = coalesce(new.notes, ''),
      entry_type = 'standard',
      item_kind = 'entity',
      item_subtype = 'person',
      inbox_status = 'organized',
      deleted_at = new.deleted_at
    where entry.id = old.entry_id
      and entry.owner_id = old.owner_id
      and entry.revision = old.revision
    returning entry.id into changed_entry_id;

    if changed_entry_id is null then
      raise exception using errcode = '40001', message = 'person_wiki_item_conflict';
    end if;
    return new;
  end if;

  delete from public.entries as entry
  where entry.id = old.entry_id
    and entry.owner_id = old.owner_id;
  return old;
end;
$$;

create function public.sync_place_wiki_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_entry_id uuid;
begin
  if tg_op = 'INSERT' then
    insert into public.entries (
      id, owner_id, title, body, entry_type, item_kind, item_subtype,
      inbox_status, date_precision, occurred_timezone, revision, created_at,
      updated_at, deleted_at
    ) values (
      new.entry_id, new.owner_id, new.name, coalesce(new.notes, ''),
      'standard', 'entity', 'place', 'organized', 'unknown', 'UTC',
      new.revision, new.created_at, new.updated_at, new.deleted_at
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    update public.entries as entry
    set
      title = new.name,
      body = coalesce(new.notes, ''),
      entry_type = 'standard',
      item_kind = 'entity',
      item_subtype = 'place',
      inbox_status = 'organized',
      deleted_at = new.deleted_at
    where entry.id = old.entry_id
      and entry.owner_id = old.owner_id
      and entry.revision = old.revision
    returning entry.id into changed_entry_id;

    if changed_entry_id is null then
      raise exception using errcode = '40001', message = 'place_wiki_item_conflict';
    end if;
    return new;
  end if;

  delete from public.entries as entry
  where entry.id = old.entry_id
    and entry.owner_id = old.owner_id;
  return old;
end;
$$;

revoke all on function public.sync_person_wiki_item() from public, anon, authenticated;
revoke all on function public.sync_place_wiki_item() from public, anon, authenticated;

create trigger people_sync_wiki_item
after insert or update or delete on public.people
for each row execute function public.sync_person_wiki_item();

create trigger places_sync_wiki_item
after insert or update or delete on public.places
for each row execute function public.sync_place_wiki_item();

drop function public.wiki_items_workspace(text,text[],text[],integer,integer);

create function public.wiki_items_workspace(
  p_query text default '',
  p_item_kinds text[] default array[]::text[],
  p_item_subtypes text[] default array[]::text[],
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  record_source text,
  item_id uuid,
  canonical_item_id uuid,
  item_kind text,
  item_subtype text,
  title text,
  excerpt text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  workspace_owner_id uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(p_query, '')));
begin
  if workspace_owner_id is null then
    return;
  end if;

  if p_query is null
    or length(p_query) > 200
    or p_item_kinds is null
    or cardinality(p_item_kinds) > 6
    or exists (
      select 1 from unnest(p_item_kinds) as kind
      where kind not in ('capture', 'writing', 'entity', 'event', 'story', 'goal')
    )
    or p_item_subtypes is null
    or cardinality(p_item_subtypes) > 50
    or exists (
      select 1 from unnest(p_item_subtypes) as subtype
      where subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    )
    or p_limit is null
    or p_limit < 1
    or p_limit > 100
    or p_offset is null
    or p_offset < 0
    or p_offset > 100000
  then
    raise exception using errcode = '22023', message = 'invalid_wiki_items_page';
  end if;

  return query
  with wiki_items as (
    select
      'entry'::text as record_source,
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      coalesce(
        nullif(btrim(entry.title), ''),
        nullif(left(btrim(entry.body), 120), ''),
        'Untitled item'
      ) as title,
      left(btrim(entry.body), 240) as excerpt,
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(' ', entry.title, entry.body, entry.item_kind, entry.item_subtype) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
      and not exists (
        select 1 from public.people as person
        where person.entry_id = entry.id and person.owner_id = entry.owner_id
      )
      and not exists (
        select 1 from public.places as place
        where place.entry_id = entry.id and place.owner_id = entry.owner_id
      )

    union all

    select
      'person'::text,
      person.id,
      person.entry_id,
      entry.item_kind,
      entry.item_subtype,
      person.name,
      left(btrim(concat_ws(' · ', person.relationship_label, person.notes)), 240),
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(' ', person.name, person.relationship_label, person.notes, 'entity', 'person')
    from public.people as person
    join public.entries as entry
      on entry.id = person.entry_id and entry.owner_id = person.owner_id
    where person.owner_id = workspace_owner_id
      and person.deleted_at is null
      and entry.deleted_at is null

    union all

    select
      'place'::text,
      place.id,
      place.entry_id,
      entry.item_kind,
      entry.item_subtype,
      place.name,
      left(btrim(concat_ws(' · ', place.address, place.city, place.region, place.country, place.notes)), 240),
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(' ', place.name, place.address, place.city, place.region, place.country, place.notes, 'entity', 'place')
    from public.places as place
    join public.entries as entry
      on entry.id = place.entry_id and entry.owner_id = place.owner_id
    where place.owner_id = workspace_owner_id
      and place.deleted_at is null
      and entry.deleted_at is null
  ),
  matches as (
    select *
    from wiki_items
    where (cardinality(p_item_kinds) = 0 or wiki_items.item_kind = any(p_item_kinds))
      and (cardinality(p_item_subtypes) = 0 or wiki_items.item_subtype = any(p_item_subtypes))
      and (normalized_query = '' or strpos(lower(wiki_items.searchable), normalized_query) > 0)
  ),
  counted as (
    select matches.*, count(*) over () as total_count
    from matches
  )
  select
    counted.record_source,
    counted.item_id,
    counted.canonical_item_id,
    counted.item_kind,
    counted.item_subtype,
    counted.title,
    counted.excerpt,
    counted.inbox_status,
    counted.occurred_start,
    counted.occurred_end,
    counted.updated_at,
    counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.record_source, counted.item_id
  limit p_limit
  offset p_offset;
end;
$$;

revoke all on function public.wiki_items_workspace(text,text[],text[],integer,integer)
  from public, anon;
grant execute on function public.wiki_items_workspace(text,text[],text[],integer,integer)
  to authenticated;

comment on function public.wiki_items_workspace(text,text[],text[],integer,integer) is
  'Returns one owner-scoped Life Wiki row per canonical item while retaining specialized registry ids for Person and Place routing.';

-- Search canonical Person and Place Entries by their specialized fields.
do $$
declare
  definition text;
  old_searchable text := E'        replace(entries.item_subtype, ''_'', '' ''),\n        entries.metadata::text,';
  new_searchable text := E'        replace(entries.item_subtype, ''_'', '' ''),\n        entries.metadata::text,\n        (\n          select concat_ws('' '', people.name, people.relationship_label, people.notes)\n          from public.people as people\n          where people.entry_id = entries.id\n            and people.owner_id = search_owner_id\n        ),\n        (\n          select concat_ws('' '', places.name, places.address, places.city, places.region,\n            places.country, places.latitude::text, places.longitude::text, places.notes)\n          from public.places as places\n          where places.entry_id = entries.id\n            and places.owner_id = search_owner_id\n        ),';
begin
  select pg_get_functiondef(procedure.oid)
  into strict definition
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'search_entries_ordered';

  if (length(definition) - length(replace(definition, old_searchable, '')))
    <> length(old_searchable)
  then
    raise exception 'Expected exactly one canonical Entity search replacement';
  end if;

  execute replace(definition, old_searchable, new_searchable);
end;
$$;

-- A trashed Person or Place is represented by its specialized record. Hide
-- the synchronized base Entry so Trash never shows duplicate rows.
do $$
declare
  definition text;
  old_scope text := E'    from public.entries\n    where entries.owner_id = auth.uid()\n      and entries.deleted_at is not null';
  new_scope text := E'    from public.entries\n    where entries.owner_id = auth.uid()\n      and entries.deleted_at is not null\n      and not exists (\n        select 1 from public.people as person\n        where person.entry_id = entries.id and person.owner_id = entries.owner_id\n      )\n      and not exists (\n        select 1 from public.places as place\n        where place.entry_id = entries.id and place.owner_id = entries.owner_id\n      )';
begin
  select pg_get_functiondef(procedure.oid)
  into strict definition
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'trash_workspace';

  if (length(definition) - length(replace(definition, old_scope, ''))) <> length(old_scope) then
    raise exception 'Expected exactly one canonical Entity Trash replacement';
  end if;

  execute replace(definition, old_scope, new_scope);
end;
$$;

comment on column public.people.entry_id is
  'Canonical Entity Wiki Item identity. people.id remains the specialized registry identity.';
comment on column public.places.entry_id is
  'Canonical Entity Wiki Item identity. places.id remains the specialized registry identity.';
