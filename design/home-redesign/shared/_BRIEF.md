# Home Redesign — build brief for concept files

You are producing standalone HTML mockups of a redesigned **MemoTrail Home page**.
MemoTrail is a private, single-user "Capture First Life Wiki" — free-form writing plus
structured life facts. Visual direction is **"Soft Ledger": minimal, archival, modern,
calm, approachable.** Warm paper canvas, muted forest-green accent, terracotta warm accent,
serif (Iowan/Georgia) for headings, sans for body.

Each concept is a **different layout idea for the same Home content**. Vary the layout and
composition boldly; keep the design language, tokens, and content identical.

## Hard rules (every file)

1. Self-contained and offline. **No external resources** — no web fonts, no image URLs, no
   CDN. Use the `.mt-photo` primitive (a CSS gradient) wherever a photo would go.
2. Reuse the shared files. Start every file with exactly:
   ```html
   <!doctype html>
   <html lang="en">
   <head>
     <meta charset="utf-8" />
     <meta name="viewport" content="width=device-width, initial-scale=1" />
     <title>Home Redesign · NN Concept Name</title>
     <link rel="stylesheet" href="shared/tokens.css" />
     <link rel="stylesheet" href="shared/frame.css" />
     <style> /* concept-specific CSS only */ </style>
   </head>
   <body data-nav="home" data-page-name="Home">
     <main class="mt-main"> ... concept layout ... </main>
     <script src="shared/ui.js"></script>
   </body>
   </html>
   ```
   `ui.js` injects the sidebar + top bar + concept switcher around your `<main>`. Do **not**
   add your own sidebar/top bar. Everything you build goes inside `<main class="mt-main">`.
3. **Always keep the Quick Capture surface** — it is the one element that must survive every
   redesign. Use the `.mt-capture` block (see template). You may restyle/reposition it per
   concept, but the composer (spark + "Capture something" + field + Photo/Voice/Date tools +
   Capture button) must be present and prominent.
4. Use design tokens (`--mt-*`) for all colors, spacing, radii, type. Never hardcode hex.
5. Use icon spans: `<span class="ico ico-NAME"></span>`. Available names: search, plus, inbox,
   spark, clock, chevron, arrow, timeline, archive, check, home, book, map, tag, layers, users,
   settings, sun, moon, mic, image, calendar, edit, grid, bookmark, compass, star, menu.
6. Responsive: must hold together down to ~390px. The shared chrome already hides the sidebar
   under 720px. Add your own media queries for the concept layout.
7. Prefer the shared primitives where they fit: `.mt-eyebrow`, `.mt-serif`, `.mt-section-head`
   (with h2/p + `.mt-section-link`), `.mt-chip`, `.mt-kind`, `.mt-photo`, `.mt-card`, `.mt-btn`
   (+`--ghost`,`--quiet`), `.mt-capture` and its parts. Read `shared/frame.css` for the full set.
8. Read `01-ledger-column.html` as the reference for structure, tone, and the capture block.
   Match its polish. Each concept must be visibly, structurally different from the others —
   not a recolor.

## Canonical content (use these exact strings in every concept)

- Date eyebrow: `Tuesday · September 23`
- Greeting: `Good morning, Ryan.`
- Sub/description: `A calm view of what is active, recent, and waiting for you.`

Quick capture: heading `Capture something`, field placeholder text
`A thought, a moment, a fact worth keeping…`, tools `Photo` (ico-image), `Voice` (ico-mic),
`Date` (ico-calendar), primary button `Capture` (ico-arrow).

Today stats (2):
- `3` — `Life in progress` — `current chapters` (icon: timeline, links to Timeline)
- `128` — `Entries kept` — `12 First Times · 7 Collections` (icon: archive, links to Library)

Ready to organize — Inbox, total `3`:
1. `Sep 23` — `Coffee with Mara before her flight` — `She mentioned wanting to move back east by spring…`
2. `Sep 22` — `Idea: a slower kind of journal` — `Something that rewards returning, not streaks.`
3. `Sep 21` — `Dad's borscht recipe, finally written down` — `A palmful of dill at the very end, never before.`

Current chapters (3):
- kind `Homes` — `Apartment on Bedford Ave` — `Aug 2023 – Present`
- kind `Career` — `Building MemoTrail` — `2024 – Present`
- kind `Learning` — `Piano, slowly` — `This year`

A memory for today (label `On this day, 2 years ago`), has a photo:
- kind `Memory` — date `Sep 23, 2023`
- title `The morning we hiked Breakneck Ridge`
- body `The fog didn't lift until noon, and we ate cold bagels on the summit anyway. Best decision of that whole trip.`
- chips `Trips`, `#hiking`, `Mara`

Recent entries (4):
1. kind `Reflection` — `Sep 22` — `On keeping a slower record` — `I don't want a feed. I want a place that gets richer the longer I keep it.` (no photo)
2. kind `First Time` — `Sep 20` — `First time making pasta from scratch` — `Flour everywhere. The dough came together on the third try.` (has photo)
3. kind `Note` — `Sep 18` — `Books to reread this winter` — `Gilead, The Dispossessed, and whatever Mara keeps recommending.` (no photo)
4. kind `Person` — `Sep 17` — `Called Grandma Lin` — `She told the story about the bicycle again. I wrote it down this time.` (no photo)

Use `—` inside prose sparingly; the project style forbids em dashes in *code/commit messages*
but these are content strings; the en dash `–` in date ranges above is intentional. Do not
introduce em dashes elsewhere.

## Concept catalog (layout direction)

Each file name is `NN-slug.html`. Build only the ones you are assigned.

- **02 today-dashboard** — Bento dashboard. Compact greeting header row, then a grid of tiles:
  a wide capture hero tile across the top, two stat tiles, a memory tile (photo), three chapter
  tiles, an inbox tile (lists the 3), and a recent tile-list. Everything visible at a glance.
- **03 split-focus** — Two columns. Left rail (~380px, sticky): greeting + quick capture +
  a search field + "ready to organize" list. Right column scrolls: stats, current chapters,
  memory, recent. Capture is always in view.
- **04 timeline-spine** — A vertical time rail down the left of the content with date nodes;
  sections hang off the spine as dated stops (Now = capture at top, then today/stats, memory as
  a dated node, recent entries as nodes, chapters as spans). Emphasize chronology.
- **05 editorial-masthead** — Magazine cover. Big serif masthead with a dateline/"issue" feel;
  the memory-of-today is a full-bleed hero cover with the title overlaid on `.mt-photo`; capture
  as an elegant bar under the masthead; below, an editorial multi-column grid — chapters as
  columns with rules, recent as a story list. Consider a drop cap.
- **06 quiet-minimal** — Extreme calm, generous whitespace, centered narrow. Greeting + capture
  front and center. Everything else compressed into one quiet line of counters
  (`3 to organize · 128 kept · 3 chapters open`), one understated memory line, and a very
  restrained recent list revealed below. Least chrome of the set.
- **07 command-center** — Search-first launcher. A large hero search bar
  (`Search your trail, or ask a question…`) with quick-jump chips (Timeline, Library, People,
  Places, First Times). Capture as a secondary card. Then a compact two-column: inbox + recent.
  Feels like a command palette landing page.
- **08 card-wall** — Masonry wall (CSS `columns`). All content as varied-height cards in 3
  columns: capture (tall, pinned first), memory (photo), two stat cards, three chapter cards,
  an inbox card, recent cards. Dense, browseable, playful but calm.
- **09 warm-hero** — A large time-of-day gradient hero banner at top (warm sunrise: mix accent +
  warm tokens) containing the greeting and an inline capture field embedded in the hero. Below
  the hero, tidy full-width rows: a stats ribbon, chapters, memory, recent in a clean grid.
- **10 context-rail** — Main canvas on the LEFT is capture + recent feed; a sticky RIGHT rail
  (~300px) holds Today context: stats, current chapters, memory, inbox count. (Mirror of 03.)
- **11 shelves** — Horizontally scrolling shelves (like a streaming home). Capture hero at top,
  then shelves: "Ready to organize", "Current chapters", "A memory for today", "Recent entries",
  each a sideways-scrolling row of cards (use `overflow-x:auto`; add faux scroll affordance).
- **12 memory-first** — The resurfaced memory is the immersive HERO at the very top: large,
  photo-forward, big serif title, overlay or split. Capture is a compact single-line bar just
  below. Then stats + chapters + recent in a modest supporting grid. Nostalgia-led.
- **13 notebook** — Skeuomorphic but refined. Warm paper surface, faint ruled lines, a margin
  rule (subtle warm line) like a legal pad; the capture area reads as writing on the page;
  notebook-divider "tabs" for Today / Chapters / Recent. Serif, tactile, still calm.
- **14 three-panel** — Three equal full-height columns, each scrolls independently: Panel 1
  "Capture" (greeting + capture + inbox), Panel 2 "Living now" (stats + current chapters +
  memory), Panel 3 "Recent" (the recent list). Thin dividers between panels. On narrow widths
  they stack.
- **15 big-type** — Oversized editorial typography. Greeting rendered very large (display++),
  one big summarizing sentence (`Three things waiting, three chapters open, and one memory from
  two years ago.`). Capture below as a wide clean field. Minimal cards; type carries the page.
  Memory + recent rendered as spare typographic lists.
- **16 scratchpad** — Quick capture lives as a persistent RIGHT scratchpad panel (full height,
  distinct raised surface, like a sticky notepad) always ready, with the 3 pending captures
  listed beneath the composer as a working desk. Main LEFT area is the archive: greeting, stats,
  chapters, memory, recent.
- **17 chapters-spotlight** — Current chapters are the hero: three large cover cards with
  `.mt-photo` backgrounds and overlaid kind/title/dates in a prominent row up top. Capture as a
  bar below. Then memory + recent + inbox in a supporting grid. Life-stages-led.
- **18 data-ribbon** — A thin metrics ribbon spans the very top (chapters 3 · entries 128 ·
  First Times 12 · Collections 7 · to organize 3). Then a balanced two-column body: left =
  capture + inbox + recent; right = memory + chapters. Calm analytics header, editorial body.
- **19 floating-capture** — Content-first single-column feed (greeting + memory hero + recent +
  chapters + a compact inbox strip), with the quick capture as a prominent FLOATING composer bar
  docked bottom-center (position: fixed, above the switcher which sits at bottom:20px — so dock
  yours higher, around bottom: 84px, and add bottom padding to the feed so nothing is hidden).
  The floating capture is the signature move.
- **20 bento-pro** — The premium, most-produced concept. A refined asymmetric bento grid:
  capture is the largest tile (spans 2 rows, top-left), memory is a large photo tile (top-right),
  plus stat tiles, chapter tiles, an inbox tile, and a recent tile — varied sizes, cohesive,
  magazine-quality. This should feel like the polished flagship.

## Quality bar

- Calm, archival, generous spacing. Serif headings, sans body. Rounded corners via radius
  tokens. Hairline borders (`--mt-color-border`). Subtle shadows only where it helps.
- Works in light and dark (tokens handle it; don't fight them).
- The capture composer stays obviously the primary action on every page.
- No lorem ipsum — use the canonical content above.
