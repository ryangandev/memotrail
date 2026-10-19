-- Two opt-in switches and one recorded consent. Chapter and year reviews and Chapter
-- suggestions each have their own switch, and both depend on the person having accepted the
-- disclosure of what is sent to the provider. The version of the disclosure they saw is
-- stored with the time they accepted it, so a change to the text can ask again.
--
-- The saved preferences of the paused AI features are not touched: existing rows keep their
-- values, and a row created for reviews does not switch on the paused features.

begin;

alter table public.ai_preferences
  add column reviews_enabled boolean not null default false,
  add column chapter_suggestions_enabled boolean not null default false,
  add column review_disclosure_version text
    check (review_disclosure_version is null or review_disclosure_version ~ '^\d{4}-\d{2}-\d{2}$'),
  add column review_disclosure_accepted_at timestamptz,
  add constraint ai_preferences_review_consent check (
    (not reviews_enabled and not chapter_suggestions_enabled) or review_disclosure_version is not null
  );

alter table public.ai_preferences
  alter column classification set default false,
  alter column tagging set default false,
  alter column search set default false,
  alter column explore set default false;

-- Saves the two switches and, when the person just accepted a disclosure, its version. The
-- expected revision is the revision the person last read, so a save from a stale screen is
-- refused with null. Turning a switch off deletes what it governs (the preference trigger
-- in the lifecycle file). Replaced at the end of the suggestions file to return the settings.
create function public.save_review_preferences(
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
  saved_revision integer;
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
    )
    returning revision into saved_revision;
  else
    update public.ai_preferences
    set reviews_enabled = p_reviews,
        chapter_suggestions_enabled = p_suggestions,
        review_disclosure_version = coalesce(p_disclosure_version, review_disclosure_version),
        review_disclosure_accepted_at = case when p_disclosure_version is null then review_disclosure_accepted_at else now() end,
        revision = revision + 1,
        updated_at = now()
    where owner_id = owner
    returning revision into saved_revision;
  end if;

  return jsonb_build_object('revision', saved_revision);
end;
$$;

revoke all on function public.save_review_preferences(boolean, boolean, text, integer) from public, anon;
grant execute on function public.save_review_preferences(boolean, boolean, text, integer) to authenticated, service_role;

commit;
