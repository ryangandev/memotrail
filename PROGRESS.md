# MemoTrail Implementation Progress

> Current phase: Authentication and first synchronized vertical slice
>
> Last updated: 2026-08-31
>
> Rule: Update this file in every commit and keep each feature in its own commit.

## Current status

- Phase 1 repository, design system, Web shell, iOS shell, local Supabase schema, RLS tests, and CI are complete.
- The production Web shell is reachable at `https://memotrail.ryangan.me`.
- Local Web and iOS clients contain matching ignored Supabase public configuration.
- Hosted Supabase Auth exposes Google as the only external provider.
- Google Web and iOS OAuth clients exist with the confirmed origins, callback, and bundle identifier.
- Vercel Production contains the public application URL, Supabase public configuration, and a server-only Supabase key.
- The linked hosted Supabase project contains both reviewed repository migrations and no development seed users.
- Hosted verification found 21 Row Level Security-enabled application tables, 22 public policies, and a private `entry-media` bucket.
- Hosted schema lint passes, and the platform-created `SECURITY DEFINER` helper is no longer executable by client roles.
- AI selection and configuration are deferred and do not block authentication, capture, keyword search, or synchronization work.

## Active acceptance criteria

### Hosted data foundation

- [x] Apply only version-controlled migrations to the confirmed hosted Supabase project.
- [x] Do not apply synthetic development seed data.
- [x] Verify profiles, Entries, history, default timeline tracks, private Storage, grants, and RLS after deployment.

### Web Google authentication

- A signed-out user can start Google Sign-In from MemoTrail.
- The OAuth callback creates a secure server-managed session and returns to MemoTrail.
- A signed-in user sees their real account identity and can sign out.
- Localhost and the production domain use their own allowed callback URLs.
- Missing public configuration produces an explicit setup state without exposing secrets.

### iOS Google authentication

- A signed-out user can start native Google Sign-In.
- The Google ID token is exchanged for the same Supabase identity model used by Web.
- The session survives a normal app relaunch and can be explicitly signed out.
- The app contains public client configuration only.
- Simulator build and launch remain warning-free before physical-device verification.

## Feature history

- `docs: define MemoTrail product direction` established the evolving product contract.
- `docs: approve MemoTrail phase one foundation` approved the implementation stack and boundaries.
- `chore: scaffold MemoTrail monorepo and web app` created the pnpm/Turborepo and Next.js foundation.
- `feat: establish Soft Ledger design system` generated shared Web and Swift design tokens.
- `feat: add native SwiftUI app foundation` created the buildable native iOS shell.
- `feat: add secure Supabase foundation` added the schema, RLS, private Storage, seed, tests, and CI.
- `fix: make web typecheck independent of build` fixed clean-checkout CI type generation.
- `docs: update credential setup checklist` recorded the first verified external credential setup.
- `docs: establish implementation progress tracking` verified production configuration and established commit-by-commit progress tracking.
- Current change: deployed and verified the hosted Supabase data foundation.

## Next sequence

1. Implement Web Google authentication.
2. Implement iOS Google authentication.
3. Build the first synchronized Inbox Entry flow on both clients.
4. Add offline persistence and retryable synchronization before expanding product areas.

## Deferred

- AI provider selection and AI-assisted organization.
- Preview or staging OAuth configuration until a stable Preview strategy is chosen.
- Sign in with Apple and App Store distribution.
- Production data import, DNS changes, and any destructive remote migration.
