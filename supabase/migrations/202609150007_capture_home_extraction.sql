-- Dedicated Entity extraction keeps a raw Capture as provenance while the
-- specialized Home form creates the durable Life Wiki object atomically.

create function public.capture_extraction_source(p_capture_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', entry.id,
    'title', entry.title,
    'body', entry.body,
    'metadata', entry.metadata,
    'entry_type', entry.entry_type,
    'item_kind', entry.item_kind,
    'item_subtype', entry.item_subtype,
    'inbox_status', entry.inbox_status,
    'created_at', entry.created_at,
    'occurred_start', entry.occurred_start,
    'occurred_end', entry.occurred_end,
    'occurred_label', entry.occurred_label,
    'date_precision', entry.date_precision,
    'occurred_timezone', entry.occurred_timezone,
    'revision', entry.revision,
    'collection_names', coalesce(
      (
        select jsonb_agg(collection.name order by collection.name)
        from public.entry_collections as membership
        join public.collections as collection
          on collection.id = membership.collection_id
          and collection.owner_id = membership.owner_id
        where membership.entry_id = entry.id
          and membership.owner_id = auth.uid()
          and collection.archived_at is null
      ),
      '[]'::jsonb
    ),
    'tag_names', coalesce(
      (
        select jsonb_agg(tag.name order by tag.name)
        from public.entry_tags as membership
        join public.tags as tag
          on tag.id = membership.tag_id
          and tag.owner_id = membership.owner_id
        where membership.entry_id = entry.id
          and membership.owner_id = auth.uid()
      ),
      '[]'::jsonb
    )
  )
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = auth.uid()
    and entry.item_kind = 'capture'
    and entry.item_subtype = 'quick_capture'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null;
$$;

create function public.extract_capture_to_home(
  p_capture_id uuid,
  p_capture_revision integer,
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_place_id uuid,
  p_place_name text,
  p_address text,
  p_city text,
  p_region text,
  p_country text,
  p_latitude numeric,
  p_longitude numeric,
  p_place_notes text,
  p_move_in_reason text,
  p_move_out_reason text,
  p_collection_names text[],
  p_tag_names text[]
)
returns table (
  capture_id uuid,
  capture_revision integer,
  home_entry_id uuid,
  home_revision integer,
  place_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_home record;
  existing_home record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_home_extraction';
  end if;

  -- A response may be lost after the transaction commits. Return the existing
  -- derived Home on retry instead of ever creating a duplicate.
  select
    target.id as entry_id,
    target.revision,
    home.place_id,
    capture.revision as source_revision
  into existing_home
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'entity'
    and target.item_subtype = 'home'
    and target.deleted_at is null
  join public.homes as home
    on home.entry_id = target.id
    and home.owner_id = target.owner_id
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
      existing_home.source_revision,
      existing_home.entry_id,
      existing_home.revision,
      existing_home.place_id;
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
  into saved_home
  from public.save_home_entry_with_occurrence(
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_place_id,
    p_place_name,
    p_address,
    p_city,
    p_region,
    p_country,
    p_latitude,
    p_longitude,
    p_place_notes,
    p_move_in_reason,
    p_move_out_reason,
    p_collection_names,
    p_tag_names,
    null,
    null
  );

  if saved_home.entry_id is null then
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
    (source.id, saved_home.entry_id, extraction_owner_id, 'derived'),
    (saved_home.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_home.entry_id,
    saved_home.revision,
    saved_home.place_id;
end;
$$;

revoke all on function public.capture_extraction_source(uuid) from public, anon;
grant execute on function public.capture_extraction_source(uuid) to authenticated;

revoke all on function public.extract_capture_to_home(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[]) from public, anon;
grant execute on function public.extract_capture_to_home(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[]) to authenticated;

comment on function public.capture_extraction_source(uuid) is
  'Returns one owned, unreviewed raw Capture with organization for a dedicated extraction form.';

comment on function public.extract_capture_to_home(uuid,integer,text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,text,text,text,numeric,numeric,text,text,text,text[],text[]) is
  'Atomically creates a Home Entity from a raw Capture, organizes the preserved Capture, and records bidirectional provenance.';
