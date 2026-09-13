# MemoTrail Status

Last reviewed: 2026-09-13.

MemoTrail has a substantial shared Web, native iOS, and Supabase implementation.
The confirmed product scope is largely implemented, but final production acceptance, recovery readiness, and a small number of lifecycle audits remain open.
Do not describe the product as fully accepted or production-ready yet.

The latest implementation checkpoint before this documentation reorganization is `cd3ab9f`.
Use Git history for the feature-by-feature delivery record.

## Implemented product surface

The Web and iOS clients share the same core product model and currently include:

- Google authentication and session restoration;
- universal Inbox capture with recoverable drafts and offline queues;
- editable AI organization suggestions with explicit user approval;
- exact, partial, approximate, age-based, ranged, description-only, and unknown dates;
- manual Types, Collections, tags, People, Places, and Entry relationships;
- keyword and natural-language search with grounded source navigation;
- Timeline, First Times, Habits, Home resurfacing, Homes, Vehicles, Goals, and Bucket List behavior;
- private original photos, optimized display derivatives, metadata suggestions, galleries, and history-aware photo membership;
- revision-safe editing, restorable Entry history, shared Trash, permanent deletion, and confirmed Empty Trash;
- persistent Explore with AI conversations and explicit Save as Entry;
- complete portable ZIP export with JSON, Markdown, CSV, relationships, and original media.

Hosted Supabase migrations for the implemented shared contracts are deployed to the confirmed MemoTrail project.
Vercel Production contains the Web application and the deployed private media and export endpoints.

## Latest recorded evidence

This is evidence from the latest implementation and acceptance work, not a promise that every check was rerun for later documentation-only changes.

- The local baseline passed 430 Web tests and 51 production-mode browser/API scenarios.
- The latest fully recorded cross-platform feature run passed 211 native tests with no failures or skips and 1,489 SQL assertions across 42 files.
- Web type checking, lint, formatting, generated-token checks, production build, and isolated deployment-trace checks passed at the implementation checkpoint.
- Vercel deployment `6420320721` of `cd3ab9f` passed authenticated synthetic JPEG, HEIC, and PNG display and thumbnail generation, repeat reads, preview metadata removal, exact camera date and GPS extraction, and unchanged original-byte hashes.
- The hosted export check produced a 5,280,211-byte ZIP with all 30 datasets, Chinese writing, partial-date labels, Markdown and CSV views, and three matching original-media hashes.
- Discarded export snapshots returned HTTP 410.
- The exact synthetic acceptance account and all nine original and derived Storage objects were verified removed.
- No personal records were accessed and no AI request was made during the hosted media and export run.

## Open acceptance and operational work

Work these in roughly this order unless the user changes the priority.

### 1. Production AI configuration

- Vercel Production currently returns HTTP 503 `provider_unavailable` for an authenticated synthetic AI connection check.
- Configure the server-only Anthropic variables, redeploy, and rerun the bounded hosted verification described in [SETUP.md](./SETUP.md).
- A valid local Anthropic key does not prove the deployed environment is configured.

### 2. Real browser and native interaction acceptance

- Verify an actual production browser export download, not only authenticated API streaming.
- Verify native Save and share behavior for a production export.
- Complete authenticated native interaction checks for the photo picker, galleries, Trash, AI, export, and other high-risk flows.
- Continue the remaining photo-surface and interactive-gallery audit on both clients.
- The most recent native UI attempt was blocked because the development Mac was locked.

### 3. Recovery and retention readiness

- Choose a protected backup destination for both database data and original Storage objects.
- Decide whether to purchase or enable point-in-time recovery. The 2026-09-13 hosted inventory showed PITR disabled and no listed restore point.
- Complete and inspect a full restore into a non-production project before treating MemoTrail as safely backed up.
- Audit abandoned unregistered photo uploads and the remaining metadata and relationship lifecycle edges.
- Do not activate automatic 30-day permanent deletion until the exact targets, interruption behavior, backup state, and rollout have been approved.

See [architecture/data-safety.md](./architecture/data-safety.md) for the durable safety contract.

### 4. Continuous integration

- GitHub Actions cannot currently start jobs because GitHub reports failed payments or an insufficient spending limit.
- A successful Vercel deployment does not substitute for a successful GitHub CI run.
- After billing is resolved, rerun the current `main` workflow and record only the resulting verified state here.

### 5. Remaining technical observations

- Two earlier hosted media URL requests rejected a valid session with HTTP 401 while export accepted it. A later run passed, so the intermittent behavior remains observed and is not attributed to the photo decoder repair.
- Next.js may report an intermittent client-aborted React Server Components request even when application assertions pass. Track the stable release containing the upstream fix before calling the log issue resolved.
- Broader metadata, relationship, and specialized-editor lifecycle audits remain open where they are not already covered by focused tests.

## Deferred or undecided

- Preview or staging OAuth configuration until a stable Preview strategy exists.
- Sign in with Apple, Apple Developer distribution, and App Store release work.
- A native macOS client.
- A Share Extension, bulk Inbox review, and optional PWA enhancements.
- Chinese application UI. English, Chinese, and mixed-language content remain supported.
- The Map view, while Places remain part of the current product.
- Production data import, DNS changes, and other unrelated account-level changes.

## How to update this file

- Replace old status with the newest verified state instead of appending a chronological entry.
- Keep shipped capability summaries broad. Detailed implementation history belongs in commits, pull requests, code, and tests.
- Name the evidence boundary: local tests, hosted API, browser UI, native UI, or recovery exercise.
- Keep a blocker only while it still blocks acceptance.
- Update [SETUP.md](./SETUP.md) when the resolution requires an external configuration step.
