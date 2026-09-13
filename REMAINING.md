# MemoTrail Completion Checklist

Updated: 2026-09-12.
Source of truth: PRODUCT.md, verified current repository, and Ryan's authorization to complete remaining work on both clients.

## Established baseline

Web and iOS already implement Google sign-in, capture, recoverable drafts and offline queues, photos, voice transcription, manual Inbox review, keyword search, Timeline, First Times, Collections browsing, Habits, Home resurfacing, Homes, Vehicles, Goals, Places, and shared Trash for implemented entities.
The last accepted checkpoint is `a7850b7`.

## Completion order

| Slice                                                                 | Contract/server | Web             | iOS             | Verified and pushed |
| --------------------------------------------------------------------- | --------------- | --------------- | --------------- | ------------------- |
| Architecture and remaining-scope audit                                | Complete        | n/a             | n/a             | Pushed 08930ab      |
| People, Entry links, and recoverable removal                          | Deployed        | Complete        | Complete        | Pushed feea315      |
| AI preferences, budgets, provider boundary, and usage                 | Deployed        | Complete        | Complete        | Pushed 6579c8d      |
| Editable AI title, Type, Collection, and tag suggestions              | Deployed        | Complete        | Complete        | Pushed 90740d3      |
| Precision-aware Inbox dates and explicit AI description adoption      | Deployed        | Complete        | Complete        | Pushed 1aec663      |
| Shared retrieval evidence and current source reader                   | Deployed        | Complete        | Complete        | Pushed 048efc0      |
| Natural-language retrieval and grounded source links                  | Complete        | Complete        | Complete        | Pushed 239fa90      |
| Exploration persistence and atomic conclusion-save contract           | Deployed        | Shared contract | Shared contract | Pushed 95e7a28      |
| Explore with AI, persisted conversation, Save as Entry                | Complete        | Complete        | Complete        | Pushed 0022aea      |
| Inspect and restore Entry history                                     | Deployed        | Complete        | Complete        | Pushed eee57bf      |
| Complete ZIP export with JSON, Markdown, CSV, and originals           | Complete        | Complete        | Complete        | Pushed 8a00293      |
| Consistent export snapshots, pagination, and temporary-data lifecycle | Deployed        | Shared contract | Shared contract | Pushed 84f6d83      |
| Timeline track creation, ordering, and hide/show management           | Deployed        | Complete        | Complete        | Pushed e06e96c      |
| Collection/tag creation and renaming, Collection ordering/Trash       | Deployed        | Complete        | Complete        | Pushed 332449a      |
| Lossless dedicated First Times dates and legacy-client guards         | Deployed        | Complete        | Complete        | Pushed fc1853e      |
| Recoverable Collection links in all four specialized editors          | Deployed        | Shared contract | Shared contract | Pushed 23a8088      |
| In-place Idea/Standard Entry to Goal conversion and history recovery  | Deployed        | Complete        | Complete        | Pushed 73ec86e      |
| Recoverable Goal progress links across target Trash and restoration   | Deployed        | Shared contract | Shared contract | Pushed 7dbe553      |
| Eight-precision Goal achievement with atomic First Time creation      | Deployed        | Complete        | Complete        | Pushed 015feac      |
| Lossless Timeline dates and unanchored moment visibility              | Deployed        | Complete        | Complete        | Pushed c2dcf04      |
| Lossless Homes/Vehicles dates and precision-aware chapter durations   | Deployed        | Complete        | Complete        | Pushed 7c6a63e      |
| Private optimized photo delivery with preserved originals             | Deployed        | Complete        | Complete        | This feature commit |
| Remaining date precision, Entry conversion and relationship gaps      | Audit ongoing   | Audit ongoing   | Audit ongoing   | Pending             |
| Photo metadata suggestions and remaining photo surfaces               | Audit pending   | Audit pending   | Audit pending   | Pending             |
| Final acceptance and production configuration                         | Pending         | Pending         | Pending         | Pending             |

## External inputs and limitations

- Existing galleries on both clients now use the shared private JPEG/PNG/WebP/HEIC display pipeline; original-byte integrity, missing-cache recovery, source overwrites, ownership, and Trash access are covered by synthetic local acceptance.
- Photo metadata date/Place suggestions, concurrent-generation/permanent-removal artifact cleanup, broader Inbox photo-surface audit, native interactive galleries, and hosted image-worker acceptance remain separate checks.

- First Times now preserves all eight precisions and original bounds on both clients; native serialization also retains untouched database microseconds.
- Goal achievement now supports all eight precisions on both clients, without invented calendar anchors, and atomically creates one linked First Time while retaining original writing.
- Timeline now supports nullable dates, precision-aware stage ends, raw exact-time preservation, and visible unanchored moments on both clients.
- Homes/Vehicles now support all eight precisions, nullable calendar anchors, preserved exact bounds, and honest duration estimates on both clients; broader Entry-link lifecycle and date-filter checks need follow-up.
- Manual Standard/Idea conversion now preserves the same Entry, original content, dates, photos, organization and Inbox state, with matching Web/native controls and reversible history.
- Goal saves now retain hidden progress links while preserving explicit active-target unlinking; restoration and later removal are verified through the real Web editor and shared authenticated RPC.
- First Times, Homes, Vehicles, and Goals now retain trashed Collection membership when saving, with active-link removal and restored Collection browsing verified through all four real Web editors and shared authenticated RPCs.
- Complete ZIP implementation passes 289 Web tests, twelve authenticated browser/API scenarios, and 169 native tests with zero skips; real ZIP extraction and original media hashes are verified locally.
- Native interactive export acceptance is currently unavailable because the Mac is locked; Ryan must unlock it before Simulator UI automation can proceed.
- Production ZIP streaming and authenticated native Save/share acceptance remain final-validation items; local streaming tests and native bearer downloads do not imply those checks passed.
- Missing-media rejection deliberately terminates an in-progress ZIP response; the negative E2E case records a sanitized expected stream error and verifies neither client-facing download path commits a complete file.
- Exploration passes 271 Web tests, ten browser/API scenarios, 167 native tests with no skips, and a real two-turn synthetic Anthropic flow costing $0.003171, including idempotent retries and original-preserving conclusion saves.
- Local AI accounting totals $0.052147 with no outstanding reservations; no provider secret was copied into either client.
- Natural-language search passed real Anthropic five-question acceptance, eight local browser scenarios, 236 Web tests, and native compilation with 164 passing tests and no skips.
- Actual authenticated native AI taps and production AI acceptance remain on the final validation checklist; native bearer API tests do not substitute for those interactions.
- The earlier local execution-review timeouts recovered and no longer block local tests.
- Final quality acceptance also tracks Next.js [client-aborted RSC reporting](https://github.com/vercel/next.js/issues/96704): the upstream fix is merged into canary but is absent from the inspected stable `v16.3.5`; application assertions pass, but the intermittent server log is not claimed fixed.

- Ryan corrected the local `AI_API_KEY`; a synthetic Anthropic request succeeded with HTTP 200 on 2026-09-12, using 9 input tokens and 4 output tokens.
- `AI_PROVIDER` is now `anthropic` locally and the default model is `claude-haiku-4-5-20251001`.
- Anthropic generation alone does not provide a vector embedding API; evaluate model-assisted retrieval first and clearly identify any remaining embedding requirement.
- Production AI configuration must be verified separately from the local key.
- GitHub Actions jobs cannot start because GitHub reports failed account payments or an insufficient spending limit; account billing requires Ryan's attention.
- Existing authorization covers incremental commits and pushes to main, implementation testing, and Supabase migrations.
- Map is explicitly deferred in PRODUCT.md; Share Extension, bulk Inbox review, PWA enhancements, Chinese UI, Apple Sign-In, and App Store distribution remain deferred or undecided.
