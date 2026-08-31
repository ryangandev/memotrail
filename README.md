# MemoTrail

MemoTrail is a private, cross-platform record of a life in progress.
The repository contains a native SwiftUI iOS app, a responsive Next.js Web app, shared Soft Ledger design tokens, and Supabase infrastructure.

Product behavior and confirmed decisions live in [PRODUCT.md](./PRODUCT.md).
External account and credential preparation lives in [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md).

## Repository structure

```text
apps/
  ios/                  Native SwiftUI app
  web/                  Next.js Web app
packages/
  design-tokens/        Cross-platform Soft Ledger token source and generator
supabase/
  migrations/           Database, RLS, Storage, and history schema
  tests/                Database security tests
  seed.sql              Synthetic local development data
```

## Requirements

- Node.js 24.13 or another compatible Node.js 24 release.
- pnpm 10.33.
- Xcode 16 or newer.
- Supabase CLI 2.115 or newer.
- Docker Desktop when running the local Supabase stack and database tests.

## Web setup

Install workspace dependencies from the repository root:

```bash
pnpm install
```

Copy the Web environment template and fill in browser-safe development values when the Supabase project exists:

```bash
cp apps/web/.env.example apps/web/.env.local
```

Start the Web client:

```bash
pnpm --filter @memotrail/web dev
```

The Web app is then available at `http://localhost:3000`.
It remains buildable before credentials exist.

## iOS setup

Open `apps/ios/MemoTrail.xcodeproj` in Xcode.

The committed project builds for iOS Simulator without an Apple Developer account.
Running on a physical iPhone requires selecting a local Apple development team in Xcode.

When backend credentials exist, copy the local configuration template:

```bash
cp apps/ios/Configuration/Secrets.xcconfig.example apps/ios/Configuration/Secrets.xcconfig
```

Do not put a Supabase secret key, Google client secret, or AI API key in the iOS configuration.

## Supabase setup

Start the local stack and recreate the database from migrations and synthetic seed data:

```bash
supabase start
supabase db reset
```

Run database security tests:

```bash
supabase test db
```

The `entry-media` bucket is private.
Object paths must begin with the authenticated user ID, for example `<user-id>/<entry-id>/<file-id>.jpg`.

Do not link or push migrations to a hosted Supabase project until the exact target project has been confirmed.

## Validation

Regenerate platform design tokens after changing `packages/design-tokens/tokens.json`:

```bash
pnpm tokens:generate
```

Run the Web and shared checks:

```bash
pnpm format:check
pnpm tokens:check
pnpm lint
pnpm typecheck
pnpm build
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

## Deployment

No deployment is part of Phase 1 foundation work.

When Web staging is approved, import the complete repository into Vercel and set the Root Directory to `apps/web`.
Use the root `pnpm-lock.yaml` and workspace configuration.
