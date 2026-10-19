-- Reading a review. The page gets everything it needs in one call: whether a review can be
-- made, the live facts from the person's records, and the stored review with the checks that
-- run every time it is shown. A quote is shown only while its Entry is active and its exact
-- words still appear in the Entry as it is now, so editing the words away or moving the Entry
-- to Trash hides the quote without touching the stored review. Restoring brings it back.

begin;

create function public.review_read(
  p_scope text,
  p_chapter_id uuid,
  p_year integer,
  p_local_date date
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  eligibility jsonb;
  review public.entry_reviews;
  prefs public.ai_preferences;
  facts jsonb;
  review_json jsonb := null;
  quote_available jsonb;
  sources jsonb;
  new_entries integer := 0;
  edited_entries integer := 0;
  trashed_entries integer := 0;
  job_done integer := 0;
  job_total integer := 0;
  job_status text;
  job_error text;
begin
  if reader_id is null then
    return null;
  end if;

  eligibility := public.review_eligibility(p_scope, p_chapter_id, p_year, p_local_date);
  select * into prefs from public.ai_preferences where owner_id = reader_id;
  select * into review
  from public.entry_reviews as stored
  where stored.owner_id = reader_id
    and stored.scope = p_scope
    and (
      (p_scope = 'chapter' and stored.chapter_id = p_chapter_id)
      or (p_scope = 'year' and stored.review_year = p_year)
    );

  if eligibility ->> 'status' in ('eligible', 'too_few_entries') then
    facts := public.review_period_facts(p_scope, p_chapter_id, p_year);
  end if;

  if review.id is not null then
    job_status := review.job_status;
    job_error := review.job_error;
    if review.job_state is not null then
      select count(*) filter (where item.value ->> 'status' = 'done'), count(*)
      into job_done, job_total
      from jsonb_array_elements(review.job_state -> 'steps') as item(value);
    end if;
    -- A job that has not moved for half an hour was interrupted, whatever its row still says.
    if job_status = 'generating' and review.job_progressed_at < now() - interval '30 minutes' then
      job_status := 'failed';
      job_error := 'generation_interrupted';
    end if;

    if review.content is not null then
      select coalesce(jsonb_agg(
        exists (
          select 1 from public.entries as entry
          where entry.id = (quote.value ->> 'entryId')::uuid
            and entry.owner_id = reader_id
            and entry.deleted_at is null
            and position((quote.value ->> 'text') in entry.body) > 0
        ) order by quote.ordinality
      ), '[]'::jsonb)
      into quote_available
      from jsonb_array_elements(review.content -> 'quotes') with ordinality as quote(value, ordinality);

      select coalesce(jsonb_agg(jsonb_build_object(
        'entryId', entry.id,
        'title', coalesce(btrim(entry.title), ''),
        'occurredStart', entry.occurred_start,
        'occurredEnd', entry.occurred_end,
        'datePrecision', entry.date_precision,
        'occurredLabel', entry.occurred_label,
        'occurredTimezone', coalesce(entry.occurred_timezone, 'UTC'),
        'trashed', entry.deleted_at is not null
      ) order by entry.occurred_start nulls last, entry.id), '[]'::jsonb)
      into sources
      from public.entries as entry
      where entry.owner_id = reader_id
        and entry.id in (
          select (cited.value)::uuid
          from (
            select jsonb_array_elements_text(phase.value -> 'entryIds') as value
            from jsonb_array_elements(review.content #> '{feelings,phases}') as phase(value)
            union
            select jsonb_array_elements_text(theme.value -> 'entryIds')
            from jsonb_array_elements(review.content -> 'themes') as theme(value)
            union
            select quote.value ->> 'entryId'
            from jsonb_array_elements(review.content -> 'quotes') as quote(value)
          ) as cited
        );

      select count(*) filter (where entry.deleted_at is not null),
             count(*) filter (
               where entry.deleted_at is null
                 and (source.content_hash is null or source.content_hash <> md5(coalesce(entry.title, '') || chr(1) || entry.body))
             )
      into trashed_entries, edited_entries
      from public.entry_review_sources as source
      join public.entries as entry on entry.id = source.entry_id and entry.owner_id = source.owner_id
      where source.review_id = review.id and source.owner_id = reader_id;

      if eligibility ->> 'status' in ('eligible', 'too_few_entries') then
        select count(*) into new_entries
        from public.review_period_entries(p_scope, p_chapter_id, p_year) as member
        join public.entries as entry on entry.id = member.entry_id
        where not member.is_subject
          and not exists (
            select 1 from public.entry_review_sources as source
            where source.review_id = review.id and source.entry_id = member.entry_id
          )
          and (review.entries_read = review.entries_in_period or entry.created_at > review.generated_at);
      end if;
    end if;

    review_json := jsonb_build_object(
      'id', review.id,
      'content', review.content,
      'model', review.model,
      'language', review.language,
      'ongoing', review.ongoing,
      'generatedAt', review.generated_at,
      'entriesInPeriod', review.entries_in_period,
      'entriesRead', review.entries_read,
      'trimmedEntries', review.trimmed_entries,
      'quoteAvailable', coalesce(quote_available, '[]'::jsonb),
      'sources', coalesce(sources, '[]'::jsonb),
      'changes', jsonb_build_object(
        'newEntries', new_entries,
        'editedEntries', edited_entries,
        'trashedEntries', trashed_entries
      ),
      'job', jsonb_build_object('status', job_status, 'error', job_error, 'done', job_done, 'total', job_total)
    );
  end if;

  return jsonb_build_object(
    'eligibility', eligibility,
    'settings', jsonb_build_object(
      'reviewsEnabled', coalesce(prefs.reviews_enabled, false),
      'disclosureVersion', prefs.review_disclosure_version
    ),
    'facts', facts,
    'review', review_json
  );
end;
$$;

create function public.chapter_review(p_chapter_id uuid, p_local_date date)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select public.review_read('chapter', p_chapter_id, null, p_local_date);
$$;

create function public.year_review(p_year integer, p_local_date date)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select public.review_read('year', null, p_year, p_local_date);
$$;

-- The small read the page polls while a job runs.
create function public.entry_review_status(p_review_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  review public.entry_reviews;
  status text;
  error text;
  done_count integer := 0;
  total_count integer := 0;
  running_count integer := 0;
begin
  if reader_id is null then
    return null;
  end if;
  select * into review from public.entry_reviews as stored where stored.id = p_review_id and stored.owner_id = reader_id;
  if review.id is null then
    return null;
  end if;
  status := review.job_status;
  error := review.job_error;
  if review.job_state is not null then
    select count(*) filter (where item.value ->> 'status' = 'done'),
           count(*),
           count(*) filter (where item.value ->> 'status' = 'running')
    into done_count, total_count, running_count
    from jsonb_array_elements(review.job_state -> 'steps') as item(value);
  end if;
  if status = 'generating' and review.job_progressed_at < now() - interval '30 minutes' then
    status := 'failed';
    error := 'generation_interrupted';
  end if;
  return jsonb_build_object(
    'status', status,
    'error', error,
    'done', done_count,
    'total', total_count,
    'running', running_count,
    'hasReview', review.content is not null
  );
end;
$$;

revoke all on function public.review_read(text, uuid, integer, date) from public, anon;
grant execute on function public.review_read(text, uuid, integer, date) to authenticated, service_role;
revoke all on function public.chapter_review(uuid, date) from public, anon;
grant execute on function public.chapter_review(uuid, date) to authenticated, service_role;
revoke all on function public.year_review(integer, date) from public, anon;
grant execute on function public.year_review(integer, date) to authenticated, service_role;
revoke all on function public.entry_review_status(uuid) from public, anon;
grant execute on function public.entry_review_status(uuid) to authenticated, service_role;

commit;
