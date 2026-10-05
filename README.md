# MemoTrail

MemoTrail is a private, cross-platform record of a life in progress.
The repository contains a native SwiftUI iOS app, a responsive Next.js Web app, shared Soft Ledger design tokens, and Supabase infrastructure.

## Start here

- [Documentation guide](./docs/README.md) routes each request to the smallest useful context.
- [Current status](./docs/status.md) summarizes what is shipped, what remains, and what is blocked.
- [Product contract](./docs/product.md) defines current behavior and scope.
- [Architecture](./docs/architecture.md) maps system boundaries and requests to likely code.

Agents should also follow the repository-wide instructions in [AGENTS.md](./AGENTS.md).

## Repository structure

```text
apps/
  ios/                  Native SwiftUI app
  web/                  Next.js Web app
assets/
  brand/                Brand mark and app icon SVG sources
docs/                   Product contract, architecture map, and current status
packages/
  design-tokens/        Cross-platform Soft Ledger token source and generator
  media-runtime/        Shared server-side image and metadata runtime
supabase/
  migrations/           Database, RLS, and Storage schema
  tests/                Database security and behavior tests
  seed.sql              Synthetic local development data
```

## Requirements

- Node.js 24.13 or another compatible Node.js 24 release.
- pnpm 10.33.
- Xcode 16 or newer.
- Supabase CLI 2.116 or newer.
- Docker Desktop when running the local Supabase stack and database tests.

## Web setup

Install workspace dependencies from the repository root:

```bash
pnpm install
```

Copy the Web environment template and fill in browser-safe development values:

```bash
cp apps/web/.env.example apps/web/.env.local
```

Start the Web client:

```bash
pnpm --filter @memotrail/web dev
```

The Web app is available at `http://localhost:3000`.
It remains buildable before credentials exist.
Set the server-only `GEOAPIFY_API_KEY` to enable address search and static maps in Web Entry and Home Location fields.
Without it, existing Entry Locations and coordinates remain accessible, but provider search and map imagery are unavailable.

## iOS setup

Open `apps/ios/MemoTrail.xcodeproj` in Xcode.

The committed project builds for iOS Simulator without an Apple Developer account.
Running on a physical iPhone requires selecting a local Apple development team in Xcode.

When backend credentials exist, copy the local configuration template:

```bash
cp apps/ios/Configuration/Secrets.xcconfig.example apps/ios/Configuration/Secrets.xcconfig
```

Use the same Supabase URL and publishable key as Web, plus the iOS Google client ID and URL scheme.
`MEMOTRAIL_API_URL` points to the Web server that handles authenticated media, metadata, and export.
For a Simulator using your local Web server, override it in the ignored configuration with `http:/$()/127.0.0.1:3000`.
Never put a Supabase secret key, Google client secret, Geoapify key, or AI provider key in the iOS configuration.

### Native UI review

Debug builds expose Design System from the signed-out screen and from More or Settings after sign-in.
The gallery uses real native components and includes appearance and Dynamic Type preview controls.
Existing screens keep their layouts pending component acceptance.

Xcode launch arguments `--review-design-system`, `--review-map`, and `--review-navigation` open isolated review modes.
Add `--review-design-section foundations` (or another section name) after `--review-design-system` to open one gallery section directly.
The Map review uses clearly synthetic records; these modes do not sign in or write to the backend and are excluded from Release builds.
The normal Map is available under More and reads the signed-in user's current Locations using MapKit.
No Geoapify key is needed on iOS.

Run Simulator UI interactions with the shared `MemoTrailUI` scheme:

```bash
xcodebuild -project apps/ios/MemoTrail.xcodeproj -scheme MemoTrailUI \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' test
```

## Supabase setup

Start the local stack and recreate the database from migrations and synthetic seed data:

```bash
supabase start
supabase db reset
supabase test db
```

The `entry-media` bucket is private.
Object paths must begin with the authenticated user ID, for example `<user-id>/<entry-id>/<file-id>.jpg`.

Do not link, migrate, or mutate a hosted Supabase project until the exact target and authorized change have been confirmed.

## Validation

After changing `packages/design-tokens/tokens.json`, regenerate both platform outputs:

```bash
pnpm tokens:generate
```

After changing an `assets/brand/memotrail-app-icon-*.svg` source, regenerate the iOS app icon PNGs with the macOS SVG renderer:

```bash
swift apps/ios/scripts/render-app-icon.swift
```

Run the Web and shared checks:

```bash
pnpm format:check
pnpm tokens:check
pnpm turbo run lint typecheck test
pnpm build
node apps/web/scripts/verify-media-trace.mjs
```

The CI Web job runs these independent checks concurrently before the build.
Web type checking runs `next typegen` before TypeScript so a fresh checkout generates the required Next.js declarations.
The generated `apps/web/next-env.d.ts` stays local and is ignored by Git.
Playwright browser tests are a separate local acceptance suite that requires the local Supabase stack; they are not part of the current GitHub CI job.
GitHub CI does not build or test the iOS app.
Each macOS runner minute costs this private repository ten Linux minutes, and the native contract and interaction suites need the Docker-based local Supabase stack, which GitHub's Apple silicon macOS runners cannot start.
Before merging a change to `apps/ios`, design tokens, migrations, or a contract both clients share, run the affected native layers below locally.

### Choose the relevant test layer

| Layer                                             | Location                                                | Command                                                                              | Runtime needed                                          |
| ------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| Web unit and rendering contracts                  | `apps/web/src/**/*.test.{ts,tsx}`                       | `pnpm --filter @memotrail/web test`                                                  | Node.js                                                 |
| Database security and RPC behavior                | `supabase/tests`                                        | `supabase test db`                                                                   | Local Supabase database                                 |
| Multi-client RPC, Storage, and locking contracts  | `apps/web/contracts`                                    | `pnpm --filter @memotrail/web test:contracts`                                        | Local Supabase stack; no Web server or browser          |
| Web browser and HTTP acceptance                   | `apps/web/e2e`                                          | `pnpm --filter @memotrail/web test:e2e`                                              | Local Supabase stack, Next.js, and Chrome               |
| Web design gallery interactions and visual checks | `apps/web/e2e/design-system.e2e.ts`                     | `pnpm --filter @memotrail/web test:e2e:design`                                       | Local Supabase, development server, and Chrome          |
| Native unit and serialization contracts           | `apps/ios/MemoTrailTests`, except `NativeContractTests` | `MemoTrail` scheme with `-skip-testing:MemoTrailTests/NativeContractTests`           | iOS Simulator                                           |
| Native backend contracts                          | `NativeContractTests`                                   | `verify-local-contracts.py` with `--only-testing MemoTrailTests/NativeContractTests` | iOS Simulator and local Supabase                        |
| Native interaction acceptance                     | `apps/ios/MemoTrailUITests`                             | `MemoTrailUI` scheme or `review-local-session.py`                                    | iOS Simulator; signed-in flows also need local Supabase |

For a focused change, select the affected files or XCTest identifiers first.
Include every affected layer when shared behavior changes, and run the full applicable suites before merging broad changes or releasing.
For example:

```bash
pnpm --filter @memotrail/web test src/lib/data/entry-detail.test.ts
pnpm --filter @memotrail/web test:contracts media-race
MEMOTRAIL_E2E_PORT=3101 pnpm --filter @memotrail/web test:e2e wiki-library.e2e.ts
```

The product browser suite starts its own isolated server and defaults to port 3100.
Set `MEMOTRAIL_E2E_PORT` to an available port if another project is using it; the server, browser base URL, and request Origin checks use the same value.
The native review script's `--web` option honors this variable as well.
Test server build output is isolated by port, so independent test servers do not share Next.js build state.
Next.js writes test type paths into an ignored per-port TypeScript configuration that extends the strict project configuration.
Use `MEMOTRAIL_E2E_PRODUCTION=1` for browser acceptance against a local production build.
Run the development-only gallery interactions and visual checks separately with `pnpm --filter @memotrail/web test:e2e:design` when shared components or design tokens change.
This suite always uses the development server because the gallery is absent from production builds.
Run any suite with `--list` to inspect collection without starting services.

Build the iOS app without signing:

```bash
xcodebuild -quiet \
  -project apps/ios/MemoTrail.xcodeproj \
  -scheme MemoTrail \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run database security and behavior tests with the local Supabase stack active:

```bash
supabase test db
```

Run the full native test suite, including real data-contract tests against local Supabase:

```bash
python3 apps/ios/scripts/verify-local-contracts.py --simulator-id YOUR_SIMULATOR_UDID
```

The script creates a temporary local account, runs the selected XCTest cases without skips, and removes the account and its owned data afterward.
It never uses the hosted Supabase project.
Regular Xcode test runs skip the local integration tests when this temporary configuration is absent.
To run only a backend contract class or method, repeat `--only-testing` as needed:

```bash
python3 apps/ios/scripts/verify-local-contracts.py --simulator-id YOUR_SIMULATOR_UDID \
  --only-testing MemoTrailTests/NativeContractTests
```

Without a filter, the script still runs the full native unit and backend contract suite.
Both native scripts reject runs that skip selected tests or pass no tests.
Their default Xcode build cache is isolated per checkout or worktree, and each run keeps its own log beside its result bundle.
Concurrent runs using the same build directory fail immediately; choose another `--derived-data` and an unused Simulator for independent native runs.

Run signed-in native UI flows as a seeded, disposable local account:

```bash
python3 apps/ios/scripts/review-local-session.py --simulator-id YOUR_SIMULATOR_UDID \
  --attachments /private/tmp/memotrail-native-review
```

The script seeds a small synthetic archive through the same database functions the apps use, opens the Debug `--review-local-session` mode, runs `LocalSessionUITests`, exports screenshots, and removes the account, its rows, and its media afterward.
Add `--web` to serve the Web media API on `127.0.0.1:3100` for photo flows, and `--only-testing` to pick other UI tests.
Both the stack and the Web API must answer on `127.0.0.1`; regular `MemoTrailUI` runs skip these tests.

Green builds do not by themselves prove authenticated user flows, production configuration, private media delivery, or recovery.
Use [docs/status.md](./docs/status.md) for the remaining acceptance gates.

## Deployment

Vercel builds the Web app from `apps/web`, using the repository root workspace and lockfile.
Supabase migrations remain version-controlled under `supabase/migrations`.

Deployment, DNS, billing, credential, production-data, and destructive retention changes require confirmation of the exact target immediately before execution.
