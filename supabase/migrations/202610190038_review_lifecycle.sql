-- What a review holds follows what it was made from, and what a switch governs follows the
-- switch.
--
-- Moving an Entry to Trash and restoring it change nothing stored: the read functions hide and
-- show. Deleting an Entry forever deletes every review that read it, because a stored review
-- holds the person's own words and an interpretation derived from the deleted writing, and
-- keeping either would break the promise that Delete forever means gone. It also stops any job
-- that was reading the Entry and discards that job's partial results, and deletes pending
-- suggestions based on it.
--
-- Turning reviews off deletes every saved review. Turning suggestions off deletes the pending
-- ones; dismissed and confirmed suggestions keep only their dates and name, so a dismissed
-- stretch never returns even after the switch is turned off and on.
--
-- Reviews and suggestions are the person's data, so a complete export includes them.

begin;

-- A before-delete trigger runs before the foreign keys cascade, so it still sees the sources.
create function public.discard_ai_work_for_deleted_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.entry_reviews as review
  using public.entry_review_sources as source
  where source.review_id = review.id
    and source.owner_id = old.owner_id
    and source.entry_id = old.id;

  update public.entry_reviews
  set job_status = 'failed',
      job_error = 'review_source_deleted',
      job_state = null,
      job_started_at = null
  where owner_id = old.owner_id
    and job_state is not null
    and job_state -> 'entryIds' ? old.id::text;

  delete from public.chapter_suggestions
  where owner_id = old.owner_id and status = 'pending' and old.id = any (source_entry_ids);

  return old;
end;
$$;

revoke all on function public.discard_ai_work_for_deleted_entry() from public, anon, authenticated;

create trigger entries_discard_ai_work
before delete on public.entries
for each row execute function public.discard_ai_work_for_deleted_entry();

-- Enforced in the database, like the semantic search index, so no path can leave reviews
-- behind a switch that is off.
create function public.apply_review_preferences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.reviews_enabled and not new.reviews_enabled then
    delete from public.entry_reviews where owner_id = new.owner_id;
  end if;
  if old.chapter_suggestions_enabled and not new.chapter_suggestions_enabled then
    delete from public.chapter_suggestions where owner_id = new.owner_id and status = 'pending';
    update public.chapter_suggestion_state set leased_until = null where owner_id = new.owner_id;
  end if;
  return null;
end;
$$;

revoke all on function public.apply_review_preferences() from public, anon, authenticated;

create trigger ai_preferences_apply_review_preferences
after update of reviews_enabled, chapter_suggestions_enabled on public.ai_preferences
for each row execute function public.apply_review_preferences();

create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','tags','entry_tags',
    'locations','entry_locations','attachments','entry_links',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects',
    'entry_reviews','entry_review_sources','chapter_suggestions'
  ]::text[];
$$;

commit;
