# MemoTrail Implementation Progress

> Current phase: Global keyword search
>
> Last updated: 2026-09-02
>
> Rule: Update this file in every commit and keep each feature in its own commit.

## Current status

- Phase 1 repository, design system, Web shell, iOS shell, local Supabase schema, RLS tests, and CI are complete.
- The production Web shell is reachable at `https://memotrail.ryangan.me`.
- Local Web and iOS clients contain matching ignored Supabase public configuration.
- Hosted Supabase Auth exposes Google as the only external provider.
- Google Web and iOS OAuth clients exist with the confirmed origins, callback, and bundle identifier.
- Vercel Production contains the public application URL, Supabase public configuration, and a server-only Supabase key.
- The linked hosted Supabase project contains all four reviewed repository migrations and no development seed users.
- The hosted atomic Entry review contract now supports content, Type, occurrence, Collection, tag, and `Done` updates in one transaction.
- Hosted verification found 21 Row Level Security-enabled application tables, 22 public policies, and a private `entry-media` bucket.
- Hosted schema lint passes, and the platform-created `SECURITY DEFINER` helper is no longer executable by client roles.
- Web now uses cookie-based Supabase SSR sessions, a Next.js 16 Proxy refresh path, Google OAuth, a safe callback, and explicit sign-out and setup states.
- Browser verification reached Google's account page with the expected Web client and hosted Supabase callback on both desktop and iPhone-sized layouts.
- Web authentication redirect safety now has an executable unit-test suite instead of a no-op repository test command.
- iOS now uses the native Google SDK, exchanges a nonce-bound ID token with Supabase, restores sessions, and supports explicit local sign-out.
- Simulator verification covered build, launch, light and dark appearance, the native authorization prompt, and cancellation recovery without using a real account.
- The user confirmed the same real Google account passes Web and iOS login, session restoration, and sign-out, and that Supabase allows both client IDs in the required order.
- Web now reads the authenticated user's real unreviewed Entries and saves validated title/body captures directly to hosted Supabase through an authenticated Server Action.
- iOS now reads and saves the same authenticated unreviewed Entry shape through Supabase, with native loading, empty, retry, refresh, validation, and save feedback states.
- The user confirmed localhost, production Web, and the iOS simulator can all sign in, create Entries, and see the same Entries across clients.
- Web and iOS now continuously preserve per-user local Inbox drafts, restore them after refresh or relaunch, and clear them only after a successful Entry save.
- Web now accepts a capture into a per-user local synchronization queue before making a network request, displays pending Entries, retries on reconnect or demand, and uses stable Entry IDs for idempotent server confirmation.
- iOS now accepts captures into the same durable queue model, visibly separates pending Entries, and retries on reconnect, foreground activation, refresh, or demand.
- Web now opens each unreviewed Entry in a focused review surface where title, body, exact occurrence time, and the initial Standard or First Time Type can be edited before saving or selecting `Done`.
- Web review updates require the Entry's current revision, so a newer cross-device edit produces a visible conflict instead of being silently overwritten.
- iOS now provides the matching native review sheet, editable fields, optimistic revision check, `Save changes`, and explicit `Done` behavior.
- The local database now passes 49 pgTAP tests plus schema lint, including atomic organization, keyword search, bilingual substring matching, structured fields, filters, history, and cross-owner denial.
- Web review now loads existing Entry relationships and available names, displays Collection and tag chips, and atomically replaces them alongside Entry content and `Done` state.
- Web now has 35 passing tests, including organization-name normalization, case-insensitive de-duplication, and limits.
- iOS now loads the same Collection and tag relationships, offers removable chips and existing-name choices, and uses the shared atomic organization RPC for Save and Done.
- The shared iOS scheme now has 19 passing native tests, including organization normalization and explicit null encoding for body-only RPC reviews.
- Hosted verification confirms the atomic review migration is recorded remotely, schema lint reports no errors, the function uses an empty `search_path`, PUBLIC execution is revoked, and only authenticated users receive execution access.
- A locally verified search contract now finds non-Trash Entries across titles, bodies, Collections, tags, occurrence dates, Types, metadata, and specialized Entry fields while returning match reasons and filter support.
- Keyword date matching and filtering use each Entry's preserved occurrence timezone, with a safe UTC fallback for invalid legacy values.
- Hosted verification confirms the keyword search migration, optimized indexes, empty function search paths, authenticated-only execution grants, and a warning-free public schema.
- Web now exposes authenticated global keyword search at `/search` with durable URL parameters, Type, Collection, tag, and date filters, match explanations, and 25-result pagination.
- The Web Inbox and Search routes now share one responsive application shell, with working Search and Inbox navigation plus a global `Command-K` or `Control-K` search shortcut.
- The Web suite now has 42 passing tests, including seven search-request tests for normalization, validation, pagination, and URL preservation.
- Synthetic local browser verification covered a real database result, empty and result states, desktop and iPhone-sized layouts, shortcut focus, accessible mobile naming, and a warning-free browser console.
- iOS now exposes the same global search contract through a native Search tab with keyword, Type, Collection, tag, start-date, and end-date criteria.
- Native search results preserve Entry Type, Inbox state, local occurrence date, Collections, tags, database match explanations, full Entry reading, and incremental 25-result pagination.
- The shared iOS scheme now has 28 passing native tests, including search normalization, limits, date-only RPC parameters, pagination, response decoding, preserved time zones, and invalid legacy time-zone fallback.
- The user confirmed keyword and filtered searches return the expected real Entries across Web and iOS.
- A locally verified Timeline contract now returns empty and populated tracks, creates or revision-safely edits Stage and Event Entries, preserves overlapping and open-ended periods, and moves Timeline Entries to Trash without losing history.
- The local database now passes 82 pgTAP tests plus schema lint, including 33 focused Timeline tests for date rules, track movement, optimistic conflicts, hidden tracks, Trash, and owner isolation.
- Hosted verification confirms the Timeline migration, aligned five-migration ledger, warning-free schema, empty function search paths, authenticated-only execution grants, and no seed or role deployment.
- AI selection and configuration are deferred and do not block authentication, capture, keyword search, or synchronization work.

## Active acceptance criteria

### Hosted data foundation

- [x] Apply only version-controlled migrations to the confirmed hosted Supabase project.
- [x] Do not apply synthetic development seed data.
- [x] Verify profiles, Entries, history, default timeline tracks, private Storage, grants, and RLS after deployment.

### Web Google authentication

- [x] A signed-out user can start Google Sign-In from MemoTrail.
- [x] The OAuth callback creates a secure server-managed session and returns to MemoTrail.
- [x] A signed-in user sees their real account identity and can sign out.
- [x] Localhost and the production domain use their own allowed callback URLs.
- [x] Missing public configuration produces an explicit setup state without exposing secrets.
- [x] Unit tests reject external callback destinations and verify production-origin fallback behavior.

### iOS Google authentication

- [x] A signed-out user can start native Google Sign-In.
- [x] The Google ID token is exchanged for the same Supabase identity model used by Web.
- [x] The session survives a normal app relaunch and can be explicitly signed out.
- [x] The app contains public client configuration only.
- [x] Simulator build and launch remain warning-free before physical-device verification.

### Synchronized Inbox Entry

- [x] Web requires a valid session again inside its capture mutation.
- [x] Web accepts an optional title, a body, or both and validates length on the server.
- [x] Web inserts each capture as a standard unreviewed Entry with separate creation and occurrence timestamps.
- [x] Web lists only the signed-in user's unreviewed, non-Trash Entries through RLS and exposes loading, empty, and error states.
- [x] Web capture parsing has unit coverage for body-only, title-only, empty, and oversized submissions.
- [x] iOS saves and lists the same Entry shape through the authenticated Supabase client.
- [x] A real Entry created on one client is visible on the other after refresh.

### Recoverable Inbox draft

- [x] Web preserves the exact title and body locally for the current MemoTrail user.
- [x] iOS preserves the exact title and body locally for the current Supabase user ID.
- [x] Refreshing, navigating away, or relaunching restores an unfinished draft without exposing it to another signed-in user.
- [x] A failed or rejected save leaves the draft intact.
- [x] A successful Entry save clears the local draft.
- [x] Malformed, obsolete, and oversized stored draft payloads fail safely.

### Offline capture and synchronization queue

- [x] Web accepts a valid Entry into durable per-user local storage before attempting synchronization.
- [x] Web visibly lists pending Entries and provides a manual retry action.
- [x] Web automatically retries its queue when a connection returns or the authenticated workspace reloads online.
- [x] Web gives each queued Entry a stable UUID and safely confirms a retry after an ambiguous successful insert.
- [x] Web preserves the original capture time and device time zone when synchronization happens later.
- [x] iOS accepts a valid Entry into durable per-user device storage before attempting synchronization.
- [x] iOS visibly lists pending Entries and provides a manual retry action.
- [x] iOS automatically retries its queue when connectivity returns, the app becomes active, or the Inbox refreshes.
- [x] iOS gives each queued Entry a stable UUID and safely confirms a retry after an ambiguous successful insert.
- [x] iOS preserves the original capture time and device time zone when synchronization happens later.
- [x] Both clients keep a failed queue item until synchronization is confirmed and retain the editable draft if local queue persistence fails.

### Entry review and explicit Done

- [x] Web opens an unreviewed Entry in an editable review surface.
- [x] Web review supports title, body, exact occurrence time, Standard Entry, and First Time.
- [x] `Save changes` preserves the unreviewed Inbox state.
- [x] `Done` marks the Entry organized and removes it from the Inbox without preventing later edits elsewhere.
- [x] Web review uses optimistic revision matching and leaves the database history trigger responsible for preserving the previous version.
- [x] iOS provides the matching review, conflict, save, and explicit Done behavior.
- [x] Web and iOS display the initial Standard Entry and First Time Type choices consistently.
- [x] Both clients preserve the original time zone unless the occurrence date is edited locally.
- [x] Web review loads and displays the Entry's current Collections and tags.
- [x] Web review supports removable chips, existing-name suggestions, and creation of new Collection or tag names.
- [x] Pending text in an organization field is included when Save or Done is selected, even before Enter is pressed.
- [x] iOS provides the matching manual Collection and tag editing behavior.
- [x] iOS includes a typed new-name field, removable chips, existing-name choices, count limits, and pending text in Save or Done.
- [x] Both clients submit content, Type, occurrence, Collections, tags, and Done state through the same atomic database contract.

### Atomic Entry organization

- [x] One authenticated database function updates Entry content, Type, exact occurrence, Collections, tags, and Inbox status in a single transaction.
- [x] Collection and tag names are trimmed, case-insensitively de-duplicated, length-limited, and scoped to the authenticated owner.
- [x] A stale revision or inaccessible Entry returns no result before any relationship changes occur.
- [x] Local pgTAP coverage verifies atomic review, immutable history, `Done`, duplicate names, and cross-owner denial.
- [x] Local schema lint reports no errors.
- [x] Apply the atomic review migration to hosted Supabase after explicit rollout approval.
- [x] Verify the hosted migration ledger, schema lint, function search path, and execution grants after rollout.

### Keyword Entry search contract

- [x] Search only the authenticated owner's non-Trash Entries.
- [x] Match titles, bodies, Collections, tags, local occurrence dates, Types, metadata, and specialized Entry fields.
- [x] Support English full-text matching and exact bilingual substring matching for Chinese or mixed-language content.
- [x] Return an ordered explanation of the fields that matched.
- [x] Support Type, Collection, tag, and inclusive date-range filters through the shared database contract.
- [x] Apply input, pagination, and organization-filter limits before executing a search.
- [x] Verify content matches, filters, local dates, structured fields, Trash exclusion, owner isolation, and unauthenticated denial with 21 pgTAP tests.
- [x] Apply and verify the keyword search migration on hosted Supabase.

### Web keyword search

- [x] Require the same authenticated server session as the Inbox before loading search data.
- [x] Keep the query and every filter in the URL so searches survive refresh and pagination.
- [x] Offer Type, Collection, tag, start-date, and end-date filters through one compact search surface.
- [x] Display Entry Type, Inbox state, local occurrence date, Collections, tags, and database-provided match reasons for every result.
- [x] Expose idle, no-result, validation-error, unavailable-filter, and search-error states without confusing them.
- [x] Paginate large result sets while preserving the complete search request.
- [x] Open Search from the shared sidebar, mobile top bar, or `Command-K` and `Control-K`, with the search field focused.
- [x] Verify search parsing with seven unit tests and inspect real local results at desktop and iPhone viewport sizes without console warnings.

### iOS keyword search

- [x] Add Search as a first-class native tab backed by the shared authenticated `search_entries` RPC.
- [x] Support keyword, Type, Collection, tag, inclusive start-date, and inclusive end-date criteria.
- [x] Load Collection and tag choices from the signed-in owner's live organization data without preventing keyword-only search when they are unavailable.
- [x] Display Entry Type, Inbox state, preserved local occurrence date, organization, and database-provided match reasons.
- [x] Open a native detail destination for the full Entry body and organization.
- [x] Load additional results in 25-Entry pages without duplicating rows.
- [x] Expose idle, loading, empty, validation-error, filter-warning, search-error, and incremental-loading states.
- [x] Verify native request normalization, parameter encoding, response decoding, date handling, and pagination limits with nine focused tests.
- [x] Confirm keyword and filtered searches against the same real Entries on Web and iOS.

### Timeline data contract

- [x] Return every visible owned Timeline track, including empty tracks, through one authenticated read contract.
- [x] Create organized Stage and Event Entries and their track relationships in one transaction.
- [x] Support open-ended or bounded stages, point events, date precision, human date labels, and preserved occurrence time zones.
- [x] Revision-safely edit content, occurrence, kind, and track without partially applying stale changes.
- [x] Preserve Entry history during Timeline edits and moves to Trash.
- [x] Exclude Trash and other owners' data from the Timeline workspace.
- [x] Verify the Timeline contract with a fresh local database, 33 focused pgTAP tests, and schema lint.
- [x] Apply and verify the Timeline contract on hosted Supabase.

## Feature history

- `docs: define MemoTrail product direction` established the evolving product contract.
- `docs: approve MemoTrail phase one foundation` approved the implementation stack and boundaries.
- `chore: scaffold MemoTrail monorepo and web app` created the pnpm/Turborepo and Next.js foundation.
- `feat: establish Soft Ledger design system` generated shared Web and Swift design tokens.
- `feat: add native SwiftUI app foundation` created the buildable native iOS shell.
- `feat: add secure Supabase foundation` added the schema, RLS, private Storage, seed, tests, and CI.
- `fix: make web typecheck independent of build` fixed clean-checkout CI type generation.
- `docs: update credential setup checklist` recorded the first verified external credential setup.
- `docs: establish implementation progress tracking` verified production configuration and established commit-by-commit progress tracking.
- `feat: deploy hosted Supabase foundation` deployed and verified the hosted data foundation without seed data.
- `feat: add Web Google authentication` implemented secure Web sessions and the signed-out experience.
- `feat: add iOS Google authentication` implemented native sessions and the signed-out experience.
- `test: cover Web authentication redirects` added executable redirect-safety tests.
- `feat: add synchronized Web Inbox entries` implemented authenticated Web capture and listing.
- `feat: add synchronized iOS Inbox entries` implemented authenticated iOS capture, listing, and native rule coverage.
- `feat: preserve recoverable Inbox drafts` implemented per-user recoverable Inbox drafts on Web and iOS.
- `feat: add Web offline capture queue` implemented the Web offline capture and retryable synchronization queue.
- `feat: add iOS offline capture queue` implemented the matching iOS offline capture and retryable synchronization queue.
- `feat: add Web Inbox review` implemented Web Entry review and explicit `Done` organization.
- `feat: add iOS Inbox review` implemented the matching iOS Entry review and explicit `Done` organization.
- `feat: add atomic Entry organization` added and locally verified the atomic database contract for manual Entry organization.
- `feat: add Web Entry organization` implemented manual Collections and tags in Web Entry review.
- `feat: add iOS Entry organization` implemented the matching manual Collection and tag review controls on iOS.
- `feat: deploy atomic Entry organization` deployed and verified the atomic Entry organization contract on hosted Supabase.
- `feat: add keyword Entry search` added and locally verified the shared database-backed keyword Entry search contract.
- `feat: deploy keyword Entry search` deployed and verified the keyword Entry search contract and supporting indexes on hosted Supabase.
- `feat: add Web keyword search` implemented the authenticated Web keyword search experience and shared application shell.
- `feat: add iOS keyword search` implemented the matching native iOS keyword search experience.
- `feat: add Timeline data contract` implemented and locally verified the initial owner-scoped Timeline data contract.
- Current change: deployed and verified the Timeline data contract on hosted Supabase.

## Next sequence

1. Add the basic Web Timeline experience.
2. Add the matching native iOS Timeline experience.

## Deferred

- AI provider selection and AI-assisted organization.
- Preview or staging OAuth configuration until a stable Preview strategy is chosen.
- Sign in with Apple and App Store distribution.
- Production data import, DNS changes, and any destructive remote migration.
