/* Floating design navigator for the timeline-ideas mockups.
   Classic script (works over file:// and a local server). Each design page opts
   in with a single tag before </body>:  <script src="shared/nav.js" defer></script>
   It injects a theme-agnostic pill (gallery · prev · index/title · next) fixed at
   the bottom, and a hover/focus popover listing all 20 designs so you can jump to
   any of them. Arrow keys move between designs. If this script is ever blocked,
   the design itself still renders on its own. */
(function () {
  "use strict";

  var DESIGNS = [
    { file: "01-vertical-spine.html", n: "01", title: "Vertical Spine", cat: "Vertical & Feed" },
    { file: "02-horizontal-river.html", n: "02", title: "Horizontal River", cat: "Horizontal & Tracks" },
    { file: "03-swimlane-gantt.html", n: "03", title: "Swimlane Gantt", cat: "Horizontal & Tracks" },
    { file: "04-spiral-of-life.html", n: "04", title: "Spiral of Life", cat: "Creative Metaphor" },
    { file: "05-metro-map.html", n: "05", title: "Metro Map", cat: "Creative Metaphor" },
    { file: "06-year-heatmap.html", n: "06", title: "Years Heatmap", cat: "Data & Playful" },
    { file: "07-sticky-year-feed.html", n: "07", title: "Sticky-Year Feed", cat: "Vertical & Feed" },
    { file: "08-chapters-book.html", n: "08", title: "Chapters (Book)", cat: "Vertical & Feed" },
    { file: "09-constellation.html", n: "09", title: "Constellation", cat: "Creative Metaphor" },
    { file: "10-mountain-elevation.html", n: "10", title: "Elevation Profile", cat: "Data & Playful" },
    { file: "11-tree-of-life.html", n: "11", title: "Tree of Life", cat: "Creative Metaphor" },
    { file: "12-filmstrip-reel.html", n: "12", title: "Filmstrip Reel", cat: "Horizontal & Tracks" },
    { file: "13-age-rings.html", n: "13", title: "Age Rings", cat: "Creative Metaphor" },
    { file: "14-split-mirror.html", n: "14", title: "Split Mirror", cat: "Vertical & Feed" },
    { file: "15-roadmap-journey.html", n: "15", title: "Winding Roadmap", cat: "Horizontal & Tracks" },
    { file: "16-life-dashboard.html", n: "16", title: "Life Dashboard", cat: "Data & Playful" },
    { file: "17-scrapbook-polaroid.html", n: "17", title: "Scrapbook Wall", cat: "Data & Playful" },
    { file: "18-minimal-typographic.html", n: "18", title: "Minimal Type", cat: "Vertical & Feed" },
    { file: "19-ruler-zoom.html", n: "19", title: "Precision Ruler", cat: "Horizontal & Tracks" },
    { file: "20-radial-now.html", n: "20", title: "Radial Now Gauge", cat: "Data & Playful" }
  ];

  var CAT_COLOR = {
    "Vertical & Feed": "#7c9cff",
    "Horizontal & Tracks": "#f0a868",
    "Creative Metaphor": "#c58cf0",
    "Data & Playful": "#67e8c3"
  };

  function currentIndex() {
    var path = (location.pathname.split("/").pop() || "").toLowerCase();
    for (var i = 0; i < DESIGNS.length; i++) {
      if (DESIGNS[i].file.toLowerCase() === path) return i;
    }
    return -1;
  }

  var CSS =
    ".tlnav{position:fixed;left:0;right:0;bottom:20px;z-index:2147483000;display:flex;" +
    "justify-content:center;pointer-events:none;" +
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;}" +
    ".tlnav *{box-sizing:border-box;}" +
    ".tlnav-hit{pointer-events:auto;display:flex;flex-direction:column;align-items:stretch;" +
    "gap:8px;max-width:calc(100vw - 24px);}" +
    /* pill */
    ".tlnav-bar{display:flex;align-items:center;gap:6px;padding:6px;border-radius:999px;" +
    "background:rgba(17,20,27,0.82);border:1px solid rgba(255,255,255,0.14);" +
    "box-shadow:0 12px 34px rgba(0,0,0,0.45);backdrop-filter:blur(14px);" +
    "-webkit-backdrop-filter:blur(14px);color:#f3f5fa;}" +
    ".tlnav-btn{appearance:none;-webkit-appearance:none;display:grid;place-items:center;" +
    "width:34px;height:34px;border-radius:50%;border:1px solid rgba(255,255,255,0.16);" +
    "background:rgba(255,255,255,0.06);color:#f3f5fa;text-decoration:none;cursor:pointer;" +
    "padding:0;transition:background .15s ease,border-color .15s ease,opacity .15s ease;}" +
    ".tlnav-btn:hover{background:rgba(255,255,255,0.16);border-color:rgba(255,255,255,0.32);}" +
    ".tlnav-btn:focus-visible{outline:2px solid #8aa4ff;outline-offset:2px;}" +
    ".tlnav-btn svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;" +
    "stroke-linecap:round;stroke-linejoin:round;}" +
    ".tlnav-btn.is-disabled{opacity:.32;pointer-events:none;}" +
    ".tlnav-gallery{background:rgba(124,156,255,0.22);border-color:rgba(124,156,255,0.5);color:#dbe4ff;}" +
    ".tlnav-label{display:flex;align-items:baseline;gap:8px;padding:0 8px;min-width:0;cursor:default;}" +
    ".tlnav-index{font-size:12px;font-weight:700;letter-spacing:.04em;color:#aab3c5;" +
    "font-variant-numeric:tabular-nums;white-space:nowrap;}" +
    ".tlnav-title{font-size:13px;font-weight:600;white-space:nowrap;overflow:hidden;" +
    "text-overflow:ellipsis;max-width:40vw;}" +
    ".tlnav-cat-dot{width:8px;height:8px;border-radius:50%;flex:none;align-self:center;}" +
    /* popover list */
    ".tlnav-panel{max-height:0;overflow:hidden;opacity:0;transform:translateY(8px);" +
    "transition:max-height .22s ease,opacity .18s ease,transform .18s ease;" +
    "border-radius:16px;background:rgba(17,20,27,0.92);border:1px solid rgba(255,255,255,0.14);" +
    "box-shadow:0 18px 48px rgba(0,0,0,0.5);backdrop-filter:blur(16px);" +
    "-webkit-backdrop-filter:blur(16px);color:#f3f5fa;pointer-events:none;}" +
    ".tlnav-hit:hover .tlnav-panel,.tlnav-hit:focus-within .tlnav-panel,.tlnav-hit.is-open .tlnav-panel{" +
    "max-height:min(62vh,560px);opacity:1;transform:translateY(0);pointer-events:auto;}" +
    ".tlnav-panel-inner{max-height:min(62vh,560px);overflow:auto;padding:10px;}" +
    ".tlnav-panel-head{display:flex;align-items:center;justify-content:space-between;gap:12px;" +
    "padding:4px 8px 10px;border-bottom:1px solid rgba(255,255,255,0.1);margin-bottom:8px;}" +
    ".tlnav-panel-title{font-size:12px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:#9aa3b2;}" +
    ".tlnav-panel-hint{font-size:11px;color:#8b93a3;font-variant-numeric:tabular-nums;}" +
    ".tlnav-grid{display:grid;grid-template-columns:1fr 1fr;gap:4px;}" +
    ".tlnav-item{display:flex;align-items:center;gap:9px;padding:8px 10px;border-radius:10px;" +
    "text-decoration:none;color:#e8ebf1;border:1px solid transparent;}" +
    ".tlnav-item:hover{background:rgba(255,255,255,0.08);}" +
    ".tlnav-item.is-current{background:rgba(124,156,255,0.16);border-color:rgba(124,156,255,0.4);}" +
    ".tlnav-item-n{font-size:11px;font-weight:700;color:#aab3c5;font-variant-numeric:tabular-nums;width:18px;flex:none;}" +
    ".tlnav-item-t{font-size:12.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}" +
    ".tlnav-item-dot{width:7px;height:7px;border-radius:50%;flex:none;margin-left:auto;}" +
    "@media (max-width:640px){.tlnav-grid{grid-template-columns:1fr;}.tlnav-title{display:none;}}" +
    "@media (prefers-reduced-motion:reduce){.tlnav-panel{transition:none;}.tlnav-btn{transition:none;}}";

  function svg(paths) {
    return '<svg viewBox="0 0 24 24" aria-hidden="true">' + paths + "</svg>";
  }
  var ICON_PREV = svg('<polyline points="15 6 9 12 15 18"/>');
  var ICON_NEXT = svg('<polyline points="9 6 15 12 9 18"/>');
  var ICON_GRID = svg('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>');

  function mount() {
    var idx = currentIndex();
    if (idx === -1) return; // not a numbered design page (e.g. the gallery)

    var cur = DESIGNS[idx];
    var prev = idx > 0 ? DESIGNS[idx - 1] : null;
    var next = idx < DESIGNS.length - 1 ? DESIGNS[idx + 1] : null;

    var style = document.createElement("style");
    style.textContent = CSS;
    document.head.appendChild(style);

    var root = document.createElement("nav");
    root.className = "tlnav";
    root.setAttribute("aria-label", "Timeline design navigator");

    // Build the jump list (two columns, numeric order, category color dot).
    var items = "";
    for (var i = 0; i < DESIGNS.length; i++) {
      var d = DESIGNS[i];
      var color = CAT_COLOR[d.cat] || "#8aa4ff";
      items +=
        '<a class="tlnav-item' + (i === idx ? " is-current" : "") + '" href="' + d.file + '"' +
        (i === idx ? ' aria-current="true"' : "") + ' title="' + d.cat + '">' +
        '<span class="tlnav-item-n">' + d.n + "</span>" +
        '<span class="tlnav-item-t">' + d.title + "</span>" +
        '<span class="tlnav-item-dot" style="background:' + color + '"></span></a>';
    }

    var curColor = CAT_COLOR[cur.cat] || "#8aa4ff";

    root.innerHTML =
      '<div class="tlnav-hit">' +
      '<div class="tlnav-panel" role="menu">' +
      '<div class="tlnav-panel-inner">' +
      '<div class="tlnav-panel-head">' +
      '<span class="tlnav-panel-title">All 20 designs</span>' +
      '<span class="tlnav-panel-hint">' + (idx + 1) + " / " + DESIGNS.length + "</span></div>" +
      '<div class="tlnav-grid">' + items + "</div>" +
      "</div></div>" +
      '<div class="tlnav-bar">' +
      '<a class="tlnav-btn tlnav-gallery" href="index.html" title="Back to gallery" aria-label="Back to gallery">' + ICON_GRID + "</a>" +
      '<a class="tlnav-btn tlnav-prev' + (prev ? "" : " is-disabled") + '"' +
      (prev ? ' href="' + prev.file + '"' : "") + ' title="Previous design" aria-label="Previous design">' + ICON_PREV + "</a>" +
      '<span class="tlnav-label"><span class="tlnav-cat-dot" style="background:' + curColor + '"></span>' +
      '<span class="tlnav-index">' + cur.n + " / " + DESIGNS.length + "</span>" +
      '<span class="tlnav-title">' + cur.title + "</span></span>" +
      '<a class="tlnav-btn tlnav-next' + (next ? "" : " is-disabled") + '"' +
      (next ? ' href="' + next.file + '"' : "") + ' title="Next design" aria-label="Next design">' + ICON_NEXT + "</a>" +
      "</div></div>";

    document.body.appendChild(root);

    // Touch/click support: tap the gallery-adjacent label toggles the list open.
    var hit = root.querySelector(".tlnav-hit");
    var label = root.querySelector(".tlnav-label");
    label.style.cursor = "pointer";
    label.setAttribute("tabindex", "0");
    label.setAttribute("role", "button");
    label.setAttribute("aria-label", "Show all designs");
    function toggle() { hit.classList.toggle("is-open"); }
    label.addEventListener("click", toggle);
    label.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); }
    });
    document.addEventListener("click", function (e) {
      if (!root.contains(e.target)) hit.classList.remove("is-open");
    });

    // Keyboard: left/right arrows move between designs; Esc closes the list.
    document.addEventListener("keydown", function (e) {
      var t = e.target;
      if (t && /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)) return;
      if (t && t.isContentEditable) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "ArrowRight" && next) { location.href = next.file; }
      else if (e.key === "ArrowLeft" && prev) { location.href = prev.file; }
      else if (e.key === "Escape") { hit.classList.remove("is-open"); }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
})();
