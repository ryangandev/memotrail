-- Import jobs: a person brings an export from another app (Apple Journal, Apple Notes, Notion,
-- Day One, or a folder of Markdown files) into MemoTrail. Web uploads the export ZIP to a private
-- staging bucket, the server reads it, and a job records what was found and how far the import
-- got, so a reload, a timeout, or a closed tab loses nothing.
--
-- This migration holds the job and item tables. Clients can only read them; every write goes
-- through the functions in later migrations, which check the owner and the job's state.
--
-- A job is active until it reaches a final status, and a person has at most one active job.

create table public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  source text not null
    check (source in ('apple_journal', 'apple_notes', 'notion', 'day_one', 'markdown')),
  status text not null default 'uploading'
    check (status in (
      'uploading', 'scanning', 'preview_ready', 'running', 'paused_quota',
      'completed', 'completed_with_issues', 'failed', 'cancelled', 'expired'
    )),
  file_name text check (file_name is null or length(file_name) <= 255),
  file_bytes bigint check (file_bytes is null or file_bytes >= 0),
  -- The staged ZIP in the import-staging bucket. Cleared once the object has been removed.
  staging_path text,
  options jsonb not null default '{}'::jsonb,
  totals jsonb not null default '{}'::jsonb,
  -- A run holds the lease while it processes items, so two tabs cannot import at once.
  lease_token uuid,
  lease_expires_at timestamptz,
  error_code text check (error_code is null or error_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz,
  unique (id, owner_id)
);

comment on table public.import_jobs is
  'One import of an export ZIP from another app. Written only through the import functions.';

create unique index import_jobs_one_active_idx
  on public.import_jobs (owner_id)
  where status in ('uploading', 'scanning', 'preview_ready', 'running', 'paused_quota');
create index import_jobs_owner_recent_idx
  on public.import_jobs (owner_id, created_at desc);

create table public.import_items (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  owner_id uuid not null,
  -- Stable identity of the item in its source, so a second import of the same file is a no-op.
  source_key text not null check (length(source_key) between 1 and 600),
  folder_path text[] not null default '{}',
  content_hash text check (content_hash is null or content_hash ~ '^[a-f0-9]{64}$'),
  status text not null default 'pending'
    check (status in (
      'pending', 'photos_pending', 'imported', 'unchanged', 'skipped', 'failed', 'partial'
    )),
  -- A stable code, such as empty, deleted_earlier, changed_in_source, or photo_upload_failed.
  reason text check (reason is null or reason ~ '^[a-z][a-z0-9_]{0,63}$'),
  retryable boolean not null default false,
  selected boolean not null default true,
  -- The parsed Entry between scan and import. Removed as soon as the Entry exists or the job ends,
  -- so a second copy of the person's writing does not linger.
  payload jsonb,
  -- Photos of the item and how each one went. Holds no text.
  media jsonb,
  entry_id uuid,
  attempts integer not null default 0 check (attempts >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (job_id, owner_id) references public.import_jobs (id, owner_id) on delete cascade,
  unique (job_id, source_key)
);

comment on table public.import_items is
  'One item found in an import ZIP. The payload is removed once the item is imported or the job ends.';

create index import_items_claim_idx
  on public.import_items (job_id, status, id)
  where selected;

alter table public.import_jobs enable row level security;
alter table public.import_items enable row level security;

revoke all on table public.import_jobs, public.import_items from public, anon, authenticated;
grant select on table public.import_jobs to authenticated;
-- The payload and media columns stay behind the functions; the page reads progress and results.
grant select (id, job_id, owner_id, source_key, folder_path, status, reason, retryable, selected,
  entry_id, attempts, updated_at)
  on table public.import_items to authenticated;

create policy "Owners read their import jobs"
on public.import_jobs for select
to authenticated
using (owner_id = (select auth.uid()));

create policy "Owners read their import items"
on public.import_items for select
to authenticated
using (owner_id = (select auth.uid()));
