# MemoTrail Status

Last reviewed: 2026-09-16.

## Current state

MemoTrail's confirmed core scope is implemented across Web, native iOS, and shared Supabase contracts.
The product is not yet fully accepted for production because live configuration, real native and browser interactions, CI, and recovery evidence remain incomplete.

Use Git history for feature-level implementation and test evidence.

| Area                                                                                 | State                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture, Inbox, organization, dates, drafts, and offline queues                      | Implemented on Web and iOS                                                                                                                                                                                 |
| Timeline, Home, First Times, Homes, Vehicles, Goals, People, Places, and Collections | Implemented on Web and iOS                                                                                                                                                                                 |
| Habits                                                                               | Deferred; removed from Web, still present on iOS pending the native rework                                                                                                                                 |
| Web navigation shell                                                                 | Persistent across routes with prefetch, route fallback, and cold-request feedback                                                                                                                          |
| Web Settings                                                                         | Account, dates, timezone, appearance, simplified AI, and account controls implemented                                                                                                                      |
| Web Collections and tags                                                             | Direct Library destinations and shared Entry organization editor implemented                                                                                                                               |
| Keyword and Command Palette search, grounded AI, suggestions, and Explore with AI    | Implemented; Production AI configuration is not accepted                                                                                                                                                   |
| Private media, Entry history, relationships, Trash, and complete export              | Implemented; hosted APIs accepted with synthetic data; final UI acceptance remains                                                                                                                         |
| Hosted Supabase contracts                                                            | Deployed to the confirmed MemoTrail project                                                                                                                                                                |
| Capture First Life Wiki information model                                            | Database foundation, Web Inbox organizer, semantic Search, all-items Library, linked Goal extraction, and Inbox-to-Home specialized handoff implemented locally; broader Web and iOS adoption not complete |
| Backup and restore                                                                   | Not ready                                                                                                                                                                                                  |
| Current GitHub CI                                                                    | Blocked before jobs start by account billing or spending limits                                                                                                                                            |

Inbox-to-Vehicle and Inbox-to-Goal specialized form handoffs remain to be added using the same provenance-preserving extraction contract as Home.

The latest hosted synthetic run verified JPEG, HEIC, and PNG display derivatives, metadata extraction, unchanged originals, and a complete ZIP with all canonical datasets.
Its marked account and Storage objects were confirmed removed without accessing personal data or calling AI.

## Next work

### 1. Accept Production AI

- Set the Production Vercel values for `AI_PROVIDER`, server-only `AI_API_KEY`, `AI_CHAT_MODEL`, and `AI_TOTAL_BUDGET_USD`.
- Confirm the existing server-only `SUPABASE_SECRET_KEY` remains present.
- Redeploy and run `MEMOTRAIL_VERIFY_HOSTED_AI=1 node apps/web/scripts/verify-hosted-ai.mjs` with synthetic data.
- The last authenticated check returned HTTP 503 `provider_unavailable`; a valid local key does not configure Production.

### 2. Complete real interaction acceptance

- Verify an actual production browser export download.
- Verify native Save and share for a production export.
- Exercise authenticated native capture, photos, galleries, Trash, AI, and export through the real UI with an isolated account.
- Finish the remaining photo-surface and specialized metadata or relationship lifecycle audit.

The latest automated native UI attempt was blocked by the locked development Mac.

### 3. Establish recovery

- Choose separately protected destinations for database backups and original Storage objects.
- Decide whether to enable point-in-time recovery; the latest inventory showed PITR disabled and no listed restore point.
- Complete and inspect a full restore in a non-production project.
- Audit abandoned unregistered uploads before approving automatic retention cleanup.

### 4. Restore current CI evidence

- Resolve the GitHub account billing or spending-limit issue.
- Rerun all Web, iOS, and database jobs for current `main` and confirm they actually execute.

## Watch list

- A valid hosted media session previously returned intermittent HTTP 401 responses before a later run passed. Do not attribute recurrence to the decoder repair without evidence.
- Next.js may log a client-aborted React Server Components request while application assertions pass. Keep it distinct from a product failure until the stable upstream fix is adopted.

## Updating this file

Keep only current state, the next actionable work, and unresolved blockers.
Remove resolved details and rely on Git history instead of appending progress entries.
Product scope and deferred features belong in [product.md](./product.md).
