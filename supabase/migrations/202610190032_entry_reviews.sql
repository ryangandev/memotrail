-- A stored review is the last review a person asked for about one Chapter or one calendar
-- year. It is written by a third-party model from Entries the person wrote, kept apart from
-- those Entries, and never changes them. One row per Chapter and one per year, so "the review
-- of this Chapter" is unambiguous, and making a new review replaces the old one in one step.
--
-- Clients read their own rows and never write them; every write goes through the definer
-- functions of the next files, which check who is asking. entry_review_sources lists every
-- Entry a review read, cited or not, at the revision it read, so the review can say which
-- Entries are new or changed since, and Delete forever of any source can delete the review.

begin;

create table public.entry_reviews (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  scope text not null check (scope in ('chapter', 'year')),
  chapter_id uuid,
  review_year integer check (review_year between 1900 and 9999),
  -- The last finished review; null until the first generation succeeds.
  content jsonb,
  schema_version integer not null default 1 check (schema_version = 1),
  model text,
  disclosure_version text,
  language text check (language in ('en', 'zh')),
  -- True when the review was made while the Chapter was still going on ("review so far").
  ongoing boolean not null default false,
  period_start date,
  period_end date,                  -- exclusive; null for a Chapter that was still going on
  entries_in_period integer check (entries_in_period >= 0),
  entries_read integer check (entries_read >= 0),
  trimmed_entries integer not null default 0 check (trimmed_entries >= 0),
  generated_at timestamptz,
  -- The job that is making the next version. job_state holds the plan and the partial
  -- results of a segmented job, and is cleared when the job finishes. A failed job keeps it,
  -- so Try again can reuse finished parts.
  job_status text not null default 'idle' check (job_status in ('idle', 'generating', 'failed')),
  job_started_at timestamptz,
  job_progressed_at timestamptz,
  job_error text check (job_error is null or job_error ~ '^[a-z0-9_]{1,64}$'),
  job_state jsonb,
  generation_count_day integer not null default 0,
  generation_day date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id),
  foreign key (chapter_id, owner_id) references public.entries (id, owner_id) on delete cascade,
  check ((scope = 'chapter') = (chapter_id is not null)),
  check ((scope = 'year') = (review_year is not null)),
  check (content is null or (generated_at is not null and model is not null and language is not null)),
  check (job_status <> 'generating' or (job_started_at is not null and job_state is not null)),
  check (job_status <> 'idle' or job_state is null)
);

create unique index entry_reviews_owner_chapter
  on public.entry_reviews (owner_id, chapter_id) where scope = 'chapter';
create unique index entry_reviews_owner_year
  on public.entry_reviews (owner_id, review_year) where scope = 'year';

create index entry_reviews_job_entries
  on public.entry_reviews using gin ((job_state -> 'entryIds')) where job_state is not null;

create table public.entry_review_sources (
  review_id uuid not null,
  owner_id uuid not null,
  entry_id uuid not null,
  entry_revision integer not null check (entry_revision > 0),
  -- A hash of the title and writing as the review read them, null when the Entry had already
  -- changed by the time the review was saved. Trashing and restoring advance an Entry's
  -- revision without changing its writing, so "changed since" compares this, not the revision.
  content_hash text,
  primary key (review_id, entry_id),
  foreign key (review_id, owner_id) references public.entry_reviews (id, owner_id) on delete cascade,
  foreign key (entry_id, owner_id) references public.entries (id, owner_id) on delete cascade
);

create index entry_review_sources_entry on public.entry_review_sources (owner_id, entry_id);

create trigger entry_reviews_set_updated_at
before update on public.entry_reviews
for each row execute function public.set_updated_at();

alter table public.entry_reviews enable row level security;
alter table public.entry_review_sources enable row level security;

create policy entry_reviews_owner_read on public.entry_reviews
  for select to authenticated
  using (owner_id = (select auth.uid()));
create policy entry_review_sources_owner_read on public.entry_review_sources
  for select to authenticated
  using (owner_id = (select auth.uid()));

revoke all on public.entry_reviews, public.entry_review_sources from public, anon, authenticated;
grant select on public.entry_reviews, public.entry_review_sources to authenticated;
grant all on public.entry_reviews, public.entry_review_sources to service_role;

comment on table public.entry_reviews is
  'AI-written review of one Chapter or one year, kept apart from the Entries it read. Deleted with any Entry it read and when reviews are turned off.';

commit;
