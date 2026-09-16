-- Establish the Capture First Life Wiki vocabulary without breaking older
-- Web and iOS clients that still read and write entries.entry_type.

alter table public.entries
  add column item_kind text,
  add column item_subtype text;

create function public.legacy_item_kind(
  p_entry_type text,
  p_inbox_status text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_entry_type
    when 'first_time' then 'event'
    when 'life_stage' then 'event'
    when 'home' then 'entity'
    when 'vehicle' then 'entity'
    when 'goal' then 'goal'
    when 'standard' then case
      when p_inbox_status = 'unreviewed' then 'capture'
      else 'writing'
    end
    else 'writing'
  end;
$$;

create function public.legacy_item_subtype(
  p_entry_type text,
  p_inbox_status text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_entry_type
    when 'first_time' then 'first_time'
    when 'life_stage' then 'life_stage'
    when 'home' then 'home'
    when 'vehicle' then 'vehicle'
    when 'goal' then 'goal'
    when 'standard' then case
      when p_inbox_status = 'unreviewed' then 'quick_capture'
      else 'note'
    end
    else 'note'
  end;
$$;

create function public.default_item_subtype(p_item_kind text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_item_kind
    when 'capture' then 'quick_capture'
    when 'writing' then 'note'
    when 'event' then 'memory'
    when 'story' then 'chapter'
    when 'goal' then 'goal'
    else null
  end;
$$;

create function public.legacy_entry_type_for_item(
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

update public.entries
set
  item_kind = public.legacy_item_kind(entry_type, inbox_status),
  item_subtype = public.legacy_item_subtype(entry_type, inbox_status);

alter table public.entries
  alter column item_kind set not null,
  alter column item_subtype set not null,
  add constraint entries_item_kind_valid
    check (item_kind in ('capture', 'writing', 'entity', 'event', 'story', 'goal')),
  add constraint entries_item_subtype_valid
    check (item_subtype ~ '^[a-z][a-z0-9_]{0,63}$'),
  add constraint entries_legacy_information_model_valid
    check (
      case entry_type
        when 'first_time' then item_kind = 'event' and item_subtype = 'first_time'
        when 'life_stage' then item_kind = 'event'
        when 'home' then item_kind = 'entity' and item_subtype = 'home'
        when 'vehicle' then item_kind = 'entity' and item_subtype = 'vehicle'
        when 'goal' then item_kind = 'goal'
        when 'standard' then item_kind in ('capture', 'writing', 'story')
        else false
      end
    );

comment on column public.entries.item_kind is
  'Structural Life Wiki category. Capture is an Inbox workflow source; Writing, Entity, Event, Story, and Goal are durable item identities.';
comment on column public.entries.item_subtype is
  'Preset inside one item kind, such as journal, vehicle, first_time, or chapter. Subtype changes never imply an unrestricted cross-kind conversion.';
comment on column public.entries.entry_type is
  'Legacy compatibility discriminator. New clients use item_kind and item_subtype.';

create index entries_owner_kind_updated_idx
  on public.entries(owner_id, item_kind, item_subtype, updated_at desc, id)
  where deleted_at is null;

create function public.sync_entry_information_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  model_changed boolean;
  legacy_type_changed boolean;
begin
  if tg_op = 'INSERT' then
    if new.item_kind is null then
      new.item_kind := public.legacy_item_kind(new.entry_type, new.inbox_status);
    end if;
    if new.item_subtype is null then
      if new.item_kind = public.legacy_item_kind(new.entry_type, new.inbox_status) then
        new.item_subtype := public.legacy_item_subtype(new.entry_type, new.inbox_status);
      else
        new.item_subtype := public.default_item_subtype(new.item_kind);
      end if;
    end if;
    if new.item_kind is not null and new.item_subtype is not null then
      new.entry_type := public.legacy_entry_type_for_item(new.item_kind, new.item_subtype);
    end if;
    return new;
  end if;

  model_changed := new.item_kind is distinct from old.item_kind
    or new.item_subtype is distinct from old.item_subtype;
  legacy_type_changed := new.entry_type is distinct from old.entry_type;

  if legacy_type_changed and not model_changed then
    -- Older clients remain safe while Web and native migrate to the new model.
    new.item_kind := public.legacy_item_kind(new.entry_type, new.inbox_status);
    new.item_subtype := public.legacy_item_subtype(new.entry_type, new.inbox_status);
  elsif model_changed then
    if new.item_kind is null then
      raise exception using errcode = '22023', message = 'invalid_item_kind';
    end if;
    if new.item_subtype is null then
      new.item_subtype := public.default_item_subtype(new.item_kind);
    end if;
    new.entry_type := public.legacy_entry_type_for_item(new.item_kind, new.item_subtype);
  elsif old.item_kind = 'capture'
    and old.item_subtype = 'quick_capture'
    and old.inbox_status = 'unreviewed'
    and new.inbox_status = 'organized'
  then
    -- An older client's Done action finalizes a simple Capture as Writing.
    new.item_kind := 'writing';
    new.item_subtype := 'note';
    new.entry_type := 'standard';
  end if;

  return new;
end;
$$;

revoke all on function public.legacy_item_kind(text, text) from public, anon, authenticated;
revoke all on function public.legacy_item_subtype(text, text) from public, anon, authenticated;
revoke all on function public.default_item_subtype(text) from public, anon, authenticated;
revoke all on function public.legacy_entry_type_for_item(text, text) from public, anon;
grant execute on function public.legacy_entry_type_for_item(text, text) to authenticated;
revoke all on function public.sync_entry_information_model() from public, anon, authenticated;

create trigger a_sync_entry_information_model
before insert or update on public.entries
for each row execute function public.sync_entry_information_model();

-- A raw Capture may be finalized in place only because it does not yet have a
-- durable semantic identity. Entity and Goal creation continue through their
-- specialized atomic editors.
create function public.organize_capture(
  p_entry_id uuid,
  p_expected_revision integer,
  p_item_kind text,
  p_item_subtype text
)
returns table (
  entry_id uuid,
  revision integer,
  item_kind text,
  item_subtype text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  capture_owner_id uuid := auth.uid();
begin
  if capture_owner_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1
    or p_item_kind not in ('writing', 'event', 'story')
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
  then
    raise exception using errcode = '22023', message = 'invalid_capture_organization';
  end if;

  if p_item_kind = 'event' and p_item_subtype = 'first_time'
    and not exists (
      select 1
      from public.entries
      where id = p_entry_id
        and owner_id = capture_owner_id
        and nullif(btrim(title), '') is not null
    )
  then
    raise exception using errcode = '22023', message = 'first_time_requires_title';
  end if;

  return query
  update public.entries as entry
  set
    item_kind = p_item_kind,
    item_subtype = p_item_subtype,
    inbox_status = 'organized'
  where entry.id = p_entry_id
    and entry.owner_id = capture_owner_id
    and entry.revision = p_expected_revision
    and entry.item_kind = 'capture'
    and entry.deleted_at is null
  returning entry.id, entry.revision, entry.item_kind, entry.item_subtype;
end;
$$;

-- Extracting creates a distinct Wiki Item and keeps the original Capture as
-- provenance. It never mutates Writing, Entity, Event, Story, or Goal identity.
create function public.extract_capture_item(
  p_capture_id uuid,
  p_expected_revision integer,
  p_item_kind text,
  p_item_subtype text,
  p_title text,
  p_body text,
  p_occurred_start timestamptz default null,
  p_occurred_end timestamptz default null,
  p_date_precision text default 'unknown',
  p_occurred_label text default null,
  p_occurred_timezone text default 'UTC'
)
returns table (
  capture_id uuid,
  capture_revision integer,
  item_id uuid,
  item_revision integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  capture_owner_id uuid := auth.uid();
  source public.entries;
  created_item public.entries;
  source_revision integer;
begin
  if capture_owner_id is null then
    return;
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  p_occurred_label := nullif(btrim(p_occurred_label), '');

  if p_expected_revision is null or p_expected_revision < 1
    or p_item_kind not in ('writing', 'event', 'story')
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    or (p_title is null and p_body = '')
    or length(coalesce(p_title, '')) > 200
    or length(p_body) > 50000
    or p_date_precision not in ('exact','day','month','year','approximate','age','range','unknown')
    or p_occurred_timezone is null
    or length(p_occurred_timezone) > 100
    or not exists (
      select 1 from pg_catalog.pg_timezone_names
      where name = p_occurred_timezone
    )
    or length(coalesce(p_occurred_label, '')) > 200
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and p_occurred_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_capture_extraction';
  end if;

  if p_item_kind = 'event' and p_item_subtype = 'first_time' and p_title is null then
    raise exception using errcode = '22023', message = 'first_time_requires_title';
  end if;

  select *
  into source
  from public.entries
  where id = p_capture_id
    and owner_id = capture_owner_id
    and revision = p_expected_revision
    and item_kind = 'capture'
    and deleted_at is null
  for update;

  if not found then
    return;
  end if;

  insert into public.entries (
    owner_id,
    title,
    body,
    entry_type,
    item_kind,
    item_subtype,
    inbox_status,
    occurred_start,
    occurred_end,
    date_precision,
    occurred_label,
    occurred_timezone
  )
  values (
    capture_owner_id,
    p_title,
    p_body,
    public.legacy_entry_type_for_item(p_item_kind, p_item_subtype),
    p_item_kind,
    p_item_subtype,
    'organized',
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    btrim(p_occurred_timezone)
  )
  returning * into created_item;

  update public.entries
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where id = source.id
  returning revision into source_revision;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values (source.id, created_item.id, capture_owner_id, 'derived');

  return query
  select source.id, source_revision, created_item.id, created_item.revision;
end;
$$;

revoke all on function public.organize_capture(uuid, integer, text, text) from public, anon;
revoke all on function public.extract_capture_item(uuid, integer, text, text, text, text, timestamptz, timestamptz, text, text, text) from public, anon;
grant execute on function public.organize_capture(uuid, integer, text, text) to authenticated;
grant execute on function public.extract_capture_item(uuid, integer, text, text, text, text, timestamptz, timestamptz, text, text, text) to authenticated;

create index entry_links_owner_derived_idx
  on public.entry_links(owner_id, source_entry_id, target_entry_id)
  where relationship = 'derived';

-- Restore the semantic identity stored by new history snapshots. Older
-- snapshots derive it from the compatibility discriminator.
do $$
declare
  definition text;
  old_statement text := E'update public.entries set title=s->>''title'',body=coalesce(s->>''body'',''''),entry_type=s->>''entry_type'',inbox_status=s->>''inbox_status'',\n    occurred_start=(s->>''occurred_start'')::timestamptz,occurred_end=(s->>''occurred_end'')::timestamptz,';
  new_statement text := E'update public.entries set title=s->>''title'',body=coalesce(s->>''body'',''''),entry_type=s->>''entry_type'',\n    item_kind=coalesce(s->>''item_kind'',public.legacy_item_kind(s->>''entry_type'',s->>''inbox_status'')),\n    item_subtype=coalesce(s->>''item_subtype'',public.legacy_item_subtype(s->>''entry_type'',s->>''inbox_status'')),\n    inbox_status=s->>''inbox_status'',\n    occurred_start=(s->>''occurred_start'')::timestamptz,occurred_end=(s->>''occurred_end'')::timestamptz,';
begin
  select pg_get_functiondef(p.oid)
  into strict definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'restore_entry_version';

  if (length(definition) - length(replace(definition, old_statement, ''))) <> length(old_statement) then
    raise exception 'Expected exactly one Entry restore information-model replacement';
  end if;

  execute replace(definition, old_statement, new_statement);
end;
$$;
