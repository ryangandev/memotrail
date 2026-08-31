# MemoTrail Setup Checklist

> Status: Phase 1 foundation approved
>
> Last updated: 2026-08-30
>
> Initial authentication: Google Sign-In only
>
> iOS bundle identifier: `com.rystudio.memotrail.app`

## 1. Security rules

- [ ] Do not send secrets through chat.
- [ ] Do not commit local environment files, credentials, private keys, or downloaded OAuth configuration files.
- [ ] Keep Supabase secret keys, Google client secrets, and AI API keys on trusted server environments only.
- [ ] Never expose a secret through a `NEXT_PUBLIC_` environment variable.
- [ ] Use separate development and production credentials when production setup begins.
- [ ] Store account recovery codes and database passwords in a password manager.

## 2. Phase 0 decisions

- [x] Use a native SwiftUI iOS app and a Next.js Web app.
- [x] Keep both clients in one monorepo.
- [x] Use Supabase for Postgres, authentication, private media, and vector-search infrastructure.
- [x] Deploy the Web client from `apps/web` to Vercel.
- [x] Use Google Sign-In as the only initial authentication method.
- [x] Defer Sign in with Apple until an Apple Developer account is available.
- [x] Exclude email magic-link authentication from the initial product.
- [x] Support both light and dark themes.
- [x] Use `com.rystudio.memotrail.app` as the iOS bundle identifier.
- [x] Select Soft Ledger as the initial visual direction.
- [x] Approve Phase 1 foundation work before external credentials are available.
- [ ] Confirm feature-level acceptance criteria before each product feature is implemented.

## 3. Supabase project

User preparation:

- [x] Create a new Supabase organization or select the organization that should own MemoTrail.
- [x] Create a new Supabase project named `memotrail`.
- [ ] Select a region appropriate for the primary user.
- [ ] Save the generated database password in a password manager.
- [x] Record the project reference and project URL.
- [x] Leave application tables and Storage buckets uncreated so repository migrations remain the source of truth.
- [x] Do not paste the database password or secret key into chat.

Phase 1 repository work:

- [x] Add local Supabase configuration under `supabase/`.
- [x] Create version-controlled SQL migrations.
- [x] Enable Row Level Security on every exposed table.
- [x] Add allow-and-deny tests for authenticated and unauthenticated access.
- [x] Create private media buckets and policies through migrations.
- [x] Create development seed data that contains no sensitive real-world information.
- [x] Configure backup and recovery expectations before production data is stored.

Useful references:

- [Supabase local development](https://supabase.com/docs/guides/local-development)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase private Storage buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals)

## 4. Google OAuth

User preparation:

- [ ] Create or select a Google Cloud project dedicated to MemoTrail.
- [ ] Configure the Google Auth Platform branding and consent screen.
- [x] Create a Web OAuth client.
- [ ] Add `http://localhost:3000` as a development JavaScript origin.
- [ ] Add the future staging and production Web origins when those URLs exist.
- [ ] Add `https://<SUPABASE_PROJECT_REF>.supabase.co/auth/v1/callback` as the hosted Supabase redirect URI.
- [x] Create an iOS OAuth client using bundle identifier `com.rystudio.memotrail.app`.
- [x] Record the Web and iOS client IDs.
- [ ] Store the Web client secret in a password manager.
- [x] Do not send the Google client secret through chat or commit it.

Supabase configuration:

- [ ] Enable only the Google provider initially. Hosted verification found that Email and Google are both enabled; disable Email before authentication testing.
- [x] Configure the Web client ID and secret in Supabase Auth. Google is enabled; end-to-end login remains unverified.
- [ ] Include the iOS client ID in the allowed Google client IDs when native authentication is implemented.
- [ ] Configure local, staging, and production redirect allow lists deliberately.
- [ ] Test that Web and iOS Google identities resolve to the same MemoTrail account.

Useful references:

- [Supabase Login with Google](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Google OAuth setup](https://developers.google.com/identity/protocols/oauth2)

## 5. iOS development

User preparation:

- [x] Confirm that Xcode is installed on the development Mac.
- [ ] Keep a physical iPhone available for authentication, photo, offline, and lifecycle testing.
- [ ] Confirm that the Apple ID used for local signing is available in Xcode.
- [x] Use bundle identifier `com.rystudio.memotrail.app`.
- [x] Defer App Store distribution, Sign in with Apple, and production entitlements until an Apple Developer account is available.

Phase 1 repository work:

- [x] Create the SwiftUI project under `apps/ios/`.
- [x] Configure safe local signing without committing developer-specific signing state.
- [x] Add development environment configuration without embedding server secrets.
- [ ] Establish local persistence and a retryable synchronization queue.
- [ ] Add unit tests and UI tests.
- [ ] Verify installation and launch separately on the physical iPhone.

## 6. AI provider

No provider is selected yet.

Selection criteria:

- [ ] Strong English, Chinese, and mixed-language understanding.
- [ ] Reliable structured output for Type, Collection, tag, title, date, Place, and Person suggestions.
- [ ] Embeddings suitable for semantic search.
- [ ] Source-grounded answer generation for smart search.
- [ ] Clear API data-retention and training policies.
- [ ] Configurable spending limits and usage visibility.
- [ ] Appropriate latency for asynchronous Inbox classification.

User preparation after choosing a provider:

- [ ] Create a dedicated MemoTrail API project or account scope.
- [ ] Create a development API key.
- [ ] Configure a conservative spending limit or alert.
- [ ] Decide whether private Entry content may be sent to the provider.
- [ ] Decide whether photos may be analyzed or only text.
- [ ] Store the key in a password manager.
- [ ] Do not send the key through chat or expose it to either client.

Phase 1 and later repository work:

- [ ] Define a provider-neutral server-side interface.
- [ ] Keep classification, embeddings, and conversational generation separately configurable.
- [ ] Add retry, failure, audit, and disable controls.
- [ ] Ensure disabling AI preserves capture, organization, browsing, and keyword search.

## 7. Vercel Web deployment

The complete monorepo can stay in GitHub.
Vercel deploys only the Next.js application selected by its Root Directory setting.

User preparation when staging deployment is approved:

- [ ] Create or select the Vercel team that should own MemoTrail.
- [ ] Import the `ryangandev/memotrail` GitHub repository as a new Vercel project.
- [ ] Set Root Directory to `apps/web`.
- [ ] Confirm that the framework preset is Next.js.
- [ ] Verify that source files outside the Root Directory are included when `apps/web` depends on shared workspace packages.
- [ ] Use the repository root lockfile and workspace configuration.
- [ ] Create a stable staging hostname for OAuth callbacks.
- [ ] Add a production domain only after explicit deployment approval.

Environment configuration when the Web app exists:

- [x] Add the Supabase project URL.
- [x] Add the Supabase publishable key for browser use.
- [ ] Add server-only Supabase credentials only where privileged server operations truly require them.
- [ ] Add the selected AI provider key as a server-only environment variable.
- [ ] Configure separate Preview and Production values.
- [ ] Update Supabase and Google redirect allow lists for the stable staging and production URLs.

Deployment safeguards:

- [ ] Do not treat a successful build as proof that authentication, private media, or cross-device sync works.
- [ ] Verify staging end to end before a production deployment.
- [ ] Confirm the exact Vercel project and domain immediately before production changes.
- [ ] Do not deploy or change DNS without explicit approval.

Useful references:

- [Vercel monorepo deployment](https://vercel.com/docs/monorepos)
- [Vercel monorepo FAQ](https://vercel.com/docs/monorepos/monorepo-faq)

## 8. Proposed monorepo layout

```text
memotrail/
  apps/
    web/                  # Next.js and TypeScript
    ios/                  # SwiftUI and Xcode project
  packages/
    contracts/            # Language-neutral API and data schemas
    design-tokens/        # Cross-platform colors, spacing, and typography intent
  supabase/
    migrations/           # Versioned database changes
    tests/                # RLS and database behavior tests
    seed.sql              # Non-sensitive development data
  docs/
    architecture/         # Technical decisions and sync behavior
    design/               # Approved flows and visual decisions
  PRODUCT.md
  SETUP_CHECKLIST.md
  package.json
  pnpm-workspace.yaml
  pnpm-lock.yaml
```

The iOS project is stored in the same Git repository but is not part of the Node package workspace.
Vercel builds `apps/web` and any declared shared JavaScript packages it depends on.
Xcode builds `apps/ios` independently.
Supabase CLI reads the root `supabase` directory independently.

## 9. Safe information to share with Codex

Safe project identifiers may be shared when needed:

- Supabase project reference.
- Supabase project URL.
- Supabase publishable key.
- Google Web client ID.
- Google iOS client ID.
- Vercel project name.
- Staging and production hostnames.

Keep these values out of chat and Git:

- Supabase database password.
- Supabase secret key or service-role key.
- Google client secret.
- AI provider API key.
- Apple private keys and signing certificates.
- Vercel access tokens.

When Phase 1 creates ignored local environment files, place secrets directly into those files or the provider dashboards rather than sending them in messages.

## 10. Phase 1 readiness gate

Phase 1 may begin when:

- [x] The Soft Ledger visual direction is approved.
- [x] Phase 1 foundation work is explicitly authorized.
- [x] The new Supabase project exists.
- [x] Google OAuth Web and iOS client IDs exist, or authentication is explicitly scheduled after the first local vertical slice.
- [x] The monorepo and deployment approach are approved.
- [x] No unresolved decision blocks the initial data model, authentication, or sync strategy.

The repository, design system, Web shell, iOS shell, local Supabase configuration, examples, and tests may be created before external credentials exist.

Remote authentication integration remains gated on the Supabase project and Google OAuth client IDs.

Creating accounts and credentials does not authorize deployment, DNS changes, App Store submission, or production data migration.
