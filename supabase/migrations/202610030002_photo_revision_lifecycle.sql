-- Photo membership changes create their own Entry revision (202609130003).
-- Saves adopt those photo-only revisions through entry_writing_revision, so an
-- editor that added or removed a photo can still save its writing.
-- Move to Trash and Goal achievement leave photo membership untouched, so they
-- follow the same rule instead of reporting a false conflict for the editor's own
-- photo action: a contiguous run of photo-only revisions after the expected one is
-- adopted, while any writing, organization, lifecycle, or history change still
-- conflicts.
-- Each writer locks the Entry before reconciling, so a concurrent photo change is
-- either already adopted or waits for this write.
-- Signatures, security, and grants are unchanged, so deployed clients are fixed
-- without an update.

create or replace function public.trash_goal_entry(p_entry_id uuid, p_expected_revision integer)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
  reconciled_revision integer;
begin
  if goal_owner_id is null or p_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  perform 1 from public.entries
  where entries.id = p_entry_id
    and entries.owner_id = goal_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_entry_id, p_expected_revision);

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = reconciled_revision
    and entries.item_kind = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

create or replace function public.trash_home_entry(p_entry_id uuid, p_expected_revision integer)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  home_owner_id uuid := auth.uid();
  reconciled_revision integer;
begin
  if home_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  perform 1 from public.entries
  where entries.id = p_entry_id
    and entries.owner_id = home_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_entry_id, p_expected_revision);

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = home_owner_id
    and entries.revision = reconciled_revision
    and entries.item_kind = 'entity' and entries.item_subtype = 'home'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.homes
      where homes.entry_id = entries.id
        and homes.owner_id = home_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

create or replace function public.trash_vehicle_entry(p_entry_id uuid, p_expected_revision integer)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  vehicle_owner_id uuid := auth.uid();
  reconciled_revision integer;
begin
  if vehicle_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  perform 1 from public.entries
  where entries.id = p_entry_id
    and entries.owner_id = vehicle_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_entry_id, p_expected_revision);

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = vehicle_owner_id
    and entries.revision = reconciled_revision
    and entries.item_kind = 'entity' and entries.item_subtype = 'vehicle'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.vehicles
      where vehicles.entry_id = entries.id
        and vehicles.owner_id = vehicle_owner_id
    )
  returning entries.id, entries.revision;
end;
$$;

create or replace function public.trash_first_time_entry(p_entry_id uuid, p_expected_revision integer)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  first_time_owner_id uuid := auth.uid();
  reconciled_revision integer;
begin
  if first_time_owner_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  perform 1 from public.entries
  where entries.id = p_entry_id
    and entries.owner_id = first_time_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_entry_id, p_expected_revision);

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = first_time_owner_id
    and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
    and entries.revision = reconciled_revision
    and entries.deleted_at is null
  returning entries.id, entries.revision;
end;
$$;

create or replace function public.trash_timeline_entry(p_entry_id uuid, p_expected_revision integer)
returns table(entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  timeline_owner_id uuid := auth.uid();
  reconciled_revision integer;
  trashed_entry_id uuid;
  trashed_revision integer;
begin
  if timeline_owner_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  perform 1 from public.entries
  where entries.id = p_entry_id
    and entries.owner_id = timeline_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_entry_id, p_expected_revision);

  update public.entries as entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = timeline_owner_id
    and entries.revision = reconciled_revision
    and entries.deleted_at is null
    and exists (
      select 1
      from public.timeline_items as items
      where items.entry_id = entries.id
        and items.owner_id = timeline_owner_id
    )
  returning entries.id, entries.revision into trashed_entry_id, trashed_revision;

  if trashed_entry_id is null then
    return;
  end if;

  return query select trashed_entry_id, trashed_revision;
end;
$$;

create or replace function public.achieve_goal_with_occurrence(
  p_goal_entry_id uuid,
  p_expected_revision integer,
  p_occurred_start timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_occurred_end timestamptz
)
returns table(goal_entry_id uuid, goal_revision integer, first_time_entry_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
  achieved_goal_title text;
  achieved_goal_revision integer;
  new_first_time_id uuid;
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  reconciled_revision integer;
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;

  perform 1 from public.entries
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_goal_entry_id, p_expected_revision);

  update public.entries
  set inbox_status = 'organized'
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = reconciled_revision
    and entries.item_kind = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
        and goals.status <> 'achieved'
    )
    and exists (
      select 1
      from public.entry_collections
      join public.collections
        on collections.id = entry_collections.collection_id
        and collections.owner_id = entry_collections.owner_id
      where entry_collections.entry_id = entries.id
        and entry_collections.owner_id = goal_owner_id
        and collections.archived_at is null
        and (collections.system_key = 'bucket_list' or lower(btrim(collections.name)) = 'bucket list')
    )
  returning entries.title, entries.revision
  into achieved_goal_title, achieved_goal_revision;

  if achieved_goal_title is null then
    return;
  end if;

  update public.goals
  set status = 'achieved'
  where goals.entry_id = p_goal_entry_id
    and goals.owner_id = goal_owner_id;

  select entry_id into new_first_time_id from public.save_first_time_with_occurrence(
    achieved_goal_title, '', p_occurred_start, p_date_precision, normalized_label,
    case when p_occurred_start is null then null else normalized_timezone end,
    '{}', '{}', null, null, p_occurred_end
  );

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$$;
