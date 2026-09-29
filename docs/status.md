# MemoTrail Status

Last reviewed: 2026-09-28.

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
Web AI capabilities are paused, with a disabled Beta setting and no active AI entry points.
The accepted Data Ribbon layout now replaces the Web Dashboard, using the signed-in user's data and the shared capture, page, image, empty-state, and tag components.
The development preview routes and all 20 static Home mockups have been removed; Production deployment verification and browser acceptance remain pending.
Native iOS now adopts the canonical Entry, Entity, and Goal contracts, optional Home Locations, and the paused AI state.
The retired native Place surface and saved-Location catalog are removed; the existing screen layouts and accepted splash remain.
Native navigation now uses Dashboard, Inbox, Timeline, Library, and More, with the active Web destinations grouped under More.
The native MapKit screen and Debug Design System gallery are implemented; personal acceptance and broad screen migration remain pending.
The merged Web release still needs Production deployment verification and browser acceptance; live configuration, native interactions, CI, and recovery evidence remain incomplete.

Use Git history for feature-level implementation and test evidence.

| Area                                                                                            | State                                                                                                                                                                |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture, Inbox, organization, dates, drafts, and offline queues                                 | Implemented on Web and iOS                                                                                                                                           |
| Timeline, Home (Dashboard on Web), First Times, Homes, Vehicles, Goals, People, and Collections | Implemented on Web and iOS; the retired Place surface is removed                                                                                                     |
| Location data layer                                                                             | Web and native Map, optional Home Location, photo GPS provenance, and Web provider quotas are implemented; personal acceptance remains.                              |
| Habits                                                                                          | Deferred and removed from the active Web, iOS, and hosted database product surface                                                                                   |
| Web navigation shell                                                                            | Persistent across routes with prefetch, route fallback, and cold-request feedback                                                                                    |
| Web Settings                                                                                    | Account, preferred name, dates, timezone, appearance, browser-local Timeline style, simplified AI, and account controls implemented                                  |
| Web Collections and tags                                                                        | Direct Library destinations and shared Entry organization editor implemented                                                                                         |
| Keyword and Command Palette search, grounded AI, suggestions, and Explore with AI               | Keyword search remains available. Web AI is paused behind an off/disabled Beta setting; provider logic and historical data are retained.                             |
| Private media, Entry history, relationships, Trash, and complete export                         | Implemented; hosted APIs accepted with synthetic data; final UI acceptance remains                                                                                   |
| Hosted Supabase contracts                                                                       | `202609240004` is deployed to project `kaivkozeyuwzqrckmyqu`; the remote ledger matches the repository                                                               |
| Entry-centered information model                                                                | Web, hosted database, and native iOS use Entry, focused records, and intentional Timeline Moment or Period; native personal acceptance remains                       |
| Web design system                                                                               | Approved canonical components migrated across Web; component-owned CSS and token boundaries enforced; local regression passed; production browser acceptance pending |
| Backup and restore                                                                              | Not ready                                                                                                                                                            |
| Current GitHub CI                                                                               | Manually disabled; the previous jobs failed before starting because of account billing or spending limits                                                            |

The latest hosted synthetic run verified JPEG, HEIC, and PNG display derivatives, metadata extraction, unchanged originals, and a complete ZIP with all canonical datasets.
Its marked account and Storage objects were confirmed removed without accessing personal data or calling AI.

## Next work

### 1. Release and accept the Entry-centered Web flow

- Verify the merged `main` deployment against the migrated hosted project, then check Quick Capture, Inbox review, Library routing, First Time, Moment, Period, Home, Vehicle, and Goal in a browser.
- The Vercel Preview has no Supabase public environment variables, so browser acceptance will be done by Ryan in a configured environment.
- Native compatibility is updated separately; complete personal native acceptance before treating it as a release.
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
- Native MapKit now reads current Entry-owned Locations and supports native clustering, Kind/year filters, city shortcuts, and associated record navigation.
  Native address-provider search remains deferred; manual Home addresses follow the Entry-owned, optional Location contract.

### 3. Accept native foundations, Map, and navigation

- Native models, filters, Capture, and ordinary Inbox review now use the shared canonical identities; focused forms retain their existing RPCs.
- Home Location IDs and labels decode as optional, and editing address facts clears stale coordinates.
- Supabase public configuration matches Web locally. Media, metadata, and export use the Web API base URL; Geoapify, AI, and Supabase secret keys remain on the server.
- Shared media and export authentication is independent of the AI pause; local HTTP checks cover native bearer identity, Web cookies and Origin checks, metadata, retired catalog responses, invalid sessions, and all four paused AI endpoints.
- The Simulator build passes, along with 202 native tests without skips, including five real local Supabase contract tests for Capture/review/search, Moment/Period, optional Home Location, and focused records across Library, Collections, and Home, plus current Map Locations and Trash exclusion.
  The temporary local test account and its owned data were removed.
  Debug and Release Simulator builds pass.
  Four Simulator UI scenarios cover native editor actions, MapKit clustering and filters, More routing, and gallery appearance/text-size controls; screenshot review is separate from personal data acceptance.
  The shared API change passed the native API and existing AI-pause E2E scenarios, 445 Web unit tests, lint, type checking, and repository formatting.
  A signed Simulator build launches to the Google sign-in screen; personal login, physical-device flows, and deployed shared API acceptance remain pending.
- Review the Debug-only native Design System gallery, including appearance, Dynamic Type, action states, forms, cards, media, toasts, and feedback.
  The new Map uses its shared presentation components; existing screens retain their layouts pending acceptance.
  Native actions, badges, headers, empty states, form fields, record and Collection cards, read-only rich writing, toasts, remote images, upload progress, and the photo field now mirror the Web gallery specimens.
  First Times, Homes, Vehicles, Goals, Collections, and the Entry photo viewer load photos through the shared remote image; Home and Trash follow with their screen syncs.
  Ten Simulator UI scenarios pass, adding form pickers, organization editing, toasts, photo field removal, and a gallery screenshot tour; 215 unit tests pass, with the five local Supabase contract tests skipped without a local stack.
  One shared OccurrenceEditor and tag/Collection editor now serve Capture, Inbox review, Timeline, First Times, Homes, Vehicles, and Goals, with the Web Date types, Present end, and optional description.
- The gallery's Writing & formatting page now previews a native Aa toolbar with bold, italic, underline, strikethrough, selection formatting, typing styles, undo/redo, and saved note reopening.
  The sample form uses the same reusable editor.
  Preview saves round-trip Web-compatible paragraph and emphasis JSON locally; they do not create an Entry.
  Six targeted native tests and three Simulator UI scenarios pass, with no runtime warnings.
  Web's actual validator accepts the Swift-encoded payload; light, dark, large-text, and native selection screenshots were reviewed.
  After component acceptance, adopt the rich payload in native Capture drafts, offline queues, review saves, and full-note rendering before enabling it on those business screens.
- Native Settings routing includes Account, dates/timezone context, app-local appearance, Collections, Tags, organization settings, export, and the paused Beta AI state.
  Web profile/date preference editing is not yet replicated on iOS.
- Review the normal authenticated Map against personal records; synthetic Simulator interaction evidence is separate from this acceptance.
- Refactor existing screens after component acceptance; native address search remains later work.

### 4. AI capabilities paused

- Web AI entry points are removed; Settings shows an off, disabled Beta status.
- Earlier AI narrative, requirements, and decision-model exploration are preserved in the [AI direction record](./ai-direction-record.md), not discarded with the UI.
- Existing AI business logic, saved preferences, and historical records remain intact behind a server pause gate.
- The old AI settings, search form, Entry suggestions panel, and exploration UI components and their dedicated styles are deleted, not merely unmounted.
- The Beta pause page has its own minimal styles; old Explore URLs retain only a redirect, and future AI UI must be designed anew.
- Do not install a local model or enable Production AI as part of this work.
- Resume only after worthwhile use cases and redesigned entry points are accepted; decision-model actions remain exploratory.
- Branch validation passed 445 unit tests, lint, type checking, a production build, and targeted AI-pause, Settings, page-frame, and navigation browser tests.
- The AI-pause flow also passed against a local production build; four retained active-AI E2E scenarios are explicitly skipped while paused, while provider unit tests still run.
- A development navigation run logged a client-aborted request; the production-build AI-pause check passed without that diagnostic.
- Production deployment and live acceptance remain unverified; native AI entry points now follow the same pause.

### 5. Complete real interaction acceptance

- Verify an actual production browser export download.
- Verify native Save and share for a production export.
- Exercise authenticated native capture, photos, galleries, Trash, AI pause status, and export through the real UI with an isolated account.
- Finish the remaining photo-surface and specialized metadata or relationship lifecycle audit.

### 6. Establish recovery

- Choose separately protected destinations for database backups and original Storage objects.
- Decide whether to enable point-in-time recovery; the latest inventory showed PITR disabled and no listed restore point.
- Complete and inspect a full restore in a non-production project.
- Audit abandoned unregistered uploads before approving automatic retention cleanup.

### 7. Restore current CI evidence

- Resolve the GitHub account billing or spending-limit issue.
- Re-enable the manually disabled CI workflow after the account issue is resolved.
- Rerun all Web, iOS, and database jobs for current `main` and confirm they actually execute.

## Watch list

- A valid hosted media session previously returned intermittent HTTP 401 responses before a later run passed. Do not attribute recurrence to the decoder repair without evidence.
- Next.js may log a client-aborted React Server Components request while application assertions pass. Keep it distinct from a product failure until the stable upstream fix is adopted.

## Updating this file

Keep only current state, the next actionable work, and unresolved blockers.
Remove resolved details and rely on Git history instead of appending progress entries.
Product scope and deferred features belong in [product.md](./product.md).
