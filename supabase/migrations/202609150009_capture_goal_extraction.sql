-- Goal extraction follows the shared Capture handoff contract while using
-- the existing specialized Goal writer for intent, state, organization, and links.

create function public.extract_capture_to_goal(
  p_capture_id uuid,
  p_capture_revision integer,
  p_title text,
  p_body text,
  p_horizon text,
  p_status text,
  p_target_date date,
  p_collection_names text[],
  p_tag_names text[],
  p_related_entry_ids uuid[]
)
returns table (
  capture_id uuid,
  capture_revision integer,
  goal_entry_id uuid,
  goal_revision integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_goal record;
  existing_goal record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_goal_extraction';
  end if;

  select
    target.id as entry_id,
    target.revision,
    capture.revision as source_revision
  into existing_goal
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'goal'
    and target.item_subtype = 'goal'
    and target.deleted_at is null
  join public.goals as goal
    on goal.entry_id = target.id
    and goal.owner_id = target.owner_id
  where capture.id = p_capture_id
    and capture.owner_id = extraction_owner_id
    and capture.item_kind = 'capture'
    and capture.item_subtype = 'source_capture'
    and capture.inbox_status = 'organized'
    and capture.deleted_at is null
  order by provenance.created_at
  limit 1;

  if found then
    return query select
      p_capture_id,
      existing_goal.source_revision,
      existing_goal.entry_id,
      existing_goal.revision;
    return;
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
    and entry.item_kind = 'capture'
    and entry.item_subtype = 'quick_capture'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null
  for update;

  if not found then
    return;
  end if;

  select *
  into saved_goal
  from public.save_goal_entry(
    p_title,
    p_body,
    p_horizon,
    p_status,
    p_target_date,
    p_collection_names,
    p_tag_names,
    p_related_entry_ids,
    null,
    null
  );

  if saved_goal.entry_id is null then
    return;
  end if;

  update public.entries as entry
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where entry.id = source.id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
  returning entry.revision into next_capture_revision;

  if next_capture_revision is null then
    raise exception using errcode = '40001', message = 'capture_changed';
  end if;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, saved_goal.entry_id, extraction_owner_id, 'derived'),
    (saved_goal.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_goal.entry_id,
    saved_goal.revision;
end;
$$;

revoke all on function public.extract_capture_to_goal(uuid,integer,text,text,text,text,date,text[],text[],uuid[]) from public, anon;
grant execute on function public.extract_capture_to_goal(uuid,integer,text,text,text,text,date,text[],text[],uuid[]) to authenticated;

comment on function public.extract_capture_to_goal(uuid,integer,text,text,text,text,date,text[],text[],uuid[]) is
  'Atomically creates a Goal from a raw Capture, organizes the preserved Capture, and records bidirectional provenance.';
