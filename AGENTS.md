# MemoTrail Agent Guide

This file is the repository-wide starting point for any AI agent working on MemoTrail.

## Before making changes

1. Read [Docs/README.md](./Docs/README.md).
2. Read [Docs/STATUS.md](./Docs/STATUS.md) for the current implementation and acceptance state.
3. Read [Docs/PRODUCT.md](./Docs/PRODUCT.md) when work may affect product behavior.
4. Read [Docs/ARCHITECTURE.md](./Docs/ARCHITECTURE.md) when work may affect data, APIs, synchronization, security, or cross-platform behavior.
5. Read [Docs/SETUP.md](./Docs/SETUP.md) before work involving hosted services, credentials, deployment, or release acceptance.
6. Inspect the current code, migrations, tests, branch, and working tree before relying on documentation.

More specific `AGENTS.md` files may add instructions inside a subtree.

## Source-of-truth rules

- The user's latest explicit direction controls the task.
- `Docs/PRODUCT.md` is the intended product contract.
- Current code, migrations, and tests show implemented behavior.
- `Docs/STATUS.md` records the latest verified completion state, open work, and blockers.
- Git history and pull requests hold chronology. Do not recreate a commit-by-commit progress log in Markdown.
- When sources disagree, verify the real behavior and update the relevant document in the same change.

## Implementation expectations

- Preserve unrelated working-tree changes.
- Reproduce bugs through the closest practical end-user path before fixing them.
- Keep shared behavior aligned across Web, native iOS, and Supabase contracts.
- Prefer owner-scoped, revision-safe, transactional database boundaries for mutations.
- Keep private data and provider credentials out of logs, clients, fixtures, documentation, and commits.
- A build or unit test is not proof of a hosted, authenticated, native, destructive, or recovery workflow.
- Do not deploy migrations, change DNS or billing, alter production data, activate retention, or perform other sensitive remote actions without confirming the exact target and authorization.

## Documentation updates

Update documentation by responsibility, not by habit:

- Update `Docs/STATUS.md` when verified completion, open work, evidence, or blockers change.
- Update `Docs/PRODUCT.md` only for confirmed product decisions or behavior.
- Update `Docs/ARCHITECTURE.md` when a durable system boundary or data contract changes.
- Update `Docs/SETUP.md` when external configuration or release procedures change.
- Update `Docs/architecture/data-safety.md` when deletion, backup, restore, or private-media guarantees change.

Replace stale status instead of appending a diary entry.
Do not add a new top-level Markdown file unless it has a distinct long-lived responsibility that does not fit the documents above.
