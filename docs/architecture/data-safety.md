# Data safety and recovery

MemoTrail will eventually contain irreplaceable personal writing and photos.
Cross-device synchronization is not a backup by itself.

## Application safeguards

- Deleting an Entry first sets `deleted_at` and moves it to Trash.
- Updating an Entry records the previous revision in `entry_versions`.
- Permanently deleting an Entry may remove its revision history and related media only after an explicit confirmation flow is designed.
- Original uploaded photos remain private and separate from optimized display derivatives.
- A Web capture is written to per-user browser storage before synchronization starts, and its pending copy is removed only after the server confirms the stable Entry ID.
- Browser drafts and pending Entries are protected by the browser and operating-system account boundary, but they are not separately end-to-end encrypted by MemoTrail.
- Clearing site data removes unsynchronized Web drafts and pending Entries, so users should reconnect and confirm the pending list is empty before clearing browser storage.

## Hosted database expectations

- Confirm the hosted Supabase plan's backup retention before storing irreplaceable production data.
- Enable point-in-time recovery before MemoTrail becomes the authoritative copy of personal history.
- Keep database migrations as the source of truth for schema recovery.
- Create encrypted logical exports on a regular schedule after production use begins.
- Store exports outside the active Supabase project and protect them with a separate account or recovery path.

## Recovery validation

- Test a full restore into a non-production project before calling the production setup complete.
- Verify that Entries, revision history, relationships, private media metadata, and authentication ownership remain intact.
- Verify several private media objects separately because database restoration does not prove Storage restoration.
- Repeat the restore exercise after material schema or backup-policy changes.

No production data should be treated as safely backed up until a restore has been completed and inspected end to end.
