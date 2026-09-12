# MemoTrail Completion Checklist

Updated: 2026-09-12.
Source of truth: PRODUCT.md, verified current repository, and Ryan's authorization to complete remaining work on both clients.

## Established baseline

Web and iOS already implement Google sign-in, capture, recoverable drafts and offline queues, photos, voice transcription, manual Inbox review, keyword search, Timeline, First Times, Collections browsing, Habits, Home resurfacing, Homes, Vehicles, Goals, Places, and shared Trash for implemented entities.
The last accepted checkpoint is `a7850b7`.

## Completion order

| Slice                                                            | Contract/server | Web           | iOS           | Verified and pushed         |
| ---------------------------------------------------------------- | --------------- | ------------- | ------------- | --------------------------- |
| Architecture and remaining-scope audit                           | Complete        | n/a           | n/a           | Pushed 08930ab              |
| People, Entry links, and recoverable removal                     | Deployed        | Complete      | Complete      | Pushed feea315              |
| AI preferences, budgets, provider boundary, and usage            | Deployed        | Complete      | Complete      | Pushed 6579c8d              |
| Editable AI title, Type, Collection, and tag suggestions         | Deployed        | Complete      | Complete      | Local verified; this commit |
| Precision-aware AI date acceptance                               | Guidance only   | Pending       | Pending       | Pending                     |
| Natural-language retrieval and grounded source links             | Pending         | Pending       | Pending       | Pending                     |
| Explore with AI, persisted conversation, Save as Entry           | Pending         | Pending       | Pending       | Pending                     |
| Inspect and restore Entry history                                | Pending         | Pending       | Pending       | Pending                     |
| Complete ZIP export with JSON, Markdown, CSV, and originals      | Pending         | Pending       | Pending       | Pending                     |
| Collection/tag management and Timeline track management          | Pending         | Pending       | Pending       | Pending                     |
| Remaining date precision, Entry conversion and relationship gaps | Audit pending   | Audit pending | Audit pending | Pending                     |
| Photo derivative and metadata suggestion gaps                    | Audit pending   | Audit pending | Audit pending | Pending                     |
| Final acceptance and production configuration                    | Pending         | Pending       | Pending       | Pending                     |

## External inputs and limitations

- Ryan corrected the local `AI_API_KEY`; a synthetic Anthropic request succeeded with HTTP 200 on 2026-09-12, using 9 input tokens and 4 output tokens.
- `AI_PROVIDER` is now `anthropic` locally and the default model is `claude-haiku-4-5-20251001`.
- Anthropic generation alone does not provide a vector embedding API; evaluate model-assisted retrieval first and clearly identify any remaining embedding requirement.
- Production AI configuration must be verified separately from the local key.
- GitHub Actions jobs cannot start because GitHub reports failed account payments or an insufficient spending limit; account billing requires Ryan's attention.
- Existing authorization covers incremental commits and pushes to main, implementation testing, and Supabase migrations.
- Map is explicitly deferred in PRODUCT.md; Share Extension, bulk Inbox review, PWA enhancements, Chinese UI, Apple Sign-In, and App Store distribution remain deferred or undecided.
