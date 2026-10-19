-- Where an imported Entry came from. One row per imported Entry holds the source, its stable key
-- in that source, a hash of what was imported, and the source's own times. A second import of the
-- same file finds the row and skips the Entry. The Entry itself is an ordinary Entry.

create table public.entry_import_origins (
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null,
  source text not null
    check (source in ('apple_journal', 'apple_notes', 'notion', 'day_one', 'markdown')),
  source_key text not null check (length(source_key) between 1 and 600),
  content_hash text not null check (content_hash ~ '^[a-f0-9]{64}$'),
  -- The source's own times. Entries keep created_at as the time they entered MemoTrail.
  source_created_at timestamptz,
  source_modified_at timestamptz,
  job_id uuid references public.import_jobs(id) on delete set null,
  imported_at timestamptz not null default clock_timestamp(),
  -- The Entry revision right after import. A later revision means the person edited it.
  imported_revision integer not null check (imported_revision >= 1),
  primary key (owner_id, source, source_key),
  unique (entry_id, owner_id),
  foreign key (entry_id, owner_id) references public.entries (id, owner_id) on delete cascade
);

comment on table public.entry_import_origins is
  'Provenance and idempotency record for imported Entries. Written only by import_entry.';

create index entry_import_origins_job_idx
  on public.entry_import_origins (job_id)
  where job_id is not null;

alter table public.entry_import_origins enable row level security;
revoke all on table public.entry_import_origins from public, anon, authenticated;
grant select on table public.entry_import_origins to authenticated;

create policy "Owners read their import origins"
on public.entry_import_origins for select
to authenticated
using (owner_id = (select auth.uid()));
