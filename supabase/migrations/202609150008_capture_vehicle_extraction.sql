-- Vehicle extraction follows the shared Capture handoff contract while using
-- the existing specialized Vehicle writer for facts, dates, and organization.

create function public.extract_capture_to_vehicle(
  p_capture_id uuid,
  p_capture_revision integer,
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_make text,
  p_model text,
  p_model_year integer,
  p_color text,
  p_collection_names text[],
  p_tag_names text[]
)
returns table (
  capture_id uuid,
  capture_revision integer,
  vehicle_entry_id uuid,
  vehicle_revision integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_vehicle record;
  existing_vehicle record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_vehicle_extraction';
  end if;

  select
    target.id as entry_id,
    target.revision,
    capture.revision as source_revision
  into existing_vehicle
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'entity'
    and target.item_subtype = 'vehicle'
    and target.deleted_at is null
  join public.vehicles as vehicle
    on vehicle.entry_id = target.id
    and vehicle.owner_id = target.owner_id
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
      existing_vehicle.source_revision,
      existing_vehicle.entry_id,
      existing_vehicle.revision;
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
  into saved_vehicle
  from public.save_vehicle_entry_with_occurrence(
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_make,
    p_model,
    p_model_year,
    p_color,
    p_collection_names,
    p_tag_names,
    null,
    null
  );

  if saved_vehicle.entry_id is null then
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
    (source.id, saved_vehicle.entry_id, extraction_owner_id, 'derived'),
    (saved_vehicle.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_vehicle.entry_id,
    saved_vehicle.revision;
end;
$$;

revoke all on function public.extract_capture_to_vehicle(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,text,text,integer,text,text[],text[]) from public, anon;
grant execute on function public.extract_capture_to_vehicle(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,text,text,integer,text,text[],text[]) to authenticated;

comment on function public.extract_capture_to_vehicle(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,text,text,integer,text,text[],text[]) is
  'Atomically creates a Vehicle Entity from a raw Capture, organizes the preserved Capture, and records bidirectional provenance.';
