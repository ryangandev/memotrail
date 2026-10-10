// Generated from packages/design-system. Do not edit directly.

/** Semantic icon names drawn on Web, from packages/design-system/icons.json. */
export const iconNames = [
  "archive",
  "arrowLeft",
  "arrowRight",
  "bold",
  "bulletList",
  "calendar",
  "car",
  "check",
  "chevron",
  "chevronDown",
  "clock",
  "close",
  "code",
  "codeBlock",
  "copy",
  "dashboard",
  "edit",
  "home",
  "inbox",
  "italic",
  "link",
  "map",
  "mic",
  "more",
  "orderedList",
  "photo",
  "plus",
  "quote",
  "refresh",
  "search",
  "settings",
  "sidebarClosed",
  "sidebarOpen",
  "sparkle",
  "star",
  "stop",
  "strike",
  "tag",
  "target",
  "timeline",
  "trash",
  "underline",
] as const;

export type IconName = (typeof iconNames)[number];

export type IconElement = readonly [
  tag: "path" | "circle" | "rect",
  attributes: Readonly<Record<string, string>>,
];

export const iconViewBox = "0 0 24 24";

export const iconStrokeWidth = 1.7;

/** Icon sizes in px. An icon's size must be one of these, so it stays on the size.icon scale. */
export const iconSizes = {
  7: 7,
  8: 8,
  10: 10,
  11: 11,
  12: 12,
  13: 13,
  14: 14,
  15: 15,
  16: 16,
  17: 17,
  18: 18,
  19: 19,
  20: 20,
  21: 21,
  22: 22,
  23: 23,
  24: 24,
  25: 25,
  30: 30,
} as const;

export type IconSize = keyof typeof iconSizes;

export type IconElements = Readonly<Record<IconName, readonly IconElement[]>>;

export const iconElements: IconElements = {
  archive: [
    ["path", { d: "M4 8.5h16v11H4z" }],
    ["path", { d: "M3 4.5h18v4H3zM9 13h6" }],
  ],
  arrowLeft: [["path", { d: "M20 12H4m0 0 7-7m-7 7 7 7" }]],
  arrowRight: [["path", { d: "M4 12h16m0 0-7-7m7 7-7 7" }]],
  bold: [
    ["path", { d: "M7 4h6a4 4 0 0 1 0 8H7V4Z" }],
    ["path", { d: "M7 12h7a4 4 0 0 1 0 8H7v-8Z" }],
  ],
  bulletList: [
    [
      "circle",
      { cx: "5", cy: "7", fill: "currentColor", r: "1", stroke: "none" },
    ],
    [
      "circle",
      { cx: "5", cy: "12", fill: "currentColor", r: "1", stroke: "none" },
    ],
    [
      "circle",
      { cx: "5", cy: "17", fill: "currentColor", r: "1", stroke: "none" },
    ],
    ["path", { d: "M9 7h10M9 12h10M9 17h10" }],
  ],
  calendar: [
    ["rect", { height: "17", rx: "2", width: "18", x: "3", y: "4" }],
    ["path", { d: "M8 2v4M16 2v4M3 9h18" }],
  ],
  car: [
    [
      "path",
      { d: "m5 11 1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11" },
    ],
    [
      "path",
      {
        d: "M4 11h16a1 1 0 0 1 1 1v5H3v-5a1 1 0 0 1 1-1ZM6 17v2M18 17v2M6.5 14h1M16.5 14h1",
      },
    ],
  ],
  check: [["path", { d: "m5 12 4 4L19 6" }]],
  chevron: [["path", { d: "m9 18 6-6-6-6" }]],
  chevronDown: [["path", { d: "m7 10 5 5 5-5" }]],
  clock: [
    ["circle", { cx: "12", cy: "12", r: "9" }],
    ["path", { d: "M12 7v5l3 2" }],
  ],
  close: [["path", { d: "m7 7 10 10M17 7 7 17" }]],
  code: [["path", { d: "m8 8-4 4 4 4M16 8l4 4-4 4M14 5l-4 14" }]],
  codeBlock: [
    ["rect", { height: "18", rx: "2", width: "20", x: "2", y: "3" }],
    ["path", { d: "m9 8-4 4 4 4M15 8l4 4-4 4" }],
  ],
  copy: [
    ["rect", { height: "12", rx: "2", width: "12", x: "9", y: "9" }],
    ["path", { d: "M15 9V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h4" }],
  ],
  dashboard: [
    ["rect", { height: "7", rx: "1", width: "7", x: "3", y: "3" }],
    ["rect", { height: "7", rx: "1", width: "7", x: "14", y: "3" }],
    ["rect", { height: "7", rx: "1", width: "7", x: "3", y: "14" }],
    ["rect", { height: "7", rx: "1", width: "7", x: "14", y: "14" }],
  ],
  edit: [
    [
      "path",
      { d: "M20 12.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7" },
    ],
    [
      "path",
      { d: "m10 14 1.8-4.4L18.7 2.7a2.1 2.1 0 0 1 3 3l-6.9 6.9L10 14Z" },
    ],
  ],
  home: [
    ["path", { d: "m3.5 10.5 8.5-7 8.5 7" }],
    ["path", { d: "M5.5 9v11h13V9M9.5 20v-6h5v6" }],
  ],
  inbox: [
    ["path", { d: "M4.5 5.5h15l1.5 9v4H3v-4l1.5-9Z" }],
    ["path", { d: "M3 14.5h5l1.5 2h5l1.5-2h5" }],
  ],
  italic: [["path", { d: "M10 4h8M6 20h8M14 4l-4 16" }]],
  link: [
    ["path", { d: "m9.5 14.5-1 1a4 4 0 0 1-5.7-5.7l3-3a4 4 0 0 1 5.7 0" }],
    [
      "path",
      { d: "m14.5 9.5 1-1a4 4 0 0 1 5.7 5.7l-3 3a4 4 0 0 1-5.7 0M8.5 12h7" },
    ],
  ],
  map: [
    ["path", { d: "m3.5 6.5 5-2 7 2 5-2v13l-5 2-7-2-5 2v-13Z" }],
    ["path", { d: "M8.5 4.5v13M15.5 6.5v13" }],
  ],
  mic: [
    ["rect", { height: "12", rx: "4", width: "7", x: "8.5", y: "2.5" }],
    ["path", { d: "M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6" }],
  ],
  more: [
    [
      "circle",
      { cx: "5", cy: "12", fill: "currentColor", r: "1", stroke: "none" },
    ],
    [
      "circle",
      { cx: "12", cy: "12", fill: "currentColor", r: "1", stroke: "none" },
    ],
    [
      "circle",
      { cx: "19", cy: "12", fill: "currentColor", r: "1", stroke: "none" },
    ],
  ],
  orderedList: [
    [
      "path",
      {
        d: "M10 7h10M10 12h10M10 17h10M4 5h1v4M4 11h2l-2 3h2M4 16h2l-1.5 1.5A1 1 0 0 1 6 19H4",
      },
    ],
  ],
  photo: [
    ["rect", { height: "16", rx: "2", width: "18", x: "3", y: "4" }],
    ["circle", { cx: "8.5", cy: "9", r: "1.5" }],
    ["path", { d: "m5.5 17 4-4 3 3 2-2 4 3" }],
  ],
  plus: [["path", { d: "M12 5v14M5 12h14" }]],
  quote: [
    ["path", { d: "M5 10h5v5H5v-4a5 5 0 0 1 5-5" }],
    ["path", { d: "M14 10h5v5h-5v-4a5 5 0 0 1 5-5" }],
  ],
  refresh: [
    ["path", { d: "M19 8a7.5 7.5 0 0 0-12.6-2L4 8" }],
    ["path", { d: "M4 4v4h4M5 16a7.5 7.5 0 0 0 12.6 2L20 16" }],
    ["path", { d: "M20 20v-4h-4" }],
  ],
  search: [
    ["circle", { cx: "10.5", cy: "10.5", r: "6.5" }],
    ["path", { d: "m15.5 15.5 5 5" }],
  ],
  settings: [
    ["circle", { cx: "12", cy: "12", r: "3" }],
    [
      "path",
      {
        d: "M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z",
      },
    ],
  ],
  sidebarClosed: [
    ["rect", { height: "17", rx: "2", width: "18", x: "3", y: "3.5" }],
    ["path", { d: "M9 3.5v17" }],
    [
      "circle",
      { cx: "6", cy: "8", fill: "currentColor", r: "0.8", stroke: "none" },
    ],
    [
      "circle",
      { cx: "6", cy: "12", fill: "currentColor", r: "0.8", stroke: "none" },
    ],
    [
      "circle",
      { cx: "6", cy: "16", fill: "currentColor", r: "0.8", stroke: "none" },
    ],
  ],
  sidebarOpen: [
    ["rect", { height: "17", rx: "2", width: "18", x: "3", y: "3.5" }],
    ["path", { d: "M9 3.5v17" }],
  ],
  sparkle: [
    [
      "path",
      {
        d: "M12 3c.7 4.4 3.2 6.9 7 7.5-3.8.6-6.3 3.1-7 7.5-.7-4.4-3.2-6.9-7-7.5 3.8-.6 6.3-3.1 7-7.5Z",
      },
    ],
  ],
  star: [
    [
      "path",
      {
        d: "m12 3 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9L12 3Z",
      },
    ],
  ],
  stop: [
    [
      "rect",
      {
        fill: "currentColor",
        height: "10",
        rx: "1.5",
        stroke: "none",
        width: "10",
        x: "7",
        y: "7",
      },
    ],
  ],
  strike: [
    [
      "path",
      {
        d: "M5 12h14M16.5 7.5A4.5 4.5 0 0 0 12 5c-2.2 0-4 1.2-4 3 0 1 .6 1.7 1.6 2.2M8 16c.8 1.8 2.4 3 4.6 3 2.4 0 4.4-1.3 4.4-3.3 0-.7-.2-1.2-.6-1.7",
      },
    ],
  ],
  tag: [
    ["path", { d: "M4 4h7.5L20 12.5 12.5 20 4 11.5V4Z" }],
    ["circle", { cx: "8.2", cy: "8.2", r: "1.25" }],
  ],
  target: [
    ["circle", { cx: "12", cy: "12", r: "8.5" }],
    ["circle", { cx: "12", cy: "12", r: "4.5" }],
    [
      "circle",
      { cx: "12", cy: "12", fill: "currentColor", r: "1", stroke: "none" },
    ],
  ],
  timeline: [
    ["path", { d: "M6 4v16" }],
    [
      "circle",
      { cx: "6", cy: "7", fill: "currentColor", r: "1.5", stroke: "none" },
    ],
    [
      "circle",
      { cx: "6", cy: "16", fill: "currentColor", r: "1.5", stroke: "none" },
    ],
    ["path", { d: "M10 7h9M10 16h7" }],
  ],
  trash: [
    [
      "path",
      { d: "M4 7h16M9 3h6l1 4H8l1-4ZM6.5 7l1 14h9l1-14M10 11v6M14 11v6" },
    ],
  ],
  underline: [["path", { d: "M7 4v7a5 5 0 0 0 10 0V4M5 20h14" }]],
};

/** Text roles; each has --mt-type-<role>-font-family, -font-size, -font-weight, -line-height, -letter-spacing, and -text-transform. */
export const typeRoles = [
  "hero",
  "heroCompact",
  "display",
  "title",
  "welcomeTitle",
  "goalCardTitle",
  "recordCardTitle",
  "sheetTitle",
  "recordTitle",
  "titleSmall",
  "cardTitle",
  "composerTitle",
  "wordmark",
  "sectionTitle",
  "heading",
  "bodyLarge",
  "subsectionTitle",
  "body",
  "bodySmall",
  "label",
  "listHeading",
  "caption",
  "tagline",
  "pageEyebrow",
  "legend",
  "micro",
  "signInEyebrow",
  "menuHeading",
  "eyebrow",
  "navigationLabel",
  "columnHeading",
  "filterLabel",
  "statusLabel",
  "factLabel",
  "fine",
  "stamp",
  "dateStamp",
  "firstTimeDate",
  "nano",
  "badgeMicro",
  "badgeSmall",
  "badgeMedium",
  "badgeMicroCaps",
  "badgeSmallCaps",
  "badgeMediumCaps",
] as const;

export type TypeRole = (typeof typeRoles)[number];

/** Maximum page content widths in px. */
export const pageWidths = {
  compact: 880,
  standard: 960,
  wide: 1080,
  canvas: 1180,
} as const;

export type PageWidth = keyof typeof pageWidths;

/** Layout breakpoints in px. Media queries use max-width at the value and min-width one pixel above it. */
export const breakpoints = {
  390: 390,
  430: 430,
  480: 480,
  520: 520,
  540: 540,
  560: 560,
  600: 600,
  640: 640,
  700: 700,
  720: 720,
  780: 780,
  800: 800,
  820: 820,
  900: 900,
  1050: 1050,
  1100: 1100,
  1300: 1300,
} as const;

/** Container query widths in px. */
export const containerWidths = { 440: 440, 620: 620, 1000: 1000 } as const;

/** Durations in ms, for code that times itself rather than reading a CSS variable, such as a toast. */
export const durations = {
  labelFade: 100,
  quick: 120,
  composerEnter: 160,
  standard: 180,
  sidebar: 240,
  deliberate: 280,
  markTurn: 320,
  loadingSpin: 700,
  spin: 800,
  progressSweep: 850,
  pulse: 1100,
  shimmer: 1250,
  toast: 4500,
  toastError: 8000,
} as const;

/** Stacking order (z-index) by layer. */
export const layers = {
  local1: 1,
  local2: 2,
  local3: 3,
  local4: 4,
  local5: 5,
  header: 5,
  sidebar: 10,
  dock: 12,
  menuScrim: 18,
  menu: 19,
  mobileNavigation: 20,
  progress: 30,
  panel: 50,
  dialog: 70,
  popover: 80,
  palette: 80,
  nestedPopover: 90,
  mapOverlay: 500,
} as const;

/** Resolved semantic colors for code that cannot read CSS variables, such as server-rendered images. */
export const themeColors = {
  light: {
    canvas: "#F4F1E9",
    surface: "#FBF9F3",
    surfaceRaised: "#FFFFFF",
    surfaceSubtle: "#ECE7DC",
    ink: "#26251F",
    inkMuted: "#716D63",
    inkFaint: "#9A9589",
    border: "#DCD6C9",
    borderStrong: "#C7BFAF",
    accent: "#315E4F",
    accentHover: "#254A3E",
    accentSubtle: "#DDE8E1",
    accentInk: "#F8FBF9",
    warm: "#A76346",
    warmSubtle: "#F1E2D8",
    success: "#49705B",
    warning: "#9B6A2F",
    scrim: "#26251F",
    danger: "#A76346",
    dangerSubtle: "#F1E2D8",
    dangerBorder: "rgb(167 99 70 / 0.34)",
    dangerTint: "rgb(167 99 70 / 0.1)",
    info: "#315E4F",
    infoSubtle: "#DDE8E1",
    successSubtle: "#DDE8E1",
    warningSubtle: "#F1E2D8",
    warningBorder: "rgb(155 106 47 / 0.35)",
    inverseSurface: "rgb(24 24 20 / 0.72)",
    inverseInk: "#FFFFFF",
    accentWash: "rgb(49 94 79 / 0.07)",
    accentTint: "rgb(49 94 79 / 0.1)",
    accentBorderFaint: "rgb(49 94 79 / 0.15)",
    accentBorder: "rgb(49 94 79 / 0.34)",
    accentBorderStrong: "rgb(49 94 79 / 0.42)",
    accentStripe: "rgb(49 94 79 / 0.62)",
    accentHalo: "rgb(221 232 225 / 0.55)",
    accentPanel: "#EEF2EB",
    accentPanelBorder: "#9BA89B",
    warmGlow: "rgb(241 226 216 / 0.78)",
    warmWash: "rgb(241 226 216 / 0.65)",
    captureQueued: "#F4F5EF",
    captureRefused: "#F8F2EA",
    chipSurface: "#FCFBF6",
    laneSurface: "#FDFEFD",
    surfaceWash: "rgb(236 231 220 / 0.42)",
    surfaceRaisedTranslucent: "rgb(255 255 255 / 0.94)",
    skeletonHighlight: "rgb(255 255 255 / 0.72)",
    borderFaint: "rgb(220 214 201 / 0.7)",
    paletteBorder: "rgb(199 191 175 / 0.82)",
    inkUnderline: "rgb(38 37 31 / 0.7)",
    scrollbar: "rgb(113 109 99 / 0.38)",
    scrimFaint: "rgb(38 37 31 / 0.12)",
    scrimMedium: "rgb(38 37 31 / 0.34)",
    scrimStrong: "rgb(38 37 31 / 0.48)",
    menuScrim: "rgb(0 0 0 / 0.48)",
    mediaControl: "rgb(0 0 0 / 0.64)",
    mediaControlBorder: "rgb(255 255 255 / 0.4)",
    onInkKey: "rgb(255 255 255 / 0.1)",
    onInkKeyBorder: "rgb(255 255 255 / 0.35)",
    map: {
      marker: "#5C6F5D",
      canvas: "#F3F1EB",
      grid: "#D9D5CA",
      labelSurface: "#FFFFFF",
      labelInk: "#4C514B",
      pin: "#526F60",
      pinInk: "#FFFFFF",
    },
    brand: { ring: "#315E4F", accent: "#A76346", innerRing: "#82AD98" },
  },
  dark: {
    canvas: "#171816",
    surface: "#1E201D",
    surfaceRaised: "#262824",
    surfaceSubtle: "#2C2E29",
    ink: "#EEEADF",
    inkMuted: "#B4AFA3",
    inkFaint: "#817D74",
    border: "#393B35",
    borderStrong: "#4B4E46",
    accent: "#82AD98",
    accentHover: "#96BEAA",
    accentSubtle: "#273C33",
    accentInk: "#142019",
    warm: "#D49373",
    warmSubtle: "#432E25",
    success: "#82AD98",
    warning: "#D3A360",
    scrim: "#000000",
    danger: "#D49373",
    dangerSubtle: "#432E25",
    dangerBorder: "rgb(212 147 115 / 0.34)",
    dangerTint: "rgb(212 147 115 / 0.1)",
    info: "#82AD98",
    infoSubtle: "#273C33",
    successSubtle: "#273C33",
    warningSubtle: "#432E25",
    warningBorder: "rgb(211 163 96 / 0.35)",
    inverseSurface: "rgb(24 24 20 / 0.72)",
    inverseInk: "#FFFFFF",
    accentWash: "rgb(130 173 152 / 0.07)",
    accentTint: "rgb(130 173 152 / 0.1)",
    accentBorderFaint: "rgb(130 173 152 / 0.15)",
    accentBorder: "rgb(130 173 152 / 0.34)",
    accentBorderStrong: "rgb(130 173 152 / 0.42)",
    accentStripe: "rgb(130 173 152 / 0.62)",
    accentHalo: "rgb(39 60 51 / 0.55)",
    accentPanel: "#222C26",
    accentPanelBorder: "#55665B",
    warmGlow: "rgb(67 46 37 / 0.78)",
    warmWash: "rgb(67 46 37 / 0.65)",
    captureQueued: "#202722",
    captureRefused: "#2A2420",
    chipSurface: "#20221F",
    laneSurface: "#262925",
    surfaceWash: "rgb(44 46 41 / 0.42)",
    surfaceRaisedTranslucent: "rgb(38 40 36 / 0.94)",
    skeletonHighlight: "rgb(38 40 36 / 0.72)",
    borderFaint: "rgb(57 59 53 / 0.7)",
    paletteBorder: "rgb(75 78 70 / 0.82)",
    inkUnderline: "rgb(238 234 223 / 0.7)",
    scrollbar: "rgb(180 175 163 / 0.38)",
    scrimFaint: "rgb(0 0 0 / 0.12)",
    scrimMedium: "rgb(0 0 0 / 0.34)",
    scrimStrong: "rgb(0 0 0 / 0.48)",
    menuScrim: "rgb(0 0 0 / 0.48)",
    mediaControl: "rgb(0 0 0 / 0.64)",
    mediaControlBorder: "rgb(255 255 255 / 0.4)",
    onInkKey: "rgb(38 40 36 / 0.1)",
    onInkKeyBorder: "rgb(38 40 36 / 0.35)",
    map: {
      marker: "#9CB6A5",
      canvas: "#252824",
      grid: "#3E433F",
      labelSurface: "#343A35",
      labelInk: "#E4E7DF",
      pin: "#526F60",
      pinInk: "#FFFFFF",
    },
    brand: { ring: "#315E4F", accent: "#A76346", innerRing: "#82AD98" },
  },
} as const;

// Badge, from packages/design-system/components/badge.yaml.

/** The badge's color treatment. Glass and inverse tones are for photos and maps; success and danger are for outcomes. */
export const badgeTones = [
  "accent",
  "neutral",
  "warm",
  "success",
  "danger",
  "outline",
  "inverse",
  "solidAccent",
  "glassAccent",
  "glassNeutral",
] as const;

export type BadgeTone = (typeof badgeTones)[number];

/** The badge's text size. Micro fits dense cards, small is the default, and medium sits beside 22 px controls. */
export const badgeSizes = ["micro", "small", "medium"] as const;

export type BadgeSize = (typeof badgeSizes)[number];

/** Badge prop defaults. */
export const badgeDefaults = {
  tone: "accent",
  size: "small",
  uppercase: false,
} as const;

// Button, from packages/design-system/components/button.yaml.

/** The action's emphasis. Primary is the main action, secondary an alternative, ghost a quiet one, and danger a destructive one. */
export const buttonVariants = [
  "primary",
  "secondary",
  "ghost",
  "danger",
] as const;

export type ButtonVariant = (typeof buttonVariants)[number];

/** The control's height, padding, and text size. Small fits dense rows and toolbars, and large stands alone. */
export const buttonSizes = ["small", "medium", "large"] as const;

export type ButtonSize = (typeof buttonSizes)[number];

/** Button prop defaults. */
export const buttonDefaults = {
  variant: "primary",
  size: "medium",
  loading: false,
} as const;

// CaptureComposer, from packages/design-system/components/capture-composer.yaml.

/** Where the composer sits. Page is a raised card with its own question, on the Home Dashboard; dialog is the open body of Quick Capture, which titles it. */
export const captureComposerVariants = ["page", "dialog"] as const;

export type CaptureComposerVariant = (typeof captureComposerVariants)[number];

/** CaptureComposer prop defaults. */
export const captureComposerDefaults = { variant: "page" } as const;

// Checkbox, from packages/design-system/components/checkbox.yaml.

/** The box and text size. Small fits dense option rows under a field, and medium stands on its own. */
export const checkboxSizes = ["small", "medium"] as const;

export type CheckboxSize = (typeof checkboxSizes)[number];

/** Checkbox prop defaults. */
export const checkboxDefaults = { size: "medium" } as const;

// DateField, from packages/design-system/components/date-field.yaml.

/** The precision of the value. Day stores yyyy-MM-dd, month yyyy-MM, and year yyyy, and the calendar opens at that view. */
export const dateFieldGranularities = ["day", "month", "year"] as const;

export type DateFieldGranularity = (typeof dateFieldGranularities)[number];

/** The control's height and corner radius, from the size.field scale. Small fits filter rows, and large stands alone, as the birth date does. */
export const dateFieldSizes = ["small", "medium", "large"] as const;

export type DateFieldSize = (typeof dateFieldSizes)[number];

/** DateField prop defaults. */
export const dateFieldDefaults = {
  granularity: "day",
  size: "medium",
  includeTime: false,
  required: false,
  editable: true,
  hideLabel: false,
} as const;

// Dialog, from packages/design-system/components/dialog.yaml.

/** The Web dialog's width. Compact holds confirmations and short choices, standard holds forms, and wide holds long reading or side-by-side content. */
export const dialogSizes = ["compact", "standard", "wide"] as const;

export type DialogSize = (typeof dialogSizes)[number];

/** Dialog prop defaults. */
export const dialogDefaults = { size: "standard", busy: false } as const;

// IconButton, from packages/design-system/components/icon-button.yaml.

/** The action's emphasis, with Button's variants. Ghost is the default, because most icon actions are quiet chrome; primary and secondary are for a standalone add or edit action, and danger for a destructive one. */
export const iconButtonVariants = [
  "primary",
  "secondary",
  "ghost",
  "danger",
] as const;

export type IconButtonVariant = (typeof iconButtonVariants)[number];

/** The square's side. Small fits dense rows and composer headers, and large stands alone. */
export const iconButtonSizes = ["small", "medium", "large"] as const;

export type IconButtonSize = (typeof iconButtonSizes)[number];

/** IconButton prop defaults. */
export const iconButtonDefaults = {
  variant: "ghost",
  size: "medium",
  loading: false,
} as const;

// Image, from packages/design-system/components/image.yaml.

/** How the photo fills the frame. Cover crops it to fill, for thumbnails and cards; contain shows it whole, for viewing a photo. */
export const imageFits = ["cover", "contain"] as const;

export type ImageFit = (typeof imageFits)[number];

/** Image prop defaults. */
export const imageDefaults = { fit: "cover" } as const;

// PageFrame, from packages/design-system/components/page-frame.yaml.

/** The page's maximum width. Compact suits forms and focused reading, standard lists and search, wide dashboards and card grids, and canvas dense spatial views. */
export const pageFrameVariants = [
  "compact",
  "standard",
  "wide",
  "canvas",
] as const;

export type PageFrameVariant = (typeof pageFrameVariants)[number];

/** PageFrame prop defaults. */
export const pageFrameDefaults = { variant: "standard" } as const;

// RichText, from packages/design-system/components/rich-text.yaml.

/** How the editor sits on its surface. Form is a bordered field among other fields; embedded draws no field, because a host such as the capture composer already draws the surface. */
export const richTextVariants = ["form", "embedded"] as const;

export type RichTextVariant = (typeof richTextVariants)[number];

/** RichText prop defaults. */
export const richTextDefaults = { variant: "form" } as const;

// SearchField, from packages/design-system/components/search-field.yaml.

/** The control's height and corner radius, from the size.field scale. Small fits filter panels, and large leads a page or the command palette. */
export const searchFieldSizes = ["small", "medium", "large"] as const;

export type SearchFieldSize = (typeof searchFieldSizes)[number];

/** SearchField prop defaults. */
export const searchFieldDefaults = {
  size: "medium",
  hideLabel: false,
} as const;

// SectionHeader, from packages/design-system/components/section-header.yaml.

/** The heading's weight. Section is a serif title for a region of content; list is the small uppercase heading above a list. */
export const sectionHeaderVariants = ["section", "list"] as const;

export type SectionHeaderVariant = (typeof sectionHeaderVariants)[number];

/** Where the detail sits. Start keeps it beside the title, for a count; end moves it to the far edge, for a total that lines up with the list below. */
export const sectionHeaderDetailAligns = ["start", "end"] as const;

export type SectionHeaderDetailAlign = (typeof sectionHeaderDetailAligns)[number];

/** SectionHeader prop defaults. */
export const sectionHeaderDefaults = {
  variant: "section",
  detailAlign: "start",
} as const;

// SelectField, from packages/design-system/components/select-field.yaml.

/** The control's height and corner radius, from the size.field scale. Small fits filter rows, and large stands alone. */
export const selectFieldSizes = ["small", "medium", "large"] as const;

export type SelectFieldSize = (typeof selectFieldSizes)[number];

/** SelectField prop defaults. */
export const selectFieldDefaults = {
  size: "medium",
  required: false,
  hideLabel: false,
} as const;

// SeparatedList, from packages/design-system/components/separated-list.yaml.

/** Which edge the lines share. Start fits facts read from the leading edge; end lines them up with a trailing edge, such as attribution under a list. */
export const separatedListAligns = ["start", "end"] as const;

export type SeparatedListAlign = (typeof separatedListAligns)[number];

/** The gap around each separator. Default leaves room for focus rings, for links and buttons; word reads like a sentence, for plain text. */
export const separatedListSpacings = ["default", "word"] as const;

export type SeparatedListSpacing = (typeof separatedListSpacings)[number];

/** SeparatedList prop defaults. */
export const separatedListDefaults = {
  align: "start",
  spacing: "default",
} as const;

// Skeleton, from packages/design-system/components/skeleton.yaml.

/** The placeholder's shape. Fill takes the whole container, like a photo still arriving; block is a card or paragraph; line is one line of text; circle is an avatar. */
export const skeletonShapes = ["fill", "block", "line", "circle"] as const;

export type SkeletonShape = (typeof skeletonShapes)[number];

/** Skeleton prop defaults. */
export const skeletonDefaults = { shape: "block", animated: true } as const;

// TextField, from packages/design-system/components/text-field.yaml.

/** The control's height and corner radius, from the size.field scale. Small fits filter rows and compact panels, and large stands alone. */
export const textFieldSizes = ["small", "medium", "large"] as const;

export type TextFieldSize = (typeof textFieldSizes)[number];

/** TextField prop defaults. */
export const textFieldDefaults = {
  size: "medium",
  required: false,
  hideLabel: false,
} as const;

// Toast, from packages/design-system/components/toast.yaml.

/** What happened. Success confirms a change, info reports a neutral outcome, and error reports a failure, in the warm color and for longer. */
export const toastTones = ["success", "info", "error"] as const;

export type ToastTone = (typeof toastTones)[number];

/** Toast prop defaults. */
export const toastDefaults = { tone: "info" } as const;

// UploadProgress, from packages/design-system/components/upload-progress.yaml.

/** Where the progress shows. Inline sits in a form beside its label and count; overlay covers a photo tile with a scrim and shows only the ring. */
export const uploadProgressVariants = ["inline", "overlay"] as const;

export type UploadProgressVariant = (typeof uploadProgressVariants)[number];

/** UploadProgress prop defaults. */
export const uploadProgressDefaults = { variant: "inline" } as const;

/** Every spec's gallery specimens. The gallery marks each with data-specimen="<id>". */
export const componentSpecimens = [
  {
    component: "Badge",
    id: "badge-tones",
    description: "Every tone at the default small size.",
    covers: {
      tone: [
        "accent",
        "neutral",
        "warm",
        "success",
        "danger",
        "outline",
        "inverse",
        "solidAccent",
        "glassAccent",
        "glassNeutral",
      ],
    },
  },
  {
    component: "Badge",
    id: "badge-sizes",
    description: "Every size in the default accent tone, beside the uppercase treatment at each size.",
    covers: { size: ["micro", "small", "medium"] },
  },
  {
    component: "Badge",
    id: "badge-tags",
    description: "Tags written with a leading # in Latin and CJK scripts, at the medium size Dashboard uses.",
    covers: {},
  },
  {
    component: "Badge",
    id: "badge-truncation",
    description: "A long label and a long tag stay on one line and truncate at the tail inside a narrow container.",
    covers: {},
  },
  {
    component: "Badge",
    id: "badge-photo-overlay",
    description: "Uppercase micro glass and inverse tones over a photo, where record cards place them.",
    covers: { tone: ["glassAccent", "glassNeutral", "inverse"] },
  },
  {
    component: "Button",
    id: "button-variants",
    description: "Every variant at the default medium size.",
    covers: { variant: ["primary", "secondary", "ghost", "danger"] },
  },
  {
    component: "Button",
    id: "button-disabled",
    description: "Every variant disabled, faded to the disabled opacity.",
    covers: { variant: ["primary", "secondary", "ghost", "danger"] },
  },
  {
    component: "Button",
    id: "button-loading",
    description: "Every variant loading, with the spinner before the label.",
    covers: { variant: ["primary", "secondary", "ghost", "danger"] },
  },
  {
    component: "Button",
    id: "button-sizes",
    description: "Every size in the secondary variant, each with a leading icon.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "Button",
    id: "button-link",
    description: "Navigation drawn as a button, with Web ButtonLink and an iOS NavigationLink.",
    covers: {},
  },
  {
    component: "CaptureComposer",
    id: "capture-composer-page",
    description: "The Dashboard composer as a raised card with its question, an empty note, and its actions.",
    covers: { variant: ["page"] },
  },
  {
    component: "CaptureComposer",
    id: "capture-composer-dialog",
    description: "The Quick Capture body without a card or question, sharing the same draft.",
    covers: { variant: ["dialog"] },
  },
  {
    component: "Checkbox",
    id: "checkbox-sizes",
    description: "Both sizes, unchecked and checked, with a description on each checked one.",
    covers: { size: ["small", "medium"] },
  },
  {
    component: "Checkbox",
    id: "checkbox-states",
    description: "A controlled option, a long description that wraps, disabled, and disabled while checked.",
    covers: { size: ["medium"] },
  },
  {
    component: "CommandPalette",
    id: "command-palette-destinations",
    description: "The palette as it opens, with the search field and every destination before a query is typed.",
    covers: {},
  },
  {
    component: "DateField",
    id: "date-field-precision",
    description: "Day, month, and year precision, each with a value from the same September.",
    covers: { granularity: ["day", "month", "year"] },
  },
  {
    component: "DateField",
    id: "date-field-with-time",
    description: "A date with its time of day, which opens a separate time picker.",
    covers: { granularity: ["day"] },
  },
  {
    component: "DateField",
    id: "date-field-sizes",
    description: "Every size, from the small filter date to the large birth date.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "DateField",
    id: "date-field-states",
    description: "Empty with its placeholder, required, and disabled, and on Web a picker-only field that opens the calendar instead of taking typing.",
    covers: { size: ["medium"] },
  },
  {
    component: "Dialog",
    id: "dialog-confirmation",
    description: "A compact confirmation to remove a memory that says where it goes, with Cancel and a danger action.",
    covers: { size: ["compact"] },
  },
  {
    component: "Dialog",
    id: "dialog-form",
    description: "A form dialog to edit a memory, with a title and a date field, and a save that keeps the dialog busy for a moment.",
    covers: { size: ["standard"] },
  },
  {
    component: "Dialog",
    id: "dialog-short-choice",
    description: "A short choice of what to add, sized to its two options.",
    covers: { size: ["compact"] },
  },
  {
    component: "Dialog",
    id: "dialog-long-content",
    description: "A wide dialog whose long story scrolls while its footer stays in reach.",
    covers: { size: ["wide"] },
  },
  {
    component: "EmptyState",
    id: "empty-state-with-action",
    description: "An icon, a title, a description, and one action, as an empty Library shows.",
    covers: {},
  },
  {
    component: "EmptyState",
    id: "empty-state-informational",
    description: "A title and a description without an icon or action, for a section that fills in on its own.",
    covers: {},
  },
  {
    component: "EmptyState",
    id: "empty-state-button",
    description: "The whole state as one button that starts the missing record.",
    covers: {},
  },
  {
    component: "FocusedRecord",
    id: "focused-record-home",
    description: "A Home's page with its photos, facts, Story, and tags, and Edit beside the title.",
    covers: {},
  },
  {
    component: "IconButton",
    id: "icon-button-variants",
    description: "Every variant at the default medium size, with add, edit, more, and remove icons.",
    covers: { variant: ["primary", "secondary", "ghost", "danger"] },
  },
  {
    component: "IconButton",
    id: "icon-button-sizes",
    description: "Every size in the ghost variant, with the close icon a dialog header uses.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "IconButton",
    id: "icon-button-states",
    description: "A ghost action at rest, disabled, and loading, where the spinner replaces the icon.",
    covers: { variant: ["ghost"] },
  },
  {
    component: "Icon",
    id: "icon-set",
    description: "Every icon the platform draws, at 20, each with its name and a mark on those that draw on only one platform.",
    covers: {},
  },
  {
    component: "Icon",
    id: "icon-sizes",
    description: "The calendar icon at 14, 16, 18, and 24 on the size.icon scale.",
    covers: {},
  },
  {
    component: "Icon",
    id: "icon-color",
    description: "Icons take the color of their text, shown beside ink, muted, accent, and warm labels.",
    covers: {},
  },
  {
    component: "Image",
    id: "image-states",
    description: "A loaded photo, one still loading, and one that failed to load, side by side.",
    covers: {},
  },
  {
    component: "Image",
    id: "image-fit",
    description: "The same tall photo cropped to fill a wide frame and shown whole inside it.",
    covers: { fit: ["cover", "contain"] },
  },
  {
    component: "PageFrame",
    id: "page-frame-widths",
    description: "Every width variant with its maximum width and the pages it suits.",
    covers: { variant: ["compact", "standard", "wide", "canvas"] },
  },
  {
    component: "PageHeader",
    id: "page-header-full",
    description: "An eyebrow, a title, a description, and two actions beside the copy.",
    covers: {},
  },
  {
    component: "PageHeader",
    id: "page-header-title-only",
    description: "A title alone, as a focused page with nothing else to say opens.",
    covers: {},
  },
  {
    component: "PhotoViewer",
    id: "photo-viewer-paged",
    description: "Three saved Home photos that open on the second, with Previous, the position, and Next.",
    covers: {},
  },
  {
    component: "RecordCard",
    id: "record-card-photo",
    description: "A Home card with a cover photo and a Current badge, then its dates, name, a fact, and its organization.",
    covers: {},
  },
  {
    component: "RecordCard",
    id: "record-card-mark",
    description: "A Vehicle card without a photo or map, showing its mark over a soft accent wash.",
    covers: {},
  },
  {
    component: "RichText",
    id: "rich-text-content",
    description: "A saved note with a paragraph, emphasis, a link, a quote, and a list.",
    covers: {},
  },
  {
    component: "RichText",
    id: "rich-text-form",
    description: "The bordered editor with a placeholder, as in the Entry editor.",
    covers: { variant: ["form"] },
  },
  {
    component: "RichText",
    id: "rich-text-embedded",
    description: "The editor without a field, as inside the capture composer.",
    covers: { variant: ["embedded"] },
  },
  {
    component: "SearchField",
    id: "search-field-sizes",
    description: "Every size, from the compact filter search to the large page search.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "SearchField",
    id: "search-field-hidden-label",
    description: "A large search whose label is hidden because the page title names it, with trailing content after the query, a shortcut hint on Web and a count on iOS.",
    covers: { size: ["large"] },
  },
  {
    component: "SearchField",
    id: "search-field-disabled",
    description: "A disabled search, faded to the field opacity.",
    covers: { size: ["medium"] },
  },
  {
    component: "SectionHeader",
    id: "section-header-section",
    description: "Section headers alone, with a count beside the title, with a description, and with a trailing action.",
    covers: { variant: ["section"] },
  },
  {
    component: "SectionHeader",
    id: "section-header-list",
    description: "List headers with a count beside the title and at the far edge, and with a trailing action.",
    covers: { variant: ["list"], detailAlign: ["start", "end"] },
  },
  {
    component: "SectionHeader",
    id: "section-header-long",
    description: "A long section title and its trailing action in a narrow column.",
    covers: { variant: ["section"] },
  },
  {
    component: "SelectField",
    id: "select-field-sizes",
    description: "Every size, from a compact sort order to a standalone default view.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "SelectField",
    id: "select-field-groups",
    description: "A required choice whose options sit in titled groups, after an All records option outside any group.",
    covers: { size: ["medium"] },
  },
  {
    component: "SelectField",
    id: "select-field-disabled",
    description: "A disabled small select, faded to the field opacity.",
    covers: { size: ["small"] },
  },
  {
    component: "SeparatedList",
    id: "separated-list-default",
    description: "Facts and links with the default spacing, wrapping in narrower frames without a separator at a line's edge.",
    covers: { align: ["start"], spacing: ["default"] },
  },
  {
    component: "SeparatedList",
    id: "separated-list-word",
    description: "Plain facts with word spacing, reading like a sentence.",
    covers: { spacing: ["word"] },
  },
  {
    component: "SeparatedList",
    id: "separated-list-end-aligned",
    description: "Attribution links whose lines share the trailing edge.",
    covers: { align: ["end"] },
  },
  {
    component: "Skeleton",
    id: "skeleton-shapes",
    description: "Every shape at its default size, with a fill skeleton inside a photo-sized frame.",
    covers: { shape: ["fill", "block", "line", "circle"] },
  },
  {
    component: "Skeleton",
    id: "skeleton-still",
    description: "A block and two lines with the shimmer turned off, as reduced motion draws them.",
    covers: {},
  },
  {
    component: "Skeleton",
    id: "skeleton-composed",
    description: "A circle beside two lines and a block below them, the way a loading record row is built.",
    covers: { shape: ["block", "line", "circle"] },
  },
  {
    component: "SyncStatus",
    id: "sync-status-counts",
    description: "Waiting captures, a refused capture beside waiting ones, and a sync in progress.",
    covers: {},
  },
  {
    component: "TextField",
    id: "text-field-sizes",
    description: "Every size, holding a nickname, a preferred name, and a full name.",
    covers: { size: ["small", "medium", "large"] },
  },
  {
    component: "TextField",
    id: "text-field-states",
    description: "Empty with a placeholder, required, disabled, and invalid with its message.",
    covers: { size: ["medium"] },
  },
  {
    component: "TimeZoneField",
    id: "time-zone-field-offsets",
    description: "The same zone on a winter and a summer reference date, each showing the offset that applied that day.",
    covers: {},
  },
  {
    component: "Toast",
    id: "toast-tones",
    description: "Success, info, and error, each with its icon and stripe.",
    covers: { tone: ["success", "info", "error"] },
  },
  {
    component: "Toast",
    id: "toast-long-message",
    description: "An error long enough to wrap onto a second line.",
    covers: { tone: ["error"] },
  },
  {
    component: "UploadProgress",
    id: "upload-progress-inline",
    description: "Three of five photos uploaded, with the label and count beside the ring.",
    covers: { variant: ["inline"] },
  },
  {
    component: "UploadProgress",
    id: "upload-progress-overlay",
    description: "The ring alone over a photo tile, as a new photo's tile shows while it uploads.",
    covers: { variant: ["overlay"] },
  },
  {
    component: "WorkspaceActionDock",
    id: "workspace-action-dock-search",
    description: "The dock with a capture control beside the search shortcut and its Command K hint.",
    covers: {},
  },
] as const;

export type ComponentSpecimen = (typeof componentSpecimens)[number];

export type ComponentSpecimenId = ComponentSpecimen["id"];
