-- Imported Entries are created through save_entry, which now takes the two marks (Chapter and
-- First Time) in place of a milestone. An imported Entry is an ordinary Entry, so import_entry
-- passes both marks as false. This replaces import_entry only to change that one call; nothing
-- else about importing changes.
--
-- This file is numbered after the import migrations it replaces a function from, so a fresh
-- database creates import_entry first and this file then updates it.

begin;

create or replace function public.import_entry(
  p_job_id uuid,
  p_item_id uuid,
  p_entry_id uuid,
  p_content_hash text,
  p_title text,
  p_body text,
  p_body_rich jsonb,
  p_occurred_start timestamp with time zone,
  p_occurred_end timestamp with time zone,
  p_occurred_timezone text,
  p_occurred_label text,
  p_date_precision text,
  p_tag_names text[],
  p_primary_location jsonb,
  p_source_created_at timestamp with time zone,
  p_source_modified_at timestamp with time zone
)
returns table(saved_entry_id uuid, outcome text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  import_owner_id uuid := auth.uid();
  job public.import_jobs;
  item public.import_items;
  origin public.entry_import_origins;
  origin_in_trash boolean;
  created_entry_id uuid;
  created_revision integer;
begin
  if import_owner_id is null then
    return;
  end if;
  if p_entry_id is null or p_content_hash is null or p_content_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_import_entry';
  end if;

  select * into job
  from public.import_jobs as found_job
  where found_job.id = p_job_id and found_job.owner_id = import_owner_id;
  if not found or job.status <> 'running' then
    raise exception using errcode = '55000', message = 'import_job_not_running';
  end if;
  select * into item
  from public.import_items as found_item
  where found_item.id = p_item_id and found_item.job_id = p_job_id and found_item.owner_id = import_owner_id
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'import_item_missing';
  end if;

  select * into origin
  from public.entry_import_origins as found_origin
  where found_origin.owner_id = import_owner_id
    and found_origin.source = job.source
    and found_origin.source_key = item.source_key;
  if found then
    select (found_entry.deleted_at is not null) into origin_in_trash
    from public.entries as found_entry
    where found_entry.id = origin.entry_id and found_entry.owner_id = import_owner_id;
    if origin.content_hash = p_content_hash then
      update public.import_items
      set status = 'unchanged',
          reason = case when origin_in_trash then 'in_trash' else null end,
          entry_id = origin.entry_id, content_hash = p_content_hash, payload = null,
          updated_at = clock_timestamp()
      where id = p_item_id;
      return query select origin.entry_id, 'unchanged'::text;
    else
      update public.import_items
      set status = 'skipped', reason = 'changed_in_source', retryable = false,
          entry_id = origin.entry_id, content_hash = p_content_hash, payload = null,
          updated_at = clock_timestamp()
      where id = p_item_id;
      return query select origin.entry_id, 'changed_in_source'::text;
    end if;
    return;
  end if;

  if exists (
    select 1 from public.entry_tombstones as tombstone
    where tombstone.owner_id = import_owner_id and tombstone.entry_id = p_entry_id
  ) then
    update public.import_items
    set status = 'skipped', reason = 'deleted_earlier', retryable = false, payload = null,
        content_hash = p_content_hash, updated_at = clock_timestamp()
    where id = p_item_id;
    return query select null::uuid, 'deleted_earlier'::text;
    return;
  end if;

  if nullif(btrim(p_title), '') is null and btrim(coalesce(p_body, '')) = '' then
    -- An Entry of photos only. A photo capture may have no words, but save_entry, the editor's
    -- save, refuses an Entry without a title or note, so this one is inserted the way a capture is.
    if coalesce(jsonb_array_length(item.media->'photos'), 0) = 0 then
      raise exception using errcode = '22023', message = 'empty_entry';
    end if;
    p_occurred_label := nullif(btrim(p_occurred_label), '');
    if p_date_precision is null or p_date_precision not in ('exact', 'day', 'month', 'year', 'range', 'unknown')
      or p_occurred_timezone is null or length(p_occurred_timezone) > 100
      or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_occurred_timezone)
      or length(coalesce(p_occurred_label, '')) > 200
      or (p_date_precision in ('exact', 'day', 'month', 'year', 'range') and p_occurred_start is null)
      or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
      or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
      or not public.valid_tag_names(p_tag_names)
    then
      raise exception using errcode = '22023', message = 'invalid_occurrence';
    end if;
    insert into public.entries (
      id, owner_id, title, body, metadata, item_kind, item_subtype,
      occurred_start, occurred_end, occurred_label, date_precision, occurred_timezone
    )
    values (
      p_entry_id, import_owner_id, null, '', '{}'::jsonb, 'entry', 'entry',
      p_occurred_start, p_occurred_end, p_occurred_label, p_date_precision, btrim(p_occurred_timezone)
    )
    on conflict on constraint entries_pkey do nothing
    returning entries.id, entries.revision into created_entry_id, created_revision;
    if created_entry_id is not null then
      perform public.replace_entry_tags(created_entry_id, p_tag_names);
      perform public.replace_primary_location(created_entry_id, p_primary_location);
    end if;
  else
    select saved.entry_id, saved.revision into created_entry_id, created_revision
    from public.save_entry(
      p_entry_id, null, p_title, p_body, p_body_rich,
      p_occurred_start, p_occurred_end, p_occurred_timezone, p_occurred_label, p_date_precision,
      p_tag_names, p_primary_location, null, false, false
    ) as saved;
  end if;
  if created_entry_id is null then
    -- The ID is taken by an Entry this import did not make.
    raise exception using errcode = '23505', message = 'import_entry_conflict';
  end if;

  insert into public.entry_import_origins (
    owner_id, entry_id, source, source_key, content_hash,
    source_created_at, source_modified_at, job_id, imported_revision
  )
  values (
    import_owner_id, created_entry_id, job.source, item.source_key, p_content_hash,
    p_source_created_at, p_source_modified_at, p_job_id, created_revision
  );

  update public.import_items
  set status = case
        when coalesce(jsonb_array_length(item.media->'photos'), 0) > 0 then 'photos_pending'
        else 'imported'
      end,
      entry_id = created_entry_id, content_hash = p_content_hash, payload = null,
      updated_at = clock_timestamp()
  where id = p_item_id;
  return query select created_entry_id, 'created'::text;
end;
$$;
revoke all on function public.import_entry(
  uuid, uuid, uuid, text, text, text, jsonb, timestamp with time zone, timestamp with time zone,
  text, text, text, text[], jsonb, timestamp with time zone, timestamp with time zone
) from public, anon;
grant execute on function public.import_entry(
  uuid, uuid, uuid, text, text, text, jsonb, timestamp with time zone, timestamp with time zone,
  text, text, text, text[], jsonb, timestamp with time zone, timestamp with time zone
) to authenticated;

commit;
