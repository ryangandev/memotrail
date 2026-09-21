# MemoTrail Architecture

Last reviewed: 2026-09-16.

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

| Request                                                     | Web                                                                                                                                 | iOS                                                                                   | Shared data and tests                                                            |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Authentication or environment                               | `app/auth`, `lib/auth`, `lib/supabase`, `src/proxy.ts`                                                                              | `Features/Authentication`, `App/AppConfiguration.swift`                               | foundation and security migrations, `0001_rls.test.sql`                          |
| Capture, Inbox, drafts, dates, rich text, or offline sync   | `app/inbox`, capture, rich-text and occurrence components, `lib/data/inbox*`, `lib/data/rich-text.ts`, `lib/data/occurrence.ts`     | `Features/Inbox`, `Models/InboxEntry.swift`, `Models/EntryOccurrence.swift`           | Inbox, occurrence, review, and media migrations and matching tests               |
| Search, AI suggestions, or exploration                      | `app/search`, `app/explore`, `app/settings/ai`, `lib/ai`, `lib/data/search*`                                                        | `Features/Search`, `Features/AI`                                                      | AI, evidence, exploration, and search migrations and tests                       |
| Photos, metadata, or export                                 | media and export API routes, `lib/media`, `lib/export`, gallery and export components                                               | `Features/Inbox`, `Features/History`, `Features/Export`, `Models/MediaDelivery.swift` | media, photo-history, cleanup, and export migrations and tests                   |
| Timeline, Homes, Vehicles, Goals, or First Times            | matching `app` route, workspace component, and `lib/data` module                                                                    | matching directory under `Features` and model under `Models`                          | matching contract and occurrence migrations and tests                            |
| Collections, tags, People, Places, links, history, or Trash | matching `app` route and component, shared Entry organization editor, `lib/data` organization, relation, history, and Trash modules | matching directory under `Features`                                                   | organization, relationship, history, Trash, and Empty Trash migrations and tests |
| Visual system                                               | shared page frame and components, CSS modules, `styles/generated-tokens.css`                                                        | `DesignSystem`, `DesignSystem/Generated`                                              | `packages/design-tokens/tokens.json` and generator                               |

For a database behavior, search migrations for the newest definition of the relevant RPC instead of assuming the first occurrence is current.
Pair it with the test file carrying the same feature name.

## Shared data rules

- Supabase Postgres is the canonical synchronized data store.
- Row Level Security is the final owner-authorization boundary for exposed data.
- Web cookies and native bearer sessions identify the same Supabase user.
- `entries` is the physical canonical Wiki Item table.
  Its historical SQL name does not make Entry a product-level Kind or identity boundary.
- `entries.item_kind` owns the structural identity boundary: Capture, Writing, Entity, Event, Story, or Goal.
- `entries.item_subtype` selects a compatible preset within that Kind.
- `wiki_items_workspace` supplies one owner-scoped Library row per canonical Wiki Item. Person rows expose both the canonical Entry ID and their specialized record ID so clients can preserve identity while opening the correct editor.
- Web `lib/data/wiki-items.ts` and native `LibraryController` consume that same bounded workspace.
  Web routes typed records to focused editors and general items to `/items/[entry]`, where current content and primary actions precede an explicit history link.
  Native Library routes typed records to their focused editors and other canonical items to the shared History detail/edit boundary.
- `collection_wiki_items` composes the established paged Collection detail with canonical Kind, subtype, and specialized routing identity. Both clients use it so Collections remain organizational lenses rather than a second generic detail system.
- `people.entry_id` is a required owner-scoped link to a canonical Entity Wiki Item. Triggers keep its name, notes, revision state, and Trash state synchronized.
- `places` is an independent owner-scoped Focused View record with its own revision and Trash history. It has no canonical `entries` mirror and owns no links to other Focused View records.
- `locations` stores private per-Entry address and coordinate snapshots with provider provenance, revision state, and soft deletion. It is not a Wiki Item or reusable catalog.
- Location rows are immutable through the authenticated table API.
  `review_wiki_item_with_location_rich` atomically creates a Geoapify snapshot or keeps the current Entry's Location and replaces only its `primary` relationship.
  Home's provider-backed save uses `save_home_entry_with_geoapify` to create and link a snapshot in the same transaction; manual Home saves use `resolve_home_location_copy_on_write` for an unchanged current value or a new snapshot.
  Specialized First Time and Vehicle editors use `save_first_time_with_location` and `save_vehicle_with_location` when changing a primary Location, preserving their existing save paths when Location is untouched.
  `locations.bound_entry_id`, owner-scoped foreign keys, and deferred link constraints reject attempts to attach one snapshot to another Entry or commit an active unbound snapshot. Provider identity is provenance, not a deduplication key.
  Replaced or removed snapshots stay bound to their Entry so history restoration remains possible. Permanently deleting that Entry cascades its Location snapshots; moving an Entry to Trash does not.
  Legacy `name` and `notes` columns remain for existing RPC and iOS wire shapes, but compatibility writers ignore those inputs, derive the label from address facts, and clear notes; Web exposes neither custom field nor saved-Location search.
- `homes.place_id` and `entry_places.place_id` remain compatibility column names for one cross-client window, but their foreign keys target `locations`; new reads use the `entry_locations` view and Location vocabulary.
- A raw Capture may be finalized as one durable item or may produce linked items through a provenance-preserving extraction.
- Established durable items never change Kind through a generic selector; cross-Kind workflows create and link another item.
- Dedicated Web extraction routes pass only the source Capture ID, reload the owner-scoped saved source on the server, and prefill the specialized form without placing personal content in the URL or client storage.
- `capture_extraction_source` supplies the reusable raw-Capture handoff contract. Specialized extraction RPCs create the typed target, organize the preserved Capture as `capture:source_capture`, and record `derived` plus `derived_from` links in one transaction.
- Web Goal extraction uses a caller-generated target UUID for idempotency, preserves the source revision and identity, and records `derived` plus `derived_from` provenance links so both items remain discoverable.
- `review_wiki_item_with_photo_place` is the plaintext-client semantic review boundary. iOS uses it to finalize a Capture or edit a same-Kind Writing, Event, or Story while preserving rich-text metadata the native editor does not author.
- The iOS Inbox sends canonical Kind and subtype values. Its generic organizer exposes only Writing, Event, and Story; Entity and Goal creation must use their dedicated forms and extraction RPCs.
- Native Inbox handoffs reuse the existing Home, Vehicle, and Goal editors with a `CaptureExtractionSource`. The same validated domain input drives either the normal save RPC or the matching extraction RPC, so specialized fields, source revision checks, organization, dates, and provenance stay aligned with Web.
- Web and iOS create a separately editable Goal with `extract_goal_from_item` when an established Wiki Item inspires a Goal. The caller-generated Goal ID makes lost-response retries idempotent, and History exposes both provenance directions.
- `convert_entry_to_goal` remains only as an administrative recovery function. Authenticated and anonymous clients have no execute grant because established items must never change Kind through a conversion.
- Specialized tables add typed facts without duplicating common writing, organization, dates, media, or history.
- `entries.body` remains canonical plaintext. Optional validated rich content is versioned under `entries.metadata.body_rich`, carries the exact matching plaintext, and is ignored when another client changes the body without updating the rich document.
- Web capture and Entry review use `components/rich-text-editor.tsx` for the reusable headless editor surface, with page, dialog, and form variants instead of separate editors.
  `components/entry-rich-text-content.tsx` safely renders validated formatting on note surfaces and falls back to canonical plaintext when rich metadata is absent, invalid, or stale.
  Formatting controls expose their real keyboard commands through accessible tooltips; drafts and pending queues preserve the same rich payload, while the compatibility RPC `review_entry_with_photo_place_rich` writes plaintext, formatting, organization, occurrence, and photo Location adoption in one revision.
  Older review RPCs preserve rich metadata they do not understand.
- Collections, tags, People, and Wiki Item links are owner-scoped reusable relationships. Locations are Entry-owned snapshots; Places remain independent personal records.
- Kind owns identity, subtype owns compatible specialized structure, Collections own curated cross-Kind groupings, tags own lightweight cross-Kind descriptors, and Timeline tracks own presentation only.
- Home and Vehicle are Entity subtypes whose occurrence range describes the user's relationship span.
- Memory and First Time are Event subtypes.
- Story or Chapter is explicit authored narrative and is never inferred from an Entity's date range.
- Web Entry editors reuse `components/entry-organization-editor.tsx`; their save RPC must atomically preserve Collection and tag memberships with the canonical Entry mutation.
- Used tags merge atomically into another stable tag identity. Only unused tags can be deleted directly.
- Tag management loads at most five linked Entry previews on demand through a server action, so the Tags page stays lightweight and never creates a per-tag data waterfall during its initial render.
- Multi-record changes use authenticated RPCs so content, relationships, history, and specialized facts commit atomically.
- Clients send the revision they read. A stale revision surfaces a conflict instead of silently merging or overwriting another device.
- Important mutations snapshot prior state. Restoring history creates another revision rather than deleting subsequent history.
- Older clients must preserve fields they cannot represent or reject the write safely.
- AI organization payloads use `classification.itemKind` and `classification.itemSubtype`.
  The database rejects the removed `entryType` payload shape so a stale client cannot silently reintroduce the legacy model.

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
- Timeline creation routes by Entry type, not track name. Generic moments use the Timeline editor; Home, Vehicle, and First Time creation and editing reuse the exported Records editors in a lazy-loaded Timeline modal. System track shortcuts select the corresponding specialized type, while ordinary tracks preselect the generic editor's placement.
- Timeline server data loads specialized records, Collection, and tag choices needed by those editors in parallel, so opening a known specialized Entry does not require a route transition or client-side data waterfall.
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
- Generation validates source identity and bounded output before registration.
- Database rows coordinate deletion, but Storage objects are removed through the Storage API.
- Permanent deletion includes registered and interrupted-generation artifacts and must remain retryable after uncertain cleanup.

## AI rules

- The Next.js server is the only AI provider boundary.
- Native requests reuse the user's Supabase bearer session and never receive provider credentials.
- Anthropic is the initial text provider behind a replaceable server interface.
- AI defaults off. Web maps its user-facing master, organizing, and photo controls onto the more granular shared preference contract; photo understanding retains separate consent.
- AI provider diagnostics, model identifiers, token prices, and editable spending caps stay out of ordinary Web settings. Existing per-user and server-wide budget enforcement remains active behind a simple monthly activity summary.
- Budget is reserved before a request and reconciled from actual usage.
- Interrupted provider outcomes do not trigger automatic paid retries.
- Suggestion and search outputs are schema-validated and remain separate from original writing until explicit user action.
- Search answers cite exact stored evidence; provenance does not imply that the model's conclusion is true.
- `search_wiki_items` accepts canonical Kind and subtype classifications and returns Kind, subtype, record source, and specialized routing identity in one owner-scoped result stream for Web and iOS. Linked Location fields contribute searchable context; independent Places remain in their Focused View.
- The persistent Web Command Palette debounces input before calling the dynamic, private, no-store `app/api/search/quick` route. That route returns one bounded owner-scoped canonical result stream and leaves filtered or AI search on the full Search page.

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
- The development-only `/design-system` route renders production Web components and current generated tokens for review; it is unavailable in Production.
- Button, Dialog, PageHeader, EmptyState, and the previously reviewed gallery components are approved migration targets.
- Production actions use Button, IconButton, or ButtonLink without changing submit or navigation semantics; composite internals and navigation controls retain their distinct roles.
- Dialog owns generic editor and confirmation shells, scroll containment, focus trapping/restoration, busy dismissal, and nested overlay containers.
  Editor forms retain their handlers; footer submit actions use native form associations.
  Native Quick Capture keeps its photo-picker cancellation and full-screen mobile behavior, PhotoViewer keeps native top-layer media geometry, and Command Palette keeps its combobox/listbox interaction model.
- Reusable components do not import `app/**.module.css`; Web lint enforces this boundary along with valid token references.
  Feature modules own composition, and `editor-fields.module.css` shares native field spacing and states while excluding the reviewed composites' internals.
- DatePickerField and OccurrenceEditor own `components/date-fields.module.css`; named date fields preserve native form validation and GET serialization without importing route styling.
- Inside a modal, date/time fields inherit its overlay container or accept an explicit `portalContainer` so their popovers stay inside its accessibility and theme boundary.
  Unnamed domain date fields retain the editor's contextual submit validation rather than introducing native custom-validity interception.
- Cross-platform components preserve meaning and state while allowing native interaction differences.
- Authenticated Web routes use `components/page-frame.tsx` for outer width, centering, responsive gutters, and vertical page rhythm.
- Page frame variants are semantic: `compact` is 880px for forms and focused reading, `standard` is 960px for lists and search, `wide` is 1080px for dashboards and card grids, and `canvas` is 1180px for dense spatial views.
- New route pages choose the narrowest variant that fits their content; feature grids and visualizations own their internal breakpoints instead of redefining the outer page geometry.
- Web photo surfaces reuse `components/progressive-image.tsx` for a reserved skeleton, decode fade-in, failure fallback, and reduced-motion behavior while private expiring media URLs continue to bypass the public Next image cache.
- Home, Vehicle, First Time, Goal, Person, and Place result layouts reuse `components/record-card.tsx`; subtype modules own only their visual, metadata, and responsive content rules.
  Noninteractive history, Collection, and Trash surfaces retain their distinct link or multi-action semantics instead of nesting actions inside a button card.
- Specialized record editors reuse `components/entry-photo-field.tsx` for selected and existing previews, removal controls, limits, and upload progress.
- Web domain editors own label-to-control spacing in their shared field wrapper; route forms reuse that wrapper and the spacing tokens instead of compensating field by field.
- Quick Capture restores local text and occurrence state before paint, keeps the loading and editor geometries equal, and loads IndexedDB photo drafts separately so editor initialization cannot move the open dialog.
- Web appearance uses the existing light and dark semantic tokens, stores a per-browser System, Light, or Dark choice in a same-site cookie, and lets the server root layout apply explicit themes before first paint without adding a client-side flash.

## Runtime and validation

- Production Web runs on Vercel from `apps/web`.
- Production data changes are versioned Supabase migrations without development seed data.
- Server-only Supabase, Geoapify, and AI credentials exist only in trusted environments.
- Web address searches and static maps pass through authenticated route handlers, so `GEOAPIFY_API_KEY` is never exposed to the browser.
  The proxy sends only the requested search text or coordinates to Geoapify, not the signed-in user's identity.
- iOS receives public backend configuration and the Web API base URL.
- Shared behavior should be implemented and tested across Web, iOS, and Supabase in the same product slice.
- Validation should cover the narrow unit or SQL contract first, then builds, then the closest real browser or native interaction.
- Hosted configuration, destructive behavior, media integrity, and recovery require their own end-to-end evidence.

Commands live in the root [README.md](../README.md).
Current acceptance gaps live in [status.md](./status.md).
