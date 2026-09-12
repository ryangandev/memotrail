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

## Occurrence semantics

Inbox review writes date precision, nullable start/end, a human description, and the recorded IANA time zone in the same atomic mutation as content and organization.
The additive `review_entry_with_occurrence` RPC keeps the original review signature available to older clients.
Unknown dates never borrow the Entry creation timestamp; legacy exact records with no occurrence are presented as Unknown.
Year and month anchors are calendar-normalized for storage but displayed only at their declared precision.
Age and approximate periods require a human description and do not require a calendar anchor or inferred birth date.
Ranges support an optional end, with no end meaning onward.
Web and native date conversion validate wall-clock dates in the recorded zone, including fractional offsets, and reject nonexistent daylight-saving times.
Unchanged edits preserve original instants and fractional seconds; newly edited repeated daylight-saving times use the earlier matching instant on both clients.
Successful Web reviews immediately retain the server-confirmed revision while route refresh is in flight, preventing false conflicts on rapid reopening.
Archived Collection links stay recoverable during review without re-creating the hidden Collection as an active group.
First Times, Homes, Vehicles, and Goals use the same active-only replacement rule: a specialized editor cannot remove a hidden Collection link it never displayed.
This rule lives in the existing shared mutations so Web and native saves agree, while explicit active-membership edits and Collection restoration retain their established behavior.
The dedicated First Times clients use the same occurrence editors and the additive `first_times_workspace_with_occurrence` / `save_first_time_with_occurrence` contract so range ends and precision survive specialized editing.
Native First Times decoding retains the original timestamp strings alongside parsed Dates and reuses them for untouched bounds, avoiding SDK fractional-second rounding during serialization.
The legacy First Times mutation rejects writes that cannot preserve existing range ends or exact/range interpretation rather than silently degrading them.
First Times also retains confirmed saved revisions during Web refresh and focuses the title only on editor mount.
Other specialized editors and broad date-filter semantics remain in the separate cross-product precision audit.

## AI architecture

### Retrieval evidence boundary

`search_entries_ordered` is the single owner-scoped keyword engine; the existing `search_entries` signature delegates to it without changing either client's response contract.
Chronological ordering occurs before the candidate limit, so First Time questions do not discard the earliest matching memory in a large archive.
`archive_search_evidence` accepts at most six bounded query expansions, intersects Entry filters, and returns up to 36 Entry sources with explicit candidate and truncation metadata.
Source projections preserve original writing, occurrence precision, organization, and linked structured facts, but never include photo bytes or storage URLs.
A latest-Home boundary is applied only when its date has day or exact precision; uncertain dates remain explicit instead of becoming fabricated calendar boundaries.
Habit evidence separately reports recorded misses, inferred past scheduled misses, skipped days, and complete-week target shortfalls.
Unrecorded today is pending rather than missed, and excess completions in one week never cancel another week's deficit.
Habit comparisons cover active Habits within the requested date range and expose their scope and total count; Entry-only filters never silently become unconstrained Habit comparisons.
Standalone People and Places are bounded to 25 matching records each and are excluded when Entry-specific or date filters cannot apply to them.
The caller supplies the user's local `as_of` date when known; the database default is the current database date.
Web source links open the authenticated current-version reader, which both clients keep visible even when no earlier version exists.
The natural-language interface and orchestration build on the deployed evidence boundary and are shared across Web and iOS.
Both clients reuse their existing query field and filters with a separate explicit `Ask AI` action; Enter or keyword Search does not incur provider usage.
The authenticated server runs a bounded bilingual query-planning call and, only when sources exist, an answer-generation call under the existing consent and spending gates.
Manual Type, Collection, tag, and date filters remain authoritative over inferred filters; All Types is never narrowed by model-inferred labels because reflections can occur inside any Entry Type.
Deterministic bilingual word segmentation removes intent words from query expansions without assuming that an English question matches English writing.
When expanded terms return no actual matches, an explicitly labeled bounded fallback removes only query terms while retaining manual filters and the latest-Home date boundary; a Home returned merely as boundary context does not suppress this fallback.
Both provider calls use [Anthropic structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs), followed by runtime validation.
Each finding selects allowed source-and-passage references such as `S1:Q2`; the server inserts the literal passage, and malformed or fabricated references reject the answer without automatic retries.
Original writing and structured facts are separate passages, with long facts expandable on both clients; schema bytes are included in conservative prompt-cost reservations.
This validates source provenance, not semantic truth, so both clients label AI interpretations and retain inspectable excerpts and original Entry navigation.
The serialized source payload is bounded, prioritizes Habit comparison records when requested, and reports source/excerpt omissions.
Questions with no useful evidence return an explicit insufficient-evidence state, and generated results remain transient rather than overwriting or creating Entries.

### Provider and review controls

Anthropic is the selected text provider.
The initial provider is pinned to `claude-haiku-4-5-20251001`, verified through a real authenticated localhost request.
Changing models requires updating the usage rates and tests together; an unknown model fails closed rather than silently using incorrect pricing.
Classification, retrieval, exploration, and resurfacing have separate user controls.
Model responses are untrusted structured suggestions, validated before storage and never executed as instructions.
Classification stores suggestions separately from original Entry content; accepting a suggestion fills an editable review and never marks an Entry Done automatically.
`ai_suggestions` deduplicates work by Entry revision and enabled feature scope, and only trusted server code can write model results.
Web schedules capture suggestions after its response; iOS starts an independent authenticated request after synchronization.
Review is also a recovery entry point for interrupted background work, with bounded status polling and explicit-only retries after a failed generation.
Accepting an AI date suggestion copies its human-readable description into Approximate precision with empty calendar bounds.
The user can change the precision to Age, Year, Month, or any other supported value and edit it before saving; model guidance is never silently converted to an exact timestamp.
New Collections require user acceptance.
Exploration remains attached to its source Entry, and Save as Entry creates a separately identified conclusion with a source relationship.
The exploration persistence contract stores ordered turns per source Entry, with immutable question, source revision, bounded text snapshot, completion, and failure state.
Only server-role RPCs can claim or finish a model turn, while authenticated owners can read paginated conversations and explicitly save edited conclusions.
Request IDs are payload-bound and serialized; repeating the same request returns its existing state without acquiring another generation, and only one turn per Entry may be generating at a time.
Interrupted turns become visibly failed after two minutes and require a fresh explicit attempt; a late completion cannot replace an already failed turn.
Save as Entry creates an unreviewed Standard Entry with Unknown occurrence precision, preserving the user's edited title and body without inserting content into the source.
One save atomically adds both `exploration_conclusion` and `exploration_source` links and advances source history before changing its relationships.
Several conclusions may be saved from one turn; duplicate save requests reuse their result, and permanent deletion leaves an idempotency tombstone rather than resurrecting the deleted Entry on retry.
Trashing a source hides its conversation and blocks new conclusions until restoration; permanent source deletion removes its conversation but does not delete independently saved conclusions.
The authenticated `/api/ai/explore` endpoint shares workspace reads, explicit generation, and conclusion saves between Web cookies and native bearer sessions.
Generation uses the claimed source snapshot and at most eight recent completed turns, bounded by serialized UTF-8 bytes including escaping, with structured output validation and the same consent and cost controls as other AI features.
Opening, pagination, and refresh never call the model, and disabling generation does not make saved conversations or manual conclusion saves unavailable.
Both clients distinguish original writing, questions, AI interpretations, and retained source snapshots, with editable conclusion drafts and bidirectional links in the current-version reader.
Unconfirmed generation and save requests retain their IDs; refresh reconciles persisted completions, while definitive pre-claim rejections unlock editing without pretending a generation ran.
Native compilation and bearer API acceptance remain distinct from authenticated simulator taps and production AI acceptance.
Retrieval answers cite only authenticated archive evidence, including Entries and Habit summaries, and report insufficient evidence explicitly.

Anthropic generation and vector embeddings are separate provider capabilities.
No embedding provider has been supplied, so the implementation must distinguish model-assisted retrieval from a complete vector index and document any remaining search limitation.
Photo analysis remains opt-in; initial live tests use synthetic text.
Real test requests have bounded input, output, request counts, and an application usage ledger.
The user authorized a maximum of $3.50 from the supplied account balance; failures must not trigger uncontrolled retry loops.
The application defaults to a $3 server-wide lifetime cap and $1 per-user monthly cap, with atomic pre-request reservations and a 60-request hourly limit.
Completed requests reconcile reported token usage; interrupted requests retain their full reservation until explicitly reconciled.
Only service-role RPCs can modify accounting, and anonymous billing records survive account removal so deleting an account cannot reset the global cap.

## Portable export boundary

A complete ZIP must derive from one immutable database capture, not sequential reads of live tables that can change between pages.
`create_export_snapshot` materializes all 29 canonical public tables and an attachment media manifest in one INSERT/SELECT statement under one [PostgreSQL MVCC snapshot](https://www.postgresql.org/docs/17/xfunc-volatility.html).
The inventory includes Trash, Entry/Person/Place/Habit histories, organization and Timeline relationships, consent and usage, and persisted AI conversations and conclusion mappings.
An explicit dataset allowlist excludes authentication tables, provider credentials, temporary exports, and the current generated search index; an inventory test requires an export decision whenever a canonical table is added.
Original IDs and complete row fields remain intact, and the manifest pins each available owner-prefixed private object's storage version, size, and ETag without exposing storage URLs or other users' object metadata.
Missing or unsafe attachment objects are recorded as unavailable rather than silently dropped; final ZIP generation must fail clearly if required bytes cannot be recovered or no longer match the snapshot.
Owner-authenticated paginated reads retain fixed ordinal cursors past the default 1,000-row REST limit, with ordinary JSON pages bounded to 1 MiB and oversized individual records returned whole instead of truncated.
Creation requests serialize by owner and replay the same snapshot; at most two captures may be active, and a ten-per-hour creation limit prevents repeated discard from bypassing resource controls.
Private snapshot content becomes unreadable after 24 hours, can be explicitly discarded sooner, and is physically removed by an hourly [Supabase Cron](https://supabase.com/docs/guides/cron) job that touches only temporary export content.
These private captures retain their original contents after later archive edits or deletions; the export interface must disclose that retained-copy lifetime and offer explicit discard.
Minimal request tombstones retain no copied archive rows or dataset counts, prevent expired retries from capturing a different archive, and disappear with account deletion.
This contract freezes database content and media identity, not the photo bytes themselves.
The authenticated `/api/export` endpoint lists, creates, discards, and downloads snapshots for Web cookie sessions and native bearer sessions without invoking any AI provider.
ZIP serialization uses `yazl` with sequential lazy streams and paginated database reads; backpressure reaches Storage downloads instead of buffering entire archives in server memory.
The ZIP contains a versioned manifest, one complete JSON array per canonical dataset, original Entry Markdown, structured CSV views, registered media variants, and media SHA-256 checksums.
User titles never become archive paths; stable UUID filenames prevent path traversal, JSON-quoted frontmatter preserves uncertain dates, and formula-leading CSV strings receive a protective apostrophe while canonical JSON remains unchanged.
Each media response must match its captured ETag and actual byte count; missing, replaced, or truncated originals abort the archive without a successful ZIP footer.
Both clients verify a fixed completion comment in the standard ZIP end-of-central-directory record before offering the file as complete; this is interruption detection, not a substitute for ZIP CRC or media SHA-256 verification.
Supported Web browsers write directly through the File System Access API and commit the destination only after completion; other browsers use an explicitly documented in-memory Blob fallback.
Native iOS uses a URLSession disk download, validates only the footer bytes in memory, and keeps the file in a protected, backup-excluded temporary folder until the user shares it or leaves the screen.
Abandoned native temporary folders older than 24 hours are removed when export is reopened; snapshots remain independently available across clients until expiration or explicit discard.
The streaming endpoint has a 300-second deployment limit and a 280-second producer deadline; large archives exceeding that limit fail explicitly, and production streaming capacity must be verified separately from local acceptance.
Local acceptance verifies an archive exceeding 5 MB, complete extraction, all 30 JSON datasets, unchanged snapshot writing after later edits, original SHA-256 identity, direct-file and Blob paths, native bearer access, and missing-media failure recovery.
Authenticated native UI taps and production download acceptance remain separate from native compilation and API tests.

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
