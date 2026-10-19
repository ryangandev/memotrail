-- The functions that write import jobs, items, and imported Entries.
--
-- Every function acts only for the signed-in owner (auth.uid()) and only on that owner's job.
-- An imported Entry is created by import_entry through save_entry, so it is an ordinary Entry:
-- it has the same validation, tags, Location, and later changes as an Entry captured by hand.
-- This migration only adds objects, so a Web deployed before it keeps working.

-- Ends a job: no more writes, staged text removed. Not callable by clients.
create function public.end_import_job(p_job_id uuid, p_status text, p_error_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.import_jobs
  set status = p_status,
      error_code = coalesce(p_error_code, error_code),
      lease_token = null,
      lease_expires_at = null,
      finished_at = coalesce(finished_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where id = p_job_id;
  -- A job that ends with items to retry keeps the text of those items until it is over for good.
  update public.import_items as item
  set payload = case
        when p_status = 'completed_with_issues' and item.status = 'failed' and item.retryable
          then item.payload
        else null
      end,
      media = case when p_status in ('failed', 'cancelled', 'expired') then null else item.media end,
      updated_at = clock_timestamp()
  where item.job_id = p_job_id
    and (item.payload is not null or p_status in ('failed', 'cancelled', 'expired'));
end;
$$;
revoke all on function public.end_import_job(uuid, text, text) from public, anon, authenticated;

create function public.create_import_job(p_source text, p_file_name text, p_file_bytes bigint)
returns table(job_id uuid, staging_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  new_job_id uuid := gen_random_uuid();
  stale record;
begin
  if job_owner_id is null then
    return;
  end if;
  if p_source is null
    or p_source not in ('apple_journal', 'apple_notes', 'notion', 'day_one', 'markdown')
    or p_file_bytes is null or p_file_bytes < 1
    or length(coalesce(p_file_name, '')) > 255
  then
    raise exception using errcode = '22023', message = 'invalid_import_job';
  end if;

  -- A job nobody touched for a day is over, so it cannot block the next import.
  for stale in
    select job.id from public.import_jobs as job
    where job.owner_id = job_owner_id
      and job.status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota')
      and job.updated_at < clock_timestamp() - interval '24 hours'
  loop
    perform public.end_import_job(stale.id, 'expired', 'expired');
  end loop;

  if exists (
    select 1 from public.import_jobs as job
    where job.owner_id = job_owner_id
      and job.status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota')
  ) then
    raise exception using errcode = '23505', message = 'import_job_active';
  end if;

  insert into public.import_jobs (id, owner_id, source, file_name, file_bytes, staging_path)
  values (
    new_job_id, job_owner_id, p_source, nullif(btrim(p_file_name), ''), p_file_bytes,
    job_owner_id::text || '/' || new_job_id::text || '/source.zip'
  );
  return query select new_job_id, job_owner_id::text || '/' || new_job_id::text || '/source.zip';
end;
$$;
revoke all on function public.create_import_job(text, text, bigint) from public, anon;
grant execute on function public.create_import_job(text, text, bigint) to authenticated;

-- Moves a job between steps and records what the step learned. Returns the new status, or null
-- when the job is not in one of the expected statuses.
create function public.update_import_job(
  p_job_id uuid,
  p_from text[],
  p_status text,
  p_patch jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  current_job public.import_jobs;
  patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  if job_owner_id is null then
    return null;
  end if;
  if p_status is null or p_status not in ('scanning', 'preview_ready', 'running', 'paused_quota', 'failed')
    or jsonb_typeof(patch) <> 'object'
    or octet_length(patch::text) > 500000
  then
    raise exception using errcode = '22023', message = 'invalid_import_job';
  end if;

  select * into current_job
  from public.import_jobs as job
  where job.id = p_job_id and job.owner_id = job_owner_id
  for update;
  if not found or p_from is null or not (current_job.status = any (p_from)) then
    return null;
  end if;

  if p_status = 'failed' then
    perform public.end_import_job(p_job_id, 'failed', nullif(patch->>'error_code', ''));
    return 'failed';
  end if;
  if p_status = 'scanning' then
    -- A scan that was cut short starts again from nothing.
    delete from public.import_items where job_id = p_job_id;
  end if;

  update public.import_jobs
  set status = p_status,
      file_bytes = case when patch ? 'file_bytes' then (patch->>'file_bytes')::bigint else file_bytes end,
      error_code = case when patch ? 'error_code' then nullif(patch->>'error_code', '') else error_code end,
      totals = case when jsonb_typeof(patch->'totals') = 'object' then patch->'totals' else totals end,
      lease_token = null,
      lease_expires_at = null,
      updated_at = clock_timestamp()
  where id = p_job_id;
  return p_status;
end;
$$;
revoke all on function public.update_import_job(uuid, text[], text, jsonb) from public, anon;
grant execute on function public.update_import_job(uuid, text[], text, jsonb) to authenticated;

-- Stores a batch of scanned items. A key that is already in the job is kept as it was.
-- Returns how many were new.
create function public.add_import_items(p_job_id uuid, p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  inserted_count integer;
begin
  if job_owner_id is null then
    return 0;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 500 then
    raise exception using errcode = '22023', message = 'invalid_import_items';
  end if;
  if not exists (
    select 1 from public.import_jobs as job
    where job.id = p_job_id and job.owner_id = job_owner_id and job.status = 'scanning'
  ) then
    raise exception using errcode = '22023', message = 'import_job_not_scanning';
  end if;

  with parsed as (
    select
      item->>'source_key' as source_key,
      coalesce(array(select jsonb_array_elements_text(coalesce(item->'folder_path', '[]'::jsonb))), '{}'::text[]) as folder_path,
      item->>'content_hash' as content_hash,
      coalesce(item->>'status', 'pending') as status,
      nullif(item->>'reason', '') as reason,
      nullif(item->'payload', 'null'::jsonb) as payload,
      nullif(item->'media', 'null'::jsonb) as media
    from jsonb_array_elements(p_items) as item
  ), inserted as (
    insert into public.import_items (
      job_id, owner_id, source_key, folder_path, content_hash, status, reason, payload, media
    )
    select p_job_id, job_owner_id, source_key, folder_path, content_hash, status, reason, payload, media
    from parsed
    where status in ('pending', 'skipped')
      and (payload is null or octet_length(payload::text) <= 400000)
    on conflict (job_id, source_key) do nothing
    returning 1
  )
  select count(*) into inserted_count from inserted;
  return inserted_count;
end;
$$;
revoke all on function public.add_import_items(uuid, jsonb) from public, anon;
grant execute on function public.add_import_items(uuid, jsonb) to authenticated;

-- How many scanned items are already in MemoTrail from an earlier import of the same file.
create function public.import_job_overlap(p_job_id uuid)
returns table(unchanged bigint, changed bigint, in_trash bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*) filter (where origin.content_hash = item.content_hash),
    count(*) filter (where origin.content_hash <> item.content_hash),
    count(*) filter (where entry.deleted_at is not null)
  from public.import_jobs as job
  join public.import_items as item on item.job_id = job.id and item.status = 'pending'
  join public.entry_import_origins as origin
    on origin.owner_id = job.owner_id and origin.source = job.source and origin.source_key = item.source_key
  join public.entries as entry on entry.id = origin.entry_id and entry.owner_id = origin.owner_id
  where job.id = p_job_id and job.owner_id = auth.uid();
$$;
revoke all on function public.import_job_overlap(uuid) from public, anon;
grant execute on function public.import_job_overlap(uuid) to authenticated;

-- A few scanned items as they will be imported, for the preview. The parsed text is only readable
-- through this function, so the preview can show it and nothing else can.
create function public.import_job_sample(p_job_id uuid, p_limit integer, p_warnings_only boolean)
returns table(source_key text, folder_path text[], payload jsonb, media jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select item.source_key, item.folder_path, item.payload, item.media
  from public.import_jobs as job
  join public.import_items as item on item.job_id = job.id
  where job.id = p_job_id and job.owner_id = auth.uid()
    and item.status = 'pending' and item.selected and item.payload is not null
    and (
      not coalesce(p_warnings_only, false)
      or jsonb_array_length(coalesce(item.payload->'warnings', '[]'::jsonb)) > 0
    )
  order by md5(item.source_key)
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;
revoke all on function public.import_job_sample(uuid, integer, boolean) from public, anon;
grant execute on function public.import_job_sample(uuid, integer, boolean) to authenticated;

-- Starts the import. Folders the person unchecked are removed here, and never imported or kept.
create function public.confirm_import_job(p_job_id uuid, p_options jsonb, p_excluded_folders jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  folder text[];
  remaining bigint;
begin
  if job_owner_id is null then
    return 0;
  end if;
  if jsonb_typeof(coalesce(p_options, '{}'::jsonb)) <> 'object'
    or jsonb_typeof(coalesce(p_excluded_folders, '[]'::jsonb)) <> 'array'
  then
    raise exception using errcode = '22023', message = 'invalid_import_options';
  end if;
  perform 1 from public.import_jobs as job
  where job.id = p_job_id and job.owner_id = job_owner_id and job.status = 'preview_ready'
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'import_job_not_ready';
  end if;

  for folder in
    select array(select jsonb_array_elements_text(entry.value))
    from jsonb_array_elements(coalesce(p_excluded_folders, '[]'::jsonb)) as entry
  loop
    if cardinality(folder) >= 1 then
      delete from public.import_items as item
      where item.job_id = p_job_id
        and item.status = 'pending'
        and item.folder_path[1:cardinality(folder)] = folder;
    end if;
  end loop;

  update public.import_jobs
  set status = 'running',
      options = coalesce(p_options, '{}'::jsonb),
      updated_at = clock_timestamp()
  where id = p_job_id;
  select count(*) into remaining
  from public.import_items as item
  where item.job_id = p_job_id and item.status = 'pending' and item.selected;
  return remaining;
end;
$$;
revoke all on function public.confirm_import_job(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.confirm_import_job(uuid, jsonb, jsonb) to authenticated;

-- A run takes the lease before it works and renews it with every batch it claims. Returns the
-- token, or null when another run holds the lease or the job is not running.
create function public.acquire_import_lease(p_job_id uuid, p_lease_seconds integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  new_token uuid := gen_random_uuid();
  taken uuid;
begin
  if job_owner_id is null or p_lease_seconds is null or p_lease_seconds not between 5 and 900 then
    return null;
  end if;
  update public.import_jobs
  set status = 'running',
      lease_token = new_token,
      lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
      updated_at = clock_timestamp()
  where id = p_job_id
    and owner_id = job_owner_id
    and status in ('running', 'paused_quota')
    and (lease_expires_at is null or lease_expires_at < clock_timestamp())
  returning lease_token into taken;
  return taken;
end;
$$;
revoke all on function public.acquire_import_lease(uuid, integer) from public, anon;
grant execute on function public.acquire_import_lease(uuid, integer) to authenticated;

create function public.release_import_lease(p_job_id uuid, p_lease_token uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.import_jobs
  set lease_token = null, lease_expires_at = null, updated_at = clock_timestamp()
  where id = p_job_id and owner_id = auth.uid() and lease_token = p_lease_token;
$$;
revoke all on function public.release_import_lease(uuid, uuid) from public, anon;
grant execute on function public.release_import_lease(uuid, uuid) to authenticated;

-- The next items to work on. An item that keeps ending a run without finishing is failed rather
-- than retried forever.
create function public.claim_import_items(
  p_job_id uuid,
  p_lease_token uuid,
  p_limit integer,
  p_lease_seconds integer
)
returns table(
  item_id uuid,
  source_key text,
  folder_path text[],
  item_status text,
  item_content_hash text,
  payload jsonb,
  media jsonb,
  item_entry_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
begin
  if job_owner_id is null then
    return;
  end if;
  update public.import_jobs
  set lease_expires_at = clock_timestamp() + make_interval(secs => least(greatest(coalesce(p_lease_seconds, 60), 5), 900)),
      updated_at = clock_timestamp()
  where id = p_job_id and owner_id = job_owner_id and lease_token = p_lease_token and status = 'running';
  if not found then
    raise exception using errcode = '55P03', message = 'import_lease_lost';
  end if;

  update public.import_items as item
  set status = 'failed', reason = 'attempts_exceeded', retryable = false, payload = null,
      updated_at = clock_timestamp()
  where item.job_id = p_job_id and item.selected
    and item.status in ('pending', 'photos_pending') and item.attempts >= 5;

  return query
  with picked as (
    select item.id
    from public.import_items as item
    where item.job_id = p_job_id and item.selected and item.status in ('pending', 'photos_pending')
    order by item.id
    limit least(greatest(coalesce(p_limit, 10), 1), 50)
    for update skip locked
  ), counted as (
    update public.import_items as item
    set attempts = item.attempts + 1
    from picked
    where item.id = picked.id
    returning item.id, item.source_key, item.folder_path, item.status, item.content_hash,
      item.payload, item.media, item.entry_id
  )
  select counted.id, counted.source_key, counted.folder_path, counted.status, counted.content_hash,
    counted.payload, counted.media, counted.entry_id
  from counted
  order by counted.id;
end;
$$;
revoke all on function public.claim_import_items(uuid, uuid, integer, integer) from public, anon;
grant execute on function public.claim_import_items(uuid, uuid, integer, integer) to authenticated;

-- Creates the Entry of one item through save_entry and records where it came from, in one
-- transaction. Outcomes: created; unchanged (an earlier import already holds this item, even if
-- the person moved it to Trash); changed_in_source (it was imported before and the source differs
-- now, so nothing is overwritten); deleted_earlier (the person deleted it forever).
create function public.import_entry(
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
      p_tag_names, p_primary_location, null, null
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

-- Records how an item ended: the Entry's photos, or a reason it did not import.
create function public.finish_import_item(
  p_item_id uuid,
  p_status text,
  p_reason text,
  p_retryable boolean,
  p_media jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return;
  end if;
  if p_status is null or p_status not in ('imported', 'skipped', 'failed', 'partial')
    or (p_reason is not null and p_reason !~ '^[a-z][a-z0-9_]{0,63}$')
    or (p_media is not null and jsonb_typeof(p_media) <> 'object')
  then
    raise exception using errcode = '22023', message = 'invalid_import_item';
  end if;
  update public.import_items as item
  set status = p_status,
      reason = p_reason,
      retryable = coalesce(p_retryable, false),
      media = coalesce(p_media, item.media),
      -- An item that failed before it had an Entry keeps its text for a retry.
      payload = case when p_status = 'failed' and coalesce(p_retryable, false) and item.entry_id is null
        then item.payload else null end,
      updated_at = clock_timestamp()
  where item.id = p_item_id and item.owner_id = auth.uid();
end;
$$;
revoke all on function public.finish_import_item(uuid, text, text, boolean, jsonb) from public, anon;
grant execute on function public.finish_import_item(uuid, text, text, boolean, jsonb) to authenticated;

-- Counts what the job did and finishes it when nothing is left to do. Returns the job's status.
create function public.finish_import_job(p_job_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  job public.import_jobs;
  open_items bigint;
  issue_items bigint;
  result jsonb;
  final_status text;
begin
  if job_owner_id is null then
    return null;
  end if;
  select * into job from public.import_jobs as found_job
  where found_job.id = p_job_id and found_job.owner_id = job_owner_id
  for update;
  if not found then
    return null;
  end if;
  if job.status not in ('running', 'paused_quota') then
    return job.status;
  end if;
  select count(*) into open_items
  from public.import_items as item
  where item.job_id = p_job_id and item.selected and item.status in ('pending', 'photos_pending');
  if open_items > 0 then
    return job.status;
  end if;

  select count(*) into issue_items
  from public.import_items as item
  where item.job_id = p_job_id and item.status in ('failed', 'partial');
  final_status := case when issue_items > 0 then 'completed_with_issues' else 'completed' end;

  perform public.end_import_job(p_job_id, final_status, null);
  return final_status;
end;
$$;
revoke all on function public.finish_import_job(uuid) from public, anon;
grant execute on function public.finish_import_job(uuid) to authenticated;

-- Puts retryable items back in line and reopens a finished job.
create function public.retry_import_items(p_job_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  retried bigint;
begin
  if job_owner_id is null then
    return 0;
  end if;
  perform 1 from public.import_jobs as job
  where job.id = p_job_id and job.owner_id = job_owner_id and job.status = 'completed_with_issues'
    and job.staging_path is not null
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'import_job_not_retryable';
  end if;
  if exists (
    select 1 from public.import_jobs as job
    where job.owner_id = job_owner_id and job.id <> p_job_id
      and job.status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota')
  ) then
    raise exception using errcode = '23505', message = 'import_job_active';
  end if;

  update public.import_items as item
  set status = case when item.entry_id is null then 'pending' else 'photos_pending' end,
      attempts = 0,
      updated_at = clock_timestamp()
  where item.job_id = p_job_id and item.status in ('failed', 'partial') and item.retryable
    and (item.entry_id is not null or item.payload is not null);
  get diagnostics retried = row_count;
  if retried = 0 then
    return 0;
  end if;
  update public.import_jobs
  set status = 'running', finished_at = null, lease_token = null, lease_expires_at = null,
      updated_at = clock_timestamp()
  where id = p_job_id;
  return retried;
end;
$$;
revoke all on function public.retry_import_items(uuid) from public, anon;
grant execute on function public.retry_import_items(uuid) to authenticated;

-- Stops an import that has not finished. Entries already imported stay.
create function public.cancel_import_job(p_job_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  perform 1 from public.import_jobs as job
  where job.id = p_job_id and job.owner_id = auth.uid()
    and job.status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota', 'completed_with_issues')
  for update;
  if not found then
    return false;
  end if;
  perform public.end_import_job(p_job_id, 'cancelled', null);
  return true;
end;
$$;
revoke all on function public.cancel_import_job(uuid) from public, anon;
grant execute on function public.cancel_import_job(uuid) to authenticated;

-- Moves the Entries of one import to Trash, where they can be restored. An Entry the person
-- edited since the import is left alone.
create function public.trash_import_job(p_job_id uuid)
returns table(trashed integer, edited integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  job public.import_jobs;
  trashed_count integer;
  edited_count integer;
begin
  if job_owner_id is null then
    return;
  end if;
  select * into job from public.import_jobs as found_job
  where found_job.id = p_job_id and found_job.owner_id = job_owner_id;
  if not found or job.status not in ('completed', 'completed_with_issues', 'cancelled') then
    raise exception using errcode = '22023', message = 'import_job_not_undoable';
  end if;
  if job.created_at < clock_timestamp() - interval '30 days' then
    raise exception using errcode = '22023', message = 'import_undo_expired';
  end if;

  with trashed_entries as (
    update public.entries as entry
    set deleted_at = clock_timestamp()
    from public.entry_import_origins as origin
    where origin.job_id = p_job_id
      and origin.owner_id = job_owner_id
      and entry.id = origin.entry_id
      and entry.owner_id = job_owner_id
      and entry.deleted_at is null
      and entry.revision = origin.imported_revision
    returning entry.id
  )
  select count(*) into trashed_count from trashed_entries;
  select count(*) into edited_count
  from public.entry_import_origins as origin
  join public.entries as entry on entry.id = origin.entry_id and entry.owner_id = origin.owner_id
  where origin.job_id = p_job_id
    and origin.owner_id = job_owner_id
    and entry.deleted_at is null
    and entry.revision <> origin.imported_revision;
  return query select trashed_count, edited_count;
end;
$$;
revoke all on function public.trash_import_job(uuid) from public, anon;
grant execute on function public.trash_import_job(uuid) to authenticated;

-- What the job has done so far, for the progress bar and the result.
create function public.import_job_progress(p_job_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', job.status,
    'items', coalesce((
      select jsonb_object_agg(counted.status, counted.total)
      from (
        select item.status, count(*) as total
        from public.import_items as item
        where item.job_id = job.id and item.selected
        group by item.status
      ) as counted
    ), '{}'::jsonb),
    'reasons', coalesce((
      select jsonb_object_agg(counted.reason, counted.total)
      from (
        select item.reason, count(*) as total
        from public.import_items as item
        where item.job_id = job.id and item.selected and item.reason is not null
        group by item.reason
      ) as counted
    ), '{}'::jsonb),
    'photos', (
      select jsonb_build_object(
        'imported', count(*) filter (where photo->>'status' = 'done'),
        'failed', count(*) filter (where photo->>'status' = 'failed'),
        'skipped', count(*) filter (where photo->>'status' = 'skipped')
      )
      from public.import_items as item
      cross join lateral jsonb_array_elements(coalesce(item.media->'photos', '[]'::jsonb)) as photo
      where item.job_id = job.id and item.selected
    ),
    'finished_at', job.finished_at
  )
  from public.import_jobs as job
  where job.id = p_job_id and job.owner_id = auth.uid();
$$;
revoke all on function public.import_job_progress(uuid) from public, anon;
grant execute on function public.import_job_progress(uuid) to authenticated;
