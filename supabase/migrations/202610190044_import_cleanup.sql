-- Removing the staged ZIP once an import is over. The database cannot delete Storage objects, so
-- this follows the same retryable pattern as media purges: a function lists the staged paths that
-- should go, the Web server removes them through the Storage API, and then confirms.
--
-- A staged ZIP is removable when its job finished, was cancelled, failed, or expired, except that a
-- job that finished with items worth retrying keeps its ZIP for a day. Opening the import page
-- runs this, because no scheduled cleanup is active yet.

create function public.expire_import_jobs()
returns table(job_id uuid, staging_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_owner_id uuid := auth.uid();
  stale record;
begin
  if job_owner_id is null then
    return;
  end if;

  for stale in
    select job.id from public.import_jobs as job
    where job.owner_id = job_owner_id
      and job.status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota')
      and job.updated_at < clock_timestamp() - interval '24 hours'
  loop
    perform public.end_import_job(stale.id, 'expired', 'expired');
  end loop;

  return query
  select job.id, job.staging_path
  from public.import_jobs as job
  where job.owner_id = job_owner_id
    and job.staging_path is not null
    and (
      job.status in ('completed', 'cancelled', 'failed', 'expired')
      or (
        job.status = 'completed_with_issues'
        and (
          job.finished_at < clock_timestamp() - interval '24 hours'
          or not exists (
            select 1 from public.import_items as item
            where item.job_id = job.id and item.status in ('failed', 'partial') and item.retryable
          )
        )
      )
    )
  order by job.created_at;
end;
$$;
revoke all on function public.expire_import_jobs() from public, anon;
grant execute on function public.expire_import_jobs() to authenticated;

-- Confirms that the staged ZIPs of these jobs were removed.
create function public.complete_import_staging_cleanup(p_job_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleaned integer;
begin
  if auth.uid() is null then
    return 0;
  end if;
  with removable as (
    select expired.job_id from public.expire_import_jobs() as expired
    where expired.job_id = any (coalesce(p_job_ids, '{}'::uuid[]))
  ), cleared as (
    update public.import_jobs as job
    set staging_path = null, updated_at = clock_timestamp()
    from removable
    where job.id = removable.job_id and job.owner_id = auth.uid()
    returning job.id
  ), emptied as (
    -- The retry window is over, so the text kept for it goes, and the photo list keeps only how
    -- each photo ended, without file names.
    update public.import_items as item
    set payload = null,
        media = case
          when item.media is null then null
          else jsonb_build_object('photos', coalesce((
            select jsonb_agg(jsonb_build_object('status', photo->>'status'))
            from jsonb_array_elements(coalesce(item.media->'photos', '[]'::jsonb)) as photo
          ), '[]'::jsonb))
        end,
        updated_at = clock_timestamp()
    from cleared
    where item.job_id = cleared.id and (item.payload is not null or item.media is not null)
    returning item.id
  )
  select count(*) into cleaned from cleared;
  return cleaned;
end;
$$;
revoke all on function public.complete_import_staging_cleanup(uuid[]) from public, anon;
grant execute on function public.complete_import_staging_cleanup(uuid[]) to authenticated;
