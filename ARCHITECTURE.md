# MemoTrail Architecture

Last reviewed: 2026-09-12.

## System boundaries

MemoTrail has one private Supabase data model and two first-class clients: Next.js Web and native SwiftUI iOS.
Both clients use the same authenticated Postgres RPCs for atomic mutations, optimistic revisions, relationships, and recoverable deletion.
Supabase Row Level Security is the authorization boundary for all personal data.
The shared Soft Ledger tokens generate platform-specific presentation values.

The Next.js server is also the authenticated API boundary for AI and portable exports.
Web requests use verified Supabase cookies; native requests use a verified Supabase bearer token.
AI credentials never enter browser JavaScript, iOS resources, application logs, or exported archives.
iOS needs only the public API base URL and its existing session.

## Data ownership and consistency

Entries remain the canonical content unit; specialized tables add facts without duplicating writing.
Collections, tags, People, and Places are reusable owner-scoped relationships.
All mutations that replace content and links happen in one database transaction.
Updates include the revision read by the client and surface a conflict when another device has changed it.
History records the prior content and relationships before mutation.
Restoration creates another revision rather than removing subsequent history.
Version-two Entry snapshots capture organization, specialized details, Timeline and Entry relationships, and private photo membership before each mutation.
Restoration validates all historical references and original files atomically and never overwrites independent shared People or Place definitions.
Legacy snapshots restore only relationships they actually recorded; missing fields do not imply empty relationships.
Trash restoration remains separate from restoring content history, and optimistic revision checks prevent overwriting newer work from another device.
Timeline tracks have independent optimistic revisions; renaming preserves their system identity and hiding is reversible presentation state, never content deletion.
Collection and tag definitions also have independent revisions, while name changes advance linked Entry revisions and snapshot previous organization before mutation.
Collection Trash preserves grouping relationships for restoration; permanent Collection deletion never deletes its Entries or original media.
Restoring a Collection with a colliding active name fails atomically and asks for an explicit rename rather than merging or overwriting data.
Bucket List behavior follows a stable Collection role, not its editable display name, and both clients consume that role from the shared Goal workspace.
Uploads preserve private originals, and display access uses expiring signed URLs.
Drafts and pending captures remain per-user and durable on each device until synchronization is confirmed.

## AI architecture

Anthropic is the selected text provider.
The initial provider is pinned to `claude-haiku-4-5-20251001`, verified through a real authenticated localhost request.
Changing models requires updating the usage rates and tests together; an unknown model fails closed rather than silently using incorrect pricing.
Classification, retrieval, exploration, and resurfacing have separate user controls.
Model responses are untrusted structured suggestions, validated before storage and never executed as instructions.
Classification stores suggestions separately from original Entry content; accepting a suggestion fills an editable review and never marks an Entry Done automatically.
`ai_suggestions` deduplicates work by Entry revision and enabled feature scope, and only trusted server code can write model results.
Web schedules capture suggestions after its response; iOS starts an independent authenticated request after synchronization.
Review is also a recovery entry point for interrupted background work, with bounded status polling and explicit-only retries after a failed generation.
Date suggestions remain readable guidance until precision-aware review can preserve their meaning without inventing timestamps.
New Collections require user acceptance.
Exploration remains attached to its source Entry, and Save as Entry creates a separately identified conclusion with a source relationship.
Retrieval answers cite only authenticated source Entries and report insufficient evidence explicitly.

Anthropic generation and vector embeddings are separate provider capabilities.
No embedding provider has been supplied, so the implementation must distinguish model-assisted retrieval from a complete vector index and document any remaining search limitation.
Photo analysis remains opt-in; initial live tests use synthetic text.
Real test requests have bounded input, output, request counts, and an application usage ledger.
The user authorized a maximum of $3.50 from the supplied account balance; failures must not trigger uncontrolled retry loops.
The application defaults to a $3 server-wide lifetime cap and $1 per-user monthly cap, with atomic pre-request reservations and a 60-request hourly limit.
Completed requests reconcile reported token usage; interrupted requests retain their full reservation until explicitly reconciled.
Only service-role RPCs can modify accounting, and anonymous billing records survive account removal so deleting an account cannot reset the global cap.

## Delivery and verification

`PRODUCT.md` is the product contract.
`PROGRESS.md` is the chronological implementation record and is updated in every commit.
`REMAINING.md` is the current cross-platform acceptance matrix and records blockers without treating partial work as complete.
`SETUP_CHECKLIST.md` records external configuration and user-only setup.
Each finished feature includes the database contract where needed, Web and iOS integration, relevant tests, and an atomic commit pushed to main.
Database migrations are tested locally with seeded pgTAP fixtures and ownership denial checks before the approved hosted push.
Client checks include relevant unit tests, Web build and interaction verification, native Simulator build and tests, and GitHub CI.
Green builds are reported separately from actual provider and authenticated user-flow verification.

## Runtime deployment

Vercel builds `apps/web` from the monorepo.
Supabase CLI deploys version-controlled migrations without development seed data.
Production AI requires the server-only provider key in the Vercel project; a local environment file does not configure production.
Native development may target localhost on Simulator; release configuration targets `https://memotrail.ryangan.me`.
App Store distribution, Apple Sign-In, DNS changes, billing upgrades, and a native macOS app remain outside this completion pass.
