# MemoTrail Documentation Guide

Last reviewed: 2026-09-13.

This directory gives contributors and AI agents a small set of durable sources for product intent, implementation context, and current acceptance status.
It is intentionally organized by responsibility rather than by date or commit.

## Recommended reading order

| Document                                                     | Read it when                                              | It owns                                                                          |
| ------------------------------------------------------------ | --------------------------------------------------------- | -------------------------------------------------------------------------------- |
| [STATUS.md](./STATUS.md)                                     | Starting any task                                         | Current shipped scope, latest evidence, open work, blockers, and deferred items  |
| [PRODUCT.md](./PRODUCT.md)                                   | Changing behavior or deciding scope                       | Product goals, terminology, user workflows, principles, and confirmed decisions  |
| [ARCHITECTURE.md](./ARCHITECTURE.md)                         | Changing data, APIs, security, sync, AI, media, or export | Durable system boundaries and cross-platform technical contracts                 |
| [SETUP.md](./SETUP.md)                                       | Working with local or hosted environments                 | Credentials policy, external configuration, deployment checks, and release gates |
| [architecture/data-safety.md](./architecture/data-safety.md) | Changing deletion, history, media, backup, or restore     | Data-loss safeguards and recovery expectations                                   |

The root [README.md](../README.md) contains the short local setup and validation commands.
The root [AGENTS.md](../AGENTS.md) defines the repository-wide agent workflow.

## Source-of-truth order

1. The user's latest explicit direction.
2. The product contract for intended behavior.
3. Current code, migrations, and tests for implemented behavior.
4. `STATUS.md` for verified completion and remaining acceptance.
5. Git history and pull requests for chronology and detailed delivery evidence.

If documentation and implementation disagree, do not silently choose one.
Verify the real behavior, preserve the intended contract, and update the stale source in the same change.

## Maintenance rules

- Keep `STATUS.md` short and current. Replace stale statements instead of appending dated progress entries.
- Record only meaningful validation evidence. State whether evidence is local, hosted API, browser UI, native UI, or recovery testing.
- Keep completed implementation details in code, tests, commits, and pull requests.
- Add product decisions to `PRODUCT.md` only after they are confirmed.
- Update architecture only when a durable boundary or contract changes, not for every internal refactor.
- Keep setup instructions free of secret values and distinguish local configuration from hosted configuration.
- Prefer updating one existing document over creating another checklist with overlapping ownership.
- Do not create historical archive documents for information already retained by Git.

## Expected task handoff

A completed task should make clear:

- what changed;
- what was actually verified;
- what remains unverified or blocked;
- whether hosted state changed;
- which durable documents were updated because their owned facts changed.
