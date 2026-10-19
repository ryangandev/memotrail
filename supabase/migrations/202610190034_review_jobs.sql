-- Making a review is a job of one to seven short steps, each of which is one request to the
-- model. The job lives on the review row, so no step needs more than one function invocation
-- and a visit to the page can resume a job whose invocation ended between steps. A step is
-- handed out once and runs under a lease: when a lease ends unfinished, the outcome of the
-- paid request is unknown, so the whole job fails instead of repeating it on its own. Finished
-- map steps are kept, so Try again pays only for what is left.
--
-- The plan holds IDs and revisions only, never Entry text. Every step reads the text again
-- with the person's own session.
--
-- p_job_started_at is the identity of a job. Pass back exactly the text a function returned.

begin;

create function public.claim_entry_review(
  p_scope text,
  p_chapter_id uuid,
  p_year integer,
  p_local_date date,
  p_plan jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  prefs public.ai_preferences;
  eligibility jsonb;
  existing public.entry_reviews;
  started timestamptz := clock_timestamp();
  today date := (now() at time zone 'UTC')::date;
  reuse boolean := false;
  merged jsonb := '[]'::jsonb;
  plan_step jsonb;
  kept jsonb;
  state jsonb;
  review_id uuid;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_scope not in ('chapter', 'year')
    or jsonb_typeof(p_plan) is distinct from 'object'
    or jsonb_typeof(p_plan -> 'steps') is distinct from 'array'
    or jsonb_array_length(p_plan -> 'steps') not between 1 and 8
    or jsonb_typeof(p_plan -> 'entryIds') is distinct from 'array'
    or jsonb_array_length(p_plan -> 'entryIds') > 20000
    or coalesce(p_plan ->> 'planHash', '') !~ '^[0-9a-f]{64}$'
    or coalesce(p_plan ->> 'mode', '') not in ('single', 'segmented')
    or coalesce(p_plan ->> 'language', '') not in ('en', 'zh')
    or jsonb_typeof(p_plan -> 'ongoing') is distinct from 'boolean'
    or coalesce(p_plan ->> 'disclosureVersion', '') !~ '^\d{4}-\d{2}-\d{2}$'
    or jsonb_typeof(p_plan -> 'entriesInPeriod') is distinct from 'number'
    or jsonb_typeof(p_plan -> 'trimmedEntries') is distinct from 'number'
  then
    raise exception using errcode = '22023', message = 'invalid_review_plan';
  end if;

  -- One lock per owner serializes starts, so two requests cannot both begin a job.
  select * into prefs from public.ai_preferences where owner_id = owner for update;
  if prefs.owner_id is null or not prefs.reviews_enabled or prefs.review_disclosure_version is null then
    raise exception using errcode = '42501', message = 'ai_disabled';
  end if;
  if prefs.review_disclosure_version is distinct from p_plan ->> 'disclosureVersion' then
    raise exception using errcode = '42501', message = 'review_disclosure_outdated';
  end if;

  eligibility := public.review_eligibility(p_scope, p_chapter_id, p_year, p_local_date);
  if eligibility ->> 'status' <> 'eligible' then
    raise exception using errcode = '22023', message = 'review_not_eligible';
  end if;

  if exists (
    select 1 from public.entry_reviews as other
    where other.owner_id = owner
      and other.job_status = 'generating'
      and other.job_progressed_at > now() - interval '30 minutes'
  ) then
    raise exception using errcode = 'P0001', message = 'review_in_progress';
  end if;

  select * into existing
  from public.entry_reviews as review
  where review.owner_id = owner
    and review.scope = p_scope
    and (
      (p_scope = 'chapter' and review.chapter_id = p_chapter_id)
      or (p_scope = 'year' and review.review_year = p_year)
    )
  for update;

  if existing.id is not null
    and existing.generation_day = today
    and existing.generation_count_day >= 3
  then
    raise exception using errcode = 'P0001', message = 'review_limit_reached';
  end if;

  -- Try again with the same plan keeps the steps that already finished.
  reuse := existing.id is not null
    and existing.job_status = 'failed'
    and existing.job_state ->> 'planHash' = p_plan ->> 'planHash';

  for plan_step in select value from jsonb_array_elements(p_plan -> 'steps') loop
    kept := null;
    if reuse then
      select old.value into kept
      from jsonb_array_elements(existing.job_state -> 'steps') as old(value)
      where old.value ->> 'index' = plan_step ->> 'index' and old.value ->> 'status' = 'done'
      limit 1;
    end if;
    merged := merged || jsonb_build_array(coalesce(kept, plan_step || jsonb_build_object('status', 'pending')));
  end loop;

  state := p_plan || jsonb_build_object('steps', merged);

  if existing.id is null then
    insert into public.entry_reviews (
      owner_id, scope, chapter_id, review_year, job_status, job_started_at, job_progressed_at,
      job_error, job_state, generation_count_day, generation_day
    )
    values (
      owner, p_scope, case when p_scope = 'chapter' then p_chapter_id end,
      case when p_scope = 'year' then p_year end, 'generating', started, started,
      null, state, 1, today
    )
    returning id into review_id;
  else
    update public.entry_reviews
    set job_status = 'generating',
        job_started_at = started,
        job_progressed_at = started,
        job_error = null,
        job_state = state,
        generation_count_day = case when generation_day = today then generation_count_day + 1 else 1 end,
        generation_day = today
    where id = existing.id
    returning id into review_id;
  end if;

  return jsonb_build_object(
    'reviewId', review_id,
    'jobStartedAt', started,
    'done', (select count(*) from jsonb_array_elements(merged) as step(value) where step.value ->> 'status' = 'done'),
    'total', jsonb_array_length(merged)
  );
end;
$$;

-- Hands out the next steps that are ready. A map step is ready at once; the reduce step is
-- ready only when every map step is done. status is ok, stale (this is not the current job),
-- or interrupted (a lease ended unfinished, and the job has failed). state is the whole job
-- state, so the caller can build each step's input from the plan and the finished results.
create function public.claim_review_steps(
  p_review_id uuid,
  p_job_started_at timestamptz,
  p_max integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  review public.entry_reviews;
  steps jsonb := '[]'::jsonb;
  step jsonb;
  claimed integer[] := '{}';
  maps_done boolean;
  limit_count integer;
  lease timestamptz := clock_timestamp() + interval '5 minutes';
  expired boolean := false;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_max is null or p_max not between 1 and 6 then
    raise exception using errcode = '22023', message = 'invalid_review_plan';
  end if;

  select * into review
  from public.entry_reviews as job
  where job.id = p_review_id and job.owner_id = owner
  for update;
  if review.id is null or review.job_status <> 'generating' or review.job_started_at is distinct from p_job_started_at then
    return jsonb_build_object('status', 'stale');
  end if;

  -- A step whose lease ended has an unknown outcome. It is never retried automatically.
  for step in select value from jsonb_array_elements(review.job_state -> 'steps') loop
    if step ->> 'status' = 'running' and (step ->> 'leasedUntil')::timestamptz < clock_timestamp() then
      expired := true;
    end if;
  end loop;
  if expired then
    update public.entry_reviews
    set job_status = 'failed',
        job_error = 'generation_interrupted',
        job_progressed_at = clock_timestamp(),
        job_state = jsonb_set(job_state, '{steps}', (
          select jsonb_agg(
            case
              when item.value ->> 'status' = 'running' and (item.value ->> 'leasedUntil')::timestamptz < clock_timestamp()
                then item.value || jsonb_build_object('status', 'uncertain')
              else item.value
            end order by item.ordinality
          )
          from jsonb_array_elements(job_state -> 'steps') with ordinality as item(value, ordinality)
        ))
    where id = review.id;
    return jsonb_build_object('status', 'interrupted');
  end if;

  maps_done := not exists (
    select 1 from jsonb_array_elements(review.job_state -> 'steps') as item(value)
    where item.value ->> 'kind' = 'map' and item.value ->> 'status' <> 'done'
  );
  limit_count := p_max;

  for step in select value from jsonb_array_elements(review.job_state -> 'steps') loop
    if limit_count > 0
      and step ->> 'status' = 'pending'
      and (step ->> 'kind' <> 'reduce' or maps_done)
    then
      step := step || jsonb_build_object('status', 'running', 'leasedUntil', lease);
      claimed := claimed || (step ->> 'index')::integer;
      limit_count := limit_count - 1;
    end if;
    steps := steps || jsonb_build_array(step);
  end loop;

  update public.entry_reviews
  set job_state = jsonb_set(job_state, '{steps}', steps),
      job_progressed_at = clock_timestamp()
  where id = review.id
  returning job_state into review.job_state;

  return jsonb_build_object(
    'status', 'ok',
    'claimed', to_jsonb(claimed),
    'state', review.job_state
  );
end;
$$;

-- Stores the validated result of a map step and marks it done.
create function public.finish_review_step(
  p_review_id uuid,
  p_job_started_at timestamptz,
  p_step integer,
  p_result jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  review public.entry_reviews;
  found_step boolean;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_step is null or p_step < 0 or jsonb_typeof(p_result) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_review_plan';
  end if;

  select * into review
  from public.entry_reviews as job
  where job.id = p_review_id and job.owner_id = owner
  for update;
  if review.id is null or review.job_status <> 'generating' or review.job_started_at is distinct from p_job_started_at then
    return false;
  end if;

  select exists (
    select 1 from jsonb_array_elements(review.job_state -> 'steps') as item(value)
    where (item.value ->> 'index')::integer = p_step and item.value ->> 'status' = 'running'
  ) into found_step;
  if not found_step then
    return false;
  end if;

  update public.entry_reviews
  set job_progressed_at = clock_timestamp(),
      job_state = jsonb_set(job_state, '{steps}', (
        select jsonb_agg(
          case
            when (item.value ->> 'index')::integer = p_step
              then (item.value - 'leasedUntil') || jsonb_build_object('status', 'done', 'result', p_result)
            else item.value
          end order by item.ordinality
        )
        from jsonb_array_elements(job_state -> 'steps') with ordinality as item(value, ordinality)
      ))
  where id = review.id;
  return true;
end;
$$;

-- Saves a finished review. Every quote is checked once more against the Entry as it is stored
-- now, so a quote that is not the person's own words cannot be saved however it got here.
-- p_sources lists the Entries the steps actually read, each with the revision it read.
create function public.store_entry_review(
  p_review_id uuid,
  p_job_started_at timestamptz,
  p_content jsonb,
  p_model text,
  p_entries_read integer,
  p_sources jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  review public.entry_reviews;
  prefs public.ai_preferences;
  plan_ids jsonb;
  allowed uuid[];
  source_ids uuid[];
  item jsonb;
  cited text;
  period daterange;
  chapter_entry public.entries;
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if jsonb_typeof(p_content) is distinct from 'object'
    or jsonb_typeof(p_content -> 'summary') is distinct from 'string'
    or jsonb_typeof(p_content #> '{feelings,overview}') is distinct from 'string'
    or jsonb_typeof(p_content #> '{feelings,phases}') is distinct from 'array'
    or jsonb_typeof(p_content -> 'themes') is distinct from 'array'
    or jsonb_typeof(p_content -> 'quotes') is distinct from 'array'
    or jsonb_typeof(p_sources) is distinct from 'array'
    or jsonb_array_length(p_sources) > 20000
    or p_model is null or not exists (select 1 from public.ai_model_price(p_model))
    or p_entries_read is null or p_entries_read < 0
  then
    raise exception using errcode = '22023', message = 'invalid_review_content';
  end if;

  select * into review
  from public.entry_reviews as job
  where job.id = p_review_id and job.owner_id = owner
  for update;
  if review.id is null or review.job_status <> 'generating' or review.job_started_at is distinct from p_job_started_at then
    return false;
  end if;

  select * into prefs from public.ai_preferences where owner_id = owner;
  if prefs.owner_id is null or not prefs.reviews_enabled then
    raise exception using errcode = '42501', message = 'ai_disabled';
  end if;

  plan_ids := review.job_state -> 'entryIds';
  allowed := array(
    select value::uuid from jsonb_array_elements_text(plan_ids) as plan(value)
  );
  if review.scope = 'chapter' then
    allowed := allowed || review.chapter_id;
  end if;
  source_ids := array(select (source.value ->> 'entryId')::uuid from jsonb_array_elements(p_sources) as source(value));
  if exists (select 1 from unnest(source_ids) as source_id where source_id <> all (allowed)) then
    raise exception using errcode = '22023', message = 'invalid_review_content';
  end if;

  for item in select value from jsonb_array_elements(p_content #> '{feelings,phases}') loop
    for cited in select value from jsonb_array_elements_text(item -> 'entryIds') loop
      if cited::uuid <> all (source_ids) then
        raise exception using errcode = '22023', message = 'invalid_review_content';
      end if;
    end loop;
  end loop;
  for item in select value from jsonb_array_elements(p_content -> 'themes') loop
    for cited in select value from jsonb_array_elements_text(item -> 'entryIds') loop
      if cited::uuid <> all (source_ids) then
        raise exception using errcode = '22023', message = 'invalid_review_content';
      end if;
    end loop;
  end loop;

  for item in select value from jsonb_array_elements(p_content -> 'quotes') loop
    if jsonb_typeof(item -> 'text') is distinct from 'string'
      or (item ->> 'entryId')::uuid <> all (source_ids)
      or not exists (
        select 1 from public.entries as entry
        where entry.id = (item ->> 'entryId')::uuid
          and entry.owner_id = owner
          and entry.deleted_at is null
          and position((item ->> 'text') in entry.body) > 0
      )
    then
      raise exception using errcode = '22023', message = 'review_quote_unverified';
    end if;
  end loop;

  delete from public.entry_review_sources where review_id = review.id;
  begin
    insert into public.entry_review_sources (review_id, owner_id, entry_id, entry_revision, content_hash)
    select
      review.id,
      owner,
      (source.value ->> 'entryId')::uuid,
      (source.value ->> 'revision')::integer,
      (
        select case
          when entry.revision = (source.value ->> 'revision')::integer
            then md5(coalesce(entry.title, '') || chr(1) || entry.body)
        end
        from public.entries as entry
        where entry.id = (source.value ->> 'entryId')::uuid and entry.owner_id = owner
      )
    from jsonb_array_elements(p_sources) as source(value);
  exception
    when foreign_key_violation then
      raise exception using errcode = '22023', message = 'review_source_deleted';
  end;

  if review.scope = 'chapter' then
    select * into chapter_entry from public.entries where id = review.chapter_id and owner_id = owner;
    period := public.chapter_window(chapter_entry.occurred_start, chapter_entry.occurred_end, chapter_entry.date_precision, chapter_entry.occurred_timezone);
  else
    period := daterange(make_date(review.review_year, 1, 1), make_date(review.review_year + 1, 1, 1), '[)');
  end if;

  update public.entry_reviews
  set content = p_content,
      model = p_model,
      disclosure_version = review.job_state ->> 'disclosureVersion',
      language = review.job_state ->> 'language',
      ongoing = (review.job_state ->> 'ongoing')::boolean,
      period_start = lower(period),
      period_end = upper(period),
      entries_in_period = (review.job_state ->> 'entriesInPeriod')::integer,
      entries_read = p_entries_read,
      trimmed_entries = (review.job_state ->> 'trimmedEntries')::integer,
      generated_at = now(),
      job_status = 'idle',
      job_started_at = null,
      job_progressed_at = null,
      job_error = null,
      job_state = null
  where id = review.id;
  return true;
end;
$$;

-- Marks the current job failed and keeps what finished, so Try again can continue from there.
-- Any previous review stays.
create function public.fail_entry_review(
  p_review_id uuid,
  p_job_started_at timestamptz,
  p_error_code text
)
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
  if p_error_code is null or p_error_code !~ '^[a-z0-9_]{1,64}$' then
    raise exception using errcode = '22023', message = 'invalid_review_plan';
  end if;

  update public.entry_reviews
  set job_status = 'failed',
      job_error = p_error_code,
      job_progressed_at = clock_timestamp()
  where id = p_review_id
    and owner_id = owner
    and job_status = 'generating'
    and job_started_at is not distinct from p_job_started_at;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create function public.delete_entry_review(p_review_id uuid)
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
  delete from public.entry_reviews where id = p_review_id and owner_id = owner;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

revoke all on function public.claim_entry_review(text, uuid, integer, date, jsonb) from public, anon;
grant execute on function public.claim_entry_review(text, uuid, integer, date, jsonb) to authenticated, service_role;
revoke all on function public.claim_review_steps(uuid, timestamptz, integer) from public, anon;
grant execute on function public.claim_review_steps(uuid, timestamptz, integer) to authenticated, service_role;
revoke all on function public.finish_review_step(uuid, timestamptz, integer, jsonb) from public, anon;
grant execute on function public.finish_review_step(uuid, timestamptz, integer, jsonb) to authenticated, service_role;
revoke all on function public.store_entry_review(uuid, timestamptz, jsonb, text, integer, jsonb) from public, anon;
grant execute on function public.store_entry_review(uuid, timestamptz, jsonb, text, integer, jsonb) to authenticated, service_role;
revoke all on function public.fail_entry_review(uuid, timestamptz, text) from public, anon;
grant execute on function public.fail_entry_review(uuid, timestamptz, text) to authenticated, service_role;
revoke all on function public.delete_entry_review(uuid) from public, anon;
grant execute on function public.delete_entry_review(uuid) to authenticated, service_role;

commit;
