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
- Reproduce a bug with the cheapest check that fails the way the user sees it: a unit test when the logic is local, one browser spec or Simulator flow only when the failure lives there.
- Keep shared behavior aligned across Web, native iOS, and Supabase.
- Keep private data and credentials out of clients, fixtures, logs, docs, and commits.
- Treat builds, automated tests, hosted APIs, browser UI, native UI, and recovery exercises as distinct evidence, and do not claim one from another.
- Confirm the exact target and authorization before deployment, hosted migrations, DNS, billing, production-data, retention, or destructive actions.

## Validation

Run the smallest checks that prove the change locally, and let GitHub CI run the full suites.
The [README](./README.md#validation) lists each test layer and its command.

- While iterating, run the affected unit test files, then lint and type checking for the touched package.
- Add the single browser spec, data contract, database test file, or XCTest identifier that covers the changed behavior; pass the file name instead of running the whole suite.
- Do not run full local suites to collect evidence.
  CI runs formatting, lint, type checking, unit tests, the build, every database test, every data contract, and the full product browser suite on each pull request.
- Run native builds and XCTest only when the change touches `apps/ios` or generated design-system output that iOS consumes; native work is otherwise paused.
- Run the design gallery suite only when shared Web components or design tokens change.
- Capture before-and-after evidence only when the request is about a regression or visual parity.
- Record the checks you ran in the pull request description, not in `docs/status.md`.

## Pushing and CI

GitHub Actions minutes for this private repository are limited.

- Commit locally as work progresses and push once the branch is ready for review, not after every commit.
- A new push cancels the branch's in-progress CI run, so batch follow-up fixes into one push.
- Fix a CI failure by reproducing only the failing check locally, then push once.
- Changes limited to documentation or `apps/ios` skip the Web and Supabase CI jobs.

## Documentation

Follow the ownership and update rules in [docs/README.md](./docs/README.md).
