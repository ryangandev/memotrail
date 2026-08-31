create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists vector with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text,
  body text not null default '',
  entry_type text not null default 'standard',
  inbox_status text not null default 'unreviewed'
    check (inbox_status in ('unreviewed', 'organized')),
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text not null default 'exact'
    check (date_precision in ('exact', 'day', 'month', 'year', 'approximate', 'age', 'range', 'unknown')),
  occurred_label text,
  occurred_timezone text,
  source_language text,
  revision integer not null default 1 check (revision > 0),
  client_id text,
  embedding extensions.vector,
  embedding_model text,
  embedding_updated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,
  search_document tsvector generated always as (
    to_tsvector(
      'simple',
      coalesce(title, '') || ' ' || coalesce(body, '') || ' ' || coalesce(occurred_label, '')
    )
  ) stored,
  unique (id, owner_id),
  check (occurred_end is null or occurred_start is null or occurred_end >= occurred_start)
);

create index entries_owner_updated_idx on public.entries (owner_id, updated_at desc);
create index entries_owner_occurred_idx on public.entries (owner_id, occurred_start desc nulls last);
create index entries_owner_inbox_idx on public.entries (owner_id, inbox_status, created_at desc)
  where deleted_at is null;
create index entries_owner_trash_idx on public.entries (owner_id, deleted_at desc)
  where deleted_at is not null;
create index entries_search_document_idx on public.entries using gin (search_document);
create index entries_title_trigram_idx on public.entries using gin (
  lower(title) extensions.gin_trgm_ops
);

create table public.entry_versions (
  id bigint generated always as identity primary key,
  entry_id uuid not null,
  owner_id uuid not null,
  version integer not null,
  operation text not null check (operation in ('update', 'delete')),
  changed_by uuid,
  snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  unique (entry_id, version)
);

create index entry_versions_owner_entry_idx
  on public.entry_versions (owner_id, entry_id, version desc);

create or replace function public.archive_entry_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.entry_versions (
    entry_id,
    owner_id,
    version,
    operation,
    changed_by,
    snapshot
  )
  values (
    old.id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    to_jsonb(old)
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    new.updated_at = timezone('utc', now());
    return new;
  end if;

  return old;
end;
$$;

revoke all on function public.archive_entry_version() from public;

create trigger archive_entry_before_change
before update or delete on public.entries
for each row execute function public.archive_entry_version();

create table public.collections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  system_key text,
  color text,
  sort_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create unique index collections_owner_name_idx
  on public.collections (owner_id, lower(name))
  where archived_at is null;

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create unique index tags_owner_name_idx on public.tags (owner_id, lower(name));

create table public.entry_collections (
  entry_id uuid not null,
  collection_id uuid not null,
  owner_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, collection_id),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (collection_id, owner_id) references public.collections(id, owner_id) on delete cascade
);

create table public.entry_tags (
  entry_id uuid not null,
  tag_id uuid not null,
  owner_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, tag_id),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (tag_id, owner_id) references public.tags(id, owner_id) on delete cascade
);

create table public.places (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  address text,
  city text,
  region text,
  country text,
  latitude numeric(9, 6) check (latitude between -90 and 90),
  longitude numeric(9, 6) check (longitude between -180 and 180),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create index places_owner_name_idx on public.places (owner_id, lower(name));

create table public.people (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  relationship_label text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create index people_owner_name_idx on public.people (owner_id, lower(name));

create table public.entry_places (
  entry_id uuid not null,
  place_id uuid not null,
  owner_id uuid not null,
  relationship text not null default 'related',
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, place_id, relationship),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (place_id, owner_id) references public.places(id, owner_id) on delete cascade
);

create table public.entry_people (
  entry_id uuid not null,
  person_id uuid not null,
  owner_id uuid not null,
  relationship text not null default 'related',
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, person_id, relationship),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (person_id, owner_id) references public.people(id, owner_id) on delete cascade
);

create table public.timeline_tracks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  system_key text,
  sort_order integer not null default 0,
  is_hidden boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create unique index timeline_tracks_owner_name_idx
  on public.timeline_tracks (owner_id, lower(name));

create table public.timeline_items (
  entry_id uuid not null,
  track_id uuid not null,
  owner_id uuid not null,
  timeline_kind text not null check (timeline_kind in ('stage', 'event')),
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, track_id),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (track_id, owner_id) references public.timeline_tracks(id, owner_id) on delete cascade
);

create table public.homes (
  entry_id uuid primary key,
  owner_id uuid not null,
  place_id uuid,
  move_in_reason text,
  move_out_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (place_id, owner_id) references public.places(id, owner_id) on delete restrict
);

create table public.vehicles (
  entry_id uuid primary key,
  owner_id uuid not null,
  make text,
  model text,
  model_year integer check (model_year between 1886 and 2200),
  color text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);

create table public.goals (
  entry_id uuid primary key,
  owner_id uuid not null,
  horizon text not null default 'someday'
    check (horizon in ('short_term', 'long_term', 'someday')),
  status text not null default 'considering'
    check (status in ('considering', 'active', 'paused', 'achieved', 'let_go')),
  target_date date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);

create table public.habits (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  tracking_mode text not null default 'check'
    check (tracking_mode in ('check', 'measure')),
  measurement_unit text,
  target_value numeric,
  schedule jsonb not null default '{"kind":"daily"}'::jsonb,
  starts_on date not null default current_date,
  ends_on date,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id),
  check (ends_on is null or ends_on >= starts_on),
  check (tracking_mode = 'measure' or target_value is null)
);

create table public.habit_occurrences (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid not null,
  owner_id uuid not null,
  local_date date not null,
  status text not null
    check (status in ('completed', 'missed', 'skipped', 'not_scheduled')),
  measured_value numeric,
  note text,
  entry_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  foreign key (habit_id, owner_id) references public.habits(id, owner_id) on delete cascade,
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete set null (entry_id),
  unique (habit_id, local_date)
);

create index habit_occurrences_owner_date_idx
  on public.habit_occurrences (owner_id, local_date desc);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null,
  parent_attachment_id uuid,
  variant text not null default 'original'
    check (variant in ('original', 'display', 'thumbnail')),
  bucket_id text not null default 'entry-media',
  object_path text not null,
  original_filename text,
  mime_type text not null,
  byte_size bigint check (byte_size is null or byte_size >= 0),
  pixel_width integer check (pixel_width is null or pixel_width > 0),
  pixel_height integer check (pixel_height is null or pixel_height > 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id),
  unique (bucket_id, object_path),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (parent_attachment_id, owner_id) references public.attachments(id, owner_id) on delete cascade
);

create index attachments_owner_entry_idx on public.attachments (owner_id, entry_id);

create table public.entry_links (
  source_entry_id uuid not null,
  target_entry_id uuid not null,
  owner_id uuid not null,
  relationship text not null default 'related',
  created_at timestamptz not null default timezone('utc', now()),
  primary key (source_entry_id, target_entry_id, relationship),
  foreign key (source_entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  foreign key (target_entry_id, owner_id) references public.entries(id, owner_id) on delete cascade,
  check (source_entry_id <> target_entry_id)
);

create table public.ai_suggestions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null,
  provider text,
  model text,
  schema_version integer not null default 1,
  suggestions jsonb not null,
  confidence numeric(5, 4) check (confidence between 0 and 1),
  status text not null default 'proposed'
    check (status in ('proposed', 'applied', 'dismissed', 'failed')),
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);

create index ai_suggestions_owner_entry_idx
  on public.ai_suggestions (owner_id, entry_id, created_at desc);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger collections_set_updated_at
before update on public.collections
for each row execute function public.set_updated_at();

create trigger tags_set_updated_at
before update on public.tags
for each row execute function public.set_updated_at();

create trigger places_set_updated_at
before update on public.places
for each row execute function public.set_updated_at();

create trigger people_set_updated_at
before update on public.people
for each row execute function public.set_updated_at();

create trigger timeline_tracks_set_updated_at
before update on public.timeline_tracks
for each row execute function public.set_updated_at();

create trigger homes_set_updated_at
before update on public.homes
for each row execute function public.set_updated_at();

create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

create trigger goals_set_updated_at
before update on public.goals
for each row execute function public.set_updated_at();

create trigger habits_set_updated_at
before update on public.habits
for each row execute function public.set_updated_at();

create trigger habit_occurrences_set_updated_at
before update on public.habit_occurrences
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.entry_versions enable row level security;

create policy "Users can view their own profile"
on public.profiles for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can update their own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can view their own entry history"
on public.entry_versions for select
to authenticated
using ((select auth.uid()) = owner_id);

do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'entries',
    'collections',
    'tags',
    'entry_collections',
    'entry_tags',
    'places',
    'people',
    'entry_places',
    'entry_people',
    'timeline_tracks',
    'timeline_items',
    'homes',
    'vehicles',
    'goals',
    'habits',
    'habit_occurrences',
    'attachments',
    'entry_links',
    'ai_suggestions'
  ]
  loop
    execute format('alter table public.%I enable row level security', relation_name);
    execute format(
      'create policy "Users can manage their own rows" on public.%I for all to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id)',
      relation_name
    );
  end loop;
end;
$$;

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.entry_versions to authenticated;
grant select, insert, update, delete on
  public.entries,
  public.collections,
  public.tags,
  public.entry_collections,
  public.entry_tags,
  public.places,
  public.people,
  public.entry_places,
  public.entry_people,
  public.timeline_tracks,
  public.timeline_items,
  public.homes,
  public.vehicles,
  public.goals,
  public.habits,
  public.habit_occurrences,
  public.attachments,
  public.entry_links,
  public.ai_suggestions
to authenticated;

revoke all on
  public.profiles,
  public.entries,
  public.entry_versions,
  public.collections,
  public.tags,
  public.entry_collections,
  public.entry_tags,
  public.places,
  public.people,
  public.entry_places,
  public.entry_people,
  public.timeline_tracks,
  public.timeline_items,
  public.homes,
  public.vehicles,
  public.goals,
  public.habits,
  public.habit_occurrences,
  public.attachments,
  public.entry_links,
  public.ai_suggestions
from anon;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'));

  insert into public.timeline_tracks (owner_id, name, system_key, sort_order)
  values
    (new.id, 'Places', 'places', 10),
    (new.id, 'Education', 'education', 20),
    (new.id, 'Career', 'career', 30),
    (new.id, 'Homes', 'homes', 40),
    (new.id, 'Vehicles', 'vehicles', 50),
    (new.id, 'Relationships', 'relationships', 60),
    (new.id, 'Health', 'health', 70),
    (new.id, 'First Times', 'first_times', 80),
    (new.id, 'Other Events', 'other_events', 90);

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'entry-media',
  'entry-media',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can view the private entry media bucket"
on storage.buckets for select
to authenticated
using (id = 'entry-media');

create policy "Users can read their own entry media"
on storage.objects for select
to authenticated
using (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can upload their own entry media"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can update their own entry media"
on storage.objects for update
to authenticated
using (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can delete their own entry media"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

comment on table public.entries is
  'The canonical searchable content model for MemoTrail, including specialized entry types.';

comment on column public.entries.deleted_at is
  'A non-null value places the entry in Trash without permanently deleting it.';

comment on column public.entries.embedding is
  'Dimension is intentionally unconstrained until an embedding provider is selected.';
