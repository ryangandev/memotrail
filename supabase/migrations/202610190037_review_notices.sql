-- The only notice MemoTrail gives is one quiet card on the Dashboard, only while reviews are
-- on: a year has just ended, or a Chapter has recently ended, and a review can be made. Reviews
-- are never made on their own, so the notice says a review can be made, not that one exists.
-- Resolving a notice, by following it or choosing Not now, retires it for that year or Chapter
-- for good. Notices are interface state and are not part of an export.

begin;

create table public.review_notices (
  owner_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (subject ~ '^(year:\d{4}|chapter:[0-9a-f-]{36})$'),
  resolved_at timestamptz not null default now(),
  primary key (owner_id, subject)
);

alter table public.review_notices enable row level security;
create policy review_notices_owner_read on public.review_notices
  for select to authenticated
  using (owner_id = (select auth.uid()));
revoke all on public.review_notices from public, anon, authenticated;
grant select on public.review_notices to authenticated;
grant all on public.review_notices to service_role;

-- At most one notice, or null. From January 1 through March 31 the year just ended comes
-- first, when it has at least five Entries, no review, and no resolved notice. Otherwise the
-- Chapter that ended most recently, within the last sixty days, with the same conditions.
create function public.review_notice(p_local_date date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  reader_id uuid := auth.uid();
  prefs public.ai_preferences;
  last_year integer;
  chapter record;
begin
  if reader_id is null then
    return null;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_review_period';
  end if;

  select * into prefs from public.ai_preferences where owner_id = reader_id;
  if prefs.owner_id is null or not prefs.reviews_enabled then
    return null;
  end if;

  last_year := extract(year from p_local_date)::integer - 1;
  if extract(month from p_local_date) <= 3 and last_year >= 1900
    and not exists (select 1 from public.review_notices where owner_id = reader_id and subject = 'year:' || last_year)
    and not exists (select 1 from public.entry_reviews where owner_id = reader_id and scope = 'year' and review_year = last_year and content is not null)
    and (public.review_eligibility('year', null, last_year, p_local_date) ->> 'status') = 'eligible'
  then
    return jsonb_build_object('subject', 'year:' || last_year, 'kind', 'year', 'year', last_year);
  end if;

  for chapter in
    select entry.id, coalesce(btrim(entry.title), '') as title, upper(dated.days) as ended_after
    from public.entries as entry
    cross join lateral (
      select public.chapter_window(entry.occurred_start, entry.occurred_end, entry.date_precision, entry.occurred_timezone) as days
    ) as dated
    where entry.owner_id = reader_id
      and entry.deleted_at is null
      and entry.item_subtype = 'chapter'
      and upper(dated.days) is not null
      and upper(dated.days) <= p_local_date
      and upper(dated.days) > p_local_date - 60
    order by upper(dated.days) desc, entry.id
  loop
    continue when exists (
      select 1 from public.review_notices where owner_id = reader_id and subject = 'chapter:' || chapter.id
    ) or exists (
      select 1 from public.entry_reviews where owner_id = reader_id and scope = 'chapter' and chapter_id = chapter.id and content is not null
    ) or (public.review_eligibility('chapter', chapter.id, null, p_local_date) ->> 'status') <> 'eligible';
    return jsonb_build_object('subject', 'chapter:' || chapter.id, 'kind', 'chapter', 'chapterId', chapter.id, 'title', chapter.title);
  end loop;
  return null;
end;
$$;

create function public.resolve_review_notice(p_subject text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_subject is null or p_subject !~ '^(year:\d{4}|chapter:[0-9a-f-]{36})$' then
    raise exception using errcode = '22023', message = 'invalid_review_notice';
  end if;
  insert into public.review_notices (owner_id, subject) values (owner, p_subject)
  on conflict (owner_id, subject) do nothing;
  return true;
end;
$$;

revoke all on function public.review_notice(date) from public, anon;
grant execute on function public.review_notice(date) to authenticated, service_role;
revoke all on function public.resolve_review_notice(text) from public, anon;
grant execute on function public.resolve_review_notice(text) to authenticated, service_role;

commit;
