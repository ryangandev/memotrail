# MemoTrail Implementation Progress

> Current phase: Web Goals experience
>
> Last updated: 2026-09-03
>
> Rule: Update this file in every commit and keep each feature in its own commit.

## Current status

- Phase 1 repository, design system, Web shell, iOS shell, local Supabase schema, RLS tests, and CI are complete.
- The production Web shell is reachable at `https://memotrail.ryangan.me`.
- Local Web and iOS clients contain matching ignored Supabase public configuration.
- Hosted Supabase Auth exposes Google as the only external provider.
- Google Web and iOS OAuth clients exist with the confirmed origins, callback, and bundle identifier.
- Vercel Production contains the public application URL, Supabase public configuration, and a server-only Supabase key.
- The linked hosted Supabase project contains all twelve reviewed repository migrations and no development seed users.
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
- Hosted First Times verification confirms the read and mutation functions, empty search paths, authenticated-only execution grants, and private attachment contract are deployed.
- Hosted schema inspection identified and corrected legacy authenticated table grants that exceeded the intended Row Level Security CRUD surface.
- Hosted authenticated table privileges are now limited to Select and Update for profiles, Select for Entry history and attachments, and RLS-managed CRUD for the remaining application tables.
- Web now exposes Timeline as a first-class authenticated destination with all visible tracks, overlapping Stage ranges, point Events, human date labels, and responsive desktop and mobile presentations.
- Web Timeline supports track-specific creation, revision-safe editing, track and kind changes, open-ended or bounded stages, preserved occurrence time zones, and recoverable moves to Trash.
- The Web suite now has 57 passing tests, including Timeline input normalization, cross-time-zone calendar conversion, padded date bounds, open stages, and overlap lane assignment.
- Synthetic localhost browser verification covered empty tracks, a multi-year Stage, a First Time Event, a revision-safe edit, desktop layout, accessible controls, and error-free server requests.
- iOS now exposes the same Timeline workspace as a first-class native tab with track-first browsing, empty-track actions, chronological moments, and native pull-to-refresh behavior.
- The native Timeline editor creates or revision-safely edits Stage and Event content, track placement, open or bounded occurrence dates, precision, human labels, and preserved occurrence time zones.
- Native Timeline Entries can move to Trash through an explicit confirmation while retaining the shared database history and conflict behavior.
- The shared iOS scheme now has 38 passing tests, including ten Timeline tests for workspace decoding, stable sorting, display dates, validation, and explicit RPC null encoding.
- The native Timeline implementation passes a warning-free generic Simulator build and the full suite on an iPhone 17 Pro simulator.
- The locally verified First Times contract supports lightweight direct creation, revision-safe editing, organization, private photo registration, and recoverable removal.
- The local database now passes 129 pgTAP tests plus schema lint, including 43 focused First Times and private media tests plus exact authenticated table-grant coverage.
- Web now exposes First Times as a dedicated authenticated archive with photo-forward and text-first cards, lightweight direct creation, revision-safe editing, and recoverable Trash actions.
- Web First Times uploads originals directly to the owner's private Storage path, registers metadata only after upload, uses expiring signed URLs for display, and retries failed photo attachment without losing saved content.
- The Web suite now has 68 passing tests, including First Time content, organization, date precision, identity, MIME type, file-size, and private object-path validation.
- Synthetic localhost browser verification covered creation, Collections and tags, an exact local date, private PNG upload, signed image display, revision-safe editing, desktop layout, and an iPhone-sized responsive layout.
- iOS now exposes First Times as a dedicated native archive with dated and unknown-date cards, photo covers, Collections, tags, pull-to-refresh, and one-hour signed private image URLs.
- The native First Time editor supports title-only creation, optional and imprecise dates, human labels, reflection, organization, multi-photo selection, preview, revision-safe edits, and recoverable Trash actions.
- Native photo uploads preserve supported originals, validate file signatures and picker metadata, use owner-scoped private paths, register only after upload, and retain failed selections for retry without losing saved content.
- The shared iOS scheme now has 51 passing tests, including 13 First Times tests, and passes a warning-free generic Simulator build.
- A locally verified Collections contract now returns every active owned Collection, including empty ones, with active Entry counts, Inbox counts, stable ordering, and recency.
- Collection detail returns paginated non-Trash Entries with Types, occurrence context, full organization, and active private attachment metadata while enforcing owner isolation.
- The local database now passes 164 pgTAP tests plus schema lint, including 35 focused Collections tests and a data-independent First Times suite that tolerates existing local records.
- Hosted verification confirms the Collections migration, aligned eight-migration ledger, warning-free schema, authenticated-only execution grants, empty function search paths, and both supporting indexes.
- Web now exposes Collections as a first-class authenticated destination with every active Collection, Entry and Inbox counts, stable ordering, and empty-Collection states.
- Web Collection detail preserves complete Entry text, Type, occurrence context, Inbox state, every Collection and tag, and expiring private image URLs across paginated routes.
- The Web suite now has 74 passing tests, including Collection identifier, page, and stable pagination-link validation.
- Authenticated localhost browser verification covered the overview, a Collection deep link, private signed image display, desktop and narrow responsive layouts, complete mobile navigation, and an error-free application console.
- iOS now exposes Collections as a first-class native tab with stable archive ordering, Entry and Inbox counts, recency, empty states, and pull-to-refresh behavior.
- Native Collection detail supports complete Entry reading, Types, occurrence context, Inbox state, every Collection and tag, one-hour signed private image URLs, and incremental 25-Entry pagination.
- The shared iOS scheme now has 61 passing tests, including ten focused Collections tests, and passes a warning-free generic Simulator build.
- The current native build installs and launches on an iPhone 17 Pro simulator while preserving the existing signed-out authentication gate.
- Native navigation now groups Collections and First Times under one Library tab, leaving room for Habits as a future primary destination without overflowing the iPhone tab bar.
- Library exposes only implemented archives as interactive routes while keeping Goals, Vehicles, Places, and People visibly marked as planned.
- First Times and Collections can render inside the shared Library navigation stack without nested navigation containers or duplicated feature implementations.
- The shared iOS scheme now has 65 passing tests, including four Library destination-contract tests, and the refactored app passes a warning-free generic Simulator build.
- The locally verified Habits contract supports check-off and measured Habits, daily, selected-weekday, weekly-target, and interval schedules, revision-safe definitions and occurrences, recoverable Trash, and immutable history.
- Habit workspaces derive pending and not-scheduled states for one local date, while the yearly calendar distinguishes completed, skipped, missed, pending, upcoming, and not-scheduled dates without storing synthetic misses.
- The local database now passes 213 pgTAP tests plus warning-free schema lint, including 49 focused Habits tests for schedule validation, creation, measurement rules, occurrence correction, optimistic conflicts, history, Trash, access boundaries, and function hardening.
- Hosted verification confirms the Habits migration, aligned nine-migration ledger, warning-free schema, empty function search paths, authenticated-only execution grants, RLS-enabled history, least-privilege table grants, and supporting indexes.
- Web now exposes Habits as a first-class authenticated destination with Check and Measure modes, selected-date check-ins, all four shared schedule types, revision-safe corrections, notes, editing, and recoverable Trash actions.
- The selected Habit includes a full-year contribution calendar and current streak, longest streak, completion, missed, and intentional-skip statistics without treating skips as failures.
- The Web suite now has 93 passing tests, including 19 focused Habits tests for input normalization, request parsing, date handling, statistics, and calendar placement.
- Isolated localhost browser verification covered Check completion and correction, a measured value with notes, a preserved occurrence across a schedule edit, responsive presentation, and a warning-free application console without touching hosted user data.
- iOS now exposes Habits as a primary native tab with Check and Measure creation, all four schedules, selected-date check-ins, quick completion, notes, revision-safe corrections, editing, and recoverable Trash actions.
- Native Habit history includes a compact twelve-month calendar, tappable eligible dates, current and longest streaks, completion rate, misses, and intentional skips with shared status semantics.
- The shared iOS scheme now has 78 passing tests, including 13 focused Habits tests for decoding, schedule JSON, input rules, date-only handling, explicit RPC nulls, and analytics.
- The native Habits implementation passes strict Swift formatting, project-file validation, a warning-free generic Simulator build, and the full suite on an iPhone 17 Pro simulator.
- The locally verified Trash contract combines deleted Entries, Habits, and individually removed photos in one owner-scoped paginated feed with thirty-day retention deadlines.
- Trash restoration matches the latest revision and deletion timestamp, preserves a recoverable version, and prevents nested photo restoration while its parent Entry remains deleted.
- Permanent deletion requires the same optimistic state, exposes every private Storage path for client removal first, cascades relational data, and removes version history under the approved deletion policy.
- The local database now passes 270 pgTAP tests plus warning-free schema lint, including 57 focused Trash tests for pagination, titles, retention, media paths, restoration, history, permanent deletion, grants, and owner isolation.
- Hosted verification confirms the Trash migration, aligned ten-migration ledger, warning-free schema, empty function search paths, authenticated-only execution grants, hardened definer boundaries, and unchanged least-privilege table grants.
- Web now exposes Trash as an authenticated archive for removed Entries, Habits, and individual photos with signed private thumbnails, per-item retention dates, and stable pagination.
- Web restoration and permanent deletion submit the current revision and deletion timestamp, surface cross-device conflicts, and require explicit confirmation before an irreversible action.
- Permanent Web deletion verifies every returned private object path, removes private Storage objects before database metadata, and revalidates every affected archive route.
- Desktop navigation places Trash under Archive while the compact header exposes it without overflowing the five-item mobile tab bar.
- The Web suite now has 101 passing tests, including eight focused Trash input tests for kinds, identifiers, timestamps, revisions, page parsing, and pagination links.
- Isolated localhost Chrome verification covered the populated desktop and mobile layouts, signed private image display, Entry restoration, permanent Habit deletion, permanent photo deletion, and confirmed database and private Storage cleanup without application or server errors.
- iOS now exposes Trash inside Library with the same unified Entry, Habit, and individual-photo feed, signed private thumbnails, exact per-item retention context, and incremental pagination.
- Native restore and permanent deletion preserve the shared optimistic revision and deletion-time contract, validate owner-scoped Storage paths, remove private objects first, and require explicit destructive confirmation.
- The shared iOS scheme now has 85 passing tests, including seven focused Trash tests for decoding, composite identity, timestamp precision, retention, pagination, and mutation encoding.
- The native Trash implementation passes strict Swift formatting, project validation, a warning-free generic Simulator build, the full suite on an iPhone 17 Pro simulator, and an install-and-launch check without bypassing authentication.
- The locally verified Home contract now returns one owner-scoped snapshot with Inbox, Entry, First Time, Collection, and active Habit counts.
- Home derives the requested local day's due, completed, and skipped Habit progress without storing synthetic states, and finds current visible Timeline stages using the device time zone.
- Home returns recent non-Trash Entries with organization and private attachment metadata plus current stage context for shared Web and iOS presentation.
- The local database now passes 306 pgTAP tests plus warning-free schema lint, including 36 focused Home tests for counts, ordering, time zones, visibility, input limits, grants, and function hardening.
- Hosted verification confirms the Home migration, aligned eleven-migration ledger, warning-free schema, authenticated-only execution, invoker security, empty function search path, and supporting partial index.
- Web now opens on an authenticated Home workspace with a local-time greeting, inline capture, Inbox and archive counts, today's Habit progress, current Timeline chapters, and recent Entries with organization and signed private photos.
- Inbox now has a durable `/inbox` route, while responsive navigation presents Home, Inbox, Timeline, Habits, and Library as the five mobile destinations and retains full desktop access to Search and archive areas.
- A shared Quick Capture dialog is available from every non-Home and non-Inbox workspace, with a focused desktop modal and full-screen mobile presentation backed by the existing offline-first queue.
- The browser's IANA time zone is stored as a non-sensitive cookie so server-rendered Home dates, Habit progress, and Timeline ranges follow the device without weakening session security.
- The Web suite now has 106 passing tests, including five focused Home date, time-zone, and greeting tests, and continues to pass formatting, design-token, lint, typecheck, and production-build checks.
- Authenticated localhost browser verification covered populated Home data, a global Library capture synchronized into Home, desktop and iPhone layouts, the exact five-item mobile navigation, the full-screen capture dialog, and an error-free browser console.
- iOS now opens on a native Home workspace with a device-local greeting, shared inline capture, Inbox and archive counts, today's Habit progress, current Timeline chapters, and recent Entries with one-hour signed private photos.
- Native navigation now uses Home, Inbox, Timeline, Habits, and Library as the exact five primary tabs, keeps Search inside Home, and exposes the current Inbox count as a tab badge.
- Home, Inbox, and the global full-screen composer share one draft and one offline synchronization queue instead of mounting competing capture state.
- Timeline, Habits, and Library expose the global native Quick Capture action, while Home and Inbox retain their integrated capture surfaces.
- The shared iOS scheme now has 95 passing tests, including ten focused Home and root-navigation tests, and passes strict Swift formatting, project validation, and a warning-free generic Simulator build.
- Web universal capture now accepts an optional exact relevant date and time, preserves it in the recoverable local draft, and otherwise records the actual capture instant as before.
- Existing version-one Web text drafts migrate in place without inventing a historical date, while every queued Entry continues to preserve one immutable occurrence instant and the browser's IANA time zone.
- The Web suite now has 111 passing tests, including five focused capture-date and draft-migration tests, and passes formatting, design-token, lint, typecheck, and production-build checks.
- Isolated localhost browser verification covered a dated draft across reload, synchronization to the exact expected instant and time zone, desktop Home, the full-screen mobile composer, and cleanup of the disposable account.
- Native universal capture now offers the same optional exact relevant date and time from Home, Inbox, Timeline, Habits, and Library while retaining the actual capture instant by default.
- The shared iOS draft preserves the optional date across every capture surface and continues to decode existing text-only drafts with no invented occurrence date.
- A native dated capture freezes the selected occurrence instant and current IANA time zone when it enters the existing offline queue, independently from its later synchronization time.
- The shared iOS scheme now has 96 passing tests and the dated capture implementation passes strict Swift formatting, project validation, a warning-free generic Simulator build, and an install-and-launch smoke check.
- The locally verified universal Entry media contract now idempotently registers an uploaded private image against any active owned Entry, not only a First Time.
- Universal attachment registration validates the owner and Entry path, supported image MIME type, 50 MB limit, optional dimensions, original filename, existing Storage object, and conflict identity before writing metadata.
- Any active Entry photo can now move to recoverable Trash without deleting its private object, while registration and removal stay behind authenticated-only hardened definer boundaries.
- The local database now passes 335 pgTAP tests plus warning-free schema lint, including 29 focused universal media tests for grants, paths, metadata, idempotency, ownership, Trash, and anonymous denial.
- Hosted Supabase now contains the universal Entry media migration with an aligned twelve-migration ledger and warning-free public and extensions schema lint.
- Hosted schema inspection confirms both universal media functions use empty-search-path definer boundaries, are executable only by authenticated users, and do not broaden direct client attachment-table writes.
- Web universal capture now accepts up to twelve private JPEG, PNG, WebP, HEIC, or HEIF originals from Home, Inbox, and every global Quick Capture surface.
- Selected Web photos are written to owner-scoped IndexedDB before they appear as recoverable draft media, survive a browser reload, and remain separate from already queued photos.
- Web photo queues preserve stable Entry and attachment identities, synchronize the Entry first, upload each original to its deterministic private Storage path, and idempotently register metadata before clearing local data.
- Existing version-one text queues migrate to the photo-capable version-two shape without data loss, while photo-only Entries are now valid captures.
- The Web suite now has 118 passing tests, and the universal photo implementation passes formatting, design-token, lint, typecheck, and production-build checks.
- Isolated localhost browser verification covered a photo draft across reload, deliberate offline queueing, automatic reconnect synchronization, one database Entry and attachment, signed Home image display, responsive desktop and mobile presentation, and disposable-account cleanup.
- Native universal capture now accepts up to twelve private JPEG, PNG, WebP, HEIC, or HEIF originals from Home, Inbox, and every global Quick Capture surface.
- Selected iOS photos are protected in owner-scoped Application Support storage before appearing in the shared recoverable draft, survive relaunch, and remain separate from already queued photos.
- Native photo queues preserve stable Entry and attachment identities, synchronize the Entry first, upload each original to its deterministic private Storage path, and idempotently register metadata before clearing local data.
- Existing version-one native text queues migrate to the photo-capable version-two shape without data loss, while photo-only Entries are now valid captures.
- The shared iOS scheme now has 102 passing tests, and the universal photo implementation passes strict Swift formatting, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.
- The locally verified Home resurfacing contract now returns at most one owner-scoped, organized memory without requiring an AI provider.
- On This Day prioritizes the nearest prior anniversary using the Entry's preserved occurrence timezone, while days without an anniversary use a deterministic daily rotation across Entries at least thirty days old.
- Resurfacing excludes unreviewed Inbox Entries, Life Stages, Trash, undated content, and other owners while preserving organization and active private attachment metadata for the selected Entry.
- The local database now passes 363 pgTAP tests plus warning-free schema lint, including 28 focused resurfacing tests for selection, time zones, privacy, validation, grants, and index hardening.
- Hosted Supabase now contains the Home resurfacing migration with an aligned thirteen-migration ledger and warning-free public and extensions schema lint.
- Hosted schema inspection confirms the resurfacing function uses invoker security, an empty search path, authenticated-only execution, and the intended partial candidate index.
- Web Home now loads its deterministic daily memory in parallel with the main workspace and quietly omits the optional card if resurfacing fails.
- The responsive Soft Ledger memory card presents On This Day or archive context, complete Entry text, Type, original occurrence date, Collections, tags, and an expiring private image URL.
- The Web suite now has 124 passing tests, including six focused resurfacing-response tests, and the implementation passes formatting, design-token, lint, typecheck, and production-build checks.
- Isolated localhost browser verification covered the real database RPC, private signed image loading, desktop and 390-pixel iPhone layouts, complete memory context, and disposable-account cleanup.
- iOS Home now loads the same deterministic daily memory in parallel with the main workspace and quietly preserves the normal Home experience if the optional request fails.
- The native Soft Ledger memory card presents anniversary or archive context, complete Entry text, Type, original occurrence date, Collections, tags, and an expiring private image URL.
- Recent Entries and the resurfaced memory share one signed-private-image batch, with the first successfully signed attachment selected as the cover image.
- The shared iOS scheme now has 106 passing tests, including four focused resurfacing tests, and the implementation passes strict changed-file formatting, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.
- The product contract now defines voice capture as live platform-native dictation into the editable Entry body without creating, persisting, or uploading an audio file.
- Native universal capture now starts and stops system speech recognition from every shared composer surface, prefers on-device recognition when supported, and uses the system service as a compatibility fallback.
- iOS preserves existing draft text while live partial results arrive, saves every transcript update through the existing recoverable draft path, and keeps date, photo, and save mutations unavailable until listening stops.
- Native voice states include permission preparation, listening, completion, denial, unavailable-input, and no-recognized-speech feedback with explicit accessibility labels.
- The shared iOS scheme now has 111 passing tests, including five focused transcript-merging tests, and the implementation passes strict Swift formatting, property-list validation, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.
- Web universal capture now uses the browser's standard or prefixed Speech Recognition implementation where available, with text and photo capture left fully usable in unsupported browsers.
- Web voice capture writes live partial results through the existing recoverable draft path, preserves text written before listening, and never records, persists, attaches, or uploads an audio file.
- Voice status and error feedback remain visible and accessible while conflicting title, body, date, photo, and save controls stay unavailable until listening ends.
- The Web suite now has 134 passing tests, including ten focused voice-capability, transcript, limit, and failure tests, and the implementation passes formatting, design-token, lint, typecheck, and production-build checks.
- Authenticated localhost browser verification covered live start, listening, stop, empty-result feedback, existing-draft preservation across navigation, and cleanup without creating an Entry.
- A locally verified Homes contract now creates or revision-safely edits an organized Home Entry, its reusable Place, Homes Timeline Stage, Collections, tags, and range dates in one transaction.
- Homes browsing returns active and completed residences in deterministic order with reusable Place details, move context, organization, private attachment metadata, and pagination totals.
- Home version history now preserves the previous specialized Home, Place, and Timeline state in addition to the shared Entry snapshot before an edit or Trash mutation.
- The contract supports open-ended current residences, exact or approximate date precision, recoverable Trash restoration, global structured search, optimistic conflicts, and owner isolation.
- The local database now passes 422 pgTAP tests plus warning-free schema lint, including 59 focused Homes tests for validation, ranges, Place reuse, organization, history, Timeline, Search, Trash, grants, and privacy.
- Hosted Supabase now contains the additive Homes migration with an aligned fourteen-migration ledger and no seed or role deployment.
- Hosted verification confirms all three Homes functions, the enriched Entry-history trigger, both supporting indexes, empty function search paths, authenticated-only execution grants, and warning-free public and extensions schema lint.
- Web now exposes Homes as a dedicated authenticated archive with current and earlier residence chapters, human date context, elapsed duration, location summaries, memories, organization, and private photo covers.
- The Web Home editor atomically creates or revision-safely updates its reusable Place, date range, move context, Collections, tags, memories, and private Entry photos through the shared hosted contract.
- Home Timeline stages now open the specialized Home editor instead of the generic Timeline editor, while Homes is available from both Records navigation and Library.
- The Web suite now has 148 passing tests, including 14 focused Home input, response, duration, location, and Place-decoding tests, and passes lint and typecheck checks.
- Authenticated localhost verification covered Home creation, revision-safe editing, Timeline deep linking, structured exact-address search, and exact hosted cleanup of the disposable Entry, Place, Collection, and tag.
- iOS now exposes Homes inside Library with distinct current and earlier residence chapters, human date context, elapsed duration, location summaries, memories, organization, and signed private photo covers.
- The native Home editor creates or revision-safely updates a reusable Place, move dates and reasons, Collections, tags, memories, coordinates, and private Entry photos through the shared hosted contract.
- Home Timeline stages now open the specialized native Home editor instead of the generic Timeline editor, and both Home and individual-photo deletion remain recoverable through Trash.
- The shared iOS scheme now has 121 passing tests, including ten focused Homes tests for decoding, ordering, range and duration presentation, validation, organization, explicit RPC nulls, and universal attachment metadata.
- The iOS Homes implementation passes strict Swift formatting, project validation, a warning-free generic Simulator build, the complete suite on an iPhone 17 Pro simulator, and an install-and-launch smoke check.
- A locally verified Vehicles contract now creates or revision-safely edits an organized Vehicle Entry, its optional make, model, year and color facts, a Vehicles Timeline Stage, Collections, tags, and ownership or regular-use dates in one transaction.
- Vehicles browsing returns current and earlier chapters in deterministic order with duration-ready ranges, organization, private attachment metadata, and pagination totals.
- Vehicle version history now preserves the previous specialized facts and Timeline state without regressing the previously enriched Home and Place snapshots.
- The contract supports incomplete historical facts, open-ended current periods, recoverable Trash restoration, global structured search, optimistic conflicts, and owner isolation while excluding operational vehicle management.
- The local database now passes 480 pgTAP tests plus warning-free schema lint, including 58 focused Vehicles tests for validation, ordering, organization, history, Timeline, Search, Trash, grants, Home-history regression, and privacy.
- Hosted Supabase now contains the additive Vehicles migration with an aligned fifteen-migration ledger and no seed or role deployment.
- Hosted verification confirms all three Vehicles functions, both supporting indexes, the combined Home and Vehicle history trigger, empty function search paths, authenticated-only execution grants, and warning-free public and extensions schema lint.
- Web now exposes Vehicles as a dedicated authenticated archive with current and earlier chapters, human date context, elapsed duration, structured facts, memories, organization, and private photo covers.
- The Web Vehicle editor atomically creates or revision-safely updates its ownership or regular-use dates, optional make, model, year and color, Collections, tags, memories, and private Entry photos through the shared hosted contract.
- Vehicle Timeline stages now open the specialized Vehicle editor instead of the generic Timeline editor, while Vehicles is available from both Records navigation and Library.
- The Web suite now has 160 passing tests, including 12 focused Vehicle input, response, fact, range, duration, and attachment-decoding tests, and passes lint, typecheck, and production build checks.
- Localhost verification confirmed the signed-out authentication boundary for the new route; authenticated mutation coverage remains enforced by the shared contract and server-action validation without retaining synthetic user data.
- iOS now exposes Vehicles inside Library with distinct current and earlier chapters, human date context, elapsed duration, structured facts, memories, organization, and signed private photo covers.
- The native Vehicle editor creates or revision-safely updates ownership or regular-use dates, precision, human labels, optional make, model, model year and color, Collections, tags, memories, and private Entry photos through the shared hosted contract.
- Vehicle Timeline stages now open the specialized native Vehicle editor instead of the generic Timeline editor, and both Vehicle and individual-photo deletion remain recoverable through Trash.
- The shared iOS scheme now has 132 passing tests, including ten focused Vehicle tests plus explicit Home and Vehicle Timeline editor routing coverage.
- The native Vehicles implementation passes strict formatting for changed sources, project validation, a warning-free generic Simulator build, the complete suite on an iPhone 17 Pro simulator, and an install-and-launch smoke check.
- A locally verified Goals contract now creates or revision-safely edits an organized Goal Entry with Short-term, Long-term, or Someday horizon, flexible reflective status, an optional calendar-only target date, Collections, tags, and related Entry context.
- Goal edits preserve the previous specialized facts and related Entry links in version history, while active browsing, global structured search, and the shared recoverable Trash path remain owner-scoped.
- A Bucket List Goal can be atomically marked Achieved and create a linked organized First Time with supplied completion context without copying the Goal description.
- The Goals contract intentionally excludes percentages, reminders, overdue pressure, subtasks, and productivity scoring.
- The local database now passes 544 pgTAP tests plus warning-free schema lint, including 64 focused Goals tests for validation, sorting, organization, related Entries, history, Search, Trash, Bucket List completion, grants, indexes, and privacy.
- Hosted Supabase now contains the additive Goals migration with an aligned sixteen-migration ledger and no seed or role deployment.
- Hosted verification confirms all four Goals functions, all three supporting indexes, the enriched Home, Vehicle, and Goal history trigger, empty function search paths, authenticated-only execution grants, and warning-free public and extensions schema lint.
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

### Web Timeline

- [x] Require the same authenticated server session as Inbox and Search before loading Timeline data.
- [x] Show every visible track, including empty tracks, without flattening overlapping life chapters into one sequence.
- [x] Render bounded and open-ended Stages as ranges and Events as points on a horizontally explorable desktop Timeline.
- [x] Provide a compact track-first mobile presentation with the same Entry content and editing access.
- [x] Create a Stage or Event directly in a selected track with a title, notes, date precision, optional human label, and preserved occurrence time zone.
- [x] Revision-safely edit content, occurrence, kind, and track through the shared atomic database contract.
- [x] Move a Timeline Entry to Trash while preserving its history and future restoration path.
- [x] Validate Timeline input and layout behavior with 15 focused Web tests.
- [x] Verify real local creation and editing through the browser without runtime request errors.

### iOS Timeline

- [x] Add Timeline as a first-class native tab backed by the shared authenticated Timeline workspace RPC.
- [x] Present every visible track as a native track-first card, including useful empty states and track-specific add actions.
- [x] Display Stage and Event markers, chronological ordering, open-ended periods, human date labels, and preserved local occurrence dates.
- [x] Create and revision-safely edit content, kind, track, date precision, occurrence range, and human date labels.
- [x] Preserve the original occurrence time zone unless an occurrence date is changed locally.
- [x] Move a Timeline Entry to Trash only after explicit confirmation and surface cross-device revision conflicts.
- [x] Expose initial loading, refresh, empty-track, unavailable, mutation-progress, validation-error, and conflict states.
- [x] Verify native decoding, sorting, formatting, validation, and RPC parameter encoding with ten focused tests.
- [x] Pass the warning-free generic Simulator build and all 38 tests on an iPhone 17 Pro simulator.

### First Times data contract

- [x] Return the authenticated owner's non-Trash First Times with Collections, tags, and active private attachment metadata.
- [x] Create an organized First Time with only a title required and preserve optional descriptions, exact or imprecise dates, labels, and time zones.
- [x] Revision-safely edit First Time content and atomically replace its Collections and tags.
- [x] Register only supported images that already exist under the owner's private Entry Storage path.
- [x] Make attachment registration idempotent so an ambiguous client retry cannot duplicate metadata.
- [x] Recoverably remove a photo without deleting its original private Storage object.
- [x] Move a First Time to Trash while preserving Entry history and its private media.
- [x] Verify owner isolation, unauthenticated denial, content and date rules, optimistic conflicts, media constraints, and Trash behavior with local pgTAP coverage.
- [x] Apply and verify the First Times contract on hosted Supabase.

### Authenticated table grants

- [x] Remove client `TRUNCATE`, `TRIGGER`, `REFERENCES`, `MAINTAIN`, and other table privileges outside the intended CRUD surface.
- [x] Keep profiles limited to Select and Update, Entry history and attachments limited to Select, and RLS-managed application tables limited to CRUD.
- [x] Verify the exact local and hosted privilege inventories after migration.

### Web First Times

- [x] Require the same authenticated server session as Inbox, Search, and Timeline before loading First Times.
- [x] Show dated and unknown-date First Times in a dedicated responsive archive with useful empty and unavailable states.
- [x] Create a First Time with only a title required and optional reflection, date precision, human date label, Collections, and tags.
- [x] Revision-safely edit First Time content and organization and surface cross-device conflicts.
- [x] Select and preview supported photos before saving, enforce client limits, and upload originals directly to the private owner and Entry path.
- [x] Register photo metadata only after Storage confirms upload and remove an orphaned object when registration fails.
- [x] Display private photos through one-hour signed URLs without persisting a public URL.
- [x] Recoverably remove a photo or move the full First Time to Trash with an explicit confirmation.
- [x] Verify input normalization with 11 focused tests and the full create, photo, display, and edit path against local Supabase in a real browser.

### iOS First Times

- [x] Add First Times as a first-class native tab backed by the shared authenticated workspace RPC.
- [x] Show dated and unknown-date First Times in a photo-forward native archive with loading, empty, unavailable, and refresh states.
- [x] Create a First Time with only a title required and optional reflection, date precision, human date label, Collections, and tags.
- [x] Revision-safely edit First Time content and organization and surface cross-device conflicts.
- [x] Select and preview up to 12 supported photos, validate signatures and size, and preserve original image bytes.
- [x] Upload photos to private owner and Entry paths, register metadata only afterward, and retain failed selections for retry.
- [x] Display private photos through one-hour signed URLs without persisting public URLs.
- [x] Recoverably remove a photo or move the full First Time to Trash only after explicit confirmation.
- [x] Verify decoding, sorting, date display, validation, photo detection, private paths, and RPC parameters with 13 focused tests.
- [x] Pass the warning-free generic Simulator build and all 51 tests on an iPhone 17 Pro simulator.

### Collections data contract

- [x] Return every active Collection owned by the authenticated user, including empty Collections.
- [x] Count only non-Trash Entries and separately report Entries still awaiting Inbox review.
- [x] Preserve configured sort order with stable case-insensitive name ordering.
- [x] Return a paginated Collection detail feed with complete Entry content, Type, Inbox state, occurrence context, and revision.
- [x] Include every active linked Collection, tag, and private attachment metadata object for each Entry.
- [x] Keep archived Collections, Trash Entries, and recoverably removed attachments out of active browsing.
- [x] Validate page limits and offsets before executing Collection detail.
- [x] Enforce owner isolation and unauthenticated denial through RLS-backed security-invoker functions.
- [x] Restrict function execution to authenticated users and use empty function search paths.
- [x] Verify the shared contract with 35 focused pgTAP tests and warning-free local schema lint.
- [x] Apply the additive Collections migration to hosted Supabase without seed or role changes.
- [x] Verify the hosted migration ledger, schema lint, function definitions, execution grants, and indexes after rollout.

### Web Collections

- [x] Expose Collections as a working destination in the shared desktop sidebar and four-item mobile navigation.
- [x] Display every active Collection, including empty Collections, with Entry counts, Inbox counts, recency, and stable ordering.
- [x] Open a durable Collection detail route and show paginated non-Trash Entries with complete content and organization context.
- [x] Display active private Entry photos through one-hour signed URLs without persisting public URLs.
- [x] Handle signed-out, missing configuration, unavailable data, empty Collection, invalid identifier, and out-of-range page states.
- [x] Validate Collection route inputs and pagination links with six focused tests and keep all 74 Web tests passing.
- [x] Pass formatting, design-token, lint, typecheck, and production-build checks.
- [x] Verify overview, detail, private image, desktop, narrow responsive, mobile navigation, and console behavior against local Supabase.

### iOS Collections

- [x] Replace the native Collections placeholder with a working first-class tab backed by the shared authenticated workspace RPC.
- [x] Show every active Collection with Entry counts, Inbox counts, recency, stable ordering, loading, empty, unavailable, and refresh states.
- [x] Open Collection detail and preserve complete Entry content, Type, Inbox state, occurrence context, Collections, and tags.
- [x] Display active private Entry photos through one-hour signed URLs without persisting public URLs.
- [x] Load Collection detail in validated 25-Entry pages without duplicating Entries during incremental pagination.
- [x] Verify summary decoding, ordering, Entry decoding, title and excerpt fallbacks, date labels, time zones, attachments, and RPC pagination with ten focused tests.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and all 61 native tests.
- [x] Install and launch the current build on an iPhone 17 Pro simulator without bypassing the existing authentication boundary.

### iOS Library navigation

- [x] Replace separate First Times and Collections tabs with one scalable Library destination.
- [x] Keep Collections and First Times fully interactive through native push navigation.
- [x] Reuse each archive inside the Library navigation stack without nesting another `NavigationStack`.
- [x] Show Goals, Vehicles, Places, and People as clearly non-interactive planned destinations.
- [x] Preserve direct primary access to Inbox, Search, and Timeline while reserving tab-bar capacity for Habits.
- [x] Verify stable destination identity, user-facing metadata, and implemented-versus-planned grouping with four focused tests.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and all 65 native tests.

### Habits data contract

- [x] Support check-off and measured Habits with validated names, units, and positive measurement targets.
- [x] Support daily, selected-weekday, weekly-target, and custom day-interval schedules with explicit active date bounds.
- [x] Return every active owned Habit and its explicit or derived state for one local calendar date.
- [x] Record completed, missed, or skipped occurrences and revision-safely correct existing records.
- [x] Preserve previous Habit definitions and occurrence records in owner-readable immutable history.
- [x] Move a Habit to recoverable Trash without deleting its occurrence or version history.
- [x] Return a complete yearly calendar with completed, skipped, missed, pending, upcoming, and not-scheduled states.
- [x] Keep other owners and anonymous callers outside the contract through RLS-backed security-invoker functions.
- [x] Restrict new history tables to authenticated Select access and every function to the minimum authenticated execution grant.
- [x] Verify the shared contract with 49 focused pgTAP tests and warning-free local schema lint.
- [x] Apply the additive Habits migration to hosted Supabase without seed or role changes.
- [x] Verify the hosted migration ledger, schema lint, function definitions, execution grants, table privileges, and indexes after rollout.

### Web Habits

- [x] Require the shared authenticated Web session before reading or mutating Habits.
- [x] Add Habits to the shared desktop and five-item mobile navigation.
- [x] Create Check or Measure Habits with daily, selected-weekday, weekly-target, or custom-interval schedules.
- [x] Select a calendar date and record completed, skipped, or missed check-ins with optional notes and measured values.
- [x] Revision-safely correct an existing check-in without losing immutable database history.
- [x] Revision-safely edit a Habit definition or move it to recoverable Trash.
- [x] Show a full-year contribution calendar with completed, missed, skipped, pending, upcoming, and not-scheduled states.
- [x] Calculate current and longest streaks, completion rate, misses, and intentional skips while keeping skips neutral.
- [x] Preserve date, selected Habit, and year state in the URL for refresh-safe navigation.
- [x] Verify parsing and analytics with 19 focused tests and keep all 93 Web tests passing.
- [x] Verify Check, Measure, correction, schedule editing, responsive layout, and console behavior against isolated local Supabase data.

### iOS Habits

- [x] Add Habits as a fifth primary native tab backed by the shared authenticated data contract.
- [x] Create Check or Measure Habits with daily, selected-weekday, weekly-target, or custom-interval schedules.
- [x] Select a local calendar date and record completed, skipped, or missed check-ins with optional notes and measured values.
- [x] Provide a one-tap completion action for pending Check Habits and a focused value editor for Measure Habits.
- [x] Revision-safely correct existing check-ins while preserving immutable database history.
- [x] Revision-safely edit Habit definitions or move them to recoverable Trash after explicit confirmation.
- [x] Show a compact twelve-month calendar with tappable eligible dates and every shared calendar state.
- [x] Calculate current and longest streaks, completion rate, misses, and intentional skips while keeping skips neutral.
- [x] Preserve local date values across time zones and queue a newer date selection if a previous load is still running.
- [x] Verify decoding, schedule JSON, validation, explicit RPC nulls, date-only handling, and analytics with 13 focused tests.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and all 78 native tests.

### Trash data contract

- [x] Return deleted Entries, deleted Habits, and individually removed attachments through one owner-scoped paginated feed.
- [x] Keep a removed attachment nested under its Entry while the parent Entry is also in Trash.
- [x] Preserve a title, concise detail, deletion time, thirty-day expiration time, revision, content kind, and private Storage paths for each item.
- [x] Restore an Entry or Habit only when its revision and deletion timestamp still match.
- [x] Restore an attachment only when its deletion timestamp still matches and its parent Entry is active.
- [x] Preserve the deleted Entry or Habit state in version history when restoring it.
- [x] Return every owned private Storage path that must be removed before permanent deletion.
- [x] Permanently delete relational data and version history only when optimistic state still matches.
- [x] Avoid the Habit occurrence-history trigger conflict by deleting occurrences while the parent Habit still exists.
- [x] Restrict every Trash function to authenticated users, use empty function search paths, and keep browsing behind Row Level Security.
- [x] Verify the shared contract with 57 focused pgTAP tests and warning-free local schema lint.
- [x] Apply the additive Trash migration to hosted Supabase without seed or role changes.
- [x] Verify the hosted migration ledger, schema lint, function definitions, execution grants, and unchanged table privileges.

### Web Trash

- [x] Require the shared authenticated Web session before browsing or mutating Trash.
- [x] Show removed Entries, Habits, and individual photos together with clear kind, removal, and retention context.
- [x] Display expiring signed URLs for private photo thumbnails without exposing raw object paths.
- [x] Restore an item only when its revision and deletion timestamp still match the visible state.
- [x] Permanently delete only after explicit confirmation and remove every private Storage object before database metadata.
- [x] Surface load, empty, success, conflict, offline, and deletion-failure states without claiming automatic retention cleanup.
- [x] Preserve a five-item compact navigation while exposing Trash through the mobile header and desktop Archive section.
- [x] Validate Trash inputs and pagination with eight focused tests and keep all 101 Web tests passing.
- [x] Verify desktop and mobile presentation, signed media, restoration, permanent deletion, and Storage cleanup against isolated local data.

### iOS Trash

- [x] Expose Trash as an interactive Library destination backed by the shared authenticated contract.
- [x] Show removed Entries, Habits, and individual photos with clear kind, removal, and exact retention context.
- [x] Display one-hour signed private thumbnails without persisting raw Storage paths or public URLs.
- [x] Restore only when the visible revision and original deletion timestamp still match.
- [x] Permanently delete only after explicit confirmation, validate every owner-scoped path, and remove Storage objects before database metadata.
- [x] Surface loading, empty, success, conflict, offline, and deletion-failure states without claiming automatic cleanup.
- [x] Load additional items in validated 25-item pages without duplicate cross-table identities.
- [x] Verify decoding, timestamp precision, identity, retention, pagination, and mutation encoding with seven focused tests.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, all 85 native tests, and an authenticated-boundary launch check.

### Home data contract

- [x] Return one authenticated owner snapshot for an explicit local date and IANA time zone.
- [x] Count active Entries, Inbox items, First Times, Collections, and Habits without including Trash, archived records, or other owners.
- [x] Derive due, completed, and skipped Habit totals from the shared schedule semantics for the requested date.
- [x] Return visible current Timeline stages using timezone-aware local-day boundaries.
- [x] Return up to ten recent Entries in stable capture order with Collections, tags, and active private attachment metadata.
- [x] Validate the local date, time zone, and recent-Entry limit before querying.
- [x] Keep execution authenticated-only with invoker security, Row Level Security, and an empty function search path.
- [x] Add a partial owner and creation-time index for the recent active Entry query.
- [x] Verify the shared contract with 36 focused pgTAP tests, all 306 database tests, and warning-free local schema lint.
- [x] Apply the additive Home migration to hosted Supabase without seed or role changes.
- [x] Verify the hosted migration ledger, schema lint, function definition, execution grant, security mode, search path, and index after rollout.

### Web Home

- [x] Require the shared authenticated Web session before loading the Home workspace.
- [x] Render a device-local greeting, inline Inbox capture, archive counts, today's Habit progress, current Timeline chapters, and recent Entries from one shared snapshot.
- [x] Display recent private photos through expiring signed URLs without exposing Storage object paths.
- [x] Keep Inbox on a durable route and expose Home, Inbox, Timeline, Habits, and Library as the exact five mobile destinations.
- [x] Preserve full desktop access to Search, First Times, Collections, Trash, and future record areas.
- [x] Offer one shared Quick Capture surface from every workspace without mounting competing capture queues on Home or Inbox.
- [x] Synchronize the browser's valid IANA time zone to server rendering through a non-sensitive cookie with a safe UTC fallback.
- [x] Verify date and time-zone behavior with five focused tests and keep all 106 Web tests passing.
- [x] Pass formatting, design-token, lint, typecheck, and production-build checks.
- [x] Verify populated Home, global capture, responsive navigation, full-screen mobile capture, synchronization, and console behavior against isolated local Supabase data.

### iOS Home

- [x] Render a device-local greeting, inline capture, archive counts, today's Habit progress, current Timeline chapters, and recent Entries from the shared Home snapshot.
- [x] Display recent private photos through one-hour signed URLs without persisting public URLs.
- [x] Expose Home, Inbox, Timeline, Habits, and Library as the exact five primary tabs and retain Search inside Home navigation.
- [x] Show a live Inbox badge derived from synchronized and pending Entries.
- [x] Share one recoverable draft and one offline synchronization queue across Home, Inbox, and global capture.
- [x] Offer full-screen Quick Capture from Timeline, Habits, and Library without duplicating capture controllers.
- [x] Refresh Home after successful pending-entry synchronization and when the app returns to the foreground.
- [x] Verify decoding, dates, time zones, presentation, request validation, tab order, and capture availability with ten focused tests.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and all 95 native tests.

### Web universal capture dates

- [x] Keep capture-time behavior unchanged until the user opts into a separate relevant date.
- [x] Accept an exact local date and time and convert it to one synchronized occurrence instant with the browser's current IANA time zone.
- [x] Preserve the selected date together with title and body in the recoverable per-user draft.
- [x] Migrate existing version-one text drafts without data loss or an invented date.
- [x] Keep the selected occurrence instant immutable after an Entry joins the offline synchronization queue.
- [x] Expose a compact desktop control and a touch-friendly mobile date editor without competing with the primary capture action.
- [x] Verify fallback, conversion, invalid input, local editing, dated persistence, and legacy migration with five focused tests.
- [x] Keep all 111 Web tests passing and pass formatting, design-token, lint, typecheck, and production-build checks.
- [x] Verify draft reload, exact database synchronization, device time zone, responsive presentation, and disposable-data cleanup against local Supabase.

### iOS universal capture dates

- [x] Keep capture-time behavior unchanged until the user opts into a separate relevant date.
- [x] Offer the same optional exact date and time from Home, Inbox, and the global full-screen composer.
- [x] Share the selected date across every native capture surface through one root draft state.
- [x] Preserve the selected date in the per-user recoverable draft and decode existing text-only drafts without data loss.
- [x] Freeze the selected occurrence instant and current IANA time zone when an Entry enters the offline synchronization queue.
- [x] Clear the optional date only after the Entry is safely accepted into the local queue.
- [x] Verify dated draft restoration and legacy draft compatibility while keeping all 96 native tests passing.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and an install-and-launch smoke check.

### Universal Entry media contract

- [x] Register an uploaded original image against any active Entry owned by the authenticated user.
- [x] Require an owner and Entry-scoped private Storage path with a filename derived from the stable attachment ID.
- [x] Validate supported image formats, byte size, optional pixel dimensions, and original filename before metadata insertion.
- [x] Require the private Storage object to exist before attachment metadata is registered.
- [x] Make an identical retry idempotent while rejecting conflicting identifiers or object paths.
- [x] Recoverably move any active Entry photo to Trash without deleting its private Storage object.
- [x] Keep direct attachment writes unavailable to clients and function execution unavailable to anonymous callers.
- [x] Use hardened definer boundaries with empty search paths for the minimum privileged attachment mutations.
- [x] Verify registration, removal, idempotency, validation, ownership, grants, and anonymous denial with 29 focused pgTAP tests.
- [x] Apply the additive migration locally and pass all 335 database tests plus warning-free schema lint.
- [x] Apply and verify the universal Entry media migration on hosted Supabase.

### Web universal capture photos

- [x] Accept up to twelve supported private image originals from Home, Inbox, and every global Quick Capture surface.
- [x] Persist selected photo blobs in owner-scoped IndexedDB before presenting them as recoverable draft media.
- [x] Preserve unfinished photo drafts across reload while keeping already queued photos out of the active draft.
- [x] Accept photo-only Entries and migrate existing text-only queues to the photo-capable queue shape without data loss.
- [x] Preserve stable Entry and attachment identifiers across offline retries and ambiguous network outcomes.
- [x] Synchronize the Entry first, upload each original to a deterministic private Storage path, and register metadata idempotently before clearing the queue.
- [x] Keep missing or failed local photos visibly pending instead of claiming that synchronization completed.
- [x] Show selected-photo previews, removal controls, photo counts, and responsive desktop and mobile presentation.
- [x] Verify validation, queue migration, photo-only input, and attachment metadata while keeping all 118 Web tests passing.
- [x] Pass formatting, design-token, lint, typecheck, production-build, real browser, database, private Storage, signed-image, responsive-layout, and cleanup checks.

### iOS universal capture photos

- [x] Accept up to twelve supported private image originals from Home, Inbox, and every global Quick Capture surface.
- [x] Persist selected photo binaries and metadata in protected owner-scoped Application Support storage before presenting them as recoverable draft media.
- [x] Restore unfinished photo drafts after relaunch while keeping already queued photos out of the active composer.
- [x] Accept photo-only Entries and migrate existing text-only queues to the photo-capable queue shape without data loss.
- [x] Preserve stable Entry and attachment identifiers across offline retries and ambiguous network outcomes.
- [x] Synchronize the Entry first, upload each original to a deterministic private Storage path, and register metadata idempotently before clearing the queue.
- [x] Keep missing, changed, or failed local photos visibly pending instead of claiming that synchronization completed.
- [x] Show native selected-photo previews, removal controls, active photo state, and pending photo counts.
- [x] Verify photo-only validation, queue migration, owner isolation, malformed metadata, and attachment parameter encoding while keeping all 102 native tests passing.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.

### Home memory resurfacing contract

- [x] Return at most one active, organized, dated Entry for the authenticated owner.
- [x] Prefer the nearest prior same-month-and-day anniversary and report how many years ago it occurred.
- [x] Match anniversaries in each Entry's preserved occurrence timezone with a safe UTC fallback for invalid legacy values.
- [x] Use a stable date-based rotation across Entries at least thirty days old when no anniversary exists.
- [x] Exclude unreviewed Inbox Entries, Life Stages, Trash, undated content, and other owners.
- [x] Include complete Entry text, Type, occurrence context, Collections, tags, and active private attachment metadata.
- [x] Keep the function security-invoker, authenticated-only, and protected by Row Level Security with an empty search path.
- [x] Add a partial owner and occurrence-time index for eligible resurfacing candidates.
- [x] Verify the shared contract with 28 focused pgTAP tests, all 363 database tests, and warning-free local schema lint.
- [x] Apply and verify the additive Home resurfacing migration on hosted Supabase.

### Web Home memory resurfacing

- [x] Load the optional resurfaced memory in parallel so it does not extend the main Home workspace request chain.
- [x] Degrade quietly to the normal Home experience when the optional resurfacing request fails or returns malformed data.
- [x] Display On This Day anniversary context or the stable archive fallback without presenting the selection as AI-generated.
- [x] Preserve complete Entry text, Type, original occurrence date, Collections, tags, and active private image metadata.
- [x] Reuse one private signed-image request across recent Entries and the resurfaced memory.
- [x] Keep the card consistent with the Soft Ledger system across desktop and narrow mobile layouts.
- [x] Verify response validation with six focused tests while keeping all 124 Web tests passing.
- [x] Pass formatting, design-token, lint, typecheck, production-build, real database, signed-image, desktop, mobile, and cleanup checks.

### iOS Home memory resurfacing

- [x] Load the optional resurfaced memory in parallel so it does not extend the main Home workspace request chain.
- [x] Degrade quietly to the normal Home experience when the optional resurfacing request fails or returns malformed data.
- [x] Display On This Day anniversary context or the stable archive fallback without presenting the selection as AI-generated.
- [x] Preserve complete Entry text, Type, original occurrence date, Collections, tags, and active private image metadata.
- [x] Reuse one private signed-image request across recent Entries and the resurfaced memory.
- [x] Keep the native card consistent with the Soft Ledger system and existing Home hierarchy.
- [x] Verify selection validation and RPC parameters with four focused tests while keeping all 106 native tests passing.
- [x] Pass strict changed-file formatting, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.

### iOS voice-to-text capture

- [x] Use live system dictation without creating, persisting, attaching, or uploading an audio file.
- [x] Prefer on-device speech recognition when supported and allow the system speech service as a compatibility fallback.
- [x] Request both Speech Recognition and Microphone access with purpose-specific usage descriptions.
- [x] Insert live partial transcription into the shared editable Entry body while preserving existing text.
- [x] Reuse the existing per-user recoverable draft path so transcribed text survives navigation and relaunch.
- [x] Stop and release the microphone when the user taps Stop or leaves the composer.
- [x] Prevent date, photo, body-edit, and save collisions while a voice session is active.
- [x] Provide accessible preparing, listening, completion, permission-denied, unavailable-input, and empty-result feedback.
- [x] Enforce the shared 50,000-character Entry limit during live transcription.
- [x] Verify transcript merging with five focused tests while keeping all 111 native tests passing.
- [x] Pass strict Swift formatting, property-list validation, project validation, a warning-free generic Simulator build, and an install-and-launch authentication-boundary check.

### Web voice-to-text capture

- [x] Use the standard or prefixed browser Speech Recognition implementation when available without making it a requirement for text or photo capture.
- [x] Transcribe directly into the editable Entry body without creating, persisting, attaching, or uploading an audio file.
- [x] Preserve existing draft text while live partial recognition results replace only the current spoken segment.
- [x] Reuse the existing per-user recoverable draft path so recognized text survives navigation and reload.
- [x] Stop and release browser recognition when the user taps Stop or leaves the composer.
- [x] Prevent title, body, date, photo, and save collisions while a voice session is active.
- [x] Provide accessible listening, finishing, completion, permission, microphone, connectivity, unsupported-browser, and empty-result feedback.
- [x] Enforce the shared 50,000-character Entry limit while merging live transcription.
- [x] Verify capability detection, transcript extraction and merging, limits, and failure messages with ten focused tests while keeping all 134 Web tests passing.
- [x] Pass formatting, design-token, lint, typecheck, production-build, and authenticated localhost browser checks without leaving test data.

### Homes and moves data contract

- [x] Create an organized Home Entry together with a reusable Place and Homes Timeline Stage in one transaction.
- [x] Require a Home name, reusable Place name, best-known move-in date, valid occurrence timezone, and valid date range.
- [x] Support open-ended current residences plus exact, day, month, year, range, age, and approximate date context.
- [x] Preserve optional address, city, region, country, coordinates, Place notes, move-in reason, and move-out reason.
- [x] Atomically normalize and replace Collections and tags alongside Home content and relationships.
- [x] Return active and completed Homes in deterministic order with pagination totals, organization, Timeline, and active private attachment metadata.
- [x] Preserve previous Entry, Home, Place, and Timeline state inside Entry version history before edits and Trash mutations.
- [x] Reuse global structured search and the shared recoverable Trash restoration path without losing Home relationships.
- [x] Reject stale revisions and cross-owner Place, Home, edit, and Trash access without partial mutations.
- [x] Keep every contract function authenticated-only, security-invoker, Row Level Security-backed, empty-search-path, and supported by focused indexes.
- [x] Verify the contract with 59 focused pgTAP tests while keeping all 422 database tests and warning-level schema lint passing.
- [x] Apply and verify the additive Homes migration on hosted Supabase.

### Web Homes experience

- [x] Present current and earlier Homes as distinct residence chapters with date range, duration, location, memories, organization, and a private photo cover.
- [x] Create a Home together with a new Place or reuse and update an existing owned Place.
- [x] Edit move-in and optional move-out dates, date precision, human labels, move reasons, Place details, Collections, tags, and memories through one revision-safe mutation.
- [x] Upload supported private Entry photos to owner-scoped Storage, register them only after upload, and preserve retryable failures.
- [x] Move a Home or individual photo to recoverable Trash without deleting the underlying private original.
- [x] Keep exact addresses inside the authenticated editor while search results expose only the matching Entry and match reason.
- [x] Route Home stages from Timeline to the specialized Home editor and expose Homes through Records and Library navigation.
- [x] Verify Home parsing, duration, location, Place decoding, create, edit, Timeline, structured search, and exact disposable-data cleanup while keeping all 148 Web tests passing.

### iOS Homes experience

- [x] Present current and earlier Homes as distinct native residence chapters with date range, duration, location, memories, organization, and a signed private photo cover.
- [x] Create a Home together with a new Place or reuse and intentionally update an existing owned Place.
- [x] Edit move dates and reasons, precision, human labels, Place details, coordinates, Collections, tags, and memories through one revision-safe mutation.
- [x] Upload supported private Entry photos to deterministic owner-scoped Storage paths and register metadata only after a successful upload.
- [x] Move a Home or individual photo to recoverable Trash without deleting the underlying private original.
- [x] Keep exact addresses inside the authenticated editor and route Home stages from Timeline to that specialized editor.
- [x] Expose Homes as an implemented Library destination without adding another primary tab.
- [x] Verify decoding, deterministic ordering, duration, location, validation, organization, explicit RPC nulls, Timeline type routing, and attachment metadata with ten focused tests while keeping all 121 native tests passing.
- [x] Pass strict Swift formatting, project validation, a warning-free generic Simulator build, the complete iPhone 17 Pro suite, and an install-and-launch smoke check.

### Vehicles and ownership-period data contract

- [x] Create an organized Vehicle Entry and Vehicles Timeline Stage in one transaction.
- [x] Require a Vehicle name and best-known start date while allowing make, model, model year, and color to remain incomplete.
- [x] Support open-ended current periods plus exact, day, month, year, range, age, and approximate date context.
- [x] Atomically normalize and replace Collections and tags alongside Vehicle content and structured facts.
- [x] Return current and earlier Vehicles in deterministic order with pagination totals, organization, Timeline, and active private attachment metadata.
- [x] Preserve previous Entry, Vehicle, and Timeline state inside Entry version history before edits and Trash mutations.
- [x] Preserve the existing enriched Home and Place version snapshots after extending the shared history trigger.
- [x] Reuse global structured search and the shared recoverable Trash path without losing Vehicle facts or relationships.
- [x] Reject invalid years and date ranges, stale revisions, cross-owner edits, and cross-owner Trash access without partial mutations.
- [x] Keep every contract function authenticated-only, security-invoker, Row Level Security-backed, empty-search-path, and supported by focused indexes.
- [x] Verify the contract with 58 focused pgTAP tests while keeping all 480 database tests and warning-level schema lint passing.
- [x] Apply and verify the additive Vehicles migration on hosted Supabase.

### Web Vehicles experience

- [x] Present current and earlier Vehicles as distinct chapters with date range, duration, structured facts, memories, organization, and a private photo cover.
- [x] Create or revision-safely edit ownership or regular-use dates, precision, human labels, make, model, model year, color, Collections, tags, and memories through one mutation.
- [x] Upload supported private Entry photos to owner-scoped Storage, register them only after upload, and preserve retryable failures.
- [x] Move a Vehicle or individual photo to recoverable Trash without deleting the underlying private original.
- [x] Route Vehicle stages from Timeline to the specialized Vehicle editor and expose Vehicles through Records and Library navigation.
- [x] Verify Vehicle parsing, facts, range and duration presentation, attachment decoding, lint, typecheck, production build, and the signed-out localhost boundary while keeping all 160 Web tests passing.

### iOS Vehicles experience

- [x] Present current and earlier Vehicles as distinct native chapters with date range, duration, structured facts, memories, organization, and a signed private photo cover.
- [x] Create or revision-safely edit ownership or regular-use dates, precision, human labels, make, model, model year, color, Collections, tags, and memories through one mutation.
- [x] Upload supported private Entry photos to deterministic owner-scoped Storage paths and register metadata only after a successful upload.
- [x] Move a Vehicle or individual photo to recoverable Trash without deleting the underlying private original.
- [x] Route Vehicle stages from Timeline to the specialized Vehicle editor and expose Vehicles as an implemented Library destination.
- [x] Verify decoding, deterministic ordering, facts, range and duration presentation, validation, organization, explicit RPC nulls, and Timeline type routing with focused tests while keeping all 132 native tests passing.
- [x] Pass strict formatting for changed sources, project validation, a warning-free generic Simulator build, the complete iPhone 17 Pro suite, and an install-and-launch smoke check.

### Goals data contract

- [x] Create an organized Goal Entry with a required title, optional description, and optional calendar-only target date.
- [x] Support Short-term, Long-term, and Someday horizons plus Considering, Active, Paused, Achieved, and Let Go reflective states without enforcing a productivity workflow.
- [x] Atomically normalize and replace Collections, tags, and up to 100 owner-scoped related Entry links alongside Goal content and structured facts.
- [x] Return Goals in deterministic reflective-state and target-date order with pagination totals, organization, related Entry context, and active private attachment metadata.
- [x] Preserve previous Entry, Goal, and related Entry-link state inside immutable Entry version history before edits and Trash mutations.
- [x] Reuse global structured search and the shared recoverable Trash path while enforcing optimistic revisions and owner isolation.
- [x] Atomically mark a Bucket List Goal Achieved and create a linked organized First Time with supplied completion context without copying the Goal description.
- [x] Keep every contract function authenticated-only, security-invoker, Row Level Security-backed, empty-search-path, and supported by focused indexes.
- [x] Verify the contract with 64 focused pgTAP tests while keeping all 544 database tests and warning-level schema lint passing.
- [x] Apply and verify the additive Goals migration on hosted Supabase.

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
- `feat: deploy Timeline data contract` deployed and verified the Timeline data contract on hosted Supabase.
- `feat: add Web Timeline experience` implemented and locally verified the authenticated Web Timeline experience.
- `feat: add iOS Timeline experience` implemented and simulator-verified the matching native iOS Timeline experience.
- `feat: add First Times data contract` implemented and locally verified the shared First Times and private photo-attachment data contract.
- `fix: restrict authenticated table grants` removed table privileges outside the intended RLS-managed client surface.
- `feat: deploy First Times data contract` deployed and verified the First Times contract and least-privilege correction on hosted Supabase.
- `feat: add Web First Times experience` implemented and locally browser-verified the dedicated Web First Times experience.
- `feat: add iOS First Times experience` implemented and simulator-verified the matching native iOS First Times experience.
- `feat: add Collections browsing contract` implemented and locally verified the shared Collections browsing contract.
- `feat: deploy Collections browsing contract` deployed and verified the Collections browsing contract on hosted Supabase.
- `feat: add Web Collections experience` implemented and locally browser-verified the authenticated Web Collections experience.
- `feat: add iOS Collections experience` implemented and simulator-verified the matching native iOS Collections experience.
- `feat: add iOS Library navigation` consolidated native archive navigation under a scalable Library destination.
- `feat: add Habits data contract` added and locally verified the shared Habits data contract.
- `feat: deploy Habits data contract` deployed and verified the Habits data contract on hosted Supabase.
- `feat: add Web Habits experience` implemented and locally browser-verified the authenticated Web Habits experience.
- `feat: add iOS Habits experience` implemented and simulator-verified the matching native iOS Habits experience.
- `feat: add Trash data contract` added and locally verified the shared Trash browsing, restoration, and permanent deletion contract.
- `feat: deploy Trash data contract` deployed and verified the Trash contract on hosted Supabase.
- `feat: add Web Trash experience` implemented and locally browser-verified the authenticated Web Trash experience.
- `feat: add iOS Trash experience` implemented and simulator-verified the matching native iOS Trash experience.
- `feat: add Home workspace contract` added and locally verified the shared Home workspace data contract.
- `feat: deploy Home workspace contract` deployed and verified the Home workspace contract on hosted Supabase.
- `feat: add Web Home experience` implemented and locally browser-verified the authenticated Web Home experience and global Quick Capture access.
- `feat: add iOS Home experience` implemented and simulator-verified the matching native iOS Home experience and shared global Quick Capture state.
- `feat: add Web capture dates` added and locally browser-verified an optional exact relevant date to every Web capture surface.
- `feat: add iOS capture dates` added the matching optional relevant date, shared draft state, and offline occurrence semantics to every native capture surface.
- `feat: add universal Entry media contract` added and locally verified universal private Entry photo registration and recoverable removal.
- `feat: deploy universal Entry media contract` deployed and verified the universal Entry media contract on hosted Supabase.
- `feat: add Web capture photos` added and locally browser-verified recoverable, offline-first private photos on every Web universal capture surface.
- `feat: add iOS capture photos` added and simulator-verified matching recoverable, offline-first private photos on every iOS universal capture surface.
- `feat: add Home memory resurfacing contract` added and locally verified a deterministic, owner-scoped Home memory resurfacing contract.
- `feat: deploy Home memory resurfacing contract` deployed and verified the Home memory resurfacing contract on hosted Supabase.
- `feat: add Web Home memory resurfacing` added and locally browser-verified the quiet Web Home memory resurfacing experience.
- `feat: add iOS Home memory resurfacing` added and simulator-verified the matching native iOS Home memory resurfacing experience.
- `feat: add iOS voice capture` added and simulator-verified live voice-to-text across every shared native capture surface.
- `feat: add Web voice capture` added progressive live Web voice-to-text with recoverable drafts and authenticated localhost verification.
- `feat: add Homes data contract` added and locally verified the shared Homes and moves data contract.
- `feat: deploy Homes data contract` deployed and verified the additive Homes and moves contract on hosted Supabase.
- `feat: add Web Homes experience` added and authenticated-browser-verified the complete Web Homes experience.
- `feat: add iOS Homes experience` added and simulator-verified the complete native iOS Homes experience.
- `feat: add Vehicles data contract` added and locally verified the shared Vehicles and ownership-period data contract.
- `feat: deploy Vehicles data contract` deployed and verified the additive Vehicles contract on hosted Supabase.
- `feat: add Web Vehicles experience` added and locally verified the complete Web Vehicles experience.
- `feat: add iOS Vehicles experience` added and simulator-verified the complete native iOS Vehicles experience.
- `feat: add Goals data contract` added and locally verified the shared Goals and Bucket List completion contract.
- Current change: deployed and verified the additive Goals contract on hosted Supabase.

## Next sequence

1. Build the Web Goals archive around reflective status, horizon, and optional target-date context.
2. Add revision-safe editing, related Entries, Collections, tags, photos, and recoverable Trash actions.
3. Add the Bucket List Achieved flow that creates a linked First Time, then verify the experience on localhost.

## Deferred

- AI provider selection and AI-assisted organization.
- Preview or staging OAuth configuration until a stable Preview strategy is chosen.
- Sign in with Apple and App Store distribution.
- Production data import, DNS changes, and any destructive remote migration.
