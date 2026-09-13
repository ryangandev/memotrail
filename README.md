# MemoTrail

MemoTrail is a private, cross-platform record of a life in progress.
The repository contains a native SwiftUI iOS app, a responsive Next.js Web app, shared Soft Ledger design tokens, and Supabase infrastructure.

## Start here

- [Documentation guide](./Docs/README.md) explains what each document owns and how agents should keep it current.
- [Current status](./Docs/STATUS.md) summarizes what is shipped, what is verified, and what remains.
- [Product contract](./Docs/PRODUCT.md) defines the intended behavior and confirmed product decisions.
- [Architecture](./Docs/ARCHITECTURE.md) describes the system boundaries and cross-platform contracts.
- [Setup and release readiness](./Docs/SETUP.md) tracks external configuration and acceptance gates.

Agents should also follow the repository-wide instructions in [AGENTS.md](./AGENTS.md).

## Repository structure

```text
apps/
  ios/                  Native SwiftUI app
  web/                  Next.js Web app
Docs/                   Product, architecture, status, and operations
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

## iOS setup

Open `apps/ios/MemoTrail.xcodeproj` in Xcode.

The committed project builds for iOS Simulator without an Apple Developer account.
Running on a physical iPhone requires selecting a local Apple development team in Xcode.

When backend credentials exist, copy the local configuration template:

```bash
cp apps/ios/Configuration/Secrets.xcconfig.example apps/ios/Configuration/Secrets.xcconfig
```

Never put a Supabase secret key, Google client secret, or AI provider key in the iOS configuration.

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
pnpm lint
pnpm typecheck
pnpm test
pnpm build
node apps/web/scripts/verify-media-trace.mjs
```

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

Green builds do not by themselves prove authenticated user flows, production configuration, private media delivery, or recovery.
Use [Docs/STATUS.md](./Docs/STATUS.md) and [Docs/SETUP.md](./Docs/SETUP.md) for the remaining acceptance gates.

## Deployment

Vercel builds the Web app from `apps/web`, using the repository root workspace and lockfile.
Supabase migrations remain version-controlled under `supabase/migrations`.

Deployment, DNS, billing, credential, production-data, and destructive retention changes require confirmation of the exact target immediately before execution.
