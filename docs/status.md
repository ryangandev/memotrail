# MemoTrail Status

Last reviewed: 2026-10-18.

## Where things stand

The branch `product/positioning-reset` implements the positioning in [positioning.md](./positioning.md) and the product in [product.md](./product.md) on Web.
Nothing on this branch is deployed.
The hosted Supabase project `kaivkozeyuwzqrckmyqu` has every migration through `202610180087` and no later one.
Production runs the Web from before this branch, which calls functions this branch's migrations drop.

## Implemented on Web

- Capture, drafts, offline retry, photos with private originals, Trash, Delete forever, and complete export, including reviews, suggestions, and import origins.
- Library with keyword search and filters, tags, First Times as a mark on any Entry, and Chapters as Entries with a span.
- Timeline of Chapter bars and First Time points, the Dashboard with current Chapters, and the Chapter Item page with its Entries and overlapping Chapters.
- Someday and the Map are gone, and their addresses lead to Library or the Entry they became.
- Homes, Vehicles, Periods, and Moment milestones became Chapters or ordinary Entries, and their addresses lead to Timeline or the Item page.
- Search by meaning in code and migrations, with its embedding service in `services/embeddings`; without `SEMANTIC_SEARCH_URL` and `SEMANTIC_SEARCH_API_KEY` Library searches by keywords only.
- Chapter and year reviews and Chapter suggestions in code and migrations, off for every person until they turn them on and accept the disclosure; the server refuses to call a provider unless `AI_PROVIDER` is `anthropic`.
- Import of a Markdown folder (which also reads Apple Notes Markdown exports), Apple Journal, Notion, and Day One into ordinary Entries, with a preview, undo, and no duplicates on a second import.
- A design system whose values all come from shared tokens.

All of it is verified against local Supabase only.
No real AI provider, deployed embedding service, hosted project, or Production deployment has been exercised.

## Native iOS

Native iOS is broken against the new schema and paused.
It still calls functions and tables these migrations drop (Homes, Vehicles, Someday, milestones, the Map).
It is rewritten to follow the finished Web behavior, and the database keeps no compatibility window for it.

## Hosted rollout

Every step needs Ryan's explicit go-ahead before it starts.
Do the steps in this order.

1. **Back up** the hosted database, schema and data, to a destination Ryan names.
2. **Apply the migrations** in filename order: `202610190001` and `202610190002`; `202610190010` through `202610190017`; `202610190020` through `202610190023`; `202610190030` through `202610190038`; `202610190040` through `202610190045`.
   `202610190011` converts every Home, Vehicle, and Period and checks its own result before committing.
   Apply them before deploying this Web, because the Web in Production calls RPCs these migrations drop.
   A migration `202610190024` that drops dead columns does not exist yet, and the follow-up migration for [issue #101](https://github.com/ryangandev/memotrail/issues/101) is still pending; neither belongs in this rollout.
3. **Set Vercel Production variables** before the deploy: `SUPABASE_SECRET_KEY`, and optionally `IMPORT_MAX_ZIP_BYTES`.
   Remove `AI_TOTAL_BUDGET_USD` and `AI_EMBEDDING_MODEL`, which nothing reads any more.
4. **Deploy this Web** to Production, then check Quick Capture, Library, Timeline, a Chapter Item page, and the Dashboard in a browser.
5. **Confirm the Anthropic account's data-sharing settings.**
   The Anthropic organization behind the key must not have opted in to any data-sharing or development program, because the disclosure tells people their review text is not shared for training.
   Then set `AI_PROVIDER=anthropic`, `AI_API_KEY`, `AI_MONTHLY_BUDGET_USD`, and `AI_USER_MONTHLY_BUDGET_USD`.
   Reviews stay off for each person until they turn them on.
6. **Deploy the Fly.io embedding service**, about $27 a month, which needs Ryan's approval.
   First run the model evaluation with `apps/web/scripts/semantic-eval.mjs` against the candidate models, as [services/embeddings/README.md](../services/embeddings/README.md) describes, and choose the model and similarity floor.
   Then set `SEMANTIC_SEARCH_URL` and `SEMANTIC_SEARCH_API_KEY` in Vercel Production only.
7. **Raise the hosted Storage file size limit** only if imports above 50 MB are wanted, then raise `IMPORT_MAX_ZIP_BYTES` to match.
8. **Verify the Apple Journal and Notion import adapters** against a real export of each app, because they are built from third-party reports and synthetic fixtures.

After the deploy, run `supabase db diff --linked`.
The hosted `service_role` and `anon` roles get no table access or function execution unless a migration grants it, and local Supabase grants both by default, so a missing grant can pass every local suite and fail only on the hosted project.

## Questions for Ryan

These are also listed in [product.md](./product.md#product-boundaries), and none is to be settled without him.

- Does the Dashboard keep one writing entrance and frame capture as today's journal ([issue #94](https://github.com/ryangandev/memotrail/issues/94))?
- Does the Dashboard keep a small daily resurfaced memory, or give that space to Chapters?
- Do Entry Locations stay?
- Do converted Work and study Periods keep the `work and study` tag?

## Next work

### 1. Accept the Web release

- Ryan accepts the Web flows in a configured browser, because the Vercel Preview has no Supabase public environment variables.
- Verify an actual Production export download.

### 2. Establish recovery

- Choose separately protected destinations for database backups and original Storage objects.
- Decide whether to enable point-in-time recovery; the latest inventory showed it disabled and no listed restore point.
- Complete and inspect a full restore in a non-production project.
- Audit abandoned unregistered uploads before approving automatic retention cleanup.

### 3. Rewrite native iOS

Start once Web is accepted.
The rewrite follows the Web behavior in [product.md](./product.md), including Chapters, Library search, reviews, and import.

### 4. Redesign the UI on the finished design system

The design system the redesign builds on is complete.
Web and iOS draw every visual value from the DTCG tokens in `packages/design-system/tokens`, and `pnpm lint` and `pnpm design-system:check` reject hardcoded values.
A full redesign is deferred while the work above comes first.
These open design decisions feed it:

- The type, spacing, and radius scales are named by value, so a retuned scale renames tokens.
- Six contrast exceptions remain until a palette change: inkFaint metadata in each theme, muted text on subtle panels, and warm, danger, and warning text in light.
- The brand mark's outer ring and arc use themed colors on iOS and fixed colors on Web, so the platforms differ in dark mode.
- Web `textSpace` is relative to the text size, so the paragraph gap is shared with iOS only once the Swift generator supports relative units.
- Library filters mix two field styles: Record and Tag are hand-styled selects with uppercase labels, while From and To use the shared date field with sentence-case labels.

## Watch list

- A valid hosted media session previously returned intermittent HTTP 401 responses before a later run passed. Do not attribute recurrence to the decoder repair without evidence.
- Next.js may log a client-aborted React Server Components request while application assertions pass. Keep it distinct from a product failure until the stable upstream fix is adopted.
- A local install whose `apps/web/node_modules/@memotrail/media-runtime` is a plain link, not a copy under `node_modules/.pnpm`, makes Next bundle the package, and every photo preview then fails with "Image decoder unavailable". The lockfile must keep the injected `file:` entry for that package.

## Updating this file

Keep only current state, the next actionable work, and unresolved blockers.
Remove resolved details and rely on Git history instead of appending progress entries.
Do not record test counts, run results, or before-and-after evidence here; they belong in the pull request description.
Product scope and deferred features belong in [product.md](./product.md).
