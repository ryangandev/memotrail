# MemoTrail Setup and Release Readiness

Last reviewed: 2026-09-13.

This document owns external configuration, credential safety, and the acceptance steps that cannot be proved by source code alone.
Routine local commands live in the root [README.md](../README.md).
Current product completion and blockers live in [STATUS.md](./STATUS.md).

## Safety rules

- Never send secrets through chat or commit them to Git.
- Keep Supabase secret keys, Google client secrets, AI keys, database passwords, recovery codes, signing credentials, and provider tokens in an appropriate password manager or secret store.
- Never expose a server credential through a `NEXT_PUBLIC_` variable or an iOS configuration file.
- Use synthetic accounts and synthetic content for automated hosted acceptance.
- Confirm the exact hosted project, environment, and domain before any remote mutation.
- Deployment, DNS, billing, production-data, backup-policy, and destructive retention changes require explicit authorization for the exact action.
- An uncertain destructive or fixture-cleanup result must be inspected before retrying.

## Local development configuration

### Web

Copy `apps/web/.env.example` to `apps/web/.env.local` and provide only the values needed for the local task.
Browser-visible variables may contain the Supabase project URL and publishable key.
AI and elevated Supabase credentials must remain server-only.

### iOS

Copy `apps/ios/Configuration/Secrets.xcconfig.example` to `apps/ios/Configuration/Secrets.xcconfig`.
The bundle identifier is `com.rystudio.memotrail.app`.
The iOS client may receive public Supabase configuration, the Google iOS client ID, and the public API base URL.
It must not contain an AI provider key, Google client secret, or Supabase secret key.

The Simulator build does not require an Apple Developer account.
A physical iPhone requires an available local signing identity and development team in Xcode.

### Supabase

Use the root `supabase/` directory as the source of truth for local configuration and migrations.
Local seed data must remain synthetic and non-sensitive.
Run database tests against a locally recreated stack before proposing a hosted migration.

Do not link to or migrate a hosted project merely because local configuration exists.
Confirm the project reference and intended migration set immediately before a hosted change.

## Current hosted configuration

### Supabase

Confirmed current state:

- The hosted MemoTrail project is in `us-west-1`.
- Version-controlled application migrations are deployed.
- Row Level Security and authenticated execution boundaries are implemented and have focused local and hosted verification.
- Application media buckets are private.
- Google is the only enabled initial authentication provider.

Open work:

- Store the database password and recovery material in a password manager if that has not been completed.
- Choose a separately protected backup destination for database exports and original Storage objects.
- Decide whether to enable a paid recovery add-on or point-in-time recovery.
- Perform and inspect a complete restore into a non-production project.
- Do not activate automatic retention cleanup until the data-safety review and explicit rollout approval are complete.

On 2026-09-13, the read-only hosted inventory reported PITR disabled, no listed restore point, and WAL backup enablement.
That snapshot is not evidence of a recoverable backup.
See [architecture/data-safety.md](./architecture/data-safety.md).

### Google OAuth

Confirmed current state:

- A dedicated Google Cloud project and consent configuration exist.
- Web and iOS OAuth clients exist.
- The production Web origin and Supabase callback are configured.
- The iOS bundle ID and callback scheme are configured.
- Web and iOS sign-in, session restoration, sign-out, and same-account identity have been accepted.

Open work:

- Store the Web client secret in a password manager if that has not been completed.
- Add Preview or staging origins and redirects only after a stable Preview hostname and strategy are chosen.
- Reconfirm the allowed client IDs and redirects whenever an OAuth environment is added.

### Vercel Web deployment

Confirmed current state:

- Vercel imports the complete repository and builds the Next.js app from `apps/web`.
- The production domain is `https://memotrail.ryangan.me`.
- Production has the public Supabase values and the server-only Supabase credential needed by AI accounting, private media delivery, and export.
- Deployment `6420320721` of `cd3ab9f` passed synthetic hosted JPEG, HEIC, and PNG media generation and complete ZIP streaming.

Open work:

- Configure the Production AI variables described below and redeploy.
- Verify an actual production browser download and native Save/share interaction separately from API streaming.
- Configure separate Preview values only when a Preview environment is intentionally introduced.
- Recheck authenticated media behavior if the intermittent valid-session HTTP 401 recurs.

### AI provider

Anthropic is the selected server-side provider.
The pinned chat model is `claude-haiku-4-5-20251001`.
Local direct and authenticated synthetic checks have passed, but Production is not accepted.
The latest hosted authenticated connection check returned HTTP 503 `provider_unavailable` with no provider request or charge.

To complete Production configuration:

1. Confirm the exact Vercel project and Production environment.
2. Add `AI_PROVIDER=anthropic`.
3. Add the server-only `AI_API_KEY` without exposing its value in chat, logs, source, or client configuration.
4. Add `AI_CHAT_MODEL=claude-haiku-4-5-20251001`.
5. Add `AI_TOTAL_BUDGET_USD=3`, or another explicitly approved conservative budget.
6. Confirm the existing server-only `SUPABASE_SECRET_KEY` remains present.
7. Redeploy Production.
8. Run the bounded synthetic verification from the repository root:

```bash
MEMOTRAIL_VERIFY_HOSTED_AI=1 node apps/web/scripts/verify-hosted-ai.mjs
```

Acceptance requires HTTP 200, one completed usage record within the fixture budget, no personal content, and confirmed removal of the marked synthetic account.
Do not repeat account creation after an uncertain cleanup result without inspecting the reported fixture.

## Native acceptance

The source, Simulator build, unit tests, and native bearer API tests do not prove actual device interaction.

Before calling the native client accepted:

- [ ] Unlock the development Mac and prepare an isolated authenticated test account.
- [ ] Confirm signing and installation on a physical iPhone when physical-device behavior is in scope.
- [ ] Exercise capture, offline recovery, Inbox review, and cross-device synchronization.
- [ ] Exercise photo selection, display, metadata adoption, gallery navigation, retry, Trash, and restoration.
- [ ] Exercise AI consent, suggestions, search, exploration, and failure states without personal content.
- [ ] Download an export and verify the native Save/share flow.
- [ ] Verify destructive confirmations and interruption behavior without using personal records.

## Continuous integration

The GitHub Actions workflow runs Web and shared checks, an iOS Simulator build, and local Supabase database tests.
The latest workflow attempt did not start because GitHub reported failed payments or an insufficient spending limit.

To restore CI evidence:

1. Resolve the GitHub billing or spending-limit issue in the account UI.
2. Rerun the workflow for the current `main` commit.
3. Confirm that all jobs actually started and ran.
4. Update [STATUS.md](./STATUS.md) with the verified result.

Do not report CI as passing based on a prior commit, a green Vercel deployment, or a command that exited without running its tests.

## Release readiness gate

MemoTrail is not ready to be called fully accepted until all of the following are true:

- [x] The core cross-platform feature surface is implemented across Web, iOS, and Supabase.
- [x] Hosted private media and export APIs pass bounded synthetic acceptance.
- [ ] Production AI configuration passes bounded synthetic acceptance.
- [ ] Production browser download and native Save/share interactions pass.
- [ ] Authenticated native high-risk flows pass through the real UI.
- [ ] GitHub CI runs successfully on the current `main` commit.
- [ ] Database and original-media backups have a separately protected destination.
- [ ] A complete restore has been inspected in a non-production project.
- [ ] Remaining lifecycle and retention audits are resolved or explicitly deferred.

## Safe project information

Identifiers that may be shared when needed include project references, project URLs, publishable keys, OAuth client IDs, Vercel project names, and public hostnames.

Never share or commit database passwords, secret or service-role keys, Google client secrets, AI provider keys, Apple private keys, signing certificates, recovery codes, or Vercel access tokens.
