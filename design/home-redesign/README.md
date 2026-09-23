# Home page redesign — concept exploration

Static, self-contained HTML mockups exploring a reconceived MemoTrail **Home** page.
Today's Home is essentially the Inbox; these explore what Home could be while **keeping
Quick Capture** as the anchor of every layout.

These are design explorations only — not wired into the Next.js app.

## View them

Open [`index.html`](./index.html) in a browser to see all 20 concepts. Open any concept and
use the **← / → arrow keys** or the **switcher pill** at the bottom to move between them. The
individual concept pages open fine by double-clicking (`file://`).

The gallery's live thumbnails are `<iframe>`s, and some browsers block `file://` iframes, so
if the thumbnails look blank, serve the folder over `http://` instead. From this directory:

```bash
python3 -m http.server 4599
```

Then open <http://localhost:4599/>. (A tiny Node equivalent is included at
`shared/preview-server.js` if you prefer: `node shared/preview-server.js`.)

The files use a tiny classic script (`shared/ui.js`) to inject the shared sidebar/top bar and
the switcher. If scripts are blocked, each concept's core layout still renders on its own.

## What's shared

- `shared/tokens.css` — the "Soft Ledger" design tokens, mirrored from
  `apps/web/src/styles/generated-tokens.css` (light + dark).
- `shared/frame.css` — reset, the injected app chrome, a CSS-mask icon set, and reusable
  primitives (`.mt-capture`, `.mt-section-head`, `.mt-chip`, `.mt-photo`, `.mt-btn`, …).
- `shared/ui.js` — injects the sidebar, top bar, and concept switcher around each `<main>`.
- `shared/_BRIEF.md` — the build brief and canonical sample content used across all concepts.
- Photos are represented by the `.mt-photo` CSS gradient so everything stays offline.

## The 20 concepts

| # | Concept | Idea |
|---|---------|------|
| 01 | Ledger Column | One calm centered column, entries stacked like a paper ledger |
| 02 | Today Dashboard | A bento of tiles — everything visible at a glance |
| 03 | Split Focus | Sticky left rail keeps Capture + inbox in view; archive scrolls right |
| 04 | Timeline Spine | A vertical time rail; sections hang off it as dated stops |
| 05 | Editorial Masthead | Magazine cover with a full-bleed memory hero |
| 06 | Quiet Minimal | Radical calm — greeting, Capture, one line of counters |
| 07 | Command Center | Search-first launcher with quick-jump chips |
| 08 | Card Wall | A masonry wall of mixed cards to browse |
| 09 | Warm Greeting Hero | A time-of-day gradient banner with inline Capture |
| 10 | Context Rail | Content left, sticky context rail on the right |
| 11 | Horizontal Shelves | Streaming-style shelves that scroll sideways |
| 12 | Memory First | The resurfaced memory as an immersive hero |
| 13 | Notebook | A warm ruled page with a margin line and tabs |
| 14 | Three Panel | Three independently scrolling columns |
| 15 | Big Type Statement | Oversized typography states the day in words |
| 16 | Scratchpad Sidebar | A persistent right notepad panel for Capture |
| 17 | Chapters Spotlight | Current life chapters as large cover cards |
| 18 | Data Ribbon | A thin metrics ribbon over a two-column body |
| 19 | Floating Capture | A content feed with Capture docked as a floating bar |
| 20 | Bento Pro | The flagship — a refined asymmetric bento |

## Picking one

Once a direction is chosen, the next step is to rebuild the real
[`apps/web/src/app/page.tsx`](../../apps/web/src/app/page.tsx) and
[`home.module.css`](../../apps/web/src/app/home.module.css) around it, keeping the existing
`CaptureComposer`, `getHomeWorkspace` data, and resurfacing rules from
[`docs/product.md`](../../docs/product.md) ("Timeline and Home").
