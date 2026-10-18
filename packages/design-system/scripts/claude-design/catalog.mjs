// Which Web components the Claude Design export bundles, and why the others stay out.
//
// Every file in apps/web/src/components is listed exactly once, so a new component cannot reach
// the copy, or miss it, without a decision here. A bundled component renders from props alone:
// no app data, Supabase, server actions, or routing state.
//
// `group` places the preview card, `height` is the card height in px at the preview width, and
// its specimens live in ./specimens/<name>.jsx. `parts` are further exports documented with the
// component, sharing its README and preview, each with a note on how it relates. `spec` names the
// component spec it follows when that differs from its own name, as when one spec names the shared
// component on both platforms.

export const cardGroups = [
  "Foundations",
  "Actions",
  "Inputs",
  "Feedback",
  "Layout",
  "Content",
  "Patterns",
];

export const bundled = [
  {
    name: "Icon",
    source: "icon.tsx",
    group: "Foundations",
    height: 720,
    summary:
      "Icon draws one line icon from the shared icon set at a given pixel size.",
  },
  {
    name: "BrandMark",
    source: "brand-mark.tsx",
    group: "Foundations",
    height: 180,
    summary:
      "BrandMark is the MemoTrail logo mark: two green rings with a clay accent.",
  },
  {
    name: "Button",
    source: "button.tsx",
    group: "Actions",
    height: 520,
    parts: [
      {
        name: "ButtonLink",
        note: "ButtonLink draws navigation with Button's variants and sizes and stays a link, so it has no loading state. It shares Button's defaults.",
      },
    ],
    summary:
      "Button is the action control, in primary, secondary, ghost, and danger variants and three sizes; ButtonLink draws navigation the same way.",
  },
  {
    name: "IconButton",
    source: "button.tsx",
    group: "Actions",
    height: 350,
    summary:
      "IconButton is a Button that shows only an icon and names its action with a required label.",
  },
  {
    name: "TextField",
    source: "text-field.tsx",
    group: "Inputs",
    height: 710,
    summary:
      "TextField is a labeled single-line text input in three sizes, with an inline error that says how to fix the value.",
  },
  {
    name: "SearchField",
    source: "search-field.tsx",
    group: "Inputs",
    height: 560,
    summary:
      "SearchField is a labeled search input with a leading search icon and an optional trailing element.",
  },
  {
    name: "SelectField",
    source: "select-field.tsx",
    group: "Inputs",
    height: 550,
    summary:
      "SelectField is a labeled native select with the shared field surface and a chevron.",
  },
  {
    name: "Checkbox",
    source: "checkbox.tsx",
    group: "Inputs",
    height: 470,
    summary:
      "Checkbox is a native checkbox in two sizes with a visible label and an optional explanation.",
  },
  {
    name: "DatePickerField",
    spec: "DateField",
    source: "date-picker-field.tsx",
    group: "Inputs",
    height: 1060,
    summary:
      "DatePickerField is the shared calendar date field, with day, month, and year precision and an optional time.",
  },
  {
    name: "Skeleton",
    source: "skeleton.tsx",
    group: "Feedback",
    height: 740,
    summary:
      "Skeleton is a decorative shimmering placeholder for content that is still loading.",
  },
  {
    name: "EmptyState",
    source: "empty-state.tsx",
    group: "Feedback",
    height: 790,
    summary:
      "EmptyState explains why a region has nothing to show and, optionally, offers the next step.",
  },
  {
    name: "PhotoUploadProgress",
    spec: "UploadProgress",
    source: "photo-upload-progress.tsx",
    group: "Feedback",
    height: 320,
    summary:
      "PhotoUploadProgress shows how many selected photos have uploaded, as a ring with a count.",
  },
  {
    name: "PageFrame",
    source: "page-frame.tsx",
    group: "Layout",
    height: 370,
    summary:
      "PageFrame sets a page's maximum width, centering, responsive gutters, and vertical rhythm.",
  },
  {
    name: "PageHeader",
    source: "page-header.tsx",
    group: "Layout",
    height: 320,
    summary:
      "PageHeader opens a page with an optional eyebrow, a serif title, a description, and actions.",
  },
  {
    name: "SectionHeader",
    source: "section-header.tsx",
    group: "Layout",
    height: 490,
    summary:
      "SectionHeader titles a region of a page, with an optional detail, description, and action.",
  },
  {
    name: "Badge",
    source: "badge.tsx",
    group: "Content",
    height: 580,
    summary:
      "Badge is a noninteractive single-line label for a status, type, or tag.",
  },
  {
    name: "SeparatedList",
    source: "separated-list.tsx",
    group: "Content",
    height: 950,
    summary:
      "SeparatedList is a wrapping row of short facts with a dot between neighbors on the same line.",
  },
  {
    name: "ProgressiveImage",
    spec: "Image",
    source: "progressive-image.tsx",
    group: "Content",
    height: 420,
    summary:
      "ProgressiveImage shows a photo over a reserved skeleton, fades it in once decoded, and explains a failure.",
  },
  {
    name: "RecordCard",
    source: "record-card.tsx",
    group: "Content",
    height: 860,
    parts: [
      {
        name: "RecordCardVisual",
        note: "RecordCardVisual is the card's media area, such as a photo or an icon well; put it first inside RecordCard.",
      },
      {
        name: "RecordCardBody",
        note: "RecordCardBody holds the card's title and facts; put it after RecordCardVisual inside RecordCard.",
      },
    ],
    summary:
      "RecordCard is the clickable card shell that Home, Vehicle, First Time, and Someday results share.",
  },
  {
    name: "FocusedViewLayout",
    source: "focused-view-layout.tsx",
    group: "Patterns",
    height: 520,
    summary:
      "FocusedViewLayout is the page pattern of a focused view: a wide frame, a page header, a summary row, and content.",
  },
  {
    name: "FocusedDetailUnavailable",
    source: "focused-detail-unavailable.tsx",
    group: "Patterns",
    height: 300,
    summary:
      "FocusedDetailUnavailable is the page shown when a focused record cannot be opened.",
  },
];

const needsData =
  "Loads or saves app data through server actions or Supabase, so it cannot render from props alone.";
const needsRouting =
  "Depends on routing, browser history, or the workspace shell's state.";
const needsCapture =
  "Belongs to the capture queue, which needs the CaptureProvider and local drafts.";
const featureView =
  "A feature view that composes bundled components around app data; its parts are bundled where reusable.";
const needsDialog = "Builds on Dialog, which is not bundled (see dialog.tsx).";

export const excluded = {
  "address-search.tsx":
    "Searches addresses through the app's location API, so it needs the network and app data.",
  "ai-paused-settings.tsx": needsData,
  "app-toast.tsx":
    "Toasts render through a global sonner Toaster and appear only in response to app events.",
  "appearance-setting.tsx": needsData,
  "auth-gate.tsx": "Signs in with Supabase Auth.",
  "birth-date-setting.tsx": needsData,
  "capture-composer.tsx": needsCapture,
  "capture-provider.tsx":
    "A context provider for the capture queue, not a visual component.",
  "command-palette.tsx": `${needsRouting} It also searches Entries through a server action.`,
  "confirmation-dialog.tsx": needsDialog,
  "dialog.tsx":
    "Uses React 19's context-as-provider syntax, which the preview's React 18 cannot render, and a modal portal with focus trapping and scroll locking that needs a page rather than a card.",
  "empty-trash-control.tsx": needsData,
  "entry-detail-view.tsx": featureView,
  "entry-editor-dialog.tsx": needsData,
  "entry-organization-editor.tsx": needsData,
  "entry-photo-dates.tsx":
    "Reads camera dates and GPS from an Entry's saved photos.",
  "entry-photo-field.tsx": `${needsData} It uploads photos.`,
  "entry-photos.tsx": "Shows an Entry's saved photos, which need app data.",
  "entry-rich-text-content.tsx":
    "Renders an Entry's stored rich-text document, which is app data rather than props a design can supply.",
  "export-settings.tsx": needsData,
  "first-times-workspace.tsx": featureView,
  "focused-editor-surface.tsx": needsDialog,
  "focused-record-detail.tsx": `${featureView} It also uses the router.`,
  "home-dashboard.tsx": featureView,
  "homes-workspace.tsx": featureView,
  "library-search.tsx": `${featureView} It also reads and writes the URL.`,
  "location-picker.tsx":
    "Searches and saves locations through the app's location API.",
  "milestone-fields.tsx":
    "Edits the milestone fields of an Entry form and is tied to its data model.",
  "occurrence-editor.tsx":
    "Edits an Entry's date and timezone model inside an editor form.",
  "overlay-container.tsx":
    "A React context for overlay containers, not a visual component.",
  "pending-captures.tsx": needsCapture,
  "photo-location-draft.tsx":
    "Reads photo GPS data and saves a draft location.",
  "photo-preview-dialog.tsx": needsDialog,
  "preferred-name-setting.tsx": needsData,
  "quick-capture-dialog.tsx": needsCapture,
  "record-card-map.tsx":
    "Loads a server-rendered static map image for a saved location.",
  "rich-text-editor.tsx":
    "A Tiptap editor whose document, extensions, and shortcuts belong to the capture and Entry editors.",
  "search-shortcut-link.tsx": `${needsRouting} It installs a global keyboard shortcut and takes its look from the workspace shell.`,
  "selected-photo-preview.tsx": needsDialog,
  "sync-status.tsx": needsCapture,
  "tag-control.tsx": needsData,
  "timeline-workspace.tsx": featureView,
  "timezone-select.tsx":
    "An unstyled select whose look comes from the enclosing editor; designs use SelectField.",
  "timezone-setting.tsx": needsData,
  "timezone-sync.tsx":
    "Syncs the browser timezone to Settings and renders nothing.",
  "top-layer.ts":
    "Helpers that place Dialog and its overlays in the browser top layer; it renders nothing, and Dialog is not bundled.",
  "trash-workspace.tsx": featureView,
  "use-confirmed-records.ts": "A hook, not a component.",
  "use-effective-theme.ts": "A hook, not a component.",
  "vehicles-workspace.tsx": featureView,
  "workspace-action-dock.tsx": `${needsRouting} It opens Quick Capture and Search.`,
  "workspace-history-controls.tsx": needsRouting,
  "workspace-shell.tsx": needsRouting,
};

// The card group of each component that has a spec but stays out of the bundle. Its card shows the
// spec in place of the component, and a spec for a component missing here stops the export.
export const specOnlyGroups = {
  CaptureComposer: "Patterns",
  CommandPalette: "Patterns",
  Dialog: "Patterns",
  FocusedRecord: "Patterns",
  PhotoViewer: "Patterns",
  RichText: "Content",
  SyncStatus: "Feedback",
  TimeZoneField: "Inputs",
  Toast: "Feedback",
  WorkspaceActionDock: "Patterns",
};

/** The name of the spec a bundled component follows. */
export function specName(component) {
  return component.spec ?? component.name;
}

/** The card that shows a spec: its bundled component's, or its own when the bundle leaves it out. */
export function cardName(spec) {
  return (
    bundled.find((component) => specName(component) === spec)?.name ?? spec
  );
}
