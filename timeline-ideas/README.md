# Timeline design explorations

## How to run

These are plain, dependency-free HTML files - no build step and nothing to
install.

**View a single design (quickest):** open any `NN-*.html` file directly in your
browser - double-click it in your file manager, or drag it into a browser window.
Every individual design works fine straight from disk.

**View the gallery (`index.html`):** the gallery loads each design in a live
preview frame, and browsers block those frames when a page is opened straight from
disk (`file://`), so the thumbnails come up blank. Serve the folder over a local
web server instead:

```bash
cd timeline-ideas
python3 -m http.server 8000
```

Then open <http://localhost:8000/> in your browser. Any static server works - for
example `npx serve` from the repo root, then open the printed URL and navigate to
`/timeline-ideas/`.

## About these designs

Twenty standalone HTML mockups exploring how MemoTrail could visualize a life
timeline from **birth to the present** - with **events** (points in time),
**stages** (spans), **milestones** (pivotal moments), and multiple **tracks**
(Career, Home, Relationships, Travel, Health).

These are **throwaway prototypes** for picking a direction. They intentionally
ignore the app's current styling and have **no external dependencies** (no CDNs,
fonts, or remote images).

## The 20 concepts

| #  | File | Concept |
|----|------|---------|
| 01 | `01-vertical-spine.html` | Classic vertical center spine, alternating cards |
| 02 | `02-horizontal-river.html` | Horizontal scrolling river path |
| 03 | `03-swimlane-gantt.html` | Multi-track swimlane Gantt with year/age axis |
| 04 | `04-spiral-of-life.html` | Spiral from birth (center) to present (edge) |
| 05 | `05-metro-map.html` | Subway/metro map; tracks as lines, milestones as interchanges |
| 06 | `06-year-heatmap.html` | GitHub-style years heatmap grid |
| 07 | `07-sticky-year-feed.html` | Social feed with a sticky, scroll-synced year |
| 08 | `08-chapters-book.html` | Life as a book of eras with collapsible chapters |
| 09 | `09-constellation.html` | Night-sky star map; tracks as constellations |
| 10 | `10-mountain-elevation.html` | Elevation profile; peaks and valleys of life |
| 11 | `11-tree-of-life.html` | Growing tree; branches as tracks, fruit as events |
| 12 | `12-filmstrip-reel.html` | Cinematic film reel of moments |
| 13 | `13-age-rings.html` | Tree-ring cross-section; one ring per year of age |
| 14 | `14-split-mirror.html` | Personal vs professional, mirrored across one axis |
| 15 | `15-roadmap-journey.html` | Winding roadmap with milestone signposts |
| 16 | `16-life-dashboard.html` | "Life in numbers" analytics dashboard |
| 17 | `17-scrapbook-polaroid.html` | Scattered Polaroid scrapbook wall |
| 18 | `18-minimal-typographic.html` | Ultra-minimal typographic index |
| 19 | `19-ruler-zoom.html` | Precision ruler axis with zoom + scrubber |
| 20 | `20-radial-now.html` | Radial life-progress gauge centered on now |

## Shared sample data

Every design uses the same fictional life - **Ava Chen**, born March 14, 1990 in
Portland, present year 2025 - so the concepts are directly comparable. The events
span career, homes, relationships, travel, and hobbies, and include a few
approximate ("~2014") dates to show date-precision handling.
