-- Owner-scoped semantic search index. Vectors never leave the database through the
-- client API; only security definer functions filtered by auth.uid() read or write them.
-- The vector dimension (1024) must match apps/web/src/lib/search/semantic-model.json.

-- Settings switch; on by default. Its trigger lives in 202610190022.
alter table public.profiles
  add column semantic_search_enabled boolean not null default true;

create function public.entry_search_source_hash(p_title text, p_body text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select extensions.digest(
    convert_to(coalesce(btrim(p_title), '') || chr(10) || coalesce(p_body, ''), 'UTF8'),
    'sha256'
  );
$$;
revoke all on function public.entry_search_source_hash(text, text) from public, anon, authenticated;

create table public.entry_search_index_state (
  entry_id uuid primary key,
  owner_id uuid not null,
  source_hash bytea not null,
  status text not null default 'pending'
    check (status in ('pending', 'indexed', 'empty', 'failed', 'disabled')),
  indexed_hash bytea,
  indexed_model text,
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default timezone('utc', now()),
  leased_until timestamptz,
  last_error text check (last_error is null or last_error ~ '^[a-z_]{1,64}$'),
  updated_at timestamptz not null default timezone('utc', now()),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);
create index entry_search_index_state_due_idx
  on public.entry_search_index_state (owner_id, next_attempt_at)
  where status <> 'disabled';

create table public.entry_search_chunks (
  entry_id uuid not null,
  owner_id uuid not null,
  chunk_index smallint not null check (chunk_index between 0 and 199),
  source_hash bytea not null,
  model text not null,
  -- Unicode code point offsets into entries.body; a title-only Entry has one 0..0 chunk.
  char_start integer not null check (char_start >= 0),
  char_end integer not null check (char_end >= char_start),
  embedding extensions.halfvec(1024) not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entry_id, chunk_index),
  foreign key (entry_id, owner_id) references public.entries(id, owner_id) on delete cascade
);
-- Exact per-owner scan on purpose: one owner has thousands of chunks, and a global
-- approximate index would post-filter by owner and lose recall.
create index entry_search_chunks_owner_model_idx on public.entry_search_chunks (owner_id, model);

alter table public.entry_search_index_state enable row level security;
alter table public.entry_search_chunks enable row level security;
revoke all on table public.entry_search_index_state, public.entry_search_chunks
  from public, anon, authenticated, service_role;

-- Any write that changes an Entry's title or plaintext body makes it due again,
-- whichever client or RPC made the write.
create function public.queue_entry_search_index()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_hash bytea := public.entry_search_source_hash(new.title, new.body);
begin
  if tg_op = 'UPDATE'
    and old.title is not distinct from new.title
    and old.body is not distinct from new.body
  then
    return null;
  end if;

  insert into public.entry_search_index_state as state (entry_id, owner_id, source_hash, status)
  values (
    new.id,
    new.owner_id,
    next_hash,
    case when exists (
      select 1 from public.profiles
      where user_id = new.owner_id and not semantic_search_enabled
    ) then 'disabled' else 'pending' end
  )
  on conflict (entry_id) do update
  set source_hash = excluded.source_hash,
      status = case when state.status = 'disabled' then 'disabled' else 'pending' end,
      attempts = 0,
      last_error = null,
      leased_until = null,
      next_attempt_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where state.source_hash is distinct from excluded.source_hash;
  return null;
end;
$$;
revoke all on function public.queue_entry_search_index() from public, anon, authenticated;

create trigger entries_queue_search_index
after insert or update of title, body on public.entries
for each row execute function public.queue_entry_search_index();

-- Backfill: every existing Entry, including Trash, so Restore needs no re-indexing.
insert into public.entry_search_index_state (entry_id, owner_id, source_hash)
select id, owner_id, public.entry_search_source_hash(title, body)
from public.entries
on conflict (entry_id) do nothing;
