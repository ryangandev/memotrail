# MemoTrail Architecture

Last reviewed: 2026-09-15.

## System map

| Area              | Responsibility                                                              | Primary location                                                                                   |
| ----------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Web client        | Next.js routes, server actions, responsive UI, browser drafts and queues    | `apps/web/src/app`, `apps/web/src/components`, `apps/web/src/lib`                                  |
| Web server        | Authenticated AI, media, metadata, and export APIs                          | `apps/web/src/app/api`, `apps/web/src/lib/ai`, `apps/web/src/lib/media`, `apps/web/src/lib/export` |
| Native client     | SwiftUI screens, controllers, device drafts and queues, native integrations | `apps/ios/MemoTrail/Features`, `apps/ios/MemoTrail/Models`, `apps/ios/MemoTrail/App`               |
| Shared data       | Postgres schema, RLS, Storage policies, atomic RPCs, history, and search    | `supabase/migrations`                                                                              |
| Data verification | Ownership, denial, concurrency, lifecycle, and contract tests               | `supabase/tests`                                                                                   |
| Design system     | Semantic source tokens and generated Web and Swift outputs                  | `packages/design-tokens`                                                                           |
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
- `entries` remains the compatibility name of the canonical Wiki Item table while Web and iOS migrate to the Capture First Life Wiki vocabulary.
- `entries.item_kind` owns the structural identity boundary: Capture, Writing, Entity, Event, Story, or Goal.
- `entries.item_subtype` selects a compatible preset within that Kind.
- `entries.entry_type` is a synchronized compatibility discriminator for older clients and must not become the source of new product semantics.
- `wiki_items_workspace` supplies the owner-scoped Library browse surface across `entries` plus the legacy People and Places registries. Those registries are exposed as Entity presets until their storage is consolidated behind canonical Wiki Item identities.
- A raw Capture may be finalized as one durable item or may produce linked items through a provenance-preserving extraction.
- Established durable items never change Kind through a generic selector; cross-Kind workflows create and link another item.
- Web Goal extraction uses a caller-generated target UUID for idempotency, preserves the source revision and identity, and records `derived` plus `derived_from` provenance links so both items remain discoverable.
- `convert_entry_to_goal` remains only as a deprecated native-client compatibility RPC until the iOS Life Wiki adoption replaces it, after which its authenticated grant must be removed.
- Specialized tables add typed facts without duplicating common writing, organization, dates, media, or history.
- `entries.body` remains canonical plaintext. Optional validated rich content is versioned under `entries.metadata.body_rich`, carries the exact matching plaintext, and is ignored when another client changes the body without updating the rich document.
- Web capture and Entry review use `components/rich-text-editor.tsx` for the reusable headless editor surface, with page, dialog, and form variants instead of separate editors.
  `components/entry-rich-text-content.tsx` safely renders validated formatting on note surfaces and falls back to canonical plaintext when rich metadata is absent, invalid, or stale.
  Formatting controls expose their real keyboard commands through accessible tooltips; drafts and pending queues preserve the same rich payload, while `review_entry_with_photo_place_rich` writes plaintext, formatting, organization, occurrence, and photo Place adoption in one revision.
  Older review RPCs preserve rich metadata they do not understand.
- Collections, tags, People, Places, and Wiki Item links are owner-scoped reusable relationships.
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
- Timeline server data loads the specialized records and shared Place, Collection, and tag choices needed by those editors in parallel, so opening a known specialized Entry does not require a route transition or client-side data waterfall.
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
- Search retains the compatibility parameter name `p_entry_types`, but `search_entries_ordered` interprets each value as a Wiki Item Kind, subtype, or legacy `entry_type` before pagination. Web result labels and routes come from `item_kind` plus `item_subtype`; People and Places join keyword and AI results when the selected semantic scope includes their Entity presets.
- The persistent Web Command Palette debounces input before calling the dynamic, private, no-store `app/api/search/quick` route. That route runs owner-scoped Entry and Library RPCs in parallel, returns a bounded result shape, and leaves filtered or AI search on the full Search page.

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
- Cross-platform components preserve meaning and state while allowing native interaction differences.
- Authenticated Web routes use `components/page-frame.tsx` for outer width, centering, responsive gutters, and vertical page rhythm.
- Page frame variants are semantic: `compact` is 880px for forms and focused reading, `standard` is 960px for lists and search, `wide` is 1080px for dashboards and card grids, and `canvas` is 1180px for dense spatial views.
- New route pages choose the narrowest variant that fits their content and keep internal grid, dialog, and visualization breakpoints in page-specific CSS instead of redefining the outer page geometry.
- Web photo surfaces reuse `components/progressive-image.tsx` for a reserved skeleton, decode fade-in, failure fallback, and reduced-motion behavior while private expiring media URLs continue to bypass the public Next image cache.
- Quick Capture restores local text and occurrence state before paint, keeps the loading and editor geometries equal, and loads IndexedDB photo drafts separately so editor initialization cannot move the open dialog.
- Web appearance uses the existing light and dark semantic tokens, stores a per-browser System, Light, or Dark choice in a same-site cookie, and lets the server root layout apply explicit themes before first paint without adding a client-side flash.

## Runtime and validation

- Production Web runs on Vercel from `apps/web`.
- Production data changes are versioned Supabase migrations without development seed data.
- Server-only Supabase and AI credentials exist only in trusted environments.
- iOS receives public backend configuration and the Web API base URL.
- Shared behavior should be implemented and tested across Web, iOS, and Supabase in the same product slice.
- Validation should cover the narrow unit or SQL contract first, then builds, then the closest real browser or native interaction.
- Hosted configuration, destructive behavior, media integrity, and recovery require their own end-to-end evidence.

Commands live in the root [README.md](../README.md).
Current acceptance gaps live in [status.md](./status.md).
