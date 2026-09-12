# MemoTrail Completion Checklist

Updated: 2026-09-12.
Source of truth: PRODUCT.md, verified current repository, and Ryan's authorization to complete remaining work on both clients.

## Established baseline

Web and iOS already implement Google sign-in, capture, recoverable drafts and offline queues, photos, voice transcription, manual Inbox review, keyword search, Timeline, First Times, Collections browsing, Habits, Home resurfacing, Homes, Vehicles, Goals, Places, and shared Trash for implemented entities.
The last accepted checkpoint is `a7850b7`.

## Completion order

| Slice                                                            | Contract/server | Web             | iOS             | Verified and pushed |
| ---------------------------------------------------------------- | --------------- | --------------- | --------------- | ------------------- |
| Architecture and remaining-scope audit                           | Complete        | n/a             | n/a             | Pushed 08930ab      |
| People, Entry links, and recoverable removal                     | Deployed        | Complete        | Complete        | Pushed feea315      |
| AI preferences, budgets, provider boundary, and usage            | Deployed        | Complete        | Complete        | Pushed 6579c8d      |
| Editable AI title, Type, Collection, and tag suggestions         | Deployed        | Complete        | Complete        | Pushed 90740d3      |
| Precision-aware Inbox dates and explicit AI description adoption | Deployed        | Complete        | Complete        | Pushed 1aec663      |
| Shared retrieval evidence and current source reader              | Deployed        | Complete        | Complete        | Pushed 048efc0      |
| Natural-language retrieval and grounded source links             | Complete        | Complete        | Complete        | Pushed 239fa90      |
| Exploration persistence and atomic conclusion-save contract      | Deployed        | Shared contract | Shared contract | Pushed 95e7a28      |
| Explore with AI, persisted conversation, Save as Entry           | Complete        | Complete        | Complete        | This feature commit |
| Inspect and restore Entry history                                | Deployed        | Complete        | Complete        | Pushed eee57bf      |
| Complete ZIP export with JSON, Markdown, CSV, and originals      | Pending         | Pending         | Pending         | Pending             |
| Timeline track creation, ordering, and hide/show management      | Deployed        | Complete        | Complete        | Pushed e06e96c      |
| Collection/tag creation and renaming, Collection ordering/Trash  | Deployed        | Complete        | Complete        | Pushed 332449a      |
| Remaining date precision, Entry conversion and relationship gaps | Audit pending   | Audit pending   | Audit pending   | Pending             |
| Photo derivative and metadata suggestion gaps                    | Audit pending   | Audit pending   | Audit pending   | Pending             |
| Final acceptance and production configuration                    | Pending         | Pending         | Pending         | Pending             |

## External inputs and limitations

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
