# MemoTrail Architecture

Last reviewed: 2026-09-28.

## System map

| Area              | Responsibility                                                              | Primary location                                                                                   |
| ----------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Web client        | Next.js routes, server actions, responsive UI, browser drafts and queues    | `apps/web/src/app`, `apps/web/src/components`, `apps/web/src/lib`                                  |
| Web server        | Authenticated AI, media, metadata, and export APIs                          | `apps/web/src/app/api`, `apps/web/src/lib/ai`, `apps/web/src/lib/media`, `apps/web/src/lib/export` |
| Native client     | SwiftUI screens, controllers, device drafts and queues, native integrations | `apps/ios/MemoTrail/Features`, `apps/ios/MemoTrail/Models`, `apps/ios/MemoTrail/App`               |
| Shared data       | Postgres schema, RLS, Storage policies, atomic RPCs, history, and search    | `supabase/migrations`                                                                              |
| Data verification | Ownership, denial, concurrency, lifecycle, and contract tests               | `supabase/tests`                                                                                   |
| Design tokens     | Semantic source tokens and generated Web and Swift outputs                  | `packages/design-tokens`                                                                           |
| Web design system | Reusable Web components and the development-only audit gallery              | `apps/web/src/components`, `apps/web/src/app/design-system`                                        |
| Media runtime     | Deployable image and metadata decoder dependencies                          | `packages/media-runtime`                                                                           |
| Delivery          | Web, iOS, and database CI                                                   | `.github/workflows/ci.yml`                                                                         |

Vercel builds the repository with `apps/web` as the application root.
Supabase migrations and the iOS Xcode project are independent of the Node workspace.

The Web root layout owns the authenticated application shell, including navigation, account context, and the Inbox count.
Route pages render only their own server-backed content inside that persistent shell.
Next.js link prefetching and `app/loading.tsx` provide route fallbacks, while navigation links expose immediate pending feedback when a cold request has not reached the fallback yet.

## Request-to-code map

Use this table to find the first likely files, then search by the product term or RPC name.
Web paths are relative to `apps/web/src`; iOS paths are relative to `apps/ios/MemoTrail`.

| Request                                                   | Web                                                                                                                                 | iOS                                                                                   | Shared data and tests                                                            |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Authentication or environment                             | `app/auth`, `lib/auth`, `lib/supabase`, `src/proxy.ts`                                                                              | `Features/Authentication`, `App/AppConfiguration.swift`                               | foundation and security migrations, `0001_rls.test.sql`                          |
| Capture, Inbox, drafts, dates, rich text, or offline sync | `app/inbox`, capture, rich-text and occurrence components, `lib/data/inbox*`, `lib/data/rich-text.ts`, `lib/data/occurrence.ts`     | `Features/Inbox`, `Models/InboxEntry.swift`, `Models/EntryOccurrence.swift`           | Inbox, occurrence, review, and media migrations and matching tests               |
| Library browsing, search, AI suggestions, or exploration  | `app/library`, `components/library-search`, `app/search` redirect, `app/explore`, `app/settings/ai`, `lib/ai`, `lib/data/search*`   | `Features/Library`, `Features/AI`                                                     | AI, evidence, exploration, and search migrations and tests                       |
| Photos, metadata, or export                               | media and export API routes, `lib/media`, `lib/export`, gallery and export components                                               | `Features/Inbox`, `Features/History`, `Features/Export`, `Models/MediaDelivery.swift` | media, photo-history, cleanup, and export migrations and tests                   |
| Timeline, Homes, Vehicles, Goals, or First Times          | matching `app` route, workspace component, and `lib/data` module                                                                    | matching directory under `Features` and model under `Models`                          | matching contract and occurrence migrations and tests                            |
| Collections, tags, People, links, history, or Trash       | matching `app` route and component, shared Entry organization editor, `lib/data` organization, relation, history, and Trash modules | matching directory under `Features`                                                   | organization, relationship, history, Trash, and Empty Trash migrations and tests |
| Visual system                                             | shared page frame and components, CSS modules, `styles/generated-tokens.css`                                                        | `DesignSystem`, `DesignSystem/Generated`                                              | `packages/design-tokens/tokens.json` and generator                               |

Native destinations and shared detail routing live in `App/WorkspaceRoute.swift`; the primary tabs live in `App/RootTabView.swift`.
The More tab lays out `WorkspaceRoute.groups` like Web's mobile More menu, with the same groups, order, and icons.
`App/AppNavigator.swift` carries cross-tab links that Web expresses as routes, such as `/inbox?entry=` and `/timeline?entry=`; the destination consumes a request once its data has loaded.
`App/WorkspaceToolbar.swift` is the native form of the Web phone workspace header on each primary tab: the brand mark that opens the Dashboard, New entry for Quick Capture, search into Library, and the initial avatar that opens Settings.
It still carries New entry and search, which Web now places in its bottom `WorkspaceActionDock`.
Map data and MapKit presentation live in `Features/Map`; native Settings live in `Features/Settings`.
`Features/Settings/SettingsController.swift` reads and writes one `profiles` column per save, with the Web validation rules in `Models/ProfileSettings.swift`; `AppNavigator.profileRevision` tells the Dashboard to reload its greeting.
Native controllers that reload after a change (History, Timeline, Homes, Vehicles, First Times, Goals, People, and Trash) give each load a generation token, like `LibraryController`: a reload replaces any load still running, and only the newest response applies.

For a database behavior, search migrations for the newest definition of the relevant RPC instead of assuming the first occurrence is current.
Pair it with the test file carrying the same feature name.

## Shared data rules

- Supabase Postgres is the canonical synchronized data store.
- Row Level Security is the final owner-authorization boundary for exposed data.
- Web cookies and native bearer sessions identify the same Supabase user.
- `entries` is the canonical content table.
- `entries.item_kind` distinguishes ordinary Entries, focused Entities, and Goals.
- `entries.item_subtype` retains focused forms such as `first_time`, `moment`, `period`, `home`, and `vehicle`; descriptive writing and event labels are tags.
- `entries.inbox_status` marks whether an Entry awaits Inbox review.
- `timeline_items` is intentional Timeline placement. A date on an ordinary Entry does not create placement.
- `wiki_items_workspace` supplies one owner-scoped Library row per organized canonical Wiki Item, excluding unreviewed Inbox Entries before filtering and pagination. Person rows expose both the canonical Entry ID and their specialized record ID so clients can preserve identity while opening the correct detail page.
- Web `lib/data/wiki-items.ts` and native `LibraryController` consume that same bounded workspace.
  Web routes typed records to focused detail pages with inline editing and general items to `/items/[entry]`, where current content and primary actions precede an explicit history link.
  Native Library routes Homes, Vehicles, First Times, Goals, and People to their focused pages like Web, other typed records to their focused editors, and other canonical items to the Item page, like Web `/items/[entry]`.
  Like Web `wikiEntryHref`, only a Person row from People opens a Person page; a person Entry opens as an Item.
  Like Web, it sends Inbox captures to their review and Moments and Periods to the Timeline.
  `App/WikiItemLink.swift` holds that routing for every native link to an Item, and `AppNavigator.openLibrary(collection:)` and `openLibrary(tag:)` open Library filtered to one Collection or tag, like Web `/library?tag=`.
- `collection_wiki_items` composes the established paged Collection detail with canonical Kind, subtype, and specialized routing identity. Both clients use it so Collections remain organizational lenses rather than a second generic detail system.
- `people.entry_id` is a required owner-scoped link to a canonical Entity Wiki Item. Triggers keep its name, notes, revision state, and Trash state synchronized.
- The former authored `places` and `place_versions` tables and Place-only RPCs were removed by `202609240002_remove_authored_places.sql`.
- `locations` stores private per-Entry address and coordinate snapshots with provider provenance, revision state, and soft deletion. It is not a Wiki Item or reusable catalog.
- Location rows are immutable through the authenticated table API.
  `review_wiki_item_with_location_rich` atomically creates a Geoapify snapshot or keeps the current Entry's Location and replaces only its `primary` relationship.
  Home's provider-backed save uses `save_home_entry_with_geoapify` to create and link a snapshot in the same transaction; manual Home saves use `resolve_home_location_copy_on_write` for an unchanged current value or a new snapshot.
  Specialized First Time and Vehicle editors use `save_first_time_with_location` and `save_vehicle_with_location` when changing a primary Location, preserving their existing save paths when Location is untouched.
  `locations.bound_entry_id`, owner-scoped foreign keys, and deferred link constraints reject attempts to attach one snapshot to another Entry or commit an active unbound snapshot. Provider identity is provenance, not a deduplication key.
  Replaced or removed snapshots stay bound to their Entry so history restoration remains possible. Permanently deleting that Entry cascades its Location snapshots; moving an Entry to Trash does not.
  Legacy `name` and `notes` columns remain for existing RPC and iOS wire shapes, but compatibility writers ignore those inputs, derive the label from address facts, and clear notes; Web exposes neither custom field nor saved-Location search.
  Homes may omit a Location entirely; `homes_workspace` keeps them visible with a left join, and manual address edits discard stale provider coordinates.
  `coordinate_source` distinguishes manual, Geoapify, and explicitly adopted photo GPS coordinates; `source_attachment_id` points to the adopted original photo while it exists.
- `homes.place_id` and `entry_places.place_id` remain compatibility column names for one cross-client window, but their foreign keys target `locations`; new reads use the `entry_locations` view and Location vocabulary.
- Quick Capture creates an unreviewed `entry:entry`; Web and iOS Inbox review save that same Entry without a Kind selector.
- First Time, Home, Vehicle, Goal, Moment, and Period creation starts in Timeline or a focused view.
- Older source extraction RPCs remain available for existing provenance links, but Web Inbox does not offer focused-form handoffs.
- `capture_extraction_source` and specialized extraction RPCs retain their owner-scoped source revision checks and link provenance when invoked directly.
- Web Goal extraction uses a caller-generated target UUID for idempotency, preserves the source revision and identity, and records `derived` plus `derived_from` provenance links so both items remain discoverable.
- `review_wiki_item_with_photo_place_rich` is the review boundary for clients without a Location editor.
  It writes plaintext and `body_rich` in one revision, clears formatting when `p_body_rich` is null, and leaves the primary Location unchanged.
  The older plaintext `review_wiki_item_with_photo_place` preserves rich metadata it does not understand and has no current client caller.
- Native iOS uses the canonical Entry, Entity, and Goal decoding and filter identities.
  Its ordinary Entry editor, `Features/Inbox/EntryReviewSheet.swift`, serves Inbox review and Edit Entry on the Item page and in version history through `InboxController.submitReview`; focused records keep their own editors and RPCs.
  Moving an Inbox capture to Trash sets `deleted_at` only at the reviewed revision, like Web `trashWikiItem`.
  The retired Place surface and saved-Location catalog are removed, and Home Location is optional.
- Web and iOS create a separately editable Goal with `extract_goal_from_item` when an established Wiki Item inspires a Goal. The caller-generated Goal ID makes lost-response retries idempotent, and History exposes both provenance directions.
- `convert_entry_to_goal` remains only as an administrative recovery function. Authenticated and anonymous clients have no execute grant because established items must never change Kind through a conversion.
- Specialized tables add typed facts without duplicating common writing, organization, dates, media, or history.
- `entries.body` remains canonical plaintext. Optional validated rich content is versioned under `entries.metadata.body_rich`, carries the exact matching plaintext, and is ignored when another client changes the body without updating the rich document.
- Web capture and Entry review use `components/rich-text-editor.tsx` for the reusable headless editor surface, with page, dialog, and form variants instead of separate editors.
  `components/entry-rich-text-content.tsx` safely renders validated formatting on note surfaces and falls back to canonical plaintext when rich metadata is absent, invalid, or stale.
  Formatting controls expose their real keyboard commands through accessible tooltips; drafts and pending queues preserve the same rich payload, while the compatibility RPC `review_entry_with_photo_place_rich` writes plaintext, formatting, organization, occurrence, and photo Location adoption in one revision.
  Older review RPCs preserve rich metadata they do not understand.
- Native `DesignSystem/Components/NativeRichTextEditor.swift` provides a reusable UIKit writing surface with an Aa formatting toggle, bold, italic, underline, strikethrough, selection formatting, typing styles, and undo/redo.
  The Debug gallery exercises standalone and sheet presentation, plus an encode/decode save preview using `Models/EntryEmphasisContent.swift`.
  This codec authors the paragraph and emphasis subset of Web's versioned `body_rich` document and rejects unsupported blocks or marks rather than flattening them.
  Native Capture now writes through it like Web: `CaptureCard` edits one formatted note, `EntryEmphasisContent.capture` trims surrounding whitespace without dropping formatting, and drafts, the offline queue, and the Entry insert carry `body_rich` only when it matches the saved plaintext.
  Native review opens editable emphasis in the same editor and saves the editor's document when the note changes.
  An untouched note resends its original `body_rich`, so Web-only lists, quotes, links, and code survive a review that does not edit the note.
- Collections, tags, People, and Wiki Item links are owner-scoped reusable relationships. Locations are Entry-owned snapshots.
- Focused forms own specialized structure, Collections own curated groupings, tags own descriptive labels, and Timeline tracks own presentation only.
- Home and Vehicle are Entity subtypes whose occurrence range describes the user's relationship span.
- First Time, Moment, and Period are focused Entry forms; Memory and Story are optional descriptive tags.
- Web Entry editors reuse `components/entry-organization-editor.tsx`; their save RPC must atomically preserve Collection and tag memberships with the canonical Entry mutation.
- Used tags merge atomically into another stable tag identity. Only unused tags can be deleted directly.
- Tag management loads at most five linked Entry previews on demand through a server action, so the Tags page stays lightweight and never creates a per-tag data waterfall during its initial render.
- Multi-record changes use authenticated RPCs so content, relationships, history, and specialized facts commit atomically.
- Clients send the revision they read. A stale revision surfaces a conflict instead of silently merging or overwriting another device.
- Important mutations snapshot prior state.
  Restoring history creates another revision rather than deleting subsequent history.
  The restore RPC accepts history schema 3 only; Web `lib/data/history.ts` and native `HistoryPresentation` in `Models/EntryHistory.swift` each name that version once, disable restoring unsupported snapshots, and explain the incompatibility while preserving their comparison view.
  `normalize_entry_history_snapshot` defines comparable history content for newly archived state and both stored and live snapshots returned by the history read RPC.
  Relationship and specialized-detail rows exclude bookkeeping timestamps; attachment rows also exclude their soft-delete bookkeeping.
  Stable identities, domain facts, array order, and authored metadata remain intact for comparison and restoration, and reading old versions never rewrites them.
  Save RPCs retain unchanged Location, Timeline, People, and Entry-link memberships and skip unchanged Home, Vehicle, and Goal detail updates.
- Older clients must preserve fields they cannot represent or reject the write safely.
- AI organization payloads offer optional title, tags, Collections, and occurrence suggestions without structural classification.
  The database rejects legacy `entryType` and `classification` payload keys.

## Date rules

- Occurrence precision is part of the data, not presentation metadata.
- Exact timestamp, day, month, year, age, range, approximate, and Unknown values remain distinct.
- Unknown and description-only dates have no fabricated calendar anchor.
- Recorded timezone controls calendar interpretation and search overlap.
- `profiles.timezone` supplies the default for new exact Timeline timestamps; an Entry stores its own timezone snapshot and may override that default.
- Shared Web timezone options derive their displayed UTC offset from the edited occurrence date when available and otherwise from the current date, so daylight-saving changes remain explicit without replacing the stored IANA identifier.
- Timeline date-only, partial, and uncertain editors do not surface a timezone control, but they preserve the stored timezone needed for stable calendar interpretation.
- Timeline, search, Home, and specialized editors must use the same occurrence semantics.
- A private profile birth date establishes the Timeline's earliest boundary and remains editable through authenticated profile settings.
- Web Timeline lanes use each item's rendered pixel bounds, including minimum stage and event-label widths, so non-overlapping periods share a lane without allowing visible cards to collide. A dashed Today line uses the same reference instant as open stages; short ongoing labels end against it with a flat right edge, and stage labels share the same vertically centered layout whether rendered as buttons or links.
- Timeline creation routes by Entry type, not track name. Generic moments use the Timeline editor; Home, Vehicle, and First Time creation reuse the exported Records editors in a lazy-loaded Timeline modal. Existing focused records navigate to their detail pages and edit inline. System track shortcuts select the corresponding specialized type, while ordinary tracks preselect the generic editor's placement.
- Timeline server data loads specialized records, Collection, and tag choices needed by its creation editors in parallel. Existing focused records navigate to their own pages.
- Web Timeline projects dated First Times without an explicit Timeline placement onto the visible First Times system track. Already placed records remain on their chosen track, and unanchored records remain in the First Times archive only.
- Native `Features/Timeline` follows the Web phone layout: track cards, the Moment, Home, Vehicle, and First Time chooser, the first-visit birth date prompt, and the Timeline editor with the Settings time zone, Collections, and tags through `save_timeline_entry_with_organization`.
  `TimelineWorkspace` in `Models/TimelineEntry.swift` ports the First Times projection and the summary's year range.
  Like Web, Homes, Vehicles, and First Times open their focused pages from the Timeline and their editors from a Dashboard or Library link.
- Native `Features/Homes` follows Web `/homes` and `/homes/[id]`: `HomesView` lists current and earlier Homes as record cards, `HomeDetailView` is the focused page with Edit and Version history, and `ResidenceEditorSheet` is the Web Home editor on `MTSheet` with its Home details, Location, and Memories and organization sections.
  Library, the Map, and Collections open the same focused page; like Web, native editors show a saved Location's preview and edit its address by hand, and provider address search stays Web-only.
- Native `Features/Vehicles` follows Web `/vehicles` and `/vehicles/[id]` with `VehiclesView`, `VehicleDetailView`, and `VehicleEditorSheet`, sharing `MTRecordSection`, `MTEntityCard`, and `MTFocusedRecordPage` with Homes.
  `EntryPrimaryLocations` in `Models/EntryLocation.swift` loads each Vehicle's primary Location like Web `getPrimaryEntryLocations`, and a failed load makes the workspace unavailable.
  The editor's `MTLocationPanel` shows the saved Location with Remove, which saves through `save_vehicle_with_location` with a null Location.
- Native `Features/FirstTimes` follows Web `/first-times` and `/first-times/[id]` with `FirstTimesView`, `FirstTimeDetailView`, and `FirstTimeEditorSheet` on the same shared parts.
  Its cards keep the Web First Time visual, falling back from a photo to the Location map to the card's archive number, and count only original photos, not generated variants.
  Its primary Location loads like a Vehicle's, and removing it saves through `save_first_time_with_location` with a null Location.
- Native `Features/Goals` follows Web `/goals` and `/goals/[id]` with `GoalsView`, `GoalDetailView`, and `GoalEditorSheet`.
  The list groups Goals by reflective state like Web `goalSections`, and a Goal's own page pages past the first 100 Goals to find it, like Web `getGoalsWorkspace(targetId)`.
  The editor keeps the Web Related Items picker and, for a saved Bucket List Goal, the milestone panel, which records the achievement through `achieve_goal_with_occurrence` and stays open.
  `App/ConnectedItemsSection.swift` lists a record's Connected Items and routes them like Web `wikiEntryHref`: Moments and Periods open on the Timeline, and other records open their own page through `WikiItemDestinationView`.
- Native `Features/People` follows Web `/people` and `/people/[id]` with `PeopleView`, `PersonDetailView`, and `PersonEditorSheet` over `PeopleController`.
  The list loads `people_workspace` in pages of 100 through `MTLoadMore`, and a Person's own page loads `person_record` by ID, so it opens the same way from People, Library, or a Collection.
  Like Web, a Person has no version history, and Move to Trash stays disabled until every Item link is removed and saved, which `trash_person` also requires.
- Native `Features/History` follows Web `/items/[entry]` and `/history` over `EntryHistoryController`: `WikiItemDetailView` is the Item page with the current writing and facts, the Kind's actions, Related Items, and Current photos, while `EntryHistoryIndexView` and `EntryHistoryDetailView` list Items with earlier versions and compare and restore one.
  `EntryRelationsView` saves links as they change, `LinkedGoalSheet` creates a linked Goal through `extract_goal_from_item`, and Move to Trash applies only at the revision shown, like Web `trashWikiItem`.
  `Models/EntryHistory.swift` holds the snapshot model and the Web `lib/data/history.ts` presentation rules.
  `reloadOnReturn` in `App/AppNavigator.swift` reloads the Item page, version history, and each focused page when version history or a linked Item returns, so a restore or change made there shows at once.
- Native `TagsView` in `Features/Collections` follows Web `/tags`: badges with each tag's Entry count, name search, and New Tag.
  `OrganizationEditorSheet` is the Web `OrganizationControl` dialog on `MTSheet` over `OrganizationActions`, which call `save_organization`, `trash_collection`, `merge_tags`, and `delete_unused_tag` with the Web failure messages.
  A saved tag's editor loads up to five of its Entries through `search_wiki_items` only when it opens, like Web, and View all opens Library filtered to the tag through `AppNavigator.openLibrary(tag:)`.
- Native `CollectionsView` and `CollectionDetailView` follow Web `/collections` and `/collections/[id]` over `CollectionsController`, which loads `collections_workspace` with the editor identities from `organization_workspace`, like Web `getCollectionsWorkspace`.
  A Collection's Entry cards render Web's rich notes through `EntryRichTextMap`, the shared Web `loadEntryRichTextMap` port Library also uses, and their Collection and tag links open Library filtered to them.
  The same `OrganizationEditorSheet` creates, edits, and moves Collections to Trash; a Collection moved to Trash from its own page closes that page once the editor has closed.
  New entry opens Quick Capture through `AppNavigator.startCapture()`, and Settings' Archive organization leaves the Settings sheet for Collections through `routeAfterSettings`, like Web's `/collections` link.
- Native `Features/Trash` follows Web `/trash` over `TrashController`: the retention badge and note, Empty Trash, and cards that restore or delete forever through the Web RPCs and messages, with results as toasts.
  Delete forever and Empty Trash confirm in Web's Permanent action sheets, and Empty Trash keeps its prepared list and progress on screen until the run ends, like Web `EmptyTrashControl`.
- Web Timeline style selection lives in Settings as an owner-scoped browser cookie. The existing track view remains the default; Vertical Spine and Sticky Year are presentation components under `apps/web/src/components/timeline` that share the Timeline workspace data and editor callbacks. The original 20 HTML design studies remain under `timeline-ideas/`.
- Web occurrence and profile date forms use `components/date-picker-field.tsx`; domain editors map their precision into its generic granularity, time, editability, and size props instead of duplicating picker UI.

## Offline rules

- Web drafts and pending captures live in owner-scoped browser storage.
- Native drafts and pending captures live in the app sandbox.
- A pending item keeps a stable Entry ID and is removed only after the server confirms synchronization.
- Clearing browser data or deleting the app can remove unsynchronized local work, so the UI must expose pending state.

## Media rules

- Original media is private and immutable under normal display processing.
- Display and thumbnail files are derived caches, never substitutes for originals.
- Signed access is short-lived and owner-scoped.
- Image and metadata decoding runs on the server through `packages/media-runtime`; provider secrets and decoder internals do not enter either client.
- Selected Web photos reuse the shared local-or-server preview and upload-progress components; browser-displayable formats stay local while HEIC and HEIF receive an authenticated derived preview.
- `SelectedPhotoPreview` reuses its prepared image URL for a single-photo dialog; `EntryPhotoField` opens the same dialog for saved photos, while preview and removal remain separate controls.
- Generation validates source identity and bounded output before registration.
- Database rows coordinate deletion, but Storage objects are removed through the Storage API.
- Permanent deletion includes registered and interrupted-generation artifacts and must remain retryable after uncertain cleanup.

## AI rules

- `lib/ai/availability.ts` is the Web product pause gate, separate from provider configuration and saved consent.
- Old AI feature components and their CSS have been removed; `ai-paused-settings` is only a status placeholder, and `/explore` is a redirect-only compatibility route.
- While paused, Settings renders an off/disabled Beta status, Explore redirects to Library, and AI API requests and generation fail with `ai_paused` before provider calls or budget reservations.
- Stored preferences and historical AI records are preserved, not bulk-reset; native requests through this server are also blocked, but native UI is unchanged.
- The Next.js server is the only AI provider boundary.
- Native requests reuse the user's Supabase bearer session and never receive provider credentials.
- Anthropic is the initial text provider behind a replaceable server interface.
- The retained preference contract distinguishes master, organizing, and photo permissions; its former Web controls are deleted, and photo understanding still requires separate consent before any future reactivation.
- AI provider diagnostics, model identifiers, token prices, and editable spending caps stay out of ordinary Web settings. Per-user and server-wide budget logic remains intact; the former monthly activity UI is deleted.
- Budget is reserved before a request and reconciled from actual usage.
- Interrupted provider outcomes do not trigger automatic paid retries.
- Suggestion and search outputs are schema-validated and remain separate from original writing until explicit user action.
- Search answers cite exact stored evidence; provenance does not imply that the model's conclusion is true.
- `search_wiki_items` accepts canonical Kind and subtype classifications and returns Kind, subtype, record source, and specialized routing identity in one owner-scoped result stream for Web and iOS. Linked Location fields contribute searchable context.
  Native `LibraryController` runs the same relevance-ordered search as Web Library, with the grouped Record filter, Collection, tag, and local date filters, and loads each result's `body_rich` separately like Web `loadEntryRichTextMap`.
- The persistent Web Command Palette debounces input before calling the dynamic, private, no-store `app/api/search/quick` route. That route returns one bounded owner-scoped canonical result stream and opens the Library page for filtered search. Legacy `/search` URLs redirect there with their query parameters.

## Deletion, export, and recovery rules

- Ordinary deletion moves supported records to recoverable Trash.
- Permanent deletion and Empty Trash require an explicit, complete confirmation scope.
- Changed targets or uncertain responses stop further destructive dispatch.
- Export captures one consistent database snapshot and streams canonical data plus original media into a ZIP.
- Missing, changed, or truncated media fails the export instead of producing a successful partial archive.
- Cross-device synchronization and an application export are not infrastructure backups.
- Database and original Storage objects need separately protected backups and a tested non-production restore before MemoTrail can be considered recoverable.
- Automatic 30-day cleanup is not active until its exact scope, backup prerequisites, and rollout are approved.

## Design-system rules

- `packages/design-tokens/tokens.json` is the semantic source of truth.
- Generated Web CSS and Swift values are never edited directly.
- Token changes run `pnpm tokens:generate` and `pnpm tokens:check`.
- The SVGs in `assets/brand` are the source of the iOS app icon.
  `apps/ios/scripts/render-app-icon.swift` writes the light, dark, and tinted PNGs in `AppIcon.appiconset`, which are never exported by hand; `AppIconTests` checks their alpha layout.
- The development-only `/design-system` route renders production Web components and current generated tokens for review; it is unavailable in Production.
- The Web Dashboard route loads `getHomeWorkspace` on the server and renders `components/home-dashboard.tsx` with component-owned CSS.
  Dashboard composes the shared PageFrame, PageHeader, CaptureComposer, EmptyState, ProgressiveImage, and Badge; Memory and Recent Entries share one Entry card renderer.
  Native `Features/Home` mirrors it with `MTPage`, `MTPageHeader`, `CaptureCard`, `MTEmptyState`, `MTRemoteImage`, and `MTBadge`; `DashboardComponents.swift` owns the ribbon, rows, and cards.
  Web `QuickCaptureDialog` shows CaptureComposer's dialog variant under its own header; native `QuickCaptureView` shows the same header over `CaptureCard(style: .dialog)` full screen, where Web now anchors the composer to its bottom dock.
  Both composers open the relevant date in place, keep only problems in the composer, and announce a synced capture with a toast.
  A capture saved without a connection gets an info toast instead: Web checks the browser's connection before syncing, while `InboxController` confirms a capture once when its first sync cannot reach MemoTrail and keeps later offline retries quiet.
- The Web Inbox renders `components/entry-review-list.tsx` and its `EntryReviewDialog` inside the compact PageFrame.
  Native `Features/Inbox` mirrors the list with `InboxCards.swift` and the dialog with `EntryReviewSheet.swift`: the same fields, sticky Save changes and Save to Library footer, confirmations anchored to Move to Trash, and toasts.
  Neither Inbox embeds a composer; Web captures from the bottom dock, and iOS from the Dashboard or New entry in the workspace header.
- Button, Dialog, PageHeader, EmptyState, and the previously reviewed gallery components are approved migration targets.
- Production actions use Button, IconButton, or ButtonLink without changing submit or navigation semantics; composite internals and navigation controls retain their distinct roles.
- Dialog owns generic editor and confirmation shells, scroll containment, focus trapping/restoration, busy dismissal, and nested overlay containers.
  Editor forms retain their handlers; footer submit actions use native form associations.
  Quick Capture uses a native HTML dialog anchored to the workspace bottom, preserving photo-picker cancellation, nested overlays, and focus restoration; its mobile geometry follows the visual viewport when the keyboard opens.
  `WorkspaceActionDock` owns the shared bottom position and glass control styling for global Search and Quick Capture.
  PhotoViewer keeps native top-layer media geometry, and Command Palette keeps its search and keyboard-result interaction model.
- Reusable components do not import `app/**.module.css`; Web lint enforces this boundary along with valid token references.
  Feature modules own composition, and `editor-fields.module.css` shares native field spacing and states while excluding the reviewed composites' internals.
- Noninteractive status, type, collection, and tag labels use `components/badge.tsx` with tone and size variants, single-line truncation, and Design System specimens.
- DatePickerField and OccurrenceEditor own `components/date-fields.module.css`; named date fields preserve native form validation and GET serialization without importing route styling.
- Inside a modal, date/time fields inherit its overlay container or accept an explicit `portalContainer` so their popovers stay inside its accessibility and theme boundary.
  Unnamed domain date fields retain the editor's contextual submit validation rather than introducing native custom-validity interception.
- Cross-platform components preserve meaning and state while allowing native interaction differences.
- Native `DesignSystem/Components` owns reusable presentation components.
  `MTFoundations.swift` maps each Web text role to the iOS Dynamic Type style with the same default size and defines the shared icon vocabulary, page widths, shadow, and line-height helpers.
  Generated Swift tokens supply semantic colors, spacing, radius, motion, line heights, shadow layers, and the catalogs the gallery lists.
  Native actions use `mtButtonStyle` variants and sizes or `MTIconButton`; `MTBadge`, `MTPageHeader`, `MTSectionHeader`, and `MTEmptyState` mirror the Web Badge, PageHeader, and EmptyState.
  `MTLoadMore` loads a list's next page as its end scrolls into view, or offers a retry, for Library and People.
  `MTListHeader` and `MTListSurface` are the uppercase list heading and bordered row surface that the Inbox and Library share, and `MTListRowButtonStyle` gives whole-row links their pressed surface.
  `MTSheet` is the Web Dialog: its eyebrow, serif title, close action, scrolling content, failure message, and footer actions.
  A form sheet opens at full height with room to push detail such as Version history, and a fitted sheet sizes itself to short content; `MTSheetOption` is the Web dialog's icon, title, and description choice.
  `confirmationDialog` stands in for the Web confirmation shell.
  `MTFields.swift` owns the labeled text, textarea, search, select, and checkbox fields on one shared surface; `MTSelectGroup` titles runs of select options like a Web `optgroup`, and `MTDateField` edits optional wall-time text at day, month, or year granularity, and `MTTimeZoneField` lists offsets for the reference date.
  `OccurrenceEditor` and `MTOrganizationEditor` are the shared date and Collection/tag editors; adding a name opens a picker sheet so suggestions stay above the keyboard.
  `MTCards.swift` owns `MTRecordCard`, `MTCollectionCard`, and the shared `MTCardButtonStyle`; `MTRichTextContent` renders `Models/EntryRichText.swift`, which validates Web `body_rich` documents like `lib/data/rich-text.ts` and falls back to the plain body.
  With a line limit it flows the writing into one clamped preview that keeps emphasis, list markers, and line breaks.
  `MTToastCenter` shows Web-timed success, info, and error toasts in a pass-through window above sheets.
  Like Web, they rise from the bottom, clear of the tab bar, sheet actions, and the keyboard, so back and close buttons stay reachable.
  `MTMedia.swift` owns `MTRemoteImage`, the loading skeleton, `MTUploadProgress`, and `MTPhotoField`; feature editors use them instead of private image loaders.
  `MTPhotoPreview` shows saved photos whole and pages between them with Previous, Next, and the position, like Web's photo viewer; `MTPhotoField` and `MTRecordPhotos` open it.
  `MTRecordDetail.swift` owns the focused-record parts: `MTFormSection` is the Web editor fieldset whose fields sit on the raised surface, with an accent tone for panels such as the Goal's Bucket List milestone, and `MTFactList`, `MTDetailSection`, and `MTRecordPhotos` lay out a record's facts, Story, Organize, and photos.
  `MTFocusedRecordPage` composes them into the Web `FocusedRecordDetail` page with Edit and Version history, and `MTFocusedRecordUnavailable` stands in for a missing record.
  `MTRecordArchive.swift` owns `MTRecordSection`, `MTEntityCard`, and `MTRecordCardFooter`: the Web record workspace section, the Home and Vehicle `RecordCard`, and the badge footer every record card shares.
  `MTLocation.swift` owns `MTLocationSnapshot`, a MapKit still with a pin that stands in for the Web static map, `MTLocationPreview`, the Web selected-Location card, and `MTLocationPanel`, the Web Location picker's panel; record cards fall back from a photo to that map to `MTRecordMark`, with glass badges over the visual.
  Clipped media sets a matching content shape, because clipping does not limit hit testing and filled photos would otherwise take taps meant for neighboring controls.
- The Debug-only `DesignSystem/DesignSystemGallery.swift` renders those real components with appearance and text-size controls, in the same section order as the Web gallery.
  It is reached from the signed-out screen, More, or Settings; broad existing-screen migration follows review.
- Debug launch arguments in `App/NativeReview.swift` expose isolated gallery, synthetic Map, and navigation review modes; `--review-design-section <name>` opens one gallery section directly.
  `--review-local-session` signs in with a disposable local Supabase session from `scripts/review-local-session.py`, keeps it out of the Keychain, and accepts only 127.0.0.1 endpoints.
  Adding `--review-offline` fails that session's requests like an iPhone with no network once it has signed in, through the `NativeReviewNetwork` switch the local contract tests also use.
  Release builds omit these modes and the gallery; `MemoTrailUI` runs their Simulator interaction tests.
  `scripts/local_supabase.py` owns disposable account creation and cleanup for both native local scripts.
- Native app targets skip App Intents metadata extraction because they declare no App Intents.
  Enable extraction when native shortcuts are introduced.
- Authenticated Web routes use `components/page-frame.tsx` for outer width, centering, responsive gutters, and vertical page rhythm.
- Page frame variants are semantic: `compact` is 880px for forms and focused reading, `standard` is 960px for lists and search, `wide` is 1080px for dashboards and card grids, and `canvas` is 1180px for dense spatial views.
- New route pages choose the narrowest variant that fits their content; feature grids and visualizations own their internal breakpoints instead of redefining the outer page geometry.
- Web photo surfaces reuse `components/progressive-image.tsx` for a reserved skeleton, decode fade-in, failure fallback, and reduced-motion behavior while private expiring media URLs continue to bypass the public Next image cache.
- Home, Vehicle, First Time, Goal, and Person result layouts reuse `components/record-card.tsx`; subtype modules own only their visual, metadata, and responsive content rules.
  Noninteractive history, Collection, and Trash surfaces retain their distinct link or multi-action semantics instead of nesting actions inside a button card.
- Specialized record editors reuse `components/entry-photo-field.tsx` for selected and existing previews, removal controls, limits, and upload progress.
- Web domain editors own label-to-control spacing in their shared field wrapper; route forms reuse that wrapper and the spacing tokens instead of compensating field by field.
- Quick Capture restores local text and occurrence state before paint, keeps the loading and editor geometries equal, and loads IndexedDB photo drafts separately so editor initialization cannot move the open dialog.
  Its initialized editor remains mounted while the native dialog is closed; reopening refreshes the shared local draft, and closing stops voice capture and online retry listeners.
  `CaptureComposer` handles Command/Control Return in the active form's capture phase before Tiptap's modified-Enter bindings, then uses native `requestSubmit` and the Save button's disabled state to retain validation and queue semantics.
  Composition, held-key repeats, and nested editing layers cannot submit through that shortcut; shared editor bindings remain available outside Capture.
  The frosted surface uses a static backdrop blur and translucent reflection, while entrance and exit animate only opacity and translation and honor reduced motion.
- Web appearance uses the existing light and dark semantic tokens, stores a per-browser System, Light, or Dark choice in a same-site cookie, and lets the server root layout apply explicit themes before first paint without adding a client-side flash.

## Runtime and validation

- Production Web runs on Vercel from `apps/web`.
- Production data changes are versioned Supabase migrations without development seed data.
- Server-only Supabase, Geoapify, and AI credentials exist only in trusted environments.
- Web address searches and static maps pass through authenticated route handlers, so `GEOAPIFY_API_KEY` is never exposed to the browser.
  The proxy sends only the requested search text or coordinates to Geoapify, not the signed-in user's identity.
- Both maps read current Entry-Location links through owner-scoped RLS.
  Native Map reads page in stable order with a 5,000-link cap and publish only complete results; Kind/year filters apply to the loaded set.
  Native MapKit provides the base map and collision-based annotation clusters without a provider key or device-location permission.
  Native `LocationMapView` lays out Web's map page, and a chosen pin or cluster lists its Entries in the panel below the map, like Web `selectedIds`.
  The Web Map proxies Geoapify raster tiles through an authenticated route.
  Its 5,000-link bound is ordered newest first and explicitly disclosed in the UI; filters apply to loaded results.
- Interactive tiles and static Location previews accept only light or dark theme parameters; authenticated routes choose allowlisted Geoapify styles while keeping the provider key server-side.
- Search, preview, and tile routes each consume an owner-scoped hourly database quota before contacting Geoapify.
- iOS receives public backend configuration and the Web API base URL.
- `lib/auth/api.ts` verifies Web cookie or native bearer identity for media, metadata, and export independently of AI availability.
  AI routes add their own pause gate before shared authentication, and native AI entry points remain paused as well.
- Shared behavior should be implemented and tested across Web, iOS, and Supabase in the same product slice.
- Validation should cover the narrow unit or SQL contract first, then builds, then the closest real browser or native interaction.
- Web unit collection includes both `.test.ts` and `.test.tsx`; synchronous rendering assertions belong in this fast layer.
- Multi-client RPC, Storage, and database-locking tests belong in `apps/web/contracts` and run independently of Next.js and Chrome.
  Browser interactions and Web HTTP route acceptance remain in `apps/web/e2e`.
  The development-only design gallery has its own browser runner and is excluded from product acceptance.
  Test servers isolate Next.js build output and generated TypeScript configuration by port.
- Native unit and backend contracts use `MemoTrail`, while Simulator UI interactions use `MemoTrailUI`.
  The local account wrappers support explicit XCTest selection without reducing the default full-suite coverage.
  Build caches are isolated per checkout, logs are unique per run, and concurrent use of one build directory fails immediately.
- Keep regression cases that protect distinct behavior, even when unit, SQL, and UI coverage overlap.
  Delete a test when its product surface has been retired and current behavior is covered; do not keep permanently skipped tests for removed UI.
  The retired active-AI browser flows are removed, while the pause flow, retained provider unit tests, SQL tests, and multi-client exploration contracts remain.
- Hosted configuration, destructive behavior, media integrity, and recovery require their own end-to-end evidence.

Commands live in the root [README.md](../README.md).
Current acceptance gaps live in [status.md](./status.md).
