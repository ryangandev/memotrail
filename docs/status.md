# MemoTrail Status

Last reviewed: 2026-09-26.

## Current state

The Entry-centered Web information model was merged into `main` through PR #9, and its migration is live on the confirmed Supabase project.
Authored Place records have also been removed from Web and the hosted schema; Entry-owned Locations and the Map remain.
The obsolete Places Timeline track has been removed, with existing placements migrated to the general track.
The accepted compact Collection card is shared by the Web Design System and Collections overview.
The Web Map and Location previews now follow light, dark, and System appearance; a local provider-backed dark map loaded successfully.
The Map also offers filtered shortcuts to the user's most recorded cities when records span more than one city.
The desktop sidebar has a compact icon rail, panel control, and animated width change; its browser preference persists across reloads.
Library now combines the organized all-items browser with keyword and filtered search; older `/search` URLs redirect to Library.
Inbox review now hides AI suggestions and places photos after tags; the Library browser excludes unreviewed captures until Save to Library.
The accepted Data Ribbon layout now replaces Web Home, using the signed-in user's data and the shared capture, page, image, empty-state, and tag components.
The development preview routes and all 20 static Home mockups have been removed; Production deployment verification and browser acceptance remain pending.
Native iOS still uses the older Kind and subtype contract and needs a separate update before its write flows are compatible.
The merged Web release still needs Production deployment verification and browser acceptance; live configuration, native interactions, CI, and recovery evidence remain incomplete.

Use Git history for feature-level implementation and test evidence.

| Area                                                                              | State                                                                                                                                                                |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture, Inbox, organization, dates, drafts, and offline queues                   | Implemented on Web and iOS                                                                                                                                           |
| Timeline, Home, First Times, Homes, Vehicles, Goals, People, and Collections      | Implemented on Web and iOS; the native Place surface is legacy and needs a separate update                                                                           |
| Location data layer                                                               | Web Map, optional Home Location, photo GPS provenance, and provider quotas are implemented; personal browser acceptance remains.                                     |
| Habits                                                                            | Deferred and removed from the active Web, iOS, and hosted database product surface                                                                                   |
| Web navigation shell                                                              | Persistent across routes with prefetch, route fallback, and cold-request feedback                                                                                    |
| Web Settings                                                                      | Account, preferred name, dates, timezone, appearance, browser-local Timeline style, simplified AI, and account controls implemented                                  |
| Web Collections and tags                                                          | Direct Library destinations and shared Entry organization editor implemented                                                                                         |
| Keyword and Command Palette search, grounded AI, suggestions, and Explore with AI | Keyword search is visible in Library; Ask AI is temporarily absent from the search form. Production AI configuration is not accepted.                                |
| Private media, Entry history, relationships, Trash, and complete export           | Implemented; hosted APIs accepted with synthetic data; final UI acceptance remains                                                                                   |
| Hosted Supabase contracts                                                         | `202609240004` is deployed to project `kaivkozeyuwzqrckmyqu`; the remote ledger matches the repository                                                               |
| Entry-centered information model                                                  | Web `main` and hosted database use Entry, focused records, and intentional Timeline Moment or Period; native iOS still needs a separate cutover                      |
| Web design system                                                                 | Approved canonical components migrated across Web; component-owned CSS and token boundaries enforced; local regression passed; production browser acceptance pending |
| Backup and restore                                                                | Not ready                                                                                                                                                            |
| Current GitHub CI                                                                 | Blocked before jobs start by account billing or spending limits                                                                                                      |

The latest hosted synthetic run verified JPEG, HEIC, and PNG display derivatives, metadata extraction, unchanged originals, and a complete ZIP with all canonical datasets.
Its marked account and Storage objects were confirmed removed without accessing personal data or calling AI.

## Next work

### 1. Release and accept the Entry-centered Web flow

- Verify the merged `main` deployment against the migrated hosted project, then check Quick Capture, Inbox review, Library routing, First Time, Moment, Period, Home, Vehicle, and Goal in a browser.
- The Vercel Preview has no Supabase public environment variables, so browser acceptance will be done by Ryan in a configured environment.
- Keep native iOS writes out of this cutover until its older Kind and subtype calls are updated.
- The earlier Entry model passed 61 database files with 1,552 assertions and all 72 browser E2E tests. Place removal passed 59 database files with 1,497 assertions. The final Web typography pass passed 438 unit tests, 14 targeted browser E2E tests, lint, type checking, and a production build; the full browser suite has not been rerun for the merged head.
- A seeded pre-migration local exercise converted Journal, Story, and Trip to tags; Timeline point and span to Moment and Period; and preserved Inbox state and revision numbers.

### 2. Accept Web Location

- The confirmed hosted project `kaivkozeyuwzqrckmyqu` is migrated through `202609240004`; the linked migration ledger matches the repository. Home Location copy-on-write compares coordinates at the database's six-decimal storage precision.
- Web now has optional Home Locations, address search that feeds Entry-owned Location snapshots on save, keyboard-accessible address suggestions, explicit photo GPS source identity, owner-scoped Geoapify quotas, and a clustered Map of current Entry coordinates with Kind and year filters.
- Local Web and database validation for the merged changes is listed above.
- `localhost:3000` points to the linked cloud Supabase project. Its health endpoint returned 200, and an authenticated browser loaded Geoapify address suggestions, a selected coordinate preview, and the Map's raster tiles after migration; the test form was canceled without saving.
- Accept the revised UI with a personal `localhost:3000` record, including retrying a provider-backed Home Location save after the precision migration, Home removal/manual address edits, and Entry map points. Map clustering is locally browser-tested but not yet personally accepted against hosted data.
- The accepted shared SearchField is now used across Web search surfaces, including Location, Library search, Tags, related Items, organization pickers, and Command Palette.
- The server-only Production `GEOAPIFY_API_KEY` is configured in Vercel. The local key and provider-backed `localhost:3000` browser flow are verified; Production browser acceptance remains pending.
- Native iOS provider UI and its legacy custom Location fields remain deferred until Web acceptance.

### 3. Update and accept native Life Wiki UI

- Native iOS source was intentionally untouched during the Web redesign. Its Inbox and related write flows still send removed Writing, Event, Story, and Capture identities.
- A full simulator build and UI acceptance remain blocked until the local Xcode license is accepted.

### 4. Accept Production AI

- Set the Production Vercel values for `AI_PROVIDER`, server-only `AI_API_KEY`, `AI_CHAT_MODEL`, and `AI_TOTAL_BUDGET_USD`.
- Confirm the existing server-only `SUPABASE_SECRET_KEY` remains present.
- Redeploy and run `MEMOTRAIL_VERIFY_HOSTED_AI=1 node apps/web/scripts/verify-hosted-ai.mjs` with synthetic data.
- The last authenticated check returned HTTP 503 `provider_unavailable`; a valid local key does not configure Production.

### 5. Complete real interaction acceptance

- Verify an actual production browser export download.
- Verify native Save and share for a production export.
- Exercise authenticated native capture, photos, galleries, Trash, AI, and export through the real UI with an isolated account.
- Finish the remaining photo-surface and specialized metadata or relationship lifecycle audit.

The latest automated native UI attempt was blocked by the locked development Mac.

### 6. Establish recovery

- Choose separately protected destinations for database backups and original Storage objects.
- Decide whether to enable point-in-time recovery; the latest inventory showed PITR disabled and no listed restore point.
- Complete and inspect a full restore in a non-production project.
- Audit abandoned unregistered uploads before approving automatic retention cleanup.

### 7. Restore current CI evidence

- Resolve the GitHub account billing or spending-limit issue.
- Rerun all Web, iOS, and database jobs for current `main` and confirm they actually execute.

## Watch list

- A valid hosted media session previously returned intermittent HTTP 401 responses before a later run passed. Do not attribute recurrence to the decoder repair without evidence.
- Next.js may log a client-aborted React Server Components request while application assertions pass. Keep it distinct from a product failure until the stable upstream fix is adopted.

## Updating this file

Keep only current state, the next actionable work, and unresolved blockers.
Remove resolved details and rely on Git history instead of appending progress entries.
Product scope and deferred features belong in [product.md](./product.md).
