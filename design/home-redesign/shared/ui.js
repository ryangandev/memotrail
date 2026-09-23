/* Shared chrome for the home-redesign mockups.
   Classic script (works over file://). Wraps the page's <main class="mt-main">
   with the MemoTrail sidebar + top bar, and adds a concept switcher so all 20
   layouts can be compared quickly. The design content lives in each concept's
   <main>; if this script is ever blocked, that content still renders on its own. */
(function () {
  "use strict";

  var CONCEPTS = [
    { file: "01-ledger-column.html", title: "01 · Ledger Column" },
    { file: "02-today-dashboard.html", title: "02 · Today Dashboard" },
    { file: "03-split-focus.html", title: "03 · Split Focus" },
    { file: "04-timeline-spine.html", title: "04 · Timeline Spine" },
    { file: "05-editorial-masthead.html", title: "05 · Editorial Masthead" },
    { file: "06-quiet-minimal.html", title: "06 · Quiet Minimal" },
    { file: "07-command-center.html", title: "07 · Command Center" },
    { file: "08-card-wall.html", title: "08 · Card Wall" },
    { file: "09-warm-hero.html", title: "09 · Warm Greeting Hero" },
    { file: "10-context-rail.html", title: "10 · Context Rail" },
    { file: "11-shelves.html", title: "11 · Horizontal Shelves" },
    { file: "12-memory-first.html", title: "12 · Memory First" },
    { file: "13-notebook.html", title: "13 · Notebook" },
    { file: "14-three-panel.html", title: "14 · Three Panel" },
    { file: "15-big-type.html", title: "15 · Big Type Statement" },
    { file: "16-scratchpad.html", title: "16 · Scratchpad Sidebar" },
    { file: "17-chapters-spotlight.html", title: "17 · Chapters Spotlight" },
    { file: "18-data-ribbon.html", title: "18 · Data Ribbon" },
    { file: "19-floating-capture.html", title: "19 · Floating Capture" },
    { file: "20-bento-pro.html", title: "20 · Bento Pro" }
  ];

  var NAV = [
    { key: "home", label: "Home", icon: "ico-home" },
    { key: "timeline", label: "Timeline", icon: "ico-timeline" },
    { key: "library", label: "Library", icon: "ico-book" },
    { key: "search", label: "Search", icon: "ico-search" }
  ];

  var NAV_FOCUSED = [
    { key: "collections", label: "Collections", icon: "ico-layers" },
    { key: "people", label: "People", icon: "ico-users" },
    { key: "places", label: "Places", icon: "ico-map" },
    { key: "tags", label: "Tags", icon: "ico-tag" }
  ];

  function el(tag, cls, html) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (html != null) node.innerHTML = html;
    return node;
  }

  function icon(name) {
    return '<span class="ico ' + name + '" aria-hidden="true"></span>';
  }

  function navLink(item, active) {
    var badge = item.key === "inbox" ? "<small>3</small>" : "";
    return (
      '<a href="#" class="' + (item.key === active ? "is-active" : "") + '">' +
      icon(item.icon) + "<span>" + item.label + "</span>" + badge + "</a>"
    );
  }

  function buildSidebar(active) {
    var side = el("aside", "mt-sidebar");
    var brand =
      '<a class="mt-brand" href="index.html">' +
      '<span class="mt-brand-mark">M</span><span>MemoTrail</span></a>';

    var nav = '<nav class="mt-nav"><div class="mt-nav-group">';
    NAV.forEach(function (i) { nav += navLink(i, active); });
    nav += "</div>";
    nav += '<p class="mt-nav-label">Focused views</p><div class="mt-nav-group">';
    NAV_FOCUSED.forEach(function (i) { nav += navLink(i, active); });
    nav += "</div></nav>";

    var foot =
      '<div class="mt-sidebar-foot"><span class="mt-avatar">RG</span>' +
      "<div><strong>Ryan Gan</strong><small>Private archive</small></div></div>";

    side.innerHTML = brand + nav + foot;
    return side;
  }

  function buildTopbar(pageName) {
    var bar = el("header", "mt-topbar");
    bar.innerHTML =
      '<div class="mt-top-leading">' +
      '<button class="mt-top-btn mt-top-btn--new">' + icon("ico-plus") +
      '<span class="mt-top-btn-label">New</span><kbd>J</kbd></button>' +
      (pageName ? '<span class="mt-page-name">' + pageName + "</span>" : "") +
      "</div>" +
      '<div class="mt-top-actions">' +
      '<button class="mt-top-btn">' + icon("ico-search") +
      '<span class="mt-top-btn-label">Search</span><kbd>K</kbd></button>' +
      '<button class="mt-top-btn mt-top-btn--icon" aria-label="Inbox">' +
      icon("ico-inbox") + '<span class="mt-badge">3</span></button>' +
      "</div>";
    return bar;
  }

  function currentIndex() {
    var path = location.pathname.split("/").pop();
    for (var i = 0; i < CONCEPTS.length; i++) {
      if (CONCEPTS[i].file === path) return i;
    }
    return -1;
  }

  function buildSwitcher() {
    var idx = currentIndex();
    if (idx === -1) return null;

    var wrap = el("div", "mt-switcher");
    var inner = el("div", "mt-switcher-inner");

    var home = el("a", "mt-switcher-home");
    home.href = "index.html";
    home.title = "All concepts";
    home.innerHTML = icon("ico-grid");

    var prev = el("a", "mt-switcher-nav" + (idx <= 0 ? " is-disabled" : ""));
    prev.innerHTML = icon("ico-chevron");
    prev.style.transform = "rotate(180deg)";
    if (idx > 0) prev.href = CONCEPTS[idx - 1].file;

    var label = el("span", "mt-switcher-index",
      String(idx + 1).padStart(2, "0") + " / " + CONCEPTS.length);

    var select = el("select");
    CONCEPTS.forEach(function (c, i) {
      var opt = el("option", null, c.title);
      opt.value = c.file;
      if (i === idx) opt.selected = true;
      select.appendChild(opt);
    });
    select.addEventListener("change", function () {
      location.href = select.value;
    });

    var next = el("a", "mt-switcher-nav" + (idx >= CONCEPTS.length - 1 ? " is-disabled" : ""));
    next.innerHTML = icon("ico-chevron");
    if (idx < CONCEPTS.length - 1) next.href = CONCEPTS[idx + 1].file;

    inner.appendChild(home);
    inner.appendChild(prev);
    inner.appendChild(label);
    inner.appendChild(select);
    inner.appendChild(next);
    wrap.appendChild(inner);

    document.addEventListener("keydown", function (e) {
      if (e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
      if (e.key === "ArrowRight" && idx < CONCEPTS.length - 1) {
        location.href = CONCEPTS[idx + 1].file;
      } else if (e.key === "ArrowLeft" && idx > 0) {
        location.href = CONCEPTS[idx - 1].file;
      }
    });

    return wrap;
  }

  function mount() {
    var main = document.querySelector("main.mt-main");
    if (!main) return;

    var active = document.body.getAttribute("data-nav") || "home";
    var pageName = document.body.getAttribute("data-page-name") || "";

    var shell = el("div", "mt-shell");
    var workspace = el("div", "mt-workspace");

    shell.appendChild(buildSidebar(active));
    workspace.appendChild(buildTopbar(pageName));

    // move main into the workspace without losing it
    main.parentNode.insertBefore(shell, main);
    workspace.appendChild(main);
    shell.appendChild(workspace);

    var switcher = buildSwitcher();
    if (switcher) document.body.appendChild(switcher);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
})();
