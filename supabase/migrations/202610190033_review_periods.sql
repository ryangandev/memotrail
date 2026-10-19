-- What a review reads is never stored apart from the review itself. The period of a Chapter
-- review is the Chapter's own writing plus every Entry dated inside it, with the same
-- containment rule Chapters use everywhere. The period of a year review is every Entry whose
-- days all lie inside that calendar year, so a Year-precision Entry for that year is inside
-- and a range that crosses New Year is not. Trash, other owners, and Entries whose date
-- cannot be placed never count.
--
-- review_period_facts computes the "From your records" block live, with no AI involved, and
-- review_years lists the past years that have enough Entries to look back on.

begin;

-- One row per Entry a review would read, oldest first. For a Chapter, the Chapter itself comes
-- first with is_subject set. Bodies are returned whole; the server trims and samples.
create function public.review_period_entries(
  p_scope text,
  p_chapter_id uuid default null,
  p_year integer default null
)
returns table (
  entry_id uuid,
  is_subject boolean,
  title text,
  body text,
  revision integer,
  is_first_time boolean,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  window_start date,
  window_end date,
  tag_names text[]
)
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  period daterange;
begin
  if reader_id is null then
    return;
  end if;

  if p_scope = 'chapter' and p_chapter_id is not null and p_year is null then
    select public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone)
    into period
    from public.entries as chapter
    where chapter.id = p_chapter_id
      and chapter.owner_id = reader_id
      and chapter.item_subtype = 'chapter'
      and chapter.deleted_at is null;
    if period is null then
      raise exception using errcode = '22023', message = 'review_subject_unavailable';
    end if;
  elsif p_scope = 'year' and p_chapter_id is null and p_year between 1900 and 3000 then
    period := daterange(make_date(p_year, 1, 1), make_date(p_year + 1, 1, 1), '[)');
  else
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  return query
  with candidates as (
    select
      entry.id,
      (p_scope = 'chapter' and entry.id = p_chapter_id) as subject,
      entry.title,
      entry.body,
      entry.revision,
      entry.is_first_time,
      entry.occurred_start,
      entry.occurred_end,
      entry.date_precision,
      entry.occurred_label,
      coalesce(entry.occurred_timezone, 'UTC') as occurred_timezone,
      entry.created_at,
      dated.days
    from public.entries as entry
    cross join lateral (
      select case
        when p_scope = 'chapter' and entry.id = p_chapter_id then
          public.chapter_window(entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone)
        else
          public.entry_date_window(entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone)
      end as days
    ) as dated
    where entry.owner_id = reader_id
      and entry.deleted_at is null
      and (
        (p_scope = 'chapter' and entry.id = p_chapter_id)
        or (entry.item_subtype = 'entry' and entry.id is distinct from p_chapter_id and period @> dated.days)
      )
  )
  select
    candidates.id,
    candidates.subject,
    coalesce(btrim(candidates.title), ''),
    candidates.body,
    candidates.revision,
    candidates.is_first_time,
    candidates.occurred_start,
    candidates.occurred_end,
    candidates.date_precision,
    candidates.occurred_label,
    candidates.occurred_timezone,
    lower(candidates.days),
    upper(candidates.days),
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id and tags.owner_id = entry_tags.owner_id
        where entry_tags.entry_id = candidates.id and entry_tags.owner_id = reader_id
      ),
      '{}'::text[]
    )
  from candidates
  order by candidates.subject desc, lower(candidates.days), candidates.occurred_start, candidates.created_at, candidates.id;
end;
$$;

-- The Chapters during a year, by name and dates only: their writing is not part of a year review.
create function public.review_period_chapters(p_year integer)
returns table (
  entry_id uuid,
  title text,
  occurred_start timestamptz,
  occurred_end timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  window_start date,
  window_end date
)
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
begin
  if reader_id is null then
    return;
  end if;
  if p_year is null or p_year not between 1900 and 3000 then
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  return query
  select
    chapter.id,
    coalesce(btrim(chapter.title), ''),
    chapter.occurred_start,
    chapter.occurred_end,
    chapter.date_precision,
    chapter.occurred_label,
    coalesce(chapter.occurred_timezone, 'UTC'),
    lower(dated.days),
    upper(dated.days)
  from public.entries as chapter
  cross join lateral (
    select public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone) as days
  ) as dated
  where chapter.owner_id = reader_id
    and chapter.deleted_at is null
    and chapter.item_subtype = 'chapter'
    and daterange(make_date(p_year, 1, 1), make_date(p_year + 1, 1, 1), '[)') && dated.days
  order by lower(dated.days), lower(chapter.title), chapter.id;
end;
$$;

-- The "From your records" block: counts and lists computed from the period's Entries.
create function public.review_period_facts(
  p_scope text,
  p_chapter_id uuid default null,
  p_year integer default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    return null;
  end if;

  with members as (
    select * from public.review_period_entries(p_scope, p_chapter_id, p_year) as member where not member.is_subject
  ),
  tag_counts as (
    select min(tag_name) as name, count(*) as uses
    from members, unnest(members.tag_names) as tag_name
    group by lower(tag_name)
    order by count(*) desc, lower(min(tag_name))
    limit 5
  ),
  months as (
    select to_char(members.window_start, 'YYYY-MM') as month, count(*) as uses
    from members
    where members.window_end is not null
      and members.window_end <= (date_trunc('month', members.window_start) + interval '1 month')::date
    group by 1
    order by count(*) desc, 1
    limit 1
  )
  select jsonb_build_object(
    'entryCount', (select count(*) from members),
    'firstWindowStart', (select min(window_start) from members),
    'lastWindowStart', (select max(window_start) from members),
    'firstTimes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', first_time.entry_id,
        'title', first_time.title,
        'occurredStart', first_time.occurred_start,
        'occurredEnd', first_time.occurred_end,
        'datePrecision', first_time.date_precision,
        'occurredLabel', first_time.occurred_label,
        'occurredTimezone', first_time.occurred_timezone
      ) order by first_time.window_start, first_time.occurred_start, first_time.entry_id)
      from (
        select * from members where members.is_first_time
        order by members.window_start, members.occurred_start, members.entry_id
        limit 10
      ) as first_time
    ), '[]'::jsonb),
    'topTags', coalesce((
      select jsonb_agg(jsonb_build_object('name', tag_counts.name, 'count', tag_counts.uses) order by tag_counts.uses desc, lower(tag_counts.name))
      from tag_counts
    ), '[]'::jsonb),
    'busiestMonth', (
      select jsonb_build_object('month', months.month, 'count', months.uses) from months
    ),
    'chapters', case when p_scope = 'year' then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', chapter.entry_id,
        'title', chapter.title,
        'occurredStart', chapter.occurred_start,
        'occurredEnd', chapter.occurred_end,
        'datePrecision', chapter.date_precision,
        'occurredLabel', chapter.occurred_label,
        'occurredTimezone', chapter.occurred_timezone
      ) order by chapter.window_start, chapter.entry_id)
      from public.review_period_chapters(p_year) as chapter
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  into result;
  return result;
end;
$$;

-- The past years that have enough Entries to look back on, newest first, with the date of the
-- stored review when there is one. p_local_date is today in the person's time zone.
create function public.review_years(p_local_date date)
returns table (review_year integer, entry_count bigint, review_generated_at timestamptz)
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
begin
  if reader_id is null then
    return;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  return query
  with dated as (
    select
      extract(year from lower(days))::integer as year_of,
      days
    from (
      select public.entry_date_window(entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone) as days
      from public.entries as entry
      where entry.owner_id = reader_id and entry.deleted_at is null and entry.item_subtype = 'entry'
    ) as windows
    where days is not null and lower(days) is not null and upper(days) is not null
  ),
  inside as (
    select dated.year_of, count(*) as entries
    from dated
    where dated.year_of between 1900 and extract(year from p_local_date)::integer - 1
      and daterange(make_date(dated.year_of, 1, 1), make_date(dated.year_of + 1, 1, 1), '[)') @> dated.days
    group by dated.year_of
    having count(*) >= 5
  )
  select inside.year_of, inside.entries, review.generated_at
  from inside
  left join public.entry_reviews as review
    on review.owner_id = reader_id and review.scope = 'year' and review.review_year = inside.year_of and review.content is not null
  order by inside.year_of desc;
end;
$$;

-- Whether a review can be made. A Chapter needs a calendar span and at least five Entries
-- inside it; it may still be going on, in which case the review is a "review so far". A year
-- needs to be over, with at least five Entries. Statuses: eligible, too_few_entries,
-- unanchored (a Chapter without a calendar span), not_over (a year still going), unavailable.
create function public.review_eligibility(
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
  period daterange;
  chapter_found boolean;
  entry_total integer;
  minimum constant integer := 5;
begin
  if reader_id is null then
    return jsonb_build_object('status', 'unavailable', 'entryCount', 0, 'minimum', minimum, 'ongoing', false);
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  if p_scope = 'chapter' and p_chapter_id is not null and p_year is null then
    select true, public.chapter_window(chapter.occurred_start, chapter.occurred_end, chapter.date_precision, chapter.occurred_timezone)
    into chapter_found, period
    from public.entries as chapter
    where chapter.id = p_chapter_id
      and chapter.owner_id = reader_id
      and chapter.item_subtype = 'chapter'
      and chapter.deleted_at is null;
    if chapter_found is not true then
      return jsonb_build_object('status', 'unavailable', 'entryCount', 0, 'minimum', minimum, 'ongoing', false);
    end if;
    if period is null or lower(period) is null then
      return jsonb_build_object('status', 'unanchored', 'entryCount', 0, 'minimum', minimum, 'ongoing', false);
    end if;
  elsif p_scope = 'year' and p_chapter_id is null and p_year between 1900 and 3000 then
    if p_year >= extract(year from p_local_date)::integer then
      return jsonb_build_object('status', 'not_over', 'entryCount', 0, 'minimum', minimum, 'ongoing', false);
    end if;
  else
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  select count(*) into entry_total
  from public.review_period_entries(p_scope, p_chapter_id, p_year) as member
  where not member.is_subject;

  return jsonb_build_object(
    'status', case when entry_total >= minimum then 'eligible' else 'too_few_entries' end,
    'entryCount', entry_total,
    'minimum', minimum,
    'ongoing', p_scope = 'chapter' and (upper(period) is null or upper(period) > p_local_date)
  );
end;
$$;

revoke all on function public.review_period_entries(text, uuid, integer) from public, anon;
grant execute on function public.review_period_entries(text, uuid, integer) to authenticated, service_role;
revoke all on function public.review_period_chapters(integer) from public, anon;
grant execute on function public.review_period_chapters(integer) to authenticated, service_role;
revoke all on function public.review_period_facts(text, uuid, integer) from public, anon;
grant execute on function public.review_period_facts(text, uuid, integer) to authenticated, service_role;
revoke all on function public.review_years(date) from public, anon;
grant execute on function public.review_years(date) to authenticated, service_role;
revoke all on function public.review_eligibility(text, uuid, integer, date) from public, anon;
grant execute on function public.review_eligibility(text, uuid, integer, date) to authenticated, service_role;

commit;
