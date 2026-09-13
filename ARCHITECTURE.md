# MemoTrail Architecture

Last reviewed: 2026-09-13.

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

## Habit check-in Entry context

Check-ins retain their optional `entry_id` through workspace/calendar decoding on both clients, and `habit_entry_choices` provides owner-scoped, bounded bilingual candidate search plus exact resolution of an existing link, including Trash.
Link selection and removal are staged with the note and status until Save; opening original writing does not copy it or commit the draft.
`save_habit_check_in` saves status, note, measurement, and explicit Entry selection atomically under existing occurrence revisions and full prior-check-in history.
New targets must be owned and active; an unchanged owned Trash target can remain attached to the same occurrence at the expected revision.
The mutation locks an owned target before the Habit, serializes competing Habit requests, and rejects stale writes without merging notes or overwriting another device.
The older `record_habit_occurrence` interface preserves the current same-revision link when an installed client with no link control sends null; only the versioned interface interprets null as explicit unlink.
Native historical-day context distinguishes an absent occurrence on that selected day from the current day's check-in, so empty notes, measurements, links, and revisions do not borrow unrelated values.
No new Entry, AI generation, or extra credential is required.

## Habit monthly and weekday summaries

Both clients derive twelve monthly rows and seven Monday-first weekday rows directly from `habit_year_calendar`, the same owner-scoped status contract used by the heatmap.
The projection uses validated recorded Gregorian dates, excludes other years and dates after the selected reference date, and never shifts a check-in through the device timezone.
Only completed, missed, and skipped statuses contribute counts; completion rate is completed divided by completed plus missed, with an absent rate when that denominator is zero.
Pending, upcoming, unscheduled, and intentionally skipped days never become invented failures.
All weekdays tied for the largest positive miss count are reported; the empty state makes no claim about a most-missed weekday.
Weekly-target schedules use recorded statuses without allocating unrecorded weekly shortfalls to invented weekdays, and both clients explain this limitation.
These are day-status summaries, not totals of measured quantities whose unit or target might have changed.
Native calendar requests capture habit, year, reference date, and request identity, clear stale data while loading, and revalidate owner and cancellation before accepting results.
The feature requires no new database table, migration, AI call, or credential.

## Confirmed Empty Trash

`prepare_empty_trash` returns a single read-only owner-scoped snapshot of kinds, IDs, exact deletion timestamps, and revisions across every Trash page, without copying private writing or Storage paths.
An attachment under a trashed Entry is covered by its parent rather than counted twice; Entry targets precede independent definitions whose removal might otherwise change relationships.
Both clients show the complete target count and irreversible effects before any deletion, with cancellation as the initial safe action.
After confirmation, clients process only that immutable list through the existing Storage cleanup and revision/deletion-time-checked permanent-delete boundary.
Newly trashed content never joins an in-progress batch, and restored or changed targets fail the original checks.
An uncertain response or conflict stops further deletion and reports only acknowledged successes; another attempt requires fresh preparation and confirmation.
Leaving the client stops dispatching further deletions; already acknowledged deletion is not reversible, and an in-flight request may still finish.
Preparation refuses manifests over 10,000 items instead of silently emptying only the loaded page or truncating the confirmation scope.
This explicit user operation does not activate automatic retention cleanup or bypass existing private-media guards.

## Standalone library keyword search

Global keyword search combines the existing Entry result section with independently paginated People, Places, and Habits through `search_library_entities`.
This read-only, authenticated invoker RPC explicitly checks ownership and active lifecycle, returns bounded excerpts and matching evidence, and requires no AI credentials or synthetic Entries.
Literal case-insensitive substrings support Chinese and punctuation; simple full-text matching also supports English terms distributed across names and notes.
Habit retrieval includes matching check-in notes and excludes archived Habits as well as Trash.
Entry date, type, Collection, and tag filters apply only to Entries; both clients explain that clearing these filters enables standalone entity results.
Stable kind-plus-UUID identities distinguish records across tables, and deterministic ordering plus bounded offsets keeps pagination consistent.
Person sources use `person_record` for exact owner-scoped resolution beyond the first workspace page; Place and Habit sources retain their existing focused routes.
Native results revalidate session ownership, task cancellation, and request generation before displaying an asynchronous response.

## Precision-aware search dates

Keyword search and model-assisted evidence share `search_entries_ordered`, so date eligibility cannot diverge between the two search modes or between clients.
`entry_occurrence_window` derives a local-calendar range using the Entry's recorded zone: year/month dates cover that entire year/month, closed periods include their end, and explicit open ranges or ongoing Home/Vehicle/life-stage periods stay open-ended.
The window is a retrieval interpretation, not a mutation or claim that an uncertain event happened on every included day.
Unknown and description-only dates have no window and are excluded only when a date filter is active.
The date text index includes only known precision and recorded ends, never fabricated January/day-one text for partial dates.
An additive `search_entries_with_occurrence` projection returns the original precision with existing search fields and explicitly preserves relevance ordering after pagination; older RPC signatures remain unchanged.
Both clients format returned dates through their shared occurrence presenters, with period labels for chapter/stage Entries and no creation-time fallback for Unknown.

## Precision-aware capture persistence

Capture uses the same eight-precision occurrence model as later editing, with an absent custom draft meaning use the actual capture time.
An explicit Unknown draft differs from an absent draft: it writes no calendar anchor.
Draft persistence stores editable field strings before semantic validation, allowing partial input to survive navigation and restart.
The offline queue contains the validated occurrence with its precision, nullable bounds, description, and recorded zone, then inserts those fields together with the canonical Entry.
Web version-three records coexist with legacy exact-date queue items; native version-three storage retains the optional full occurrence alongside backward-compatible decoded fields.
Native pending cards and inserts always use the full occurrence when present; legacy fields are fallback data only and cannot turn an explicit Unknown into capture time.
Stable UUIDs and the existing owner-scoped duplicate check preserve retry idempotency, including after a queue was saved by an older client version.
No database migration is required because the canonical Entries schema already supports these occurrence fields.

## Editing after Inbox organization

The current Entry/history reader loads fresh owner-scoped `editable_entry` context before opening the shared Web or native review form.
Only active Standard and First Time Entries use this generic editor; Goal, Home, and Vehicle details keep their dedicated mutation contracts.
Ordinary Save preserves the existing Inbox state, while Done remains an explicit transition from Inbox review.
The same revision-checked transaction retains history, archived Collection links, dates, and optional photo Place adoption.
Organized editors hide Inbox-only AI suggestions and Done, without changing exploration availability.
Native history saves reuse the existing serialized review parameters directly rather than creating another Inbox controller and offline synchronization monitor.
Both clients retain validated original timestamp strings when the user has not changed the date, avoiding accidental loss of database microseconds during a writing-only edit.

## Private photo delivery

Specialized First Times, Homes, Vehicles, and Goals editors share retry-safe upload orchestration on both clients.
A selected Web File retains an attachment UUID scoped to its owner and Entry for the open editor's lifetime; native reuses the existing immutable photo draft UUID.
Uploads use create-only Storage writes, and upload errors still proceed to owner-scoped idempotent registration because the original may already have committed.
Known successful Web uploads are not resent, and each batch retains only unconfirmed photos for retry while allowing other selected photos to finish.
Neither client deletes an original in an upload/registration error handler or overwrites it during retry.
Native cancellation stops before network writes or registration, and session-owner checks surround the upload/registration boundary.
This does not introduce durable specialized-editor drafts or automatic cleanup of abandoned unregistered uploads; those lifecycle choices remain separate from universal capture's existing offline queue.

Web galleries and native galleries share the Next.js media boundary instead of downloading full originals for display.
The caller's RLS-scoped attachment query issues one-hour HMAC grants bound to owner, original attachment, expiry, and explicit Trash access.
The signing key is domain-separated from the existing server-only Supabase credential; neither that credential nor the Anthropic key enters iOS.
Every image request rechecks the owned original and Entry lifecycle through a service-only resolver, so ordinary grants cease working when the source enters Trash.
Native URL issuance uses a verified bearer session and validates that returned URLs match its configured server and requested paths.

The universal current-record/history reader on both clients offers a Current photos gallery and explicit photo management for every active Entry type.
It reads current attachment membership through the shared authenticated photo-list endpoint, independently from the selected historical snapshot.
Web uses a modal dialog with contained images, bounded previous/next navigation, Escape dismissal, and focus restoration; native uses a matching full-screen contained-image viewer.
List failures clear stale membership, unavailable images explain retry, and Refresh requests renewed grants and current membership without mutating the Entry.
Gallery identity uses a distinct photo namespace.
The Web gallery preserves its pending immutable File identities across Entry revision refreshes, then coalesces a current-membership refresh when no upload remains unconfirmed.
Native refreshes its gallery after confirmed changes; neither surface may discard an unconfirmed selection solely because registration advanced the Entry revision.
Native delivery continues validating the configured server origin, image route, and grant token; no photo bytes or provider credentials are embedded in history snapshots or the application bundle.
Both readers stage selected photos in the current view, validate the shared supported formats/50-MiB limit, and require Upload photos before persisting them through the retry-safe upload boundary.
Confirmed photos leave the selection, unconfirmed photos stay retryable, and ordinary photo additions do not change the Entry's writing, occurrence precision, or Inbox state.
Move to Trash requires confirmation and uses the existing owner-scoped recoverable attachment mutation; the Web action additionally verifies the original belongs to the current Entry before invoking it.
Mutation controls remain disabled during upload/removal and current-photo refresh; both readers refresh their current metadata after confirmed changes without presenting the selected historical snapshot as current membership.
Selections are view-local and explicitly labeled as such; this editor does not replace the durable universal quick-capture queue.

### Photo membership history and writing concurrency

Registration, photo Trash, and photo restoration lock the active owned Entry before locking or changing its attachment.
Each actual change snapshots the complete prior Entry and membership, then advances the same Entry revision exactly once.
Idempotent registration replays validate the immutable original identity without producing duplicate versions; invalid metadata or missing Storage objects roll back the entire archive and mutation.
Derivative workers do not generate user versions, and restoring a complete Entry version retains its existing single-transaction, strict-revision behavior.

The private `entry_photo_changes` ledger identifies only revisions produced by those protected photo boundaries.
The four structured editors use `entry_writing_revision` to reconcile a stale base only when every intervening revision was photo-only, since these saves do not replace photo membership.
A writing, organization, relationship, lifecycle, or full-history restoration creates a gap and preserves the original conflict guard, including after a lost photo-registration acknowledgment.
The subsequent ordinary save still checks the returned revision atomically, so a race after reconciliation cannot overwrite newer writing.
Clients cannot write the ledger or call the internal history-bypassing helpers.
The ledger is internal concurrency evidence, not another user-content dataset; exports already preserve complete writing versions and original attachment membership.
Universal capture also uses create-only original uploads, and optional AI organization runs after the complete photo batch against the reconciled capture revision rather than once for every photo.

On first display, a bounded worker generates 1600-pixel display and 400-pixel thumbnail WebP files without enlarging small photos.
Sharp handles orientation, resizing, and metadata stripping; the server-side libheif WASM bundle decodes HEIC when the platform's Sharp build lacks HEVC support.
The worker receives bytes and fixed decoder paths, not application credentials, and has a 25-second deadline, 80-million-pixel input limit, and 8-MiB limit per output.
The service accepts at most 50 MiB of original bytes, verifies Storage version, ETag, and size, deduplicates same-source work, and bounds local processing to two workers with a bounded queue.
Private derived paths include original identity, pipeline version, and source SHA-256; registration atomically validates both variants and unchanged source version.
Only the service can write the reserved derived Storage namespace; reads verify derived hashes and regenerate missing or corrupted cached objects from the original.
Delivery uses private no-store responses and rechecks visibility and source version after processing.

Originals remain unchanged and exportable; generated variants do not increase photo counts, appear as separate Trash items, or become prerequisites for restoring writing history.
Permanent removal of an original includes its generated family, while removing an Entry includes all its owned media.
Removal manifests also read owned derived Storage paths that have not reached attachment registration, covering an interrupted worker without depending on an in-memory cleanup callback.
Derived Storage insertion/update takes a key-share lock on the owned original; a before-delete guard rejects original deletion while any generated object remains.
Thus a deletion that locks first makes a late upload fail, while an upload that locks first makes deletion recheck the committed object and remain retryable.
Both clients explain the cleanup race and offer an explicit refresh/retry instead of claiming permanent deletion succeeded.
No Storage object is deleted through SQL: deletion still uses the [Storage API](https://supabase.com/docs/guides/storage/management/delete-objects), with transaction ordering grounded in [PostgreSQL row locks](https://www.postgresql.org/docs/17/explicit-locking.html).
Existing export manifests continue to include registered variants and originals with their actual integrity checks.
Display generation never invokes AI or changes Entry dates; optional photo analysis is a separate consent-checked suggestion path described below.
Deployment traces Sharp through a static server import and explicitly includes the worker-only libheif bundle.
`MEMOTRAIL_E2E_PRODUCTION=1 pnpm --filter @memotrail/web test:e2e` builds and serves the same synthetic local-only configuration with `next start`; hosted acceptance remains separate.
Decoder behavior follows [Sharp output documentation](https://sharp.pixelplumbing.com/api-output/) and [libheif-js's supported WASM interface](https://github.com/catdad-experiments/libheif-js).

### Camera metadata and explicit date adoption

Web and native Inbox review can browse saved originals and request camera metadata through shared authenticated POST endpoints.
Cookie requests enforce same-origin checks, native requests use verified bearer sessions, and both paths reject other owners and trashed sources.
Metadata reads reuse the bounded original download, Storage version/ETag/size checks, concurrency queue, and post-processing lifecycle recheck.
A separate five-second worker receives no application credentials and uses Sharp to extract at most 1 MiB of EXIF from JPEG, PNG, WebP, or HEIC without decoding pixels.
[exifr](https://github.com/MikeKovarik/exifr) parses only that TIFF payload with date revival disabled; no full HEIC container parsing, model call, geocoding, database write, or original mutation occurs.
The response exposes validated camera wall time, optional subsecond text and UTC offset, calendar date, and a complete valid GPS coordinate pair, not arbitrary EXIF fields such as artist or camera serial number.
Missing time zones remain explicitly missing instead of becoming UTC or the viewer's zone.
Use calendar date changes only the editor draft to Day precision, clears its prior range/description, and preserves the editor's selected IANA zone; Save changes or Done remains the only persistence step.
Cancel discards adoption, and later manual edits take precedence.
Coordinates are displayed without automatically creating or linking a Place; metadata controls beyond Inbox remain tracked follow-ups.
Synthetic JPEG/PNG/WebP/HEIC metadata fixtures, owner isolation, cookie/native parity, cancellation, manual override, original-byte identity, and desktop/mobile Web layouts are verified locally.
Production tracing includes the runtime Sharp and exifr entry points; hosted metadata acceptance and authenticated native UI interaction remain separate checks.

Both Inbox editors can explicitly stage one photo Place per save: name a new reusable Place with editable coordinates, or search and choose an existing owned Place without overwriting its independent facts.
`review_entry_with_photo_place` wraps the existing occurrence review in one transaction, validates the owned active original, and atomically adds the Place relationship with writing and organization.
The source-row lock uses a narrowly scoped owner-checked definer helper because clients intentionally have no direct attachment UPDATE privilege; the review itself remains security invoker.
Existing Place selection includes its revision and locks the shared record before Entry review; a changed or trashed Place rejects the whole save.
New Place creation happens only after the Entry revision wins, so same-revision competing requests cannot create duplicate or orphan Places.
Existing links, protected Home relationships, Place names/coordinates/notes, and original photo bytes remain unchanged.
Adding a new relationship advances the existing Place revision and archives its prior links; Entry history records its pre-adoption relationships and supports restoration in both directions without deleting independent Places.
Removing a pending Place or canceling review writes nothing; source/Place conflicts keep the draft and ask the user to refresh instead of partially saving.
The authenticated Place-option endpoint searches names with escaped literal wildcards, returns at most 100 matches with explicit refinement guidance, and supports both Web cookies and native bearer sessions.
No reverse geocoding, address inference, or paid AI call is involved.

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
Goal `related` links use the equivalent active-target rule: a hidden target in Trash remains linked through unrelated edits, reappears on restoration, and can then be explicitly unlinked.
Achievement and other relationship kinds are not part of the Goal editor's replaceable related-link set.
The dedicated First Times clients use the same occurrence editors and the additive `first_times_workspace_with_occurrence` / `save_first_time_with_occurrence` contract so range ends and precision survive specialized editing.
Native First Times decoding retains the original timestamp strings alongside parsed Dates and reuses them for untouched bounds, avoiding SDK fractional-second rounding during serialization.
The legacy First Times mutation rejects writes that cannot preserve existing range ends or exact/range interpretation rather than silently degrading them.
First Times also retains confirmed saved revisions during Web refresh and focuses the title only on editor mount.
Bucket List achievement uses these same eight-precision editors and the additive `achieve_goal_with_occurrence` mutation, which delegates date validation and First Time creation to the existing shared helper.
Both clients start with Unknown rather than silently defaulting the milestone to today; age and approximate descriptions need no calendar anchor, and ranges retain their optional end.
Goal status, history, the new First Time, and its achievement link commit atomically; invalid dates roll everything back, while revision checks and an already-achieved guard prevent competing or repeated submissions from creating duplicate milestones.
The legacy six-argument achievement signature remains available for older clients.
Broad date-filter semantics and remaining relationship paths remain in the cross-product audit.
Timeline now uses `save_timeline_entry_with_occurrence` and the shared date editor on both clients, preserving nullable bounds and original raw timestamps instead of converting exact memories to date-only noon anchors.
The shared editor's explicit span mode permits precision-aware ends for Life Stages, including year, month, and exact-time ends, without relaxing ordinary Entry validation or allowing point Events to carry an end.
Unanchored Timeline moments remain in their tracks and native/mobile lists; desktop exposes them above the calendar axis in a separate non-calendar section rather than using creation/update time to invent a position.
Confirmed Web mutations retain their revision until matching server props arrive, preventing false conflicts on immediate reopening; acknowledged overrides and explicitly trashed Entries are cleared.
The legacy Timeline RPC retains its signature and validation but delegates actual writes to the new mutation, rejecting edits to exact or unanchored records it cannot represent safely.
Homes and Vehicles use the same span editor and additive `save_home_entry_with_occurrence` / `save_vehicle_entry_with_occurrence` mutations, with all eight precisions and nullable workspace bounds on both clients.
Native decoding retains both original timestamp strings for untouched saves, preserving microseconds and repeated daylight-saving instants.
Chapter lists sort dated rows before undated rows within their current/earlier groups; no end keeps the existing current-chapter semantics.
Shared chapter labels display year/month bounds at recorded precision, mark uncertain durations as estimates, and decline to calculate duration without a calendar anchor.
Home move-out reasons require a known end; removing the end never silently erases existing writing, and both editors allow the user to explicitly clear the reason.
Web chapter editors retain confirmed records during route refresh so immediate reopening uses the saved revision and content; newer acknowledged server revisions supersede temporary overrides.
Legacy chapter mutations delegate writes but reject exact or unanchored existing records they cannot safely edit, while owned Place updates, private photos, archived Collection links, history, and Timeline stages keep their established shared contracts.

## In-place Goal conversion

The authenticated `convert_entry_to_goal` mutation locks the current owned Standard Entry and applies explicit title and Goal fields at the expected revision.
It leaves writing, occurrence metadata, Inbox state, organization, media, and relationships untouched, and the existing history trigger captures the complete pre-conversion state before the Goal detail row is added.
An identical immediate retry returns the already-confirmed revision; mismatched, stale, deleted, cross-owner, or other-specialized-Type requests cannot overwrite the source.
Restoring history can return to Standard or restore the prior Goal details without creating a duplicate Entry.
Subsequent Goal saves preserve original occurrence metadata; target dates remain separate calendar-only planning fields.
Web and native expose the same confirmed conversion fields from the current Entry/history reader and reuse existing Goal validation and enum definitions.

## Ordinary Entry relationships

Web and native current-record readers expose Related Entries after the writing/history comparison, with matching linked, backlink, and candidate views.
`entry_relations` uses owner-scoped, literal bilingual substring search and deterministic 20-row pages; it includes retained Trash links with an explicit label but excludes deleted targets from new-link candidates.
Relationships reuse the existing directed `related` edges, including Goal progress links; incoming edges are navigable backlinks and are edited only from their owning source Entry.
`set_entry_relation` locks source/target rows in UUID order, checks ownership, source revision and target lifecycle, and supports explicit link/unlink operations with a 100-outgoing-link limit.
It archives the source's complete old state before changing relationships, while leaving writing, occurrence fields, Inbox state, and target content unchanged.
No-op requests add neither revisions nor history, stale requests do not write, and restoring Entry history can restore the prior outgoing links once their targets are available.
Ordinary unlinking never changes `achievement`, `exploration_source`, or `exploration_conclusion` provenance.
Authenticated direct table writes to `entry_links` are revoked so clients cannot bypass revision history or forge those system relationships.
Existing Goal save and achievement RPCs retain their explicit `auth.uid()` ownership checks, source revision checks, and empty search paths as audited definer boundaries; other invoker functions retain their previous rights.
Known foreign-ID mutations, retained Trash links, no-op history, page boundaries, competing device requests, Goal compatibility, and original-preserving history restoration are covered by the shared regression suites.

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

Anthropic is the selected text and optional photo-suggestion provider.
The initial provider is pinned to `claude-haiku-4-5-20251001`, verified through a real authenticated localhost request.
Changing models requires updating the usage rates and tests together; an unknown model fails closed rather than silently using incorrect pricing.
Classification, retrieval, exploration, and resurfacing have separate user controls.
Model responses are untrusted structured suggestions, validated before storage and never executed as instructions.
Classification stores suggestions separately from original Entry content; accepting a suggestion fills an editable review and never marks an Entry Done automatically.
`ai_suggestions` deduplicates work by Entry revision and enabled feature scope, and only trusted server code can write model results.
Web schedules capture suggestions after its response; iOS starts an independent authenticated request after synchronization.
Review is also a recovery entry point for interrupted background work, with bounded status polling and explicit-only retries after a failed generation.
Accepting an AI date suggestion copies its human-readable description into Approximate precision with empty calendar bounds.
The server retains a date suggestion only when it appears literally in the author's title or body, preventing capture time and photo appearance from becoming inferred occurrence dates.
The user can change the precision to Age, Year, Month, or any other supported value and edit it before saving; model guidance is never silently converted to an exact timestamp.
New Collections require user acceptance.

### Optional photo organization context

`suggestionPhotos` selects only the authenticated owner's active original attachments for the unreviewed Entry.
Separate Photo analysis consent plus Classification or Tagging permission allows up to 12 existing 400-pixel metadata-free WebP thumbnails, each capped at 1 MiB, to accompany the text in an Anthropic Messages request.
Inline base64 previews follow the official [vision input contract](https://platform.claude.com/docs/en/build-with-claude/vision); original bytes, EXIF, and Storage URLs are never sent to the provider.
Each preparation pass has a 20-second deadline and the suggestion route allows 90 seconds; timed-out work cannot continue onto additional photos.
Preview IDs and content hashes extend the existing revision/feature cache key, so adding, removing, or changing photos does not reuse incompatible suggestions even without a writing revision.
The service-only claim validates photo consent, provider reservation atomically rechecks the feature permission and budget, and the server rechecks writing/consent before generation and photo content plus writing/consent before publishing.
Failed preparation never silently omits a saved photo; the user can retry explicitly or disable Photo analysis for text-only suggestions.
The pinned model reserves an additional 2,048 input microdollars per image before generation and records actual returned token usage afterward.
Both clients disclose included photo counts, support older responses without that count, and retain manual per-field adoption with no automatic filing.

### Exploration persistence

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
