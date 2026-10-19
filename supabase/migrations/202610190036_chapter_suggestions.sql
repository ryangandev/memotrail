-- Chapter suggestions are opt-in and quiet. While the switch is on, about once a month a model
-- may notice that a stretch of recent writing deserves a name and propose it, with the
-- Entries it is based on. A suggestion becomes a Chapter only when the person adds it through
-- the ordinary Entry editor. Dismissing one deletes everything written about it and keeps only
-- its dates, so the same stretch never comes back. Nothing counts, badges, or nags.

begin;

create table public.chapter_suggestions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'dismissed')),
  -- Content exists only while pending, and the name alone after confirming. Dismissing keeps
  -- only the dates, so the same stretch is never proposed again and nothing written about it
  -- is kept.
  name text check (name is null or length(btrim(name)) between 1 and 80),
  rationale text check (rationale is null or length(rationale) <= 400),
  source_entry_ids uuid[] not null default '{}' check (cardinality(source_entry_ids) <= 60),
  start_date date not null,
  start_precision text not null check (start_precision in ('day', 'month')),
  end_date date,
  end_precision text check (end_precision in ('day', 'month')),
  window_start date not null,
  window_end date,                  -- exclusive; null while the stretch is still going on
  chapter_id uuid,
  model text,
  disclosure_version text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (chapter_id, owner_id) references public.entries (id, owner_id) on delete set null (chapter_id),
  check ((end_date is null) = (end_precision is null)),
  check (window_end is null or window_end > window_start),
  check (status <> 'pending' or (name is not null and rationale is not null and resolved_at is null)),
  check (status <> 'dismissed' or (name is null and rationale is null and cardinality(source_entry_ids) = 0))
);

create index chapter_suggestions_owner_status on public.chapter_suggestions (owner_id, status, created_at);
create index chapter_suggestions_sources
  on public.chapter_suggestions using gin (source_entry_ids) where status = 'pending';

-- Scheduling only: when the last run happened and whether one is running. Never read by clients.
create table public.chapter_suggestion_state (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  last_run_at timestamptz,
  last_entry_count integer not null default 0,
  leased_until timestamptz
);

alter table public.chapter_suggestions enable row level security;
alter table public.chapter_suggestion_state enable row level security;
create policy chapter_suggestions_owner_read on public.chapter_suggestions
  for select to authenticated
  using (owner_id = (select auth.uid()));
revoke all on public.chapter_suggestions, public.chapter_suggestion_state from public, anon, authenticated;
grant select on public.chapter_suggestions to authenticated;
grant all on public.chapter_suggestions, public.chapter_suggestion_state to service_role;

-- How much two stretches of days overlap: the overlap over the union, in days. A stretch
-- without an end reads as running through the day after p_today.
create function public.window_iou(p_left daterange, p_right daterange, p_today date)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  left_start date := lower(p_left);
  left_end date;
  right_start date := lower(p_right);
  right_end date;
  overlap integer;
  total integer;
begin
  if left_start is null or right_start is null or p_today is null then
    return 0;
  end if;
  left_end := greatest(coalesce(upper(p_left), p_today + 1), left_start + 1);
  right_end := greatest(coalesce(upper(p_right), p_today + 1), right_start + 1);
  overlap := greatest(0, least(left_end, right_end) - greatest(left_start, right_start));
  total := (left_end - left_start) + (right_end - right_start) - overlap;
  if total <= 0 then
    return 0;
  end if;
  return overlap::numeric / total::numeric;
end;
$$;

-- Whether a run is due, and if so takes a five-minute lease on it. Due means the switch is on
-- with a recorded disclosure, no run holds a lease, fewer than three suggestions wait, and
-- either no run has happened or thirty days and fifteen new Entries have passed.
create function public.claim_chapter_suggestion_run()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  prefs public.ai_preferences;
  state public.chapter_suggestion_state;
  entry_total integer;
  lease timestamptz := clock_timestamp() + interval '5 minutes';
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select * into prefs from public.ai_preferences where owner_id = owner;
  if prefs.owner_id is null or not prefs.chapter_suggestions_enabled or prefs.review_disclosure_version is null then
    return jsonb_build_object('due', false);
  end if;

  insert into public.chapter_suggestion_state (owner_id) values (owner) on conflict (owner_id) do nothing;
  select * into state from public.chapter_suggestion_state where owner_id = owner for update;

  if state.leased_until is not null and state.leased_until > clock_timestamp() then
    return jsonb_build_object('due', false);
  end if;
  if (select count(*) from public.chapter_suggestions where owner_id = owner and status = 'pending') >= 3 then
    return jsonb_build_object('due', false);
  end if;

  select count(*) into entry_total
  from public.entries
  where owner_id = owner and deleted_at is null and item_subtype = 'entry';

  if state.last_run_at is not null and (
    state.last_run_at >= now() - interval '30 days' or entry_total < state.last_entry_count + 15
  ) then
    return jsonb_build_object('due', false);
  end if;

  update public.chapter_suggestion_state set leased_until = lease where owner_id = owner;
  return jsonb_build_object('due', true, 'leaseUntil', lease);
end;
$$;

-- What the model may read for a run: recent Entries by title, tags, date, and the start of
-- the writing; the Chapters that exist; and the windows of every earlier suggestion.
create function public.chapter_suggestion_inputs(p_since date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
begin
  if reader_id is null then
    return null;
  end if;
  if p_since is null then
    raise exception using errcode = '22023', message = 'invalid_chapter_suggestion';
  end if;

  return jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(item.value order by item.window_start desc, item.id)
      from (
        select
          entry.id,
          lower(dated.days) as window_start,
          jsonb_build_object(
            'id', entry.id,
            'title', coalesce(btrim(entry.title), ''),
            'excerpt', left(btrim(entry.body), 500),
            'tags', coalesce((
              select jsonb_agg(tags.name order by lower(tags.name), tags.id)
              from public.entry_tags
              join public.tags on tags.id = entry_tags.tag_id and tags.owner_id = entry_tags.owner_id
              where entry_tags.entry_id = entry.id and entry_tags.owner_id = reader_id
            ), '[]'::jsonb),
            'occurredStart', entry.occurred_start,
            'occurredEnd', entry.occurred_end,
            'datePrecision', entry.date_precision,
            'occurredLabel', entry.occurred_label,
            'occurredTimezone', coalesce(entry.occurred_timezone, 'UTC'),
            'windowStart', lower(dated.days),
            'windowEnd', upper(dated.days)
          ) as value
        from public.entries as entry
        cross join lateral (
          select public.entry_date_window(entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone) as days
        ) as dated
        where entry.owner_id = reader_id
          and entry.deleted_at is null
          and entry.item_subtype = 'entry'
          and lower(dated.days) >= p_since
        order by lower(dated.days) desc, entry.id
        limit 600
      ) as item
    ), '[]'::jsonb),
    'chapters', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', chapter.id,
        'title', coalesce(btrim(chapter.title), ''),
        'occurredStart', chapter.occurred_start,
        'occurredEnd', chapter.occurred_end,
        'datePrecision', chapter.date_precision,
        'occurredLabel', chapter.occurred_label,
        'occurredTimezone', coalesce(chapter.occurred_timezone, 'UTC'),
        'windowStart', lower(dated.days),
        'windowEnd', upper(dated.days)
      ) order by lower(dated.days), chapter.id)
      from public.entries as chapter
      cross join lateral (
        select public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone) as days
      ) as dated
      where chapter.owner_id = reader_id
        and chapter.deleted_at is null
        and chapter.item_subtype = 'chapter'
        and dated.days is not null
    ), '[]'::jsonb),
    'suggestions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'status', suggestion.status,
        'windowStart', suggestion.window_start,
        'windowEnd', suggestion.window_end
      ) order by suggestion.created_at, suggestion.id)
      from public.chapter_suggestions as suggestion
      where suggestion.owner_id = reader_id
    ), '[]'::jsonb)
  );
end;
$$;

-- Saves what a run proposed, at most as many as there is room for, and records the run, so a
-- run that proposed nothing still waits thirty days. Returns null when the lease is not the
-- current one or suggestions were turned off meanwhile.
create function public.store_chapter_suggestions(
  p_lease_until timestamptz,
  p_suggestions jsonb,
  p_model text,
  p_disclosure_version text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  prefs public.ai_preferences;
  state public.chapter_suggestion_state;
  item jsonb;
  room integer;
  stored integer := 0;
  entry_total integer;
  new_window daterange;
  today date := (now() at time zone 'UTC')::date;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if jsonb_typeof(p_suggestions) is distinct from 'array'
    or jsonb_array_length(p_suggestions) > 3
    or p_model is null or not exists (select 1 from public.ai_model_price(p_model))
    or coalesce(p_disclosure_version, '') !~ '^\d{4}-\d{2}-\d{2}$'
  then
    raise exception using errcode = '22023', message = 'invalid_chapter_suggestion';
  end if;

  select * into prefs from public.ai_preferences where owner_id = owner;
  select * into state from public.chapter_suggestion_state where owner_id = owner for update;
  if prefs.owner_id is null or not prefs.chapter_suggestions_enabled
    or state.owner_id is null or state.leased_until is distinct from p_lease_until
  then
    return null;
  end if;

  room := 3 - (select count(*) from public.chapter_suggestions where owner_id = owner and status = 'pending');

  for item in select value from jsonb_array_elements(p_suggestions) loop
    exit when stored >= room;
    if length(btrim(coalesce(item ->> 'name', ''))) not between 1 and 80
      or length(coalesce(item ->> 'rationale', '')) not between 1 and 400
      or jsonb_typeof(item -> 'sourceEntryIds') is distinct from 'array'
      or jsonb_array_length(item -> 'sourceEntryIds') not between 1 and 60
      or coalesce(item ->> 'startPrecision', '') not in ('day', 'month')
      or (item ->> 'endDate' is null) <> (item ->> 'endPrecision' is null)
      or (item ->> 'endPrecision' is not null and item ->> 'endPrecision' not in ('day', 'month'))
    then
      raise exception using errcode = '22023', message = 'invalid_chapter_suggestion';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(item -> 'sourceEntryIds') as cited(value)
      where not exists (
        select 1 from public.entries
        where entries.id = cited.value::uuid
          and entries.owner_id = owner
          and entries.deleted_at is null
          and entries.item_subtype = 'entry'
      )
    ) then
      raise exception using errcode = '22023', message = 'invalid_chapter_suggestion';
    end if;

    new_window := daterange((item ->> 'windowStart')::date, (item ->> 'windowEnd')::date, '[)');
    -- A stretch that is already a Chapter, or was suggested before, is not proposed again.
    continue when exists (
      select 1 from public.chapter_suggestions as earlier
      where earlier.owner_id = owner
        and public.window_iou(new_window, daterange(earlier.window_start, earlier.window_end, '[)'), today) >= 0.5
    ) or exists (
      select 1 from public.entries as chapter
      where chapter.owner_id = owner and chapter.deleted_at is null and chapter.item_subtype = 'chapter'
        and public.window_iou(
          new_window,
          public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone),
          today
        ) >= 0.5
    );

    insert into public.chapter_suggestions (
      owner_id, name, rationale, source_entry_ids, start_date, start_precision, end_date, end_precision,
      window_start, window_end, model, disclosure_version
    )
    values (
      owner,
      btrim(item ->> 'name'),
      item ->> 'rationale',
      array(select value::uuid from jsonb_array_elements_text(item -> 'sourceEntryIds') as cited(value)),
      (item ->> 'startDate')::date,
      item ->> 'startPrecision',
      (item ->> 'endDate')::date,
      item ->> 'endPrecision',
      (item ->> 'windowStart')::date,
      (item ->> 'windowEnd')::date,
      p_model,
      p_disclosure_version
    );
    stored := stored + 1;
  end loop;

  select count(*) into entry_total
  from public.entries
  where owner_id = owner and deleted_at is null and item_subtype = 'entry';
  update public.chapter_suggestion_state
  set last_run_at = now(), last_entry_count = entry_total, leased_until = null
  where owner_id = owner;
  return stored;
end;
$$;

-- Gives the lease back after a failure that charged nothing, so a later visit may try again.
create function public.release_chapter_suggestion_run(p_lease_until timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  affected integer;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.chapter_suggestion_state
  set leased_until = null
  where owner_id = owner and leased_until is not distinct from p_lease_until;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

-- The one suggestion the Timeline shows: the oldest pending one that is not already covered by
-- a Chapter the person made. A pending suggestion stays hidden while one covers it.
create function public.pending_chapter_suggestion(p_local_date date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  suggestion public.chapter_suggestions;
begin
  if reader_id is null then
    return null;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_chapter_suggestion';
  end if;

  select * into suggestion
  from public.chapter_suggestions as candidate
  where candidate.owner_id = reader_id
    and candidate.status = 'pending'
    and not exists (
      select 1 from public.entries as chapter
      where chapter.owner_id = reader_id and chapter.deleted_at is null and chapter.item_subtype = 'chapter'
        and public.window_iou(
          daterange(candidate.window_start, candidate.window_end, '[)'),
          public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone),
          p_local_date
        ) >= 0.5
    )
  order by candidate.created_at, candidate.id
  limit 1;
  if suggestion.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', suggestion.id,
    'name', suggestion.name,
    'rationale', suggestion.rationale,
    'startDate', suggestion.start_date,
    'startPrecision', suggestion.start_precision,
    'endDate', suggestion.end_date,
    'endPrecision', suggestion.end_precision,
    'entryCount', cardinality(suggestion.source_entry_ids),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', entry.id,
        'title', coalesce(btrim(entry.title), ''),
        'occurredStart', entry.occurred_start,
        'occurredEnd', entry.occurred_end,
        'datePrecision', entry.date_precision,
        'occurredLabel', entry.occurred_label,
        'occurredTimezone', coalesce(entry.occurred_timezone, 'UTC')
      ) order by entry.occurred_start nulls last, entry.id)
      from public.entries as entry
      where entry.owner_id = reader_id
        and entry.id = any (suggestion.source_entry_ids)
        and entry.deleted_at is null
    ), '[]'::jsonb)
  );
end;
$$;

-- Records that a suggestion became the Chapter the person added. Only its name is kept.
create function public.confirm_chapter_suggestion(p_id uuid, p_chapter_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  affected integer;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (
    select 1 from public.entries
    where id = p_chapter_id and owner_id = owner and item_subtype = 'chapter' and deleted_at is null
  ) then
    return false;
  end if;
  update public.chapter_suggestions
  set status = 'confirmed', chapter_id = p_chapter_id, resolved_at = now(), rationale = null, source_entry_ids = '{}'
  where id = p_id and owner_id = owner and status = 'pending';
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

-- Dismissing deletes everything written about the suggestion and keeps only its dates.
create function public.dismiss_chapter_suggestion(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  affected integer;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.chapter_suggestions
  set status = 'dismissed', resolved_at = now(), name = null, rationale = null, source_entry_ids = '{}'
  where id = p_id and owner_id = owner and status = 'pending';
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

-- The review settings the interface reads. The counts decide what the confirmations say and
-- whether Delete forever mentions reviews; they are never shown as badges.
create function public.review_settings()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  prefs public.ai_preferences;
begin
  if reader_id is null then
    return null;
  end if;
  select * into prefs from public.ai_preferences where owner_id = reader_id;
  return jsonb_build_object(
    'reviewsEnabled', coalesce(prefs.reviews_enabled, false),
    'chapterSuggestionsEnabled', coalesce(prefs.chapter_suggestions_enabled, false),
    'disclosureVersion', prefs.review_disclosure_version,
    'revision', coalesce(prefs.revision, 0),
    'reviewCount', (select count(*) from public.entry_reviews where owner_id = reader_id and content is not null),
    'pendingSuggestionCount', (select count(*) from public.chapter_suggestions where owner_id = reader_id and status = 'pending')
  );
end;
$$;

create or replace function public.save_review_preferences(
  p_reviews boolean,
  p_suggestions boolean,
  p_disclosure_version text,
  p_expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  current_revision integer;
  stored_version text;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_reviews is null or p_suggestions is null
    or p_expected_revision is null or p_expected_revision < 0
    or (p_disclosure_version is not null and p_disclosure_version !~ '^\d{4}-\d{2}-\d{2}$')
  then
    raise exception using errcode = '22023', message = 'invalid_review_preferences';
  end if;

  -- Serialize with reservations, so turning a switch off takes effect before the next request.
  perform pg_advisory_xact_lock(741924);
  select revision, review_disclosure_version into current_revision, stored_version
  from public.ai_preferences
  where owner_id = owner
  for update;
  if coalesce(current_revision, 0) <> p_expected_revision then
    return null;
  end if;
  if (p_reviews or p_suggestions) and p_disclosure_version is null and stored_version is null then
    raise exception using errcode = '22023', message = 'review_consent_required';
  end if;

  if current_revision is null then
    insert into public.ai_preferences (
      owner_id, reviews_enabled, chapter_suggestions_enabled, review_disclosure_version, review_disclosure_accepted_at
    )
    values (
      owner, p_reviews, p_suggestions, p_disclosure_version,
      case when p_disclosure_version is null then null else now() end
    );
  else
    update public.ai_preferences
    set reviews_enabled = p_reviews,
        chapter_suggestions_enabled = p_suggestions,
        review_disclosure_version = coalesce(p_disclosure_version, review_disclosure_version),
        review_disclosure_accepted_at = case when p_disclosure_version is null then review_disclosure_accepted_at else now() end,
        revision = revision + 1,
        updated_at = now()
    where owner_id = owner;
  end if;

  return public.review_settings();
end;
$$;

revoke all on function public.window_iou(daterange, daterange, date) from public, anon;
grant execute on function public.window_iou(daterange, daterange, date) to authenticated, service_role;
revoke all on function public.claim_chapter_suggestion_run() from public, anon;
grant execute on function public.claim_chapter_suggestion_run() to authenticated, service_role;
revoke all on function public.chapter_suggestion_inputs(date) from public, anon;
grant execute on function public.chapter_suggestion_inputs(date) to authenticated, service_role;
revoke all on function public.store_chapter_suggestions(timestamptz, jsonb, text, text) from public, anon;
grant execute on function public.store_chapter_suggestions(timestamptz, jsonb, text, text) to authenticated, service_role;
revoke all on function public.release_chapter_suggestion_run(timestamptz) from public, anon;
grant execute on function public.release_chapter_suggestion_run(timestamptz) to authenticated, service_role;
revoke all on function public.pending_chapter_suggestion(date) from public, anon;
grant execute on function public.pending_chapter_suggestion(date) to authenticated, service_role;
revoke all on function public.confirm_chapter_suggestion(uuid, uuid) from public, anon;
grant execute on function public.confirm_chapter_suggestion(uuid, uuid) to authenticated, service_role;
revoke all on function public.dismiss_chapter_suggestion(uuid) from public, anon;
grant execute on function public.dismiss_chapter_suggestion(uuid) to authenticated, service_role;
revoke all on function public.review_settings() from public, anon;
grant execute on function public.review_settings() to authenticated, service_role;
revoke all on function public.save_review_preferences(boolean, boolean, text, integer) from public, anon;
grant execute on function public.save_review_preferences(boolean, boolean, text, integer) to authenticated, service_role;

commit;
