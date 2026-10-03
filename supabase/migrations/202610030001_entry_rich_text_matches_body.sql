-- Formatting is an optional view of the canonical plaintext body, valid only while
-- `body_rich.text` matches `body` exactly. Plaintext writers such as the focused Goal,
-- Moment, Period, First Time, Home, and Vehicle editors replace `body` without
-- formatting, so enforce the invariant on the table instead of in each writer. A save
-- that keeps the writing keeps its formatting; a save that changes it drops the
-- outdated formatted copy that search and export would otherwise still see.
create or replace function public.discard_stale_entry_rich_text()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.metadata ? 'body_rich'
    and new.metadata->'body_rich'->>'text' is distinct from new.body
  then
    new.metadata := new.metadata - 'body_rich';
  end if;
  return new;
end;
$$;

revoke all on function public.discard_stale_entry_rich_text() from public, anon, authenticated;

comment on function public.discard_stale_entry_rich_text() is
  'Removes Entry formatting whose plaintext no longer matches the canonical body.';

-- Same-timing triggers fire by name, so this runs after archive_entry_before_change
-- has archived the previous row and advanced the revision for the same write. It only
-- edits the new row, so it adds no revision or history version of its own.
create or replace trigger discard_stale_entry_rich_text
before insert or update on public.entries
for each row
execute function public.discard_stale_entry_rich_text();

comment on function public.review_wiki_item_with_photo_place(
  uuid, integer, text, text, text, text, timestamptz, text, text[], text[], boolean,
  timestamptz, text, text, jsonb
) is 'Reviews a Capture or same-Kind Wiki Item from a plaintext client while preserving rich metadata it cannot author for unchanged writing.';

-- Earlier plaintext saves left formatted copies of replaced writing behind. Readers
-- already ignore them, so removing them is maintenance rather than an edit: keep the
-- revision, update time, and history unchanged.
alter table public.entries disable trigger archive_entry_before_change;
update public.entries
set metadata = metadata - 'body_rich'
where metadata ? 'body_rich'
  and metadata->'body_rich'->>'text' is distinct from body;
alter table public.entries enable trigger archive_entry_before_change;

-- History snapshots are restored and exported as recorded. Each outdated copy repeats
-- writing an earlier version already holds, so keep every snapshot consistent too.
update public.entry_versions
set snapshot = jsonb_set(snapshot, '{metadata}', (snapshot->'metadata') - 'body_rich')
where jsonb_typeof(snapshot->'metadata') = 'object'
  and snapshot->'metadata' ? 'body_rich'
  and snapshot->'metadata'->'body_rich'->>'text' is distinct from snapshot->>'body';
