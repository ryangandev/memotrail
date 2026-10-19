# AI direction record

Recorded 2026-09-27 at Ryan's request.
This is historical context for revisiting AI, not an active feature specification or a commitment to restore the previous interface.
Current behavior belongs in [product.md](./product.md); current implementation and acceptance state belong in [status.md](./status.md).

## Earlier narrative and requirements worth retaining

AI was intended to help people organize, retrieve, and reflect on their own writing without replacing their voice or silently rewriting their archive.
Manual capture, organization, and keyword retrieval must remain useful without AI.

- Organizing suggestions: optional titles, Collections, tags, and occurrence context, adopted explicitly by the user.
- Grounded AI search: answer questions from bounded personal-archive evidence, cite the original Entries, and distinguish interpretation from recorded facts.
- Explore with AI: a separate conversation attached to an Entry, with the original writing unchanged.
- Save as Entry: an editable, independent Inbox Entry linked back to the source, rather than silently changing it.
- Photo understanding: independently consented assistance using compact previews, separate from deterministic photo metadata and Location workflows.
- Control and privacy: opt-in permissions, owner-scoped data, server-only provider credentials, bounded usage, and explicit handling of uncertain or interrupted requests.

## Exploration before the pause

We considered small, non-generative decision models for candidate classification and structured judgments, including Collections/tags, related or duplicate Entries, search reranking, date-candidate selection, and evidence checks.
These were investigation candidates, not approved product features or demonstrated improvements on MemoTrail data.
Decision outputs do not directly replace open-ended title generation, explanations, conversations, or visual understanding.

The last proposed development setup was a local Laya multilingual model for inexpensive iteration and a hosted official API such as Jev for production.
Browser-installed models were ruled out for that proposed setup.
No model was installed or integrated, and no provider was selected for a production change.
Similar input/output contracts do not guarantee identical model decisions, calibration, or thresholds; production-provider evaluation would still be required.

## Pause and future reconsideration

Ryan judged the current use cases insufficiently valuable to justify exposing AI now; basic text correction or suggestions alone are not a compelling product direction.
The previous AI feature UI and dedicated styles are deliberately deleted because the interaction and visual design should be reconsidered, not merely switched back on.
Existing business logic, API contracts, saved preferences, and historical data remain available as implementation references.
Until the reviews below, the off, disabled Beta status was the only retained AI settings surface; it has since been removed.

Future work may reuse these requirements, extend them, or adopt a different AI narrative, potentially including decision-model-assisted actions on the user's behalf.
That possibility is not authorization for automatic actions or a change to current consent boundaries.
Before resuming, establish concrete user value, action/confirmation boundaries, evaluation criteria, and a newly designed interface.

## Chapter and year reviews, and Chapter suggestions

Recorded 2026-10-18 at Ryan's request.
AI returns in one narrow, reflective form: a review of a Chapter or a year, and an optional monthly suggestion that a stretch of writing could be a Chapter.
This is the concrete user value, action boundary, and newly designed interface that the pause above asked for; the earlier organizing, search, exploration, and photo features stay paused.

- A review is made only when the person asks, after they have read and accepted what is sent.
- A review separates records counted from the person's own Entries, labeled interpretation, and quotes copied exactly from their writing.
- Nothing in an Entry changes, and nothing becomes a Chapter until the person reviews and saves it.
- Anthropic's Claude is the provider, called by the Next.js server with text only: no photos, Locations, names, or email addresses.
- MemoTrail has no zero data retention agreement, and the disclosure says so.
  Before enabling this in Production, confirm the Anthropic account behind the key is not in any data-sharing or development program.
- Reviews are saved, exported, and deleted with the Entries they read or when reviews are turned off.
- Spending is bounded per person and for the server, and a request with an unknown outcome is never retried automatically.

## Provenance

This record summarizes the product-owner discussion leading to the `hide-ai-capabilities` change.
The pre-removal implementation is recoverable from Git history at `76cf685`; the removal PR records the delivery and validation details.
