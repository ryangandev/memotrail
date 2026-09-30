# MemoTrail Status

Last reviewed: 2026-09-29.

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
Native navigation now uses Dashboard, Inbox, Timeline, Library, and More, with the active Web destinations grouped under More and the Web navigation icons.
The native Dashboard now follows the Web Data Ribbon order and links, verified against a seeded local account.
The native Inbox now matches the Web review list and Review Entry dialog, including Move to Trash and formatted note review, verified against a seeded local account.
The native Library now matches Web Library, combining the all-items browser with keyword search, grouped filters, formatted result notes, and match reasons, verified against a seeded local account.
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
  First Times, Homes, Vehicles, Goals, Collections, and an Item's Current photos load photos through the shared remote image; Home and Trash follow with their screen syncs.
  Twelve Simulator UI scenarios pass, adding form pickers, organization editing, toasts rising clear of the keyboard, photo field removal, and a gallery screenshot tour; all 246 native tests pass against local Supabase, including twelve contract tests.
  `review-local-session.py` now runs signed-in UI flows as a seeded, disposable local account, so screen syncs are checked against real local data rather than synthetic previews.
  One shared OccurrenceEditor and tag/Collection editor now serve Capture, Inbox review, Timeline, First Times, Homes, Vehicles, and Goals, with the Web Date types, Present end, and optional description.
- The gallery's Writing & formatting page now previews a native Aa toolbar with bold, italic, underline, strikethrough, selection formatting, typing styles, undo/redo, and saved note reopening.
  The sample form uses the same reusable editor.
  Preview saves round-trip Web-compatible paragraph and emphasis JSON locally; they do not create an Entry.
  Six targeted native tests and three Simulator UI scenarios pass, with no runtime warnings.
  Web's actual validator accepts the Swift-encoded payload; light, dark, large-text, and native selection screenshots were reviewed.
  Native Capture now uses this editor as its single note, like the Web composer, and stores Web-compatible `body_rich` through drafts, the offline queue, and sync; a seeded local run confirmed the stored bold run.
  Native Inbox review now saves the same payload through `review_wiki_item_with_photo_place_rich` and keeps untouched Web-only formatting; a seeded local run confirmed a stored bold edit and an unchanged Web list.
  Native full-note rendering on focused record pages still needs to adopt the rich payload.
- Native Settings now follows Web `/settings`: the account card with Sign out, preferred name, birth date, and default time zone each save on their own with Web validation and toasts, then app-local appearance and the paused Beta AI, organization, and export rows.
  The Dashboard greeting refreshes after a name save; a local contract run and a seeded Simulator UI run confirmed saving, clearing, and the greeting.
  Web's browser-local Timeline style stays Web-only.
- Native Timeline now follows the Web phone layout with the shared header, type chooser, birth date prompt, and a Timeline editor that uses the Settings time zone and saves Collections and tags.
  Local contract and seeded Simulator runs confirmed creating, editing, and trashing Moments and saving the birth date.
  Manage tracks opens the Web track page, where each track saves its own name, order, and visibility.
- Native Homes now follow Web `/homes` and its focused Home page: record cards with a photo, map, or mark, the facts, Story, and Organize page with Edit and Version history, and the sectioned Web Home editor.
  Local contract and seeded Simulator runs confirmed opening a Home from Homes and the Timeline, editing it, adding one, and moving it to Trash.
- Native Vehicles now follow Web `/vehicles` and its focused Vehicle page: one Vehicle archive of record cards with a photo, map, or mark, the When, Vehicle, and Location facts page, and the sectioned Web Vehicle editor with its Location panel.
  Local contract and seeded Simulator runs confirmed loading and removing a Vehicle's Location, opening a Vehicle from Vehicles and the Timeline, editing it, adding one, and moving it to Trash.
- Native First Times now follow Web `/first-times` and its focused First Time page: the archive of record cards with a photo, map, or number, the When and Location page, and the Web First Time editor with its Location panel.
  Local contract and seeded Simulator runs confirmed loading and removing a First Time's Location, opening a First Time from First Times and the Timeline, editing it, adding one, and moving it to Trash.
- Native Goals now follow Web `/goals` and its focused Goal page: record cards grouped by reflective state, the Status, Horizon, and Target page with Connected Items, and the sectioned Web Goal editor with Related Items and the Bucket List milestone.
  Local contract and seeded Simulator runs confirmed recording a Bucket List achievement with its linked First Time, following connected Items to a Home page and the Timeline, replacing a related Item, adding a Goal, and moving it to Trash.
- Native People now follow Web `/people` and its focused Person page: cards with the initial, relationship, a short note, and connected Item count; the Relationship, Notes, and Connected Items page; and the Web Person editor with its linked Item picker.
  Local contract and seeded Simulator runs confirmed opening a Person from Library and People, following connected Items to the Timeline and a Home page, swapping a linked Item, keeping a linked Person out of Trash, moving them to Trash once unlinked, and adding one.
- Native Item pages and version history now follow Web `/items/[entry]` and `/history`: the current writing and facts with Edit, Version history, Create linked Goal, and Move to Trash; Related Items with the Web views and search; Current photos in the shared photo field; and the version picker, differences, side-by-side snapshots, and Restore.
  Local contract and seeded Simulator runs confirmed opening an Entry from Library, linking and following another Item, restoring the version from before the link, loading current photos, creating a linked Goal, and moving the Entry to Trash at the revision shown.
- Native Tags now follow Web `/tags`: tag badges with Entry counts, name search, New Tag, and the Web tag editor with its Entry previews, merge panel, and unused-tag deletion.
  A seeded Simulator run confirmed searching tags, opening a tagged Entry from the editor, merging one tag into another, creating and deleting an unused tag, and opening Library filtered to a tag.
- Native Collections now follow Web `/collections` and its Collection pages: compact cards with each Collection's editor, New Collection, and Entry cards with Web's rich notes, Read full note, and Collection and tag links into Library.
  A seeded Simulator run confirmed creating a Collection ahead of the others by display order, opening an Entry and a filtered Library from a Collection, opening Quick Capture from New entry, moving an empty Collection to Trash from its page, and reaching Collections from the Settings sheet.
- Native Trash now follows Web `/trash`: the retention badge and note, Web's cards with the photo or mark, removal date, and restorable window, toasts for each result, and the Permanent action sheets for Delete forever and Empty Trash.
  A seeded Simulator run confirmed restoring a Collection, deleting one forever, and emptying Trash with its confirmation.
- The native More tab now follows Web's mobile More menu: the shared workspace header, then Explore, Focused views, Organize, and Archive and account as two columns of destinations with Web's icons.
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
