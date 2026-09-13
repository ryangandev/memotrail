# MemoTrail Agent Guide

## Start with the smallest useful context

1. Inspect the current branch, working tree, and recent commits.
2. Read [docs/README.md](./docs/README.md) to route the request.
3. Read [docs/status.md](./docs/status.md) for current work and blockers.
4. Read only the relevant section of [docs/product.md](./docs/product.md) or [docs/architecture.md](./docs/architecture.md).
5. Inspect the referenced code, migrations, and tests before making claims or changes.

Do not read every document by default.
Use headings and keyword search to load only the context the request needs.
More specific `AGENTS.md` files may add instructions inside a subtree.

## Source of truth

- The user's latest explicit direction controls the task.
- `docs/product.md` defines intended product behavior.
- Current code, migrations, and tests define implemented behavior.
- `docs/architecture.md` defines durable boundaries and points to likely files.
- `docs/status.md` defines the current completion state and open work.
- Git history and pull requests hold chronology and detailed delivery evidence.

When these disagree, verify the real behavior and update the stale source in the same change.

## Implementation rules

- Preserve unrelated working-tree changes.
- Reproduce bugs through the closest practical user path before fixing them.
- Keep shared behavior aligned across Web, native iOS, and Supabase.
- Keep private data and credentials out of clients, fixtures, logs, docs, and commits.
- Treat builds, automated tests, hosted APIs, browser UI, native UI, and recovery exercises as distinct evidence.
- Confirm the exact target and authorization before deployment, hosted migrations, DNS, billing, production-data, retention, or destructive actions.

## Documentation

Follow the ownership and update rules in [docs/README.md](./docs/README.md).
