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
- iOS stores drafts and pending Entries inside the app sandbox, retries when connectivity or foreground activity returns, and removes a pending copy only after the stable Entry ID is confirmed by the server.
- Deleting the iOS app removes unsynchronized drafts and pending Entries, so users should reconnect and confirm the pending list is empty before uninstalling or clearing app data.
- Entry review updates include the revision originally loaded by the client, so a newer edit from another client causes a conflict instead of a silent overwrite.
- Selecting `Done` changes organization state through a normal versioned Entry update and does not delete the Entry or its prior revision.
- Entry content, organization state, Collections, and tags are replaced through one owner-scoped database transaction so an error cannot leave a partially organized Entry.
- A stale revision returns before any Collection or tag relationship is changed.

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
