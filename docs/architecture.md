# MemoTrail Architecture

Last reviewed: 2026-10-18.

## System map

| Area              | Responsibility                                                              | Primary location                                                                                   |
| ----------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Web client        | Next.js routes, server actions, responsive UI, browser drafts and queues    | `apps/web/src/app`, `apps/web/src/components`, `apps/web/src/lib`                                  |
| Web server        | Authenticated AI, media, metadata, and export APIs                          | `apps/web/src/app/api`, `apps/web/src/lib/ai`, `apps/web/src/lib/media`, `apps/web/src/lib/export` |
| Native client     | SwiftUI screens, controllers, device drafts and queues, native integrations | `apps/ios/MemoTrail/Features`, `apps/ios/MemoTrail/Models`, `apps/ios/MemoTrail/App`               |
| Shared data       | Postgres schema, RLS, Storage policies, atomic RPCs, and search             | `supabase/migrations`                                                                              |
| Data verification | Ownership, denial, concurrency, lifecycle, and contract tests               | `supabase/tests`                                                                                   |
| Design tokens     | DTCG token source, component specs, and generated Web and Swift outputs     | `packages/design-system`                                                                           |
| Web design system | Reusable Web components and the development-only audit gallery              | `apps/web/src/components`, `apps/web/src/app/design-system`                                        |
| Media runtime     | Deployable image and metadata decoder dependencies                          | `packages/media-runtime`                                                                           |
| Delivery          | Web, iOS, and database CI                                                   | `.github/workflows/ci.yml`                                                                         |

Vercel builds the repository with `apps/web` as the application root.
Supabase migrations and the iOS Xcode project are independent of the Node workspace.

The Web root layout owns the authenticated application shell, including navigation and account context.
Route pages render only their own server-backed content inside that persistent shell.
Next.js link prefetching and `app/loading.tsx` provide route fallbacks, while navigation links expose immediate pending feedback when a cold request has not reached the fallback yet.
`app/error.tsx` and `app/not-found.tsx` render inside that shell through `components/route-fallback.tsx`, so a failed or missing page keeps navigation and offers a retry or Home.
`app/global-error.tsx` replaces the document only when the root layout itself fails.
A failed client request, such as saving Appearance offline, is handled where it happened and never reaches these boundaries.

## Request-to-code map

Use this table to find the first likely files, then search by the product term or RPC name.
Web paths are relative to `apps/web/src`; iOS paths are relative to `apps/ios/MemoTrail`.

| Request                                                        | Web                                                                                                                                                                                                                           | iOS                                                                                                                                 | Shared data and tests                                                              |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Authentication or environment                                  | `app/auth`, `lib/auth`, `lib/supabase`, `src/proxy.ts`                                                                                                                                                                        | `Features/Authentication`, `App/AppConfiguration.swift`                                                                             | foundation and security migrations, `0001_rls.test.sql`                            |
| Capture, drafts, dates, rich text, or offline sync             | `app/inbox`, capture, rich-text and occurrence components, `lib/data/inbox*`, `lib/data/rich-text.ts`, `lib/data/occurrence.ts`                                                                                               | `Features/Capture`, `Features/Editor`, `Models/CaptureQueue.swift`, `Models/EntryOccurrence.swift`                                  | Inbox, occurrence, review, and media migrations and matching tests                 |
| Library browsing, search, AI suggestions, or exploration       | `app/library`, `components/library-search`, `/search` redirect, `app/explore`, `lib/ai`, `lib/data/search*`, `lib/search`                                                                                                     | `Features/Library`; AI is Web-only                                                                                                  | AI, evidence, exploration, and search migrations and tests                         |
| Chapter or year reviews, Chapter suggestions, or their notices | `app/reviews`, `app/api/reviews`, `app/api/chapter-suggestions`, `components/review-*`, `components/chapter-suggestion-*`, `components/reviews-setting`, `lib/ai/review`, `lib/ai/chapter-suggestions.ts`, `lib/data/review*` | `Features/Item/ItemReviewView.swift` shows a saved Chapter review read-only                                                         | review migrations `202610190030` to `202610190038` and `0082_reviews.test.sql`     |
| Photos, metadata, or export                                    | media and export API routes, `lib/media`, `lib/export`, gallery and export components                                                                                                                                         | `Features/Capture`, `Features/Editor`, `Features/Item`, `Features/Export`, `Models/MediaDelivery.swift`, `Models/EntryPhotos.swift` | media, cleanup, and export migrations and tests                                    |
| Import from another app                                        | `app/settings/import`, `app/api/import`, `components/import-*`, `lib/import`                                                                                                                                                  | none; Settings says Import is on the Web                                                                                            | import migrations `202610190040` to `202610190044` and `0081_import_jobs.test.sql` |
| Timeline, Chapters, or First Times                             | matching `app` route, workspace component, and `lib/data` module                                                                                                                                                              | matching directory under `Features` and model under `Models`                                                                        | matching contract and occurrence migrations and tests                              |
| Tags, links, the Item page, or Trash                           | matching `app` route and component, shared Entry tag editor, `lib/data` organization, Entry detail, and Trash modules                                                                                                         | matching directory under `Features`                                                                                                 | organization, relationship, Trash, and Empty Trash migrations and tests            |
| Visual system                                                  | shared page frame and components, CSS modules, `styles/generated-tokens.css`                                                                                                                                                  | `DesignSystem`, `DesignSystem/Generated`                                                                                            | `packages/design-system/tokens`, `components` specs, and generator                 |

`App/RootTabView.swift` holds the four primary tabs, Dashboard, Timeline, Library, and More, like Web's phone navigation.
It owns the `CaptureController` and the capture draft, and puts the controller in the environment for the Dashboard, Quick Capture, and the workspace header.
The More tab lays out `WorkspaceRoute.groups` in `App/WorkspaceRoute.swift` like Web's mobile More menu: First Times, Tags, Trash, and Settings, with the same groups, order, and icons.
`App/AppNavigator.swift` carries cross-tab links that Web expresses as routes, such as `/library?tag=`, `/library?record=`, and `/first-times`; the destination consumes a request once its data has loaded.
Its `entriesRevision` rises after any Entry is saved, moved to Trash, restored, or synced, so every tab reloads what it shows.
`App/ItemLink.swift` opens every Entry, Chapters and First Times included, on the Item page in `Features/Item`, like Web `wikiEntryHref`.
`App/WorkspaceToolbar.swift` is the native form of the Web phone workspace header on each primary tab: the brand mark that opens the Dashboard, New entry for Quick Capture, the pending-sync count while captures wait, search into Library, and the initial avatar that opens Settings.
It still carries New entry and search, which Web now places in its bottom `WorkspaceActionDock`.
Native Settings live in `Features/Settings`.
`Features/Settings/SettingsController.swift` reads and writes one `profiles` column per save, with the Web validation rules in `Models/ProfileSettings.swift`; `AppNavigator.profileRevision` tells the Dashboard to reload its greeting.
Native controllers that reload after a change (Dashboard, Library, Timeline, First Times, Trash, and the Item page) give each load a generation token, like `LibraryController`: a reload replaces any load still running, and only the newest response applies.

For a database behavior, search migrations for the newest definition of the relevant RPC instead of assuming the first occurrence is current.
Pair it with the test file carrying the same feature name.

## Shared data rules

- Supabase Postgres is the canonical synchronized data store.
- Row Level Security is the final owner-authorization boundary for exposed data.
- Web cookies and native bearer sessions identify the same Supabase user.
- `entries` is the canonical content table.
- `entries.item_kind` is `entry` for every row.
  Migration `202610190001` retired the Goal Kind with Someday, and `202610190012` retired the Entity Kind with Homes and Vehicles, so `entries_item_kind_valid` allows only `entry`.
- `entries.item_subtype` is `entry` or `chapter`, and `entries.is_first_time` flags a First Time.
  A Chapter is a named stretch of time with a start and an optional end; a First Time is a flag any Entry can carry, a Chapter included.
  Descriptive writing and event labels are tags.
- Entries have no Inbox state.
  Migration `202610040004` retired Inbox, and `202610040005` dropped `entries.inbox_status`, `home_workspace.inbox_count`, and the organize flag on Entry review.
  Web `app/inbox/actions.ts` and the `lib/data/inbox*` modules keep their names but now serve capture, sync, and the Entry editor.
- A Chapter and a First Time are marks on an ordinary Entry, never separate records.
  `save_entry` sets both marks, `entries_item_subtype_valid` limits the subtype to `entry` and `chapter`, and `invalid_entry_marks` and `chapter_requires_title` reject a Chapter without a title or a mark combination that is not allowed.
  A date on an ordinary Entry does not put it on Timeline; a Chapter or a First Time with a calendar date does.
- Which Entries sit inside a Chapter is computed, never stored.
  `chapter_window` and `entry_date_window` turn a recorded date into the days it covers in its own time zone: a Chapter without an end has no upper bound, Month and Year cover the whole month or year, and Unknown dates have no window.
  An Entry is inside a Chapter when the Chapter's days contain all of the Entry's days, so a year a Chapter covers only in part is not counted.
  `chapter_entries` pages a Chapter's Entries, and `chapter_overlaps` lists the Chapters that share any day with it, so moving a Chapter to Trash or giving it an end changes no Entry.
  A Chapter never lists another Chapter as an Entry inside it.
- `timeline_workspace` returns every Chapter and every First Time with the days each covers; a Chapter that is also a First Time is one row.
  `first_times_workspace` returns the Entries marked First Time, and `home_workspace.now_items` the Chapters that started and have no end.
  A resurfaced memory is always an ordinary Entry.
- Migrations `202610190010` through `202610190017` introduced Chapters, with `202610190045` carrying the marks through `import_entry`.
  `202610190011` is the only one that depends on data: it turned every Period, Home, and Vehicle into a Chapter and every First Time Moment into an Entry marked First Time, kept each Entry ID, and checked its own result before committing.
  A Home's or Vehicle's typed facts (reasons for moving, make, model, model year, color) became readable lines appended to the Chapter's note, and the Work and study lane became a `work and study` tag.
  `202610190012` dropped the `homes`, `vehicles`, and `milestones` tables, their workspace and save RPCs, `enforce_milestone_entry`, and the Entity constraints.
  `202610190013` replaced `save_entry`, `editable_entry`, and `entry_detail` with the two-mark contract, `202610190014` through `202610190016` added the Chapter, Timeline, First Times, and Dashboard reads, and `202610190017` reworked search.
  Prepared export snapshots were discarded with the conversion; a new export works immediately.
- `wiki_items_workspace` supplies one owner-scoped Library row per canonical Wiki Item before filtering and pagination, with each row's date fields.
  Migration `202610180087` dropped its `p_needs_organizing` filter with the Needs organizing view.
  Migration `202610190017` dropped the earlier five- and six-argument overloads and added `is_first_time`, so one five-argument function with defaults remains.
- Web `lib/data/wiki-items.ts` and native `LibraryController` consume that same bounded workspace.
  Web opens every Entry, Chapters and First Times included, on `/items/[entry]`, which reads `entry_detail` for the current content, tags, Locations, marks, and provenance links.
  Native Library opens every row on the same Item page through `App/ItemLink.swift`, and `AppNavigator.openLibrary(tag:)` and `openLibrary(record:)` open Library filtered to one tag or one Record, like Web `/library?tag=` and `?record=`.
  Native browse pages by 36 rows with Load more, where Web pages by 12 with Previous and Next.
- The former `people`, `person_versions`, and `entry_people` tables and People RPCs were removed by `202610040002_remove_people.sql`.
- The former authored `places` and `place_versions` tables and Place-only RPCs were removed by `202609240002_remove_authored_places.sql`.
- `locations` stores private per-Entry address and coordinate snapshots with provider provenance and revision state. It is not a Wiki Item or reusable catalog.
- `entry_locations` links an Entry to its Locations with relationship `primary` (the Entry's own Location, including a Chapter's address) or `photo` (a position adopted from a photo's GPS).
  Migration `202610040008` renamed it from `entry_places`, moved Home Locations off `homes.place_id` into `primary` links, turned `related` links into `photo` links, and dropped the `name`, `notes`, and `deleted_at` columns from `locations`; the conversion to Chapters kept each converted Home's `primary` link.
- Location rows are immutable through the authenticated table API.
  `resolve_selected_location` keeps the Entry's current snapshot, creates one from a Geoapify result, or creates one from a typed address without coordinates (`kind: "manual"`), and `replace_primary_location` swaps the `primary` link.
  `save_entry` calls it in the same transaction as the Entry save, and an editor that leaves the Location untouched sends the existing snapshot with its current `revision`.
  An `existing` selection whose revision no longer matches fails with `primary_location_changed` (40001), so a retry must carry the snapshot the previous save created.
  `reviewInboxEntry` returns the saved snapshot's id and revision, so the editor holds it before the page refreshes.
  `locations.bound_entry_id`, owner-scoped foreign keys, and deferred link constraints reject attempts to attach one snapshot to another Entry or commit an unbound snapshot. Provider identity is provenance, not a deduplication key.
  The deferred `entry_locations_discard_unlinked_location` trigger deletes a snapshot at commit once nothing links to it, so a save that relinks the same snapshot keeps it.
  Permanently deleting an Entry cascades its Location snapshots; moving an Entry to Trash does not.
  A Location's label is its formatted address, which `normalize_location_snapshot` derives from the address parts when the provider gave none; a photo position with no address reads as its coordinates.
  A Chapter may omit a Location entirely, and typing an address part in the editor replaces any chosen search result, so an edited address never keeps old coordinates.
  `coordinate_source` distinguishes manual, Geoapify, and explicitly adopted photo GPS coordinates; `source_attachment_id` points to the adopted original photo while it exists.
- Quick Capture creates an organized `entry:entry` in Library; the Web and iOS Entry editors save that same Entry without a Kind selector.
- A Chapter or a First Time is an Entry: it is created in the Entry editor from Timeline or First Times, or marked later on its Item page.
- Migration `202610040004` dropped `organize_capture`, `extract_capture_item`, `capture_extraction_source`, and the Capture handoffs to Goals, Homes, and Vehicles, so Captures no longer hand off to focused records.
  Migration `202610040008` turned the `source_capture` subtype those handoffs left on a source Entry back into a plain `entry`.
  Migration `202610190001` deleted the `derived` and `derived_from` provenance links those handoffs and Add to Someday left.
- An Entry save that leaves some photos unattached keeps its editor open; later saves, including photo retries, are ordinary updates.
  After a save that chose a provider or typed Location, the editor holds the saved snapshot with its revision (`savedLocationSelection`), so a retry leaves the Location unchanged instead of creating another one.
- Someday and the Map destination are retired.
  Migration `202610190001` converted every Goal, including those in Trash, into an `entry:entry` that keeps its title, writing and formatting, photos, Location, tags, created and updated times, and Trash state.
  Each owner gains one `someday` tag, reusing a differently cased one, which the Entry receives unless it already holds 70 tags; the status and target date become readable lines appended to the writing, such as `Someday status: Done`.
  It deleted the `achievement`, `derived`, and `derived_from` links, which leaves the First Time a done item created and the source of an item added to Someday as ordinary Entries, and dropped the `goals` table, `save_goal_entry`, `extract_goal_from_item`, `achieve_goal_with_occurrence`, `trash_goal_entry`, and `goals_workspace`.
  `wiki_items_workspace`, `search_wiki_items`, `archive_wiki_search_evidence`, `default_item_subtype`, and `export_dataset_names` no longer name Goals.
  Migration `202610190002` removed the `tiles` provider quota, which only the Map's tile proxy used.
  Web `app/goals/[[...rest]]` redirects an old Someday address to `/items/[entry]` while the Entry exists and to Library otherwise, and `/map` redirects to Library in `next.config.ts`.
- Migration `202610040006` deletes every general `related` link, scrubs them from version history, drops `entry_relations` and `set_entry_relation`, and limited `entry_links.relationship` to `achievement`, `derived`, `derived_from`, `exploration_conclusion`, and `exploration_source`; `202610190001` removed the first three, leaving only the exploration links.
- `save_entry` is the Web Entry editor's only save.
  Its 15 arguments end in `p_is_chapter` and `p_is_first_time`, which are required; one save turns an Entry into a Chapter or back and checks or unchecks First Time while keeping its tags, Location, and photos.
  A Chapter needs a title and may carry a Day, Month, or Year with an end.
  It writes plaintext and `body_rich` in one revision, and clears formatting when `p_body_rich` is null and the primary Location when `p_primary_location` is null.
  `p_photo_location` (`{attachmentId, latitude, longitude}`) adds the photo's GPS position as a `photo` Location, and fails with `photo_source_changed` if the photo is no longer the Entry's active original.
  Migration `202610040008` replaced `review_wiki_item_with_location_rich` and its nested review steps, which took a Kind that could only be `entry`, and dropped functions no client called: `save_home_entry`, `save_vehicle_entry`, `save_timeline_entry`, `mark_goal_achieved_with_first_time`, `library_text_matches`, and `save_location`.
- Native iOS follows the current schema: `Models/EntryAPI.swift` reads `editable_entry` and `entry_detail`, saves through `save_entry` with both marks, and moves an Entry to Trash only at the revision it read and while `deleted_at` is null, like Web `trashWikiItem`.
  `Models/SaveEntry.swift` builds the 15 arguments and resends an untouched Location as the existing snapshot with its revision, because a null `p_primary_location` clears it.
  `NativeContractTests/testEveryNativeRPCResolvesAgainstTheCurrentSchema` calls every RPC and table read iOS uses, so a dropped function or column fails a contract test instead of a person's save.
- Native `Features/Editor/EntryEditorSheet.swift` is the one Entry editor for new and saved Entries, opened from the Item page, Timeline, and First Times.
  Its fields follow Web: Title, Note, Tags with Most used, Photos, the Chapter and First Time checkboxes, Date, the Location preview with Remove and Undo, and Camera dates, with Move to Trash, Cancel, and Save in the footer.
  `Models/EntryEditorDraft.swift` ports Web `resolveOccurrenceDraft`: an empty calendar date saves as Unknown and keeps its description, an end without a start asks for the start first, and a stale revision shows "This Entry changed on another device. Close it, refresh, and edit the latest version."
  When some photos fail to attach, the Entry stays saved and the editor stays open, and Save again updates the same Entry.
  Location editing and provider address search are Web-only; iOS shows a saved Location and can remove it.
- Specialized tables add typed facts without duplicating common writing, organization, dates, or media.
- `entries.body` remains canonical plaintext. Optional validated rich content is versioned under `entries.metadata.body_rich` and carries the exact matching plaintext.
  The `discard_stale_entry_rich_text` trigger removes `body_rich` whenever a write leaves its text different from `body`, so plaintext focused editors, direct client writes, and restores cannot keep outdated formatted text for search or export.
- Web capture and Entry review use `components/rich-text-editor.tsx` for the reusable headless editor surface, with page, dialog, and form variants instead of separate editors.
  `components/entry-rich-text-content.tsx` safely renders validated formatting on note surfaces and falls back to canonical plaintext when rich metadata is absent, invalid, or stale.
  Formatting controls expose their real keyboard commands through accessible tooltips; drafts and pending queues preserve the same rich payload, while `save_entry` writes plaintext, formatting, organization, occurrence, photo Location adoption, and the primary Location in one revision.
  Drafts keep the editor's untrimmed note; on Capture and review save, `trimEntryNote` in `lib/data/rich-text.ts` trims surrounding whitespace from the document and derives the plaintext from the result, like native `EntryEmphasisContent.capture`.
  The review parser and RPCs still reject formatting whose text differs from the trimmed body.
- Native `DesignSystem/Components/NativeRichTextEditor.swift` provides a reusable UIKit writing surface with an Aa formatting toggle, bold, italic, underline, strikethrough, selection formatting, typing styles, and undo/redo.
  The Debug gallery exercises standalone and sheet presentation, plus an encode/decode save preview using `Models/EntryEmphasisContent.swift`.
  This codec authors the paragraph and emphasis subset of Web's versioned `body_rich` document and rejects unsupported blocks or marks rather than flattening them.
  Native Capture now writes through it like Web: `CaptureCard` edits one formatted note, `EntryEmphasisContent.capture` trims surrounding whitespace without dropping formatting, and drafts, the offline queue, and the Entry insert carry `body_rich` only when it matches the saved plaintext.
  The native Entry editor opens editable emphasis in the same editor and saves the editor's document when the note changes.
  A note with Web-only lists, quotes, links, or code opens read-only with an Edit note here action that confirms first, and an untouched note resends its original `body_rich`, so that formatting survives a save that does not edit the note.
- Tags and Wiki Item links are owner-scoped reusable relationships. Locations are Entry-owned snapshots.
- Tags own grouping and descriptive labels, and the Chapter and First Time marks own how an Entry reads on Timeline and in Library.
- A Chapter's occurrence range describes the stretch of time it names, such as a home, a job, or a school; typed facts about a home or vehicle are ordinary writing.
- Chapter and First Time are marks on an ordinary Entry, not forms; Memory and Story are optional descriptive tags.
- Web Entry editors reuse `components/entry-organization-editor.tsx`; their save RPC must atomically preserve tag memberships with the canonical Entry mutation.
  `replace_entry_tags` and `valid_tag_names` hold the shared tag write and the 70-name, 80-character limits, which Web `lib/data/organization.ts` mirrors.
- Every Entry editor's tag choices come from `lib/data/tag-options.ts`, ordered by how many Entries outside Trash use each tag, so the editor's first options are its most used suggestions.
  `lib/data/organization.ts` resolves a typed name to the existing tag that differs only by case, matching the case-insensitive tag uniqueness that `replace_entry_tags` relies on.
- Used tags merge atomically into another stable tag identity. Only unused tags can be deleted directly.
- Tag management loads at most five linked Entry previews on demand through a server action, so the Tags page stays lightweight and never creates a per-tag data waterfall during its initial render.
- Multi-record changes use authenticated RPCs so content, relationships, and specialized facts commit atomically.
- Clients send the revision they read. A stale revision surfaces a conflict instead of silently merging or overwriting another device.
  The `advance_entry_revision` trigger advances `entries.revision` and `updated_at` on every Entry update, whatever revision a write sends.
  Registering, trashing, or restoring a photo locks the Entry but leaves its revision, so an editor's own photo action never reads as another device's change; every writing, organization, or lifecycle change still conflicts.
  Focused editors refresh the page after a save, and `FocusedRecordDetail` shows its saved copy only until the server copy reaches that revision, so photos uploaded after the save appear.
- MemoTrail keeps no earlier versions.
  Migration `202610040007` dropped `entry_versions`, `entry_photo_changes`, the history and restore RPCs, and the archiving trigger, deleted every stored version, and purged prepared export snapshots that held them.
  Web `/history` redirects to `/items/[entry]` or `/library` in `next.config.ts`.
- Save RPCs retain unchanged Location and Entry-link memberships.
- Older clients must preserve fields they cannot represent or reject the write safely.
- AI organization payloads offer optional title, tags, and occurrence suggestions without structural classification.
  The database rejects legacy `entryType`, `classification`, and `collections` payload keys.

## Date rules

- Occurrence precision is part of the data, not presentation metadata.
- Exact timestamp, day, month, year, age, range, approximate, and Unknown values remain distinct.
- Unknown and description-only dates have no fabricated calendar anchor.
- The Web `OccurrenceEditor` offers Day, Month, Year, and Not sure and maps them, with its Add time and Add end date toggles, onto the stored precisions; `resolveOccurrenceDraft` stores an empty calendar date as Unknown.
- The Web composer's Date is a day with an optional time: `lib/data/inbox-capture-date.ts` maps it to and from the draft's occurrence, saves an empty field as the capture time, and shows a draft an earlier composer kept at another precision by its day.
- Recorded timezone controls calendar interpretation and search overlap.
- `profiles.timezone` supplies the default for new exact timestamps; an Entry stores its own timezone snapshot and may override that default.
- Shared Web timezone options derive their displayed UTC offset from the edited occurrence date when available and otherwise from the current date, so daylight-saving changes remain explicit without replacing the stored IANA identifier.
- Every Web date editor receives the Settings default through `lib/data/profile-timezone.ts`: the Entry editor and the Timeline forms.
  They do not surface a timezone control for date-only, partial, and uncertain dates, but they preserve the stored timezone needed for stable calendar interpretation.
  `components/occurrence-editor.tsx` shows an exact time in that default as text with a Change action, and shows the select only when the profile cannot be read.
- Timeline, search, the Dashboard, and the Entry editor must use the same occurrence semantics.
- Workspaces return an Entry's stored title, an empty string when it has none, and never a stand-in made from its writing.
  Migration `202610180087` made `home_workspace`, `home_resurfaced_memory`, `first_times_workspace`, `goals_workspace` (since dropped), and `wiki_items_workspace` follow that, with the date fields each needs to name an untitled Entry.
  It only adds fields, so the Web deployed before it keeps working whichever ships first.
  Where that Web shows a title without its own fallback, the earlier stand-in stays until a later migration removes it: `timeline_workspace` adds `stored_title`, and `trash_workspace` adds `entry_title`, the stored title of the row's Entry or of the Entry a photo belongs to, with that Entry's date.
- Web `entryDisplayTitle` and `occurrenceTitle` in `lib/data/occurrence.ts` name an untitled Entry by its date at its recorded precision, read in its recorded time zone with the fixed `en-US` locale, so the server and every browser render the same text.
  Every Web surface that shows an Entry title goes through them: Dashboard, Library, Library search, the Command Palette, Pending sync, the Item page and its page title, Timeline, First Times, Trash, and AI search.
- An optional private profile birth date establishes the Timeline's earliest boundary and remains editable through authenticated profile settings; without it, `createTimelineLayout` starts from the earliest dated item, padded.
- Web Timeline draws two bands, Chapters and First Times, instead of lanes.
  A Chapter is a bar from its window start to its window end, with an open Chapter running to Today, and a First Time is a point on its day; `createTimelineLayout` in `lib/data/timeline-layout.ts` stacks overlapping items in one band on separate rows from each item's rendered pixel bounds, including titles beside a dot or bar, so visible items never collide.
  `TimelineWorkspace` measures titles in the band item font once fonts load, estimating on the server and first render, and `createTimelineLayout` puts a title inside a Chapter only when the bar holds it.
  A shorter Chapter draws its bar alone with the title after it, or before it at the end of the Timeline, like a First Time; titles beside an item mask the year and Today lines and end in an ellipsis only past 180 pixels.
  A dashed Today line uses the same reference instant as open Chapters, whose bars end against it with a flat right edge.
  The canvas fills its card and a long Timeline scrolls; a Chapter or First Time with no calendar date is listed apart from the bands.
- Every Timeline item is a link to its Item page through `wikiEntryHref`. Adding opens `NewEntryDialog` from `components/entry-editor-dialog.tsx` with the Add Chapter or Add First Time preset.
- The Entry editor's Chapter and First Time checkboxes live in `components/entry-marks-fields.tsx` beside the date fields; a Chapter requires a title.
- Timeline server data loads the bands, the profile's time zone and birth date, and tag choices in parallel.
- Native `Features/Timeline` follows Web `/timeline` over `timeline_workspace`.
  `Models/TimelineLayout.swift` is a Swift port of `createTimelineLayout`, checked against the Web output, and `TimelineCanvas` draws its two bands, year marks, and Today line in a horizontal scroll that opens at the recent end.
  Its geometry lives in `TimelineMetrics` as constants that mirror the Web layout code, not as design tokens.
  Unlike Web, which lists the Timeline below 780 px, the canvas also shows on a phone.
  Items without a calendar date are listed under it as Without a calendar date, Set birth date opens only when the person asks, and Add opens the Entry editor with the Chapter or First Time mark set.
  Year reviews and Chapter suggestions are Web-only.
- Native `Features/FirstTimes` follows Web `/first-times` over `first_times_workspace`, and Add opens the Entry editor with First Time checked.
  Its counts appear only after a successful load.
- Native `Features/Item` is the Item page for every Entry, like Web `/items/[entry]`, over `entry_detail`: the date heading for an untitled Entry, the note, photos with `MTPhotoPreview`, the Date, Tags, and Locations facts, Edit, and Move to Trash, which confirms in a popover.
  A dated Chapter adds its saved review read-only from `chapter_review`, "In this Chapter" from `chapter_entries` 50 at a time, and "Chapters during this time" from `chapter_overlaps`; a Chapter with no start date offers Add a start date instead.
  A review quote shows only while its words still appear in the current note, matched by text, and a quote or citation whose Entry is in Trash is hidden with a note saying so.
  Making, deleting, and turning on reviews are Web-only.
- Native `Features/Tags` follows Web `/tags` over `tags_workspace`, with `OrganizationActions` calling `save_tag`, `merge_tags`, and `delete_unused_tag` with the Web failure messages.
  A saved tag's editor loads up to five of its Entries through `search_wiki_items` only when it opens, like Web, and View all opens Library filtered to the tag through `AppNavigator.openLibrary(tag:)`.
  Settings' Tags row leaves the Settings sheet for Tags through `routeAfterSettings`.
- Native `Features/Trash` follows Web `/trash` over `TrashController`: Empty Trash and rows that restore or delete forever through the Web RPCs and messages, with results as toasts and dates in the profile time zone.
  Delete forever and Empty Trash confirm in Web's Permanent action sheets with Web's titles, add "Reviews that read these Entries are deleted too." when `review_settings` counts any, and Empty Trash keeps its prepared list and progress on screen until the run ends, like Web `EmptyTrashControl`.
- Web Timeline has only the band view; the Vertical Spine and Sticky Year styles and their Settings cookie were removed so Timeline changes land in one layout. The original 20 HTML design studies remain under `timeline-ideas/`.
- Web occurrence and profile date forms use `components/date-picker-field.tsx`; domain editors map their precision into its generic granularity, time, editability, and size props instead of duplicating picker UI.
  Its open calendar and time picker render in the top layer as manual popovers, so a scrolling or translucent container such as Quick Capture's native dialog cannot clip them.

## Offline rules

- Web drafts and pending captures live in owner-scoped browser storage.
- Native drafts and pending captures live in the app sandbox.
- A pending item keeps a stable Entry ID and is removed only after the server confirms synchronization.
- Clearing browser data or deleting the app can remove unsynchronized local work, so the UI must expose pending state.
- Web `components/capture-provider.tsx` mounts once in the signed-in workspace and owns pending-capture sync through the framework-free store in `lib/data/inbox-sync.ts`.
  Composers enqueue captures and render its items, run problem, and photo progress, so synchronization never depends on a mounted composer.
- The store syncs on load, on `online`, and after each new capture, with one run at a time per tab; a run sends the oldest capture first and stops at the first retryable failure.
  While the browser reports online, the provider retries a run that left a capture waiting through `lib/data/inbox-sync-retry.ts`, backing off from 1 second to at most 1 minute and restarting after progress.
  `online` can fire before requests get through, so a single attempt per event is not enough.
  The retry belongs to the provider's lifetime, never the per-tab store, so it stops on `offline` and on sign-out and cannot send one person's queue under a later session.
- Sync failures are classified by PostgREST and Postgres error code, never message text, in Web `lib/data/sync-failure.ts` and native `CaptureSyncFailure` in `Models/CaptureQueue.swift`.
  Missing codes, connection and schema-cache errors, and retryable SQLSTATEs stay retryable; JWT errors ask the person to sign in again; `PGRST1xx`, `42501`, and SQLSTATE classes `22`, `23`, and `54` are refusals.
  `syncInboxEntry` and `registerEntryAttachment` in `app/inbox/actions.ts` return `rejected` for a refusal, and the client also refuses a photo that changed or has an invalid path on the device.
- A capture insert refused as a duplicate looks up the existing Entry: an active one counts as synced, one in Trash is refused with its own message, and a failed lookup downgrades the refusal to a retry.
  `entry_deleted_forever` (SQLSTATE `23505`) is refused without a lookup, and `register_entry_attachment` raises `entry_in_trash` or `entry_deleted_forever` for the owner's Entry; each code is matched together with its SQLSTATE.
- Photo uploads run through Web `lib/data/inbox-photo-sync.ts` and native `CaptureController.synchronizeAttachments`, which classify a Storage error by its status code, never message text, with Web `classifyUploadFailure` and native `CaptureUploadFailure`.
  `409` means an earlier upload whose answer was lost, so registration continues; network errors, `408`, `423`, `425`, `429`, and `5xx` retry; `401` asks the person to sign in; `413`, `415`, and other `4xx` refuse the photo with a fitting message.
  Storage answers an expired session with the same `403` as a policy denial, so a `403` first checks the session with the Auth server: the same owner means a refusal, an unreachable server a retry, and anything else a sign-in.
  `attachment_object_missing` is a refusal only when the original is no longer on the device; while it is, the next run uploads it again.
  When registration refuses a photo that was just uploaded, the client removes that unregistered original, which the Storage delete policy allows.
  This removal is best effort; there is still no server sweep of abandoned unregistered uploads.
- A refused capture keeps its content in the queue with a `rejection` marker (message and time), written by `rejectInboxQueueEntry` in `lib/data/inbox-queue.ts` or `CaptureQueueStore.markRejected`.
  Runs skip marked captures and continue with later ones, and a malformed marker only makes the capture sendable again.
  If the marker cannot be stored, the run stops with a retry instead, so the capture is never sent again unmarked.
  Discard, `InboxSyncStore.discard` or `CaptureController.discardRejected`, removes only refused captures: their photo drafts first, then the queue entry, so orphaned photos cannot reappear in a composer.
- Reading the Web queue never writes, and no write persists a reduced queue.
  Stored items that fail validation, repeat an id with different content, carry a future version, or sit in a damaged queue are kept in the `memotrail:inbox-queue-quarantine:<owner>` key by `lib/data/inbox-queue.ts` before any write, and the write is refused when that fails.
  Pending sync lists them as unreadable with Copy text and Discard, and their photos stay out of the draft until they are discarded.
  A Web draft that no longer validates restores what it can, with a notice, and its original is kept under `memotrail:inbox-draft-quarantine:<owner>` before it is replaced.
  Native `CaptureQueueStore` in `Models/CaptureQueue.swift` follows the same rules with the `memotrail.inboxQueueQuarantine.<owner>` and `memotrail.inboxDraftQuarantine.<owner>` keys, still reads version 1 to 3 queues, and lists unreadable captures in Pending sync with Copy text and Discard.
- A per-owner Web Lock serializes runs across tabs, and each capture is reread from storage before it is sent, so a tab skips captures another tab already synced.
  `storage` events refresh the pending lists of other tabs, and a tab whose captures another tab synced refreshes its route so Library and Dashboard stay current.
  The tab that sends a capture needs no extra refresh, because the sync Server Actions revalidate and return its current route.
  Browsers without Web Locks fall back to per-tab runs, where the stable Entry ID still keeps a repeated send from creating a second Entry.
- The same provider owns the capture draft through the framework-free store in `lib/data/inbox-draft-store.ts`, read with `useCaptureDraft()`.
  Every `CaptureComposer` renders and edits that one draft: writing, `body_rich`, occurrence, photo drafts, and the voice capture in progress.
  A save clears it for every composer once the capture is queued; the queued capture keeps its photos in IndexedDB, and a photo removed from the draft is deleted there.
  Composer messages are tagged with the draft revision, so a change from any composer dismisses them.
  Leaving the Dashboard or closing Quick Capture ends a voice capture, whichever composer started it.
- Drafts follow other tabs: `storage` events for the draft key reload the writing and date, and a per-owner `BroadcastChannel` announces photo changes, after which a tab rereads IndexedDB without the photos of queued captures.
  A tab restored from the back-forward cache rereads both, and a dictating tab stops voice capture rather than overwrite another tab's edit.
- Native `CaptureController` in `Features/Capture` belongs to the root tab view, so iOS sync is independent of any composer.
  It syncs on a network change, on returning to the foreground, after a save, and on Retry now, and while online it retries a run that left a capture waiting after 1, 2, 4, 8, 15, 30, and then every 60 seconds through `CaptureSyncRetry`, restarting after any capture syncs.
  Going offline, signing out, or deleting the account stops the backoff, and an expired session stops sync with an error until the same person signs in again or the token refreshes.
  Like Web, each run rereads the queue before each capture, sends the oldest first, sets a refused capture aside without blocking later ones, and stops at the first capture that has to wait.
  Native `RootTabView` also owns the draft and binds it into both `CaptureCard`s, so the Dashboard and Quick Capture share it.

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
- The database delete is the commit point: deleting an attachment row records its remaining Storage objects in `media_purges` in the same transaction, so nothing deleted is restorable and no file is forgotten.
  Clients then remove only the paths from `pending_media_purge_paths` and confirm with `complete_media_purges`, through Web `lib/data/media-purge.ts` and native `TrashController.finishPendingMediaRemoval`; opening Trash retries anything left.
- The Storage delete policy refuses a client removal of a registered original, and restoring an Entry or photo, by RPC or direct update, fails with `trash_media_unavailable` while an original it would show is missing.
- Account deletion requires generated previews to be removed first (`media_cleanup_required`).

## AI rules

- `lib/ai/availability.ts` is the Web product gate, separate from provider configuration and saved consent.
  It allows exactly two features, `review` and `chapter_suggestion`; every other AI feature stays paused.
- A paused feature fails with `ai_paused` before authentication-dependent work, provider calls, or budget reservations, and `/explore` is a redirect-only compatibility route.
- Old AI feature components and their CSS have been removed, and the Settings "AI capabilities" row and `/settings/ai` page are gone; `/settings/ai` redirects to the review switches in Settings.
- Capture completion in `app/inbox/actions.ts` returns before authentication or revision lookups, and `suggestForEntry` fails with `ai_paused` before reading preferences, preparing photo previews, or claiming a suggestion row.
- Stored preferences and historical AI records are preserved, not bulk-reset; native requests through this server are also blocked, but native UI is unchanged.
- The Next.js server is the only AI provider boundary.
- Native requests reuse the user's Supabase bearer session and never receive provider credentials.
- Anthropic is the text provider behind a replaceable server interface (`lib/ai/provider.ts`), called through its official SDK with no automatic retries.
- The retained preference contract distinguishes master, organizing, and photo permissions; its former Web controls are deleted, and photo understanding still requires separate consent before any future reactivation.
- AI provider diagnostics, model identifiers, token prices, and editable spending caps stay out of ordinary Web settings. Per-user and server-wide budget logic remains intact; the former monthly activity UI is deleted.
- Budget is reserved before a request and reconciled from actual usage.
- Interrupted provider outcomes do not trigger automatic paid retries.
- Suggestion and search outputs are schema-validated and remain separate from original writing until explicit user action.
- Search answers cite exact stored evidence; provenance does not imply that the model's conclusion is true.
- `search_wiki_items` accepts canonical Kind and subtype classifications and returns Kind, subtype, record source, and specialized routing identity in one owner-scoped result stream for Web and iOS. Linked Location fields contribute searchable context.
  Native `LibraryController` runs the same keyword search as Web Library with `p_order` `relevance` and no embedding arguments, with the Record, tag, and local date filters, searches 400 ms after typing stops, and loads each result's `body_rich` separately like Web `loadEntryRichTextMap`.
- The persistent Web Command Palette debounces input before calling the dynamic, private, no-store `app/api/search/quick` route. That route returns one bounded owner-scoped canonical result stream and opens the Library page for filtered search. Legacy `/search` URLs redirect there with their query parameters.

## Review and Chapter suggestion rules

Chapter reviews, year reviews, and Chapter suggestions are the only AI features offered.
They are made only on request, or about monthly for suggestions, and only after a person accepts the disclosure in `lib/ai/review-disclosure.ts`, whose version is stored with the preference.

- **Preferences.**
  `reviews_enabled`, `chapter_suggestions_enabled`, and `review_disclosure_version` live in `ai_preferences` and are changed only through `save_review_preferences`.
  A trigger deletes every saved review when reviews are turned off.
  `app/reviews/actions.ts` records the disclosure version on the server, never from the client.
- **Periods.**
  A Chapter review reads the Entries whose dates fall inside `chapter_window`; a year review reads the Entries in a year by `entry_date_window`.
  A period needs at least 5 Entries, a year must be over, and an ongoing Chapter offers "Review so far".
  SQL (`review_eligibility`, `review_period_inputs`) decides eligibility and returns only title, date, tags, and body; photos, Locations, names, and email addresses never reach the provider.
- **Jobs.**
  A review is one to seven steps (map parts, then a reduce, or one request) stored in `entry_reviews.job_state` with five-minute leases.
  `lib/ai/review/jobs.ts` advances a job from `after()` in `app/api/reviews` and from each status poll.
  A paid step is never retried automatically, and "Try again" reuses finished map steps when the plan hash still matches.
  The page polls `POST /api/reviews/{id}` because the identity check needs the app's Origin header, and a finished job reads as `idle`, not `ready`.
- **Grounding.**
  The model sees numbered passages and chooses quotes by passage ID, so `lib/ai/review/grounding.ts` inserts the exact words and never trusts retyped text.
  Cited Entries, phase dates, quotation marks in prose, and counts are checked, and an ungrounded result is not stored.
  Quotes are checked again in SQL when stored and on every read (`quoteAvailable`), so an edited or trashed Entry hides its quote and the page counts what is hidden.
- **Deletion and export.**
  `entry_review_sources` records each Entry a review read, and permanently deleting one of those Entries deletes the review.
  Moving an Entry to Trash only hides what came from it.
  Export includes `data/entry_reviews.json` and `reviews/{id}.md` (`lib/export/contracts.ts`), and the archive README says what they are.
- **Accounting.**
  `reserve_ai_usage`, `finish_ai_usage`, and `ai_budget_allows` apply per-feature byte, token, and time limits (`lib/ai/contracts.ts`), a per-person and a server-wide monthly budget, and a cap on one reservation.
  A request whose outcome is unknown keeps its reservation.
- **Suggestions.**
  `claim_chapter_suggestion_run` takes a lease and returns whether a run is due; `lib/ai/chapter-suggestions.ts` reads at most 120,000 bytes of recent Entries and drops every suggestion that fails `validateSuggestions`.
  Nothing becomes a Chapter until the person reviews it in the editor and saves; dismissing keeps only the stretch's dates so it is not suggested again.
  The run starts from a Server Action or from `app/api/chapter-suggestions`, because `cookies()` cannot be read inside `after()` in a Server Component.
- **Notices.**
  The Dashboard shows at most one quiet notice (`review_notice`), only while reviews are on; resolving it retires that year or Chapter for good.
- **Tests.**
  Unit tests use the scripted provider in `lib/ai/fake-provider.ts`, and browser tests use `apps/web/scripts/fake-ai-provider.mjs`, a local server that speaks the Messages API.
  Neither calls a real provider, and `MEMOTRAIL_E2E_LIVE_AI=1` is the only way a browser run reaches one.

## Semantic search rules

Semantic search is not a third-party AI capability.
It lives in `lib/search`, outside `lib/ai`, and the AI pause gate does not apply to it.

- The embedding model is MemoTrail's own copy of one open model, named in `lib/search/semantic-model.json` (model, pinned revision, vector size, similarity floor, query instruction).
  `semantic-config.ts` derives `SEMANTIC_MODEL`, the label stored with every vector, so vectors from another model never match a query.
  Switching models means editing that file, the image in `services/embeddings`, and the `halfvec` size when the dimension changes; a unit test checks that they agree.
- The model runs only in the container defined in `services/embeddings` (Text Embeddings Inference with the weights baked in).
  The container holds no database credentials and only turns text into vectors.
  The Next.js server is the only caller, through `lib/search/embedding-client.ts` and the server-only `SEMANTIC_SEARCH_URL` and `SEMANTIC_SEARCH_API_KEY`.
  Without both variables, or when they do not name an HTTPS or loopback URL, search is keyword-only and nothing is indexed.
- The client logs only reason codes, never query or Entry text.
  It validates every response (size, finiteness, model name), L2-normalizes vectors, caches query vectors in process memory for ten minutes, and stops calling a failing service for thirty seconds.
- Vectors live in `entry_search_chunks` (`halfvec`) and indexing state in `entry_search_index_state`.
  Neither table is granted to any client role; only `security definer` functions filtered by `auth.uid()` read or write them, and neither is exported.
- Postgres decides what needs indexing.
  A trigger on `entries` marks an Entry pending whenever its title or plaintext body changes, whichever client or RPC wrote it.
  Trash keeps vectors so Restore is instant; Delete forever, Empty Trash, and account deletion remove them by cascade.
- The Web server drains pending Entries with the signed-in user's session in `after()` callbacks, scheduled after a save and whenever a search sees pending work.
  `lib/search/search-index.ts` claims leased jobs, chunks the plaintext body (`chunking.ts`, offsets in Unicode code points), embeds, and stores.
  A store is refused when the Entry changed or the setting was switched off meanwhile.
  An unavailable service stops the drain without counting a failure.
  There is no cron, service-role key, or public webhook.
  Indexing advances only while the user is active on Web.
- `profiles.semantic_search_enabled` is the Settings switch, on by default.
  Settings shows the switch only when `semanticSearchConfigured()` is true, because without a service it would change nothing.
  Turning it off deletes the user's vectors and the server stops sending that user's queries to the model; turning it on queues every Entry again.
- Search keeps one RPC, `search_wiki_items`.
  `lib/search/semantic-query.ts` decides per search whether to embed the query, and any doubt (no service, an opt-out, an outage, a query of one character or an exact quoted phrase) sends the keyword-only call.
  The RPC takes an optional query vector, model label, and similarity floor (`p_query_embedding`, `p_embedding_model`, `p_semantic_min_similarity`).
  Without a vector and a model label it returns exactly the keyword-only rows in the keyword-only order.
  With them, `semantic_entry_matches` returns each Entry's closest current chunk of the caller's own index, above the floor and only while the Settings switch is on.
  Those Entries join the keyword matches after the same Kind, tag, date, and Chapter filters apply to both, the closest 50 are kept, and the two rankings are fused by reciprocal rank (`1/(60 + rank)` summed), so no calibration between the two scales is needed.
  A result matched by meaning lists `Meaning` last among its reasons and carries its closest chunk's similarity, range, and the Entry's chunk count.
  `MERGED_SEARCH_AVAILABLE` in `semantic-config.ts` is the switch that sends the vector; it exists for a database that predates migration 202610190023.
- Keyword search reads an Entry's `metadata` without its `body_rich` document, so rich text node and mark names never match; the plain body already carries the words.
- Library says why meaning results are missing (`SemanticSearchStatus`): it shows a notice only when the service is unavailable or Entries are still being prepared, and nothing when search is keyword-only by configuration or by the user's choice.
  A result matched by meaning shows `Meaning` among its reasons and, for a long Entry, the closest passage cut from the body by the stored range.
- The deterministic `apps/web/scripts/fake-embedding-server.mjs` stands in for the service in tests, and `scripts/semantic-eval.mjs` compares candidate models offline on a synthetic bilingual fixture.
  Only `playwright.semantic.config.ts` (`test:e2e:semantic`, running `e2e/semantic-search.e2e.ts`) starts the fake service and points the app at it.
  `scripts/e2e-server.mjs` clears `SEMANTIC_SEARCH_URL` and `SEMANTIC_SEARCH_API_KEY` for every other browser suite, so those stay keyword-only whatever the developer's environment holds.

## Deletion, export, and recovery rules

- Ordinary deletion moves supported records to recoverable Trash.
- Permanent deletion and Empty Trash require an explicit, complete confirmation scope.
- Changed targets or uncertain responses stop further destructive dispatch.
- Every hard delete of an Entry records its owner, ID, and deletion time in `entry_tombstones` through a trigger, so a delayed capture cannot create it again.
  A later insert of that ID for the same owner fails with `entry_deleted_forever` (SQLSTATE `23505`), after waiting for any uncommitted Delete forever of the same row.
  Tombstones hold no content, have row level security with no client grants, are not exported, and are kept until the account is deleted, which removes them by cascade and records none for its own Entries.
- Export captures one consistent database snapshot and streams canonical data plus original media into a ZIP.
  Web `components/export-settings.tsx` opens the save picker while the click is still active, then creates the snapshot with a client id that a retry reuses and downloads it in the same action; its recent exports list downloads a snapshot again or discards it.
- Missing, changed, or truncated media fails the export instead of producing a successful partial archive.
  A server-side failure or timeout logs one `Export stopped before completion` warning with its cause, while a download the person closes logs nothing.
- Cross-device synchronization and an application export are not infrastructure backups.
- Database and original Storage objects need separately protected backups and a tested non-production restore before MemoTrail can be considered recoverable.
- Automatic 30-day cleanup is not active until its exact scope, backup prerequisites, and rollout are approved.

## Import rules

Import turns an export ZIP from another app into ordinary Entries.
One engine reads every source, and each source is an adapter in `apps/web/src/lib/import/adapters` that turns a ZIP into candidates.
The sources are a Markdown folder (which also reads Apple Notes Markdown exports), Apple Journal, Notion, and Day One.

- The browser uploads the ZIP to the private `import-staging` bucket with resumable TUS, as the signed-in user, because a Vercel function body is capped at 4.5 MB.
  Storage policies let a user write only the exact object of their own `uploading` job and read or delete only their own folder.
  The size cap is `IMPORT_MAX_ZIP_BYTES` (default 50 MiB, ceiling 5 GiB); a larger cap also needs the hosted Storage file size limit raised.
- The server never downloads the ZIP whole.
  `lib/import/storage.ts` reads it through a signed URL by HTTP range requests, and `lib/import/zip.ts` caches 4 MiB blocks and refuses encrypted archives, path traversal, too many members, and extreme compression ratios.
  Only a Notion export of part ZIPs is expanded, one level deep.
- Import is a resumable job in Postgres (`import_jobs`, `import_items`) with one active job per user, driven by a single `app/api/import` action route.
  A scan stores one item per candidate with its content hash and payload.
  The preview reads totals and a sample, and the person's choices (time zone, tags, folders to leave out, a Notion date property) are stored on the job when it is confirmed.
  The run action takes a lease, claims batches, writes Entries and photos until a 240 second budget ends, and returns so the page can call it again.
  Reloading the page, losing the connection, or a function timeout only pauses the job.
  A full Storage quota moves it to `paused_quota` until the person continues.
- Imported Entries are created through `save_entry` (or the canonical insert for a photo-only Entry) inside `import_entry`, so later Entry rules apply to them.
  Photos are uploaded to `entry-media` first and registered second with `register_entry_attachment`, like capture, and an Entry holds at most 12.
- Imports are idempotent.
  An Entry id is a version 5 UUID of the owner, source, and source key, and `entry_import_origins` records each source key with a content hash.
  A repeated import reports each item as created, unchanged, changed in the source (left alone so edits are safe), or deleted earlier (`entry_tombstones`).
- A date keeps the precision the source has.
  A day, month, or year is stored at noon in the chosen zone like the editor does, an unreadable date becomes `unknown` with its text as the description, and an ambiguous slashed date is refused rather than guessed.
  `created_at` stays the import time.
- Import clients can select job and origin rows but not the `payload` or `media` columns of items, which are read only through `import_job_sample`.
  The result report is a CSV of source keys, statuses, and reasons with no titles or text.
  Staged ZIPs are removed when a job ends or goes stale (`expire_import_jobs`), and undo moves a job's untouched Entries to Trash for 30 days.
- The Apple Journal and Notion adapters are built from third-party importers' reports and synthetic fixtures, so unknown markup degrades to plain text.
  Change them only against a real export of the same app.

## Design-system rules

- `packages/design-system/tokens` is the token source of truth, written in the DTCG 2025.10 format.
  `soft-ledger.resolver.json` merges the foundation files and selects the light or dark color file through its `theme` modifier.
  The `palette` group holds raw colors that only semantic tokens reference; generated outputs never include it, so components use semantic roles.
  The semantic groups are `color`, `font`, `lineHeight`, `type` text roles, `space`, `textSpace`, `size`, `radius`, `layout`, `motion` durations and easing, `shadow`, `state`, `material`, and `elevation`.
  `textSpace` is Web spacing in `em`, such as list indents and inline code padding, so it scales with the text it sits in.
  Both platforms share the numeric `space` scale, including hyphenated half steps such as `space.1-5`, which Swift names `MTSpacing.s1_5`; a semantic spacing token exists only where both platforms use it for the same purpose.
  Values reproduce what each platform renders today, so a group may hold several near values rather than a snapped scale.
- `$extensions["com.memotrail"]` carries what DTCG cannot express.
  `platforms` limits a token or group to Web or iOS, and the generator emits it only there; `web` and `ios` override a value on one platform.
  A design decision both platforms make is one token that both read, never a Web-only and an iOS-only copy; when a platform draws it differently, such as a text role at an iOS Dynamic Type size, that token carries the difference as an override.
  `web.unit: "em"` writes a Web-only number token as a length relative to the surrounding text.
  A text role names its iOS Dynamic Type style in `ios.textStyle`, and a material names its iOS system material in `ios.material`.
  `mix` records the colors a translucent or mixed color comes from, and the generator verifies the value against them.
  Web CSS writes such a color as the `color-mix()` it replaces, because Chrome draws a rounded `rgb()` or hex value up to one level differently; a color without `mix` keeps its `rgb()` or hex form.
  A shadow layer that names a color token draws through that token's variable on Web, so a mixed shadow color stays a `color-mix()` too.
- `packages/design-system/icons.json` names each icon once, with its Web SVG and its SF Symbol.
  The generator writes the Web `IconName` type and the Swift `MTIcon` enum from it; an icon drawn on only one platform lists that platform.
  Web `Icon` sizes are typed as `IconSize`, the `size.icon` scale.
  Its `cssImages` section turns a Web icon, a color token, and size tokens into a themed `--mt-image-*` data URL, for CSS that cannot use `currentColor`, such as the native select chevron.
- `packages/design-system/contrast.json` lists the text and background pairs held to WCAG AA in both themes on both platforms: 4.5:1 for body text and 3:1 for large text, judged from each pair's text role.
  A pair that fails today needs a named exception with a reason, and an exception that no longer fails is reported as stale.
- Generated Web CSS variables, the Web gallery catalog and typed `design-system.ts` in `apps/web/src/generated`, and Swift values are never edited directly.
- Token changes run `pnpm design-system:generate` and `pnpm design-system:check`; the check also rejects invalid DTCG values, unresolved or circular references, themes that define different tokens, and contrast failures without an exception.
  `pnpm --filter @memotrail/design-system test` covers the generator.
- `packages/design-system/components/*.yaml` specifies each shared component once for Web and iOS, and is where to look up which files implement a component.
  A spec names the implementing files and symbols on each platform, its purpose and when to use or avoid it, its anatomy, props, and states, the semantic tokens that draw each part, its content and accessibility rules, every intended platform difference with its reason, and the specimens both galleries show.
  `packages/design-system/schema/component-spec.schema.json` is its JSON Schema.
  The control and overlay specs map Web to native as follows: IconButton to `MTIconButton`, Icon to `MTIcon`, TextField, SearchField, and Checkbox to their `MTFields.swift` fields, SelectField to `MTSelectField` with `MTSelectGroup`, DateField to Web `DatePickerField` and `MTDateField`, and TimeZoneField to Web `TimezoneSelect` and `MTTimeZoneField`.
  One Dialog spec covers Web `Dialog` and `ConfirmationDialog` with `MTSheet` and `confirmationDialog`, and one Toast spec covers Web `AppToaster` with `MTToast` and `MTToastCenter`.
  CommandPalette and WorkspaceActionDock are Web-only, so their specs mark iOS `unavailable` and give the reason; `sync-status.yaml` pairs SyncStatus with `MTSyncStatusButton` in the native workspace header.
  `pnpm design-system:check` validates every spec against the schema, then checks what a schema cannot: that the files declare the symbols, that every token exists on the platforms that use it with the type its property needs, that token rules name only real props, values, parts, and states, and that specimen ids are unique.
- Specs pair these Web components with their native counterparts, and a spec named differently from the Web component says so.
  `badge.yaml` pairs Badge with `MTBadge`, and `button.yaml` pairs Button with `mtButtonStyle`.
  `empty-state.yaml`, `page-header.yaml`, and `page-frame.yaml` pair EmptyState, PageHeader, and PageFrame with `MTEmptyState`, `MTPageHeader`, and `MTPage`.
  `section-header.yaml` pairs SectionHeader with `MTSectionHeader`, whose `list` variant is the uppercase list heading on both platforms.
  `image.yaml` pairs ProgressiveImage with `MTRemoteImage`, `skeleton.yaml` pairs Skeleton with `MTLoadingSkeleton`, and `upload-progress.yaml` pairs PhotoUploadProgress with `MTUploadProgress`.
  `separated-list.yaml` pairs SeparatedList with `MTFlowLayout` and `MTFlowSeparator`.
  `record-card.yaml` pairs RecordCard with `MTRecordCard` and its visual and body parts.
  `capture-composer.yaml` pairs CaptureComposer with `CaptureCard`, and `photo-viewer.yaml` pairs PhotoPreviewDialog with `MTPhotoPreview`.
  `rich-text.yaml` pairs EntryRichTextContent and RichTextEditor with `MTRichTextContent` and `MTRichTextEditor`.
- The generator writes each spec's enum values as lists and union types, its prop defaults, and the specimen list into `apps/web/src/generated/design-system.ts`, and the same as Swift enums, `MT<Name>Defaults`, and `MTComponentSpecimen` into `apps/ios/MemoTrail/DesignSystem/Generated/ComponentVariants.swift`.
  Web props and native parameters take those types and defaults, so a value removed from a spec stops both platforms compiling; component unit tests catch the other direction, a value the spec adds that a Web stylesheet does not draw.
- Both galleries show every specimen a spec lists: Web wraps each in `SpecimenCase`, marked `data-specimen="<id>"`, and iOS in `GalleryCase`, with the accessibility identifier `specimen-<id>`.
  The `/design-system` e2e test and the native `testGalleryShowsEveryComponentSpecimen` UI test iterate the generated lists, and the Web test also checks that each specimen draws every prop value it covers.
- Native Swift reads every visual value from a token, and the check enforces it because CI does not build iOS.
  `scripts/check-swift.mjs` scans `apps/ios/MemoTrail` for literal fonts, colors, opacity, spacing, sizes, radii, strokes, shadows, gradients, animation timing, and materials, and prints each one's file, line, and the tokens with the same value.
  Only `DesignTokens.swift` and `MTFoundations.swift` may hold literals; a value no token has gets a semantic token, iOS-only through `platforms` when Web has no counterpart.
  The commented allowances in `scripts/lib/swift-guard.mjs` name each deliberate exception, such as a writer's bold or code mark, a system spring, gradient stops that stay with their drawing as they do in Web CSS, or the gallery's specimen diagrams, and an allowance that matches nothing fails the check.
- The SVGs in `assets/brand` are the source of the iOS app icon.
  `apps/ios/scripts/render-app-icon.swift` writes the light, dark, and tinted PNGs in `AppIcon.appiconset`, which are never exported by hand; `AppIconTests` checks their alpha layout.
- The development-only `/design-system` route renders production Web components and current generated tokens for review; it is unavailable in Production.
- `pnpm design-system:export [output]` writes the Claude Design copy of the design system to the gitignored `packages/design-system/dist/claude-design/project/`, and nothing it writes is committed or edited by hand.
  The copy is a display copy regenerated from this repository: `tokens.json` names each token like its Web variable without `--`, resolves mixed colors to `rgba()`, and takes each usage from `$description`, so every token or its group needs one.
  `README.md` is the brand book, rendered from the hand-written `scripts/claude-design/brand-book.md` with tables generated from the tokens, `contrast.json`, and `icons.json`.
  `components/` holds an esbuild bundle of the Web components that render from props alone, exposed as `window.MemoTrail` for React 18, plus a README and a preview card per component from `scripts/claude-design/specimens` and any spec in `packages/design-system/components`.
  `components/index.d.ts` declares them with the types they import from the app, such as the unions generated from the specs, written out as literal unions so the file stands alone.
  `scripts/claude-design/catalog.mjs` lists every Web component file as bundled or excluded with a reason.
  A bundled component whose spec has another name, such as DatePickerField for DateField, names it in `spec`, and a spec with no bundled component gets a card in the group `specOnlyGroups` gives it.
  `pnpm design-system:test:previews` renders every card in both themes in Chromium and checks that each spec specimen draws every prop value it covers.
- The Web Dashboard route loads `getHomeWorkspace` on the server and renders `components/home-dashboard.tsx` with component-owned CSS.
  Dashboard composes the shared PageFrame, PageHeader, CaptureComposer, EmptyState, ProgressiveImage, and Badge; Memory and Recent Entries share one Entry card renderer.
  Native `Features/Home` mirrors it with `MTPage`, `MTPageHeader`, `CaptureCard`, `MTEmptyState`, `MTRemoteImage`, and `MTBadge`; `DashboardComponents.swift` owns the counts, rows, and cards, with the identifiers `dashboard-counts`, `dashboard-memory`, `dashboard-now`, and `dashboard-recent`.
  The memory and Now stack on a phone, as Web stacks them below 900 px, and a one-line notice above them opens Pending sync while captures wait or cannot be read.
  Web `QuickCaptureDialog` shows CaptureComposer's dialog variant under its own header; native `QuickCaptureView` in `Features/Capture` shows the same header over `CaptureCard(style: .dialog)` full screen, where Web now anchors the composer to its bottom dock.
  The native composer saves a calendar day with an optional time from `Features/Capture/CaptureDate.swift`, and Command-Return saves from a hardware keyboard.
  Both composers open the relevant date in place, keep only problems in the composer, and announce a synced capture with a toast.
  A capture saved without a connection gets an info toast instead: Web checks the browser's connection before syncing, while `CaptureController` confirms a capture once when its first sync cannot reach MemoTrail and keeps later offline retries quiet.
  Web `SyncStatus` in the workspace header counts waiting and refused captures separately; selecting it retries now and opens a compact Dialog with the same `PendingCaptureList` both composers render.
  Native `MTSyncStatusButton` in `WorkspaceToolbar` does the same and opens Pending sync as a sheet.
  A refused capture is announced with an error toast, and `PendingCaptureList` and native `PendingCaptureRow` give it Copy text and a confirmed Discard; Retry now appears only while a capture is still waiting.
- Web `components/entry-editor-dialog.tsx` is the Entry editor on the Item page, with Cancel and Save changes, and its `NewEntryDialog` adds a Chapter or First Time from Timeline and First Times.
  It edits photos through `EntryPhotoField`: new photos upload after the Entry saves, and a saved photo moves to Trash at once after confirmation.
  `EntryPhotoDates` reads camera dates and GPS from the Entry's saved photos.
- The Web Item page loads its photos on the server with `lib/data/entry-photos.ts`, which also serves `/api/media/photos` for native, and `components/entry-photos.tsx` shows them read-only and pages through them in `PhotoPreviewDialog`.
- A Chapter's Item page adds the Entries dated inside it and the Chapters that share days with it, read through `lib/data/chapter-contents.ts` (server-only; the client-safe types and page size live in `chapter-contents-types.ts`) over `chapter_entries` and `chapter_overlaps` and paged with `?page=`.
  A Chapter with no calendar date has no days, so its page shows no contents; its Date fact reads the span and how long it lasted, or Undated.
- Library and search classify by the marks: `search_wiki_items` and `archive_wiki_search_evidence` take classifications `entry`, `chapter`, and `first_time`, combined by OR, and a date filter treats a Chapter without an end as still going on.
  `lib/data/search-input.ts` reads the older `home`, `vehicle`, `entity`, and `milestone` types as Chapters and First Times, and AI search has no "before the latest move" boundary.
- The complete export lists Chapters and First Times as the Entries they are: `export_dataset_names` has no `homes`, `vehicles`, or `milestones`, and `tables/entries.csv` carries the two marks as columns.
- Dashboard "Now" lists the Chapters that have started and not ended, and its First Time count comes from the mark.
- `/homes`, `/vehicles`, and `/first-times/[id]` redirect through `redirectRetiredRecord` in `lib/data/retired-routes.ts`: an address that names an Entry opens its Item page while the Entry exists, and every other address opens Timeline (or First Times).
  `/inbox` redirects to `/library` and `/inbox?entry=` to `/items/[entry]` in `next.config.ts`; Library ignores the retired `show=needs-organizing` parameter.
  Web captures from the bottom dock, and iOS from the Dashboard or New entry in the workspace header.
- Button, Dialog, PageHeader, EmptyState, and the previously reviewed gallery components are approved migration targets.
- Production actions use Button, IconButton, or ButtonLink without changing submit or navigation semantics; composite internals and navigation controls retain their distinct roles.
  `packages/design-system/components/button.yaml` specifies Button and ButtonLink with native `mtButtonStyle`.
- Dialog owns generic editor and confirmation shells, scroll containment, focus trapping/restoration, busy dismissal, and nested overlay containers.
  Its first focus goes to a `data-autofocus` control, else the first field; React's `autoFocus` fires before the trap starts, so an enclosing dialog's trap takes it back.
  Editor forms retain their handlers; footer submit actions use native form associations.
  Quick Capture uses a native HTML dialog anchored to the workspace bottom, preserving photo-picker cancellation, nested overlays, and focus restoration; its mobile geometry follows the visual viewport when the keyboard opens.
  The browser shows that dialog in the top layer and makes everything outside it inert, so a Dialog opened over it, such as the photo preview or a confirmation, portals into it and shows its positioner as a manual popover with the scrim as its `::backdrop` (`components/top-layer.ts`).
  A Dialog's content is a `data-escape-layer`, so Quick Capture leaves its Escape, Tab, and Mod-Enter to it.
  `WorkspaceActionDock` owns the shared bottom position and glass control styling for global Search and Quick Capture.
  PhotoViewer keeps native top-layer media geometry, and Command Palette keeps its search and keyboard-result interaction model.
- Reusable components do not import `app/**.module.css`; Web lint enforces this boundary along with valid token references.
  Feature modules own composition, and `editor-fields.module.css` shares native field spacing and states while excluding the reviewed composites' internals.
  Every hand-styled Web field draws the same surface as TextField, SelectField, and DateField: a `font.size.label` medium `color.inkMuted` label, a `space.2` label gap, a `size.field` height with its radius, and a `color.borderStrong` border, so mixed fields line up in one row.
- `apps/web/scripts/check-design-system.mjs`, part of `pnpm lint`, rejects any visual value Web CSS or scripts write by hand instead of reading a generated token; the rules live in `design-system-rules.mjs` with unit tests beside it.
  It fails on literal font sizes, line heights, letter spacing, weights, and families; hex, `rgb()`, `hsl()`, and named colors other than `transparent` and `currentColor`, including colors inside data URLs; `color-mix()` outside the generated tokens; literal z-index, opacity, durations, easing curves, and backdrop filters; and literal spacing, radii, stroke widths, focus offsets, shadow lengths, and icon sizes.
  It also rejects a fallback inside `var(--mt-*, ...)`, which would hide a literal.
  Each finding names the file and line and, when a token renders the same value in both themes, the token to use.
  CSS cannot read variables in media queries, so a media query width must be a `--mt-layout-breakpoint-*` value as `max-width` or one pixel above it as `min-width`, and a container query must be a `--mt-layout-container-*` value.
  That rule stands in for `@custom-media`, which Next.js leaves untranspiled and, with its Lightning CSS option, resolves only within one stylesheet, so a definition in the generated file cannot reach the modules.
  Scripts read colors from `themeColors` in the generated `design-system.ts`; the checker's allow list keeps only the Google sign-in mark's brand colors.
- Noninteractive status, type, and tag labels use `components/badge.tsx` with tone and size variants, single-line truncation, and Design System specimens.
  `packages/design-system/components/badge.yaml` specifies it with native `MTBadge`.
- Checkbox, SectionHeader, and Skeleton are the Web counterparts of `MTCheckbox`, `MTSectionHeader`, and `MTLoadingSkeleton`.
  `components/checkbox.tsx` is a native `input type="checkbox"` that submits like any other, named by its label and described by an optional explanation, with a `small` and a `medium` size.
  `components/section-header.tsx` is one component whose `variant` is `section` (a serif title) or `list` (the small uppercase heading above a list), like `MTSectionHeader`; both take a detail, a description, an action, and a heading level chosen by the caller, because the two differ only in typography.
  `components/skeleton.tsx` is a decorative placeholder hidden from assistive technology that stops its shimmer for reduced motion; `ProgressiveImage` and the route loading fallback use it, and the surrounding region announces the loading state.
  Feature code does not hand-roll checkbox markup, uppercase list headings, or shimmer placeholders; the `/design-system` specimens `checkbox`, `section-header`, and `skeleton` show every variant and state.
- Dot-separated summary and metadata rows use Web `components/separated-list.tsx` and native `MTFlowLayout` with `MTFlowSeparator`, or `MTWordFlow` for facts that read like a sentence.
  Facts wrap whole, and a "·" shows only between two facts on the same line, hidden from assistive technology.
  Web clips the separator of a fact that starts a line one gap outside the list, so focus rings stay whole; native line breaking leaves that separator out.
  `e2e/separated-rows.e2e.ts` and the native large-text summary test check the drawn lines.
- DatePickerField and OccurrenceEditor own `components/date-fields.module.css`; named date fields preserve native form validation and GET serialization without importing route styling.
- Inside a modal, date/time fields inherit its overlay container or accept an explicit `portalContainer` so their popovers stay inside its accessibility and theme boundary.
  Unnamed domain date fields retain the editor's contextual submit validation rather than introducing native custom-validity interception.
- Cross-platform components preserve meaning and state while allowing native interaction differences.
- Native `DesignSystem/Components` owns reusable presentation components.
  Generated `DesignTokens.swift` supplies semantic colors, the `MTTextRole` and `MTFont` text roles that follow Dynamic Type, `MTIcon`, `MTPageWidth`, spacing, sizes, layout, radius, motion and easing, line heights, shadow layers, state, materials, elevation, and the catalogs the gallery lists.
  `MTFoundations.swift` holds the view helpers that apply them, such as `mtTextRole`, `mtIcon`, `mtShadow`, `mtMaterial`, `mtLineSpacing`, and the `MTIcon` image and label initializers.
  Native actions use `mtButtonStyle` variants and sizes or `MTIconButton`; `MTBadge`, `MTPageHeader`, `MTSectionHeader`, and `MTEmptyState` mirror the Web Badge, PageHeader, SectionHeader, and EmptyState.
  `MTLoadMore` loads a list's next page as its end scrolls into view, or offers a retry, for Library, Tags, Trash, and a Chapter's Entries.
  `MTSectionHeader` with the `list` variant and `MTListSurface` are the uppercase list heading and bordered row surface that Library uses, and `MTListRowButtonStyle` gives whole-row links their pressed surface.
  `MTSheet` is the Web Dialog: its eyebrow, serif title, close action, scrolling content, failure message, and footer actions.
  A form sheet opens at full height for editors, and a fitted sheet sizes itself to short content; `MTSheetOption` is the Web dialog's icon, title, and description choice.
  `confirmationDialog` stands in for the Web confirmation shell.
  `MTFields.swift` owns the labeled text, textarea, search, select, and checkbox fields on one shared surface; `MTSelectGroup` titles runs of select options like a Web `optgroup`, and `MTDateField` edits optional wall-time text at day, month, or year granularity, and `MTTimeZoneField` lists offsets for the reference date.
  `OccurrenceEditor` is the Web date editor, and `MTOrganizationEditor` is the Web tag field with Most used suggestions, reusing a tag that differs only by case and showing the count from 60 of the 70 allowed; adding a name opens a picker sheet so suggestions stay above the keyboard.
  `MTCheckbox` passes its accessibility identifier through and reads On or Off, and `MTFlowLayout` can align each row on its children's first text baseline, as the date toggles do.
  `MTCards.swift` owns `MTRecordCard`, `MTRecordCardFooter`, and the shared `MTCardButtonStyle`; `MTRichTextContent` renders `Models/EntryRichText.swift`, which validates Web `body_rich` documents like `lib/data/rich-text.ts` and falls back to the plain body.
  With a line limit it flows the writing into one clamped preview that keeps emphasis, list markers, and line breaks.
  `MTToastCenter` shows Web-timed success, info, and error toasts in a pass-through window above sheets.
  Like Web, they rise from the bottom, clear of the tab bar, sheet actions, and the keyboard, so back and close buttons stay reachable.
  `MTMedia.swift` owns `MTRemoteImage`, the loading skeleton, `MTUploadProgress`, and `MTPhotoField`; feature editors use them instead of private image loaders.
  `MTPhotoPreview` shows saved photos whole and pages between them with Previous, Next, and the position, like Web's photo viewer; `MTPhotoField` and `MTRecordPhotos` open it.
  `MTRecordDetail.swift` owns `MTFormSection`, the Web editor fieldset whose fields sit on the raised surface, with an accent tone for panels such as the tag editor's Merge this tag, and `MTFactList`, `MTDetailSection`, and `MTRecordPhotos`, which lay out facts, sections, and photos.
  `MTLocation.swift` owns `MTLocationSnapshot`, a MapKit still with a pin that stands in for the Web static map, `MTLocationPreview`, the Web selected-Location card, and `MTLocationPanel`, the Web Location picker's panel; record cards fall back from a photo to that map to `MTRecordMark`, with glass badges over the visual.
  Clipped media sets a matching content shape, because clipping does not limit hit testing and filled photos would otherwise take taps meant for neighboring controls.
- The Debug-only `DesignSystem/DesignSystemGallery.swift` renders those real components with appearance and text-size controls, in the same section order as the Web gallery.
  It is reached from the signed-out screen, More, or Settings.
- Debug launch arguments in `App/NativeReview.swift` expose isolated gallery, sign-in, and navigation review modes; `--review-design-section <name>` opens one gallery section directly.
  The navigation mode has no backend, so First Times, Tags, and Trash show their unavailable states there.
  `--review-local-session` signs in with a disposable local Supabase session from `scripts/review-local-session.py`, keeps it out of the Keychain, and accepts only 127.0.0.1 endpoints.
  Adding `--review-offline` fails that session's requests like an iPhone with no network once it has signed in, through the `NativeReviewNetwork` switch the local contract tests also use.
  In that mode the environment key `MEMOTRAIL_REVIEW_UNREADABLE_CAPTURE` seeds one unreadable capture into an empty queue, and `-native-appearance dark` forces dark mode.
  Release builds omit these modes and the gallery; `MemoTrailUI` runs their Simulator interaction tests.
  `scripts/local_supabase.py` owns disposable account creation and cleanup for both native local scripts.
- Native app targets skip App Intents metadata extraction because they declare no App Intents.
  Enable extraction when native shortcuts are introduced.
- Authenticated Web routes use `components/page-frame.tsx` for outer width, centering, responsive gutters, and vertical page rhythm.
- Page frame variants are semantic: `compact` is 880px for forms and focused reading, `standard` is 960px for lists and search, `wide` is 1080px for dashboards and card grids, and `canvas` is 1180px for dense spatial views.
- New route pages choose the narrowest variant that fits their content; feature grids and visualizations own their internal breakpoints instead of redefining the outer page geometry.
- Web photo surfaces reuse `components/progressive-image.tsx` for a reserved skeleton, decode fade-in, failure fallback, and reduced-motion behavior while private expiring media URLs continue to bypass the public Next image cache.
- Chapter and First Time result layouts reuse `components/record-card.tsx`; mark modules own only their visual, metadata, and responsive content rules.
  Noninteractive history, Collection, and Trash surfaces retain their distinct link or multi-action semantics instead of nesting actions inside a button card.
- Entry editors reuse `components/entry-photo-field.tsx` for selected and existing previews, removal controls, limits, and upload progress.
- Web domain editors own label-to-control spacing in their shared field wrapper; route forms reuse that wrapper and the spacing tokens instead of compensating field by field.
- Quick Capture renders the shared draft from `CaptureProvider`, so its editor is ready before the dialog first opens and photo drafts load without moving it; its loading and editor geometries stay equal.
  Its editor remains mounted while the native dialog is closed and follows edits from the Dashboard composer; closing stops voice capture while pending captures keep syncing.
  `RichTextEditor` applies outside changes without emitting an update and toggles editability silently, so a mirrored or disabled editor never writes its text back as a new edit.
  `CaptureComposer` handles Command/Control Return in the active form's capture phase before Tiptap's modified-Enter bindings, then uses native `requestSubmit` and the Save button's disabled state to retain validation and queue semantics.
  Composition, held-key repeats, and nested editing layers cannot submit through that shortcut; shared editor bindings remain available outside Capture.
  The frosted surface uses a static backdrop blur and translucent reflection, while entrance and exit animate only opacity and translation and honor reduced motion.
- Web appearance uses the existing light and dark semantic tokens, stores a per-browser System, Light, or Dark choice in a same-site cookie, and lets the server root layout apply explicit themes before first paint without adding a client-side flash.

## Runtime and validation

- Production Web runs on Vercel from `apps/web`.
- Production data changes are versioned Supabase migrations without development seed data.
- Server-only Supabase, Geoapify, AI, and embedding-service credentials exist only in trusted environments.
- Web address searches and static maps pass through authenticated route handlers, so `GEOAPIFY_API_KEY` is never exposed to the browser.
  The proxy sends only the requested search text or coordinates to Geoapify, not the signed-in user's identity.
- The Web Map destination is retired along with its tile proxy and Leaflet; Web shows a Location only as an editor preview and on record cards.
  The native Map is retired too; iOS shows a saved Location as a MapKit still in the Entry editor and on First Times cards, lists it as a fact on the Item page, and has no address search.
- Static Location previews accept only light or dark theme parameters; the authenticated route chooses an allowlisted Geoapify style while keeping the provider key server-side.
- Address search and preview routes each consume an owner-scoped hourly database quota before contacting Geoapify.
- iOS receives public backend configuration and the Web API base URL.
- `lib/auth/api.ts` verifies Web cookie or native bearer identity for media, metadata, and export independently of AI availability.
  AI routes add their own per-feature gate before shared authentication, and iOS has no AI entry points.
- `src/proxy.ts` refreshes the Supabase session for pages and Server Actions.
  API routes are outside its matcher because they authenticate and refresh the session themselves, so Next.js does not copy upload bodies for the proxy, and an upload the browser abandons ends quietly.
- Shared behavior should be implemented and tested across Web, iOS, and Supabase in the same product slice.
- Validation should cover the narrow unit or SQL contract first, then builds, then the closest real browser or native interaction.
- Web unit collection includes both `.test.ts` and `.test.tsx`; synchronous rendering assertions belong in this fast layer.
- Multi-client RPC, Storage, and database-locking tests belong in `apps/web/contracts` and run independently of Next.js and Chrome.
  Browser interactions and Web HTTP route acceptance remain in `apps/web/e2e`.
  A browser test ends only after the page shows the result of its last action, so the server never logs a render the closing page cut short.
  The development-only design gallery has its own browser runner and is excluded from product acceptance.
  Test servers isolate Next.js build output and generated TypeScript configuration by port.
- Native unit and backend contracts use `MemoTrail`, while Simulator UI interactions use `MemoTrailUI`.
  The local account wrappers support explicit XCTest selection without reducing the default full-suite coverage.
  Build caches are isolated per checkout, logs are unique per run, and concurrent use of one build directory fails immediately.
- Keep regression cases that protect distinct behavior, even when unit, SQL, and UI coverage overlap.
  Delete a test when its product surface has been retired and current behavior is covered; do not keep permanently skipped tests for removed UI.
  The retired active-AI browser flows are removed, while the pause flow, the review browser flows, retained provider unit tests, SQL tests, and multi-client exploration contracts remain.
- Hosted configuration, destructive behavior, media integrity, and recovery require their own end-to-end evidence.

Commands live in the root [README.md](../README.md).
Current acceptance gaps live in [status.md](./status.md).
