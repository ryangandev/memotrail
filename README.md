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
docs/                   Product contract, architecture map, and current status
packages/
  design-tokens/        Cross-platform Soft Ledger token source and generator
  media-runtime/        Shared server-side image and metadata runtime
supabase/
  migrations/           Database, RLS, Storage, and history schema
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

The script creates a temporary local account, runs XCTest, requires the contract tests to execute, and removes the account and its owned data afterward.
It never uses the hosted Supabase project.
Regular Xcode test runs skip the local integration tests when this temporary configuration is absent.

Green builds do not by themselves prove authenticated user flows, production configuration, private media delivery, or recovery.
Use [docs/status.md](./docs/status.md) for the remaining acceptance gates.

## Deployment

Vercel builds the Web app from `apps/web`, using the repository root workspace and lockfile.
Supabase migrations remain version-controlled under `supabase/migrations`.

Deployment, DNS, billing, credential, production-data, and destructive retention changes require confirmation of the exact target immediately before execution.
