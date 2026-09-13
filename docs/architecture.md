# MemoTrail Architecture

Last reviewed: 2026-09-13.

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

| Request                                                  | Web                                                                                               | iOS                                                                                   | Shared data and tests                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Authentication or environment                            | `app/auth`, `lib/auth`, `lib/supabase`, `src/proxy.ts`                                            | `Features/Authentication`, `App/AppConfiguration.swift`                               | foundation and security migrations, `0001_rls.test.sql`                          |
| Capture, Inbox, drafts, dates, or offline sync           | `app/inbox`, capture and occurrence components, `lib/data/inbox*`, `lib/data/occurrence.ts`       | `Features/Inbox`, `Models/InboxEntry.swift`, `Models/EntryOccurrence.swift`           | Inbox, occurrence, review, and media migrations and matching tests               |
| Search, AI suggestions, or exploration                   | `app/search`, `app/explore`, `app/settings/ai`, `lib/ai`, `lib/data/search*`                      | `Features/Search`, `Features/AI`                                                      | AI, evidence, exploration, and search migrations and tests                       |
| Photos, metadata, or export                              | media and export API routes, `lib/media`, `lib/export`, gallery and export components             | `Features/Inbox`, `Features/History`, `Features/Export`, `Models/MediaDelivery.swift` | media, photo-history, cleanup, and export migrations and tests                   |
| Timeline, Homes, Vehicles, Goals, or First Times         | matching `app` route, workspace component, and `lib/data` module                                  | matching directory under `Features` and model under `Models`                          | matching contract and occurrence migrations and tests                            |
| Collections, People, Places, links, history, or Trash    | matching `app` route and component, `lib/data` organization, relation, history, and Trash modules | matching directory under `Features`                                                   | organization, relationship, history, Trash, and Empty Trash migrations and tests |
| Visual system                                            | components, CSS modules, `styles/generated-tokens.css`                                            | `DesignSystem`, `DesignSystem/Generated`                                              | `packages/design-tokens/tokens.json` and generator                               |

For a database behavior, search migrations for the newest definition of the relevant RPC instead of assuming the first occurrence is current.
Pair it with the test file carrying the same feature name.

## Shared data rules

- Supabase Postgres is the canonical synchronized data store.
- Row Level Security is the final owner-authorization boundary for exposed data.
- Web cookies and native bearer sessions identify the same Supabase user.
- Entries are canonical content; specialized tables add facts without duplicating writing.
- Collections, tags, People, Places, and Entry links are owner-scoped reusable relationships.
- Multi-record changes use authenticated RPCs so content, relationships, history, and specialized facts commit atomically.
- Clients send the revision they read. A stale revision surfaces a conflict instead of silently merging or overwriting another device.
- Important mutations snapshot prior state. Restoring history creates another revision rather than deleting subsequent history.
- Older clients must preserve fields they cannot represent or reject the write safely.

## Date rules

- Occurrence precision is part of the data, not presentation metadata.
- Exact timestamp, day, month, year, age, range, approximate, and Unknown values remain distinct.
- Unknown and description-only dates have no fabricated calendar anchor.
- Recorded timezone controls calendar interpretation and search overlap.
- Timeline, search, Home, and specialized editors must use the same occurrence semantics.

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
- AI defaults off and is controlled per feature; photo analysis has separate consent.
- Budget is reserved before a request and reconciled from actual usage.
- Interrupted provider outcomes do not trigger automatic paid retries.
- Suggestion and search outputs are schema-validated and remain separate from original writing until explicit user action.
- Search answers cite exact stored evidence; provenance does not imply that the model's conclusion is true.

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
