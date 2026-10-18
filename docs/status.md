# MemoTrail Status

Last reviewed: 2026-10-10.

## Focus

Web is the client Ryan uses most, so work now focuses on finishing Web before returning to native iOS.
Native iOS work, including the acceptance items in section 3, is paused until Web is complete; native then follows the finished Web behavior.
Before more Web building, unclear features and requirements are reviewed with Ryan and settled in [product.md](./product.md).
The first review removed general links between Entries from Web; source and achievement links remain.
Product direction is settled before UI questions.
Collections are merged into tags: each Collection became a tag with the same name and kept its Entries.
Migration `202610040001` carries this change; native iOS still calls the retired Collection functions until it follows Web.
People are removed: migration `202610040002` deletes every Person, its Entity Wiki Item, its links, and its version history, and strips People from Entry version snapshots.
Native iOS still calls the retired People functions until it follows Web.
Goals became Someday: migration `202610040003` maps Considering and Paused to the open status, shown as Not yet, drops horizons, and stops Goal saves from touching related links; the former Bucket List Collection is already an ordinary tag.
Native iOS still sends horizons and related links and fails against it until it follows Web.
The list is named Someday and its open status Not yet; the working name Want to Do is retired.
Inbox is retired: captures save straight to Library, and Library and the Dashboard show Entries without a title or tag under Needs organizing.
Migration `202610040004` marks every Entry organized, keeps new ones organized, and drops the Inbox organize and capture-handoff functions.
Native iOS still opens Inbox review and calls the retired functions until it follows Web.
Native iOS is not in use and will be rewritten, so the database keeps no compatibility window for it.
Migration `202610040005` drops `entries.inbox_status`, the Dashboard Inbox count, the organize flag on Entry review, the Capture source on Home and Vehicle saves, the constant record source in Library and search, the empty Trash storage path helper, and the native-only review functions.
General related links are deleted: migration `202610040006` removes them, including those older Goals carried, from the data and version history, and drops the functions that browsed and edited them.
Version history is removed: migration `202610040007` deletes every stored version and stops recording them, stops photo changes from creating Entry revisions, drops Locations kept only for history, and purges prepared export snapshots.
`/history` links open the Item page or Library.
Database leftovers are dropped: migration `202610040008` links Home Locations through `entry_locations` like every other Entry, turns `related` Location links into `photo` links and `source_capture` Entries into plain Entries, drops unused Location columns and functions no client calls, and replaces the Entry review chain with one `save_entry`.
Timeline shows life milestones: any Entry can be marked as a Moment or a Period in Work and study or Other milestones, and a First Time is a flag on a milestone.
Homes and Vehicles appear on Timeline in their own lanes, custom tracks are gone, First Times is a filtered view of Entries, and the Dashboard Now block replaces current chapters.
Migration `202610040009` converts existing Moments, Periods, First Times, and track placements into milestones and turns custom track names into tags.
Native iOS still calls the retired Timeline and First Time functions until it follows Web.
Migrations `202610040001` through `202610040009` were applied to the hosted project on 2026-10-05 after a schema and data backup, and `main` at `cf68cab` was deployed to Production.
Item page photos, the export page, and Timeline styles are settled: photos show on the Item page and are edited in the Entry editor, export is one Export everything action, and Timeline keeps only the lane view.
The date precision controls are settled too: Web date forms choose Day, Month, Year, or Not sure, with Add time and Add end date toggles, and an empty date means Unknown.
Native iOS still shows the eight Date types until it follows Web.
Web Timeline no longer opens the birth date prompt on its own; native iOS still asks on the first Timeline visit until it follows Web.
Open `audit-2026-10` issues stay tracked in GitHub.

## Current state

The Entry-centered Web information model was merged into `main` through PR #9, and its migration is live on the confirmed Supabase project.
Authored Place records have also been removed from Web and the hosted schema; Entry-owned Locations and the Map remain.
The obsolete Places Timeline track has been removed, with existing placements migrated to the general track.
The Web Map and Location previews now follow light, dark, and System appearance; a local provider-backed dark map loaded successfully.
The Map also offers filtered shortcuts to the user's most recorded cities when records span more than one city.
The desktop sidebar has a compact icon rail, panel control, and animated width change; its browser preference persists across reloads.
The Web sidebar supports an editor-aware Command B shortcut, and the bottom glass dock groups sparkle-icon New Entry on the left with Search on the right, retaining Command J and Command K.
The capture dock uses an inset focus ring, a consistent frosted composer surface, and a retained editor with entrance and exit motion; personal visual acceptance is pending.
Library now combines the organized all-items browser with keyword and filtered search; older `/search` URLs redirect to Library.
The Entry editor hides AI suggestions and places photos after tags; the Library browser includes every capture as soon as it is saved.
Web AI capabilities are paused, with a disabled Beta setting and no active AI entry points.
The accepted Data Ribbon layout now replaces the Web Dashboard, using the signed-in user's data and the shared capture, page, image, empty-state, and tag components.
The development preview routes and all 20 static Home mockups have been removed; Production deployment verification and browser acceptance remain pending.
Native iOS now adopts the canonical Entry, Entity, and Goal contracts, optional Home Locations, and the paused AI state.
The retired native Place surface and saved-Location catalog are removed; the existing screen layouts and accepted splash remain.
Native navigation now uses Dashboard, Inbox, Timeline, Library, and More, with the active Web destinations grouped under More and the Web navigation icons.
The native Dashboard now follows the Web Data Ribbon order and links.
The native Inbox now matches the Web review list and Review Entry dialog, including Move to Trash and formatted note review.
The native Library now matches Web Library, combining the all-items browser with keyword search, grouped filters, formatted result notes, and match reasons.
The native MapKit screen and Debug Design System gallery are implemented; personal acceptance and broad screen migration remain pending.
Adding or removing a photo in a focused First Time, Home, Vehicle, or Goal editor no longer makes Move to Trash or Mark achieved report a false conflict on Web or native.
Delete forever and Empty Trash now delete an item's record before its private photo files on Web and native, so an interrupted request or a Restore from another device can no longer leave a restorable item without its originals.
Restore refuses an item whose originals are missing, and opening Trash finishes any file removal left unfinished.
Migration `202610030003` enforces this order on the server for every client, including deployed ones.
Pending captures now stop as Not accepted instead of retrying forever when Storage refuses a photo or the Entry is already in Trash, and a capture still waiting on a device can no longer create an Entry again after Delete forever, on Web and native.
Migration `202610030004` records each Entry deleted forever and refuses to insert it again.
Migrations `202610030001` through `202610030004` are applied to the hosted project, which the new Web and native clients require.
The merged Web release still needs Production deployment verification and browser acceptance; live configuration, native interactions, and recovery evidence remain incomplete.

Use Git history for feature-level implementation and test evidence.

| Area                                                                              | State                                                                                                                                                                        |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture, organization, dates, drafts, and offline queues                          | Implemented on Web and iOS; Web retired Inbox for Needs organizing in Library, while native still shows Inbox                                                                |
| Timeline, Home (Dashboard on Web), First Times, Homes, Vehicles, and Someday      | Implemented on Web and iOS; Web simplified Goals into Someday and turned Timeline into fixed-lane milestones, and the retired Place and People surfaces are removed from Web |
| Location data layer                                                               | Web and native Map, optional Home Location, photo GPS provenance, and Web provider quotas are implemented; personal acceptance remains.                                      |
| Habits                                                                            | Deferred and removed from the active Web, iOS, and hosted database product surface                                                                                           |
| Web navigation shell                                                              | Persistent across routes with prefetch, route fallback, and cold-request feedback                                                                                            |
| Web Settings                                                                      | Account, preferred name, dates, timezone, appearance, simplified AI, and account controls implemented                                                                        |
| Web tags                                                                          | One Tags destination and shared Entry tag editor implemented; Collections are merged into tags                                                                               |
| Keyword and Command Palette search, grounded AI, suggestions, and Explore with AI | Keyword search remains available. Web AI is paused behind an off/disabled Beta setting; provider logic and historical data are retained.                                     |
| Private media, relationships, Trash, and complete export                          | Implemented; hosted APIs accepted with synthetic data; final UI acceptance remains                                                                                           |
| Hosted Supabase contracts                                                         | Every repository migration through `202610040009` is deployed to project `kaivkozeyuwzqrckmyqu`; `202610040001` through `202610040009` were applied on 2026-10-05            |
| Entry-centered information model                                                  | Web, hosted database, and native iOS use Entry, focused records, and intentional Timeline Moment or Period; native personal acceptance remains                               |
| Web design system                                                                 | Every value comes from shared tokens and lint rejects hardcoded ones; 28 component specs shared with iOS; production browser acceptance pending                              |
| Backup and restore                                                                | Not ready                                                                                                                                                                    |
| Current GitHub CI                                                                 | Pull requests run the Linux Web job and a Supabase job with database tests, data contracts, and the full browser suite; native checks run locally                            |

## Next work

### 1. Release and accept the Entry-centered Web flow

- Verify the Production deployment against the hosted project migrated through `202610040009`, then check Quick Capture, Needs organizing, Library, Timeline milestones, First Times, the Dashboard Now block, Home, Vehicle, and Someday in a browser.
- The Vercel Preview has no Supabase public environment variables, so browser acceptance will be done by Ryan in a configured environment.
- Native iOS is rewritten to follow Web once Web is complete; complete personal native acceptance before treating it as a release.
- The hosted schema matches the migrations except for platform privilege defaults that `supabase db diff --linked` reports.
  Hosted `service_role` and `anon` get no table access or function execution unless a migration grants it, and new public tables get row level security automatically.
  Local Supabase grants both roles by default, so a missing explicit grant can pass every local suite and fail only on the hosted project.

### 2. Accept Web Location

- The confirmed hosted project `kaivkozeyuwzqrckmyqu` is migrated through `202610040009`, which includes every Location migration. Home Location copy-on-write compares coordinates at the database's six-decimal storage precision.
- Web now has optional Home Locations, address search that feeds Entry-owned Location snapshots on save, keyboard-accessible address suggestions, explicit photo GPS source identity, owner-scoped Geoapify quotas, and a clustered Map of current Entry coordinates with Kind and year filters.
- `localhost:3000` points to the linked cloud Supabase project.
- Accept the revised UI with a personal `localhost:3000` record, including retrying a provider-backed Home Location save after the precision migration, Home removal/manual address edits, and Entry map points. Map clustering is locally browser-tested but not yet personally accepted against hosted data.
- The accepted shared SearchField is now used across Web search surfaces, including Location, Library search, Tags, organization pickers, and Command Palette.
- The server-only Production `GEOAPIFY_API_KEY` is configured in Vercel; Production browser acceptance remains pending.
- Native MapKit now reads current Entry-owned Locations and supports native clustering, Kind/year filters, city shortcuts, and associated record navigation.
  Native address-provider search remains deferred; manual Home addresses follow the Entry-owned, optional Location contract.

### 3. Accept native foundations, Map, and navigation

Paused until Web is complete; see Focus.
When native resumes, remove the general Related Items panel from the native Item page to match Web.
Migration `202610040006` already drops the `entry_relations` and `set_entry_relation` functions that panel calls.

- Native models, filters, Capture, and ordinary Inbox review now use the shared canonical identities; focused forms retain their existing RPCs.
- Native `InboxController` retries waiting captures only when its network path becomes satisfied, a capture is saved, or Inbox or Home refreshes, including on return to the foreground.
  A failed attempt therefore waits for one of those events; Web now keeps retrying with capped backoff while online, and native should adopt the same policy.
- Home Location IDs and labels decode as optional, and editing address facts clears stale coordinates.
- Supabase public configuration matches Web locally. Media, metadata, and export use the Web API base URL; Geoapify, AI, and Supabase secret keys remain on the server.
- Shared media and export authentication is independent of the AI pause; local HTTP checks cover native bearer identity, Web cookies and Origin checks, metadata, retired catalog responses, invalid sessions, and all four paused AI endpoints.
  A signed Simulator build launches to the Google sign-in screen; personal login, physical-device flows, and deployed shared API acceptance remain pending.
- Review the Debug-only native Design System gallery, including appearance, Dynamic Type, action states, forms, cards, media, toasts, and feedback.
  The new Map uses its shared presentation components; existing screens retain their layouts pending acceptance.
  Native actions, badges, headers, empty states, form fields, record and Collection cards, read-only rich writing, toasts, remote images, upload progress, and the photo field now mirror the Web gallery specimens.
  First Times, Homes, Vehicles, Goals, Collections, and an Item's Current photos load photos through the shared remote image; Home and Trash follow with their screen syncs.
  One shared OccurrenceEditor and tag/Collection editor now serve Capture, Inbox review, Timeline, First Times, Homes, Vehicles, and Goals, with the Web date precision, Present end, and optional description at the time.
- The gallery's Writing & formatting page now previews a native Aa toolbar with bold, italic, underline, strikethrough, selection formatting, typing styles, undo/redo, and saved note reopening.
  The sample form uses the same reusable editor.
  Preview saves round-trip Web-compatible paragraph and emphasis JSON locally; they do not create an Entry.
  Web's validator accepts the Swift-encoded payload.
  Native Capture now uses this editor as its single note, like the Web composer, and stores Web-compatible `body_rich` through drafts, the offline queue, and sync.
  Native Inbox review now saves the same payload through `review_wiki_item_with_photo_place_rich` and keeps untouched Web-only formatting.
  Native full-note rendering on focused record pages still needs to adopt the rich payload.
- Native Settings now follows Web `/settings`: the account card with Sign out, preferred name, birth date, and default time zone each save on their own with Web validation and toasts, then app-local appearance and the paused Beta AI, organization, and export rows.
  The Dashboard greeting refreshes after a name save.
- Native Timeline now follows the Web phone layout with the shared header, type chooser, birth date prompt, and a Timeline editor that uses the Settings time zone and saves Collections and tags.
  Manage tracks opens the Web track page, where each track saves its own name, order, and visibility.
- Native Homes now follow Web `/homes` and its focused Home page: record cards with a photo, map, or mark, the facts, Story, and Organize page with Edit and Version history, and the sectioned Web Home editor.
- Native Vehicles now follow Web `/vehicles` and its focused Vehicle page: one Vehicle archive of record cards with a photo, map, or mark, the When, Vehicle, and Location facts page, and the sectioned Web Vehicle editor with its Location panel.
- Native First Times now follow Web `/first-times` and its focused First Time page: the archive of record cards with a photo, map, or number, the When and Location page, and the Web First Time editor with its Location panel.
- Native Goals now follow Web `/goals` and its focused Goal page: record cards grouped by reflective state, the Status, Horizon, and Target page with Connected Items, and the sectioned Web Goal editor with Related Items and the Bucket List milestone.
- Native People now follow Web `/people` and its focused Person page: cards with the initial, relationship, a short note, and connected Item count; the Relationship, Notes, and Connected Items page; and the Web Person editor with its linked Item picker.
- Native Item pages and version history now follow Web `/items/[entry]` and `/history`: the current writing and facts with Edit, Version history, Create linked Goal, and Move to Trash; Related Items with the Web views and search; Current photos in the shared photo field; and the version picker, differences, side-by-side snapshots, and Restore.
- Native Tags now follow Web `/tags`: tag badges with Entry counts, name search, New Tag, and the Web tag editor with its Entry previews, merge panel, and unused-tag deletion.
- Native Collections now follow Web `/collections` and its Collection pages: compact cards with each Collection's editor, New Collection, and Entry cards with Web's rich notes, Read full note, and Collection and tag links into Library.
- Native Trash now follows Web `/trash`: the retention badge and note, Web's cards with the photo or mark, removal date, and restorable window, toasts for each result, and the Permanent action sheets for Delete forever and Empty Trash.
- The native More tab now follows Web's mobile More menu: the shared workspace header, then Explore, Focused views, Organize, and Archive and account as two columns of destinations with Web's icons.
- Native sign-in now follows Web `AuthGate` at phone width: the brand header, the welcome story, and the sign-in card with Web's own Continue with Google button and Setup needed notice.
- Native Export now follows Web `/settings/export`: the page header, the Everything in one ZIP and Prepare a snapshot cards, snapshot cards with Download ZIP and an inline discard confirmation, and toasts for each result.
- Native Quick Capture now follows Web `QuickCaptureDialog` at phone width: the full-screen composer under Web's header and close button, the relevant date panel in place of a separate sheet, Web's photo and status strips, and a toast once the capture syncs.
  Like Web, a capture saved without a connection is confirmed once with an info toast that it is safe on this iPhone; later offline retries stay quiet until it syncs and announces Saved to Inbox.
  Web's bottom capture dock landed after this sync, so native still opens New entry from the header and Quick Capture full screen; adopting the dock and its bottom-anchored composer remains native work.
- Native Map now follows Web `/map` at phone width: the page header, Category and year fields that filter as they change, Your areas shortcuts with View all, the map card, and the Entries here panel for the chosen pin or cluster, instead of a filter sheet and a record list sheet.
- Review the normal authenticated Map against personal records; synthetic Simulator interaction evidence is separate from this acceptance.
- Native History, Timeline, Homes, Vehicles, First Times, Goals, People, and Trash now apply only their newest load, so a slower refresh can no longer replace the reload after a restore or save.
- Refactor existing screens after component acceptance; native address search remains later work.

### 4. AI capabilities paused

- Web AI entry points are removed; Settings shows an off, disabled Beta status.
- Earlier AI narrative, requirements, and decision-model exploration are preserved in the [AI direction record](./ai-direction-record.md), not discarded with the UI.
- Existing AI business logic, saved preferences, and historical records remain intact behind a server pause gate.
- Web captures no longer start suggestion work while paused.
  The browser capture scenario in `ai-paused.e2e.ts` reaches that path only with `MEMOTRAIL_E2E_LIVE_AI=1` and a synthetic `AI_API_KEY`, because the default E2E server disables the provider; both modes pass.
- The old AI settings, search form, Entry suggestions panel, and exploration UI components and their dedicated styles are deleted, not merely unmounted.
- The Beta pause page has its own minimal styles; old Explore URLs retain only a redirect, and future AI UI must be designed anew.
- Do not install a local model or enable Production AI as part of this work.
- Resume only after worthwhile use cases and redesigned entry points are accepted; decision-model actions remain exploratory.
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

### 7. Redesign the UI on the finished design system

The design system the redesign builds on is complete.
Web and iOS draw every visual value from the DTCG tokens in `packages/design-system/tokens`, and `pnpm lint` and `pnpm design-system:check` reject hardcoded values.
All 28 shared components have a YAML spec that generates their variant types for both platforms, and both galleries show every specimen the specs list.
The Claude Design copy is published from `pnpm design-system:export`; values tried there return through pull requests.

The redesign itself waits for Ryan's direction.
These open design decisions feed it:

- The type, spacing, and radius scales are named by value, so a retuned scale renames tokens.
- Six groups of contrast pairs are named exceptions until a palette change: inkFaint metadata, muted text on subtle panels, warm, danger, and warning text in light, and success text on its notice.
- The brand mark's outer ring and arc use themed colors on iOS and fixed colors on Web, so the platforms differ in dark mode.
- iOS `accentGroupBorder` looks the same as the shared `accentPanelBorder`, but merging them could shift a color by one rounding level.
- Web `textSpace` is relative to the text size, so the paragraph gap is shared with iOS only once the Swift generator supports relative units.
- Library filters mix two field styles: Record and Tag are hand-styled selects with uppercase labels, while From and To use the shared date field with sentence-case labels.

## Watch list

- A valid hosted media session previously returned intermittent HTTP 401 responses before a later run passed. Do not attribute recurrence to the decoder repair without evidence.
- Next.js may log a client-aborted React Server Components request while application assertions pass. Keep it distinct from a product failure until the stable upstream fix is adopted.
- Two native UI tests have each failed once under load and passed on rerun: `testPhotoFieldSamplesUploadProgressAndRemoval`, whose upload progress shows for about 1.8 seconds, and the rich-text typing test's bold assertion.

## Updating this file

Keep only current state, the next actionable work, and unresolved blockers.
Remove resolved details and rely on Git history instead of appending progress entries.
Do not record test counts, run results, or before-and-after evidence here; they belong in the pull request description.
Product scope and deferred features belong in [product.md](./product.md).
