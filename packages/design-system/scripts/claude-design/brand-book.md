MemoTrail is a private, single-user record of a life in progress, on the Web and on iPhone.
Its visual direction is Soft Ledger: minimal, archival, modern, calm, and approachable, like a well-kept paper ledger in warm light.
This copy describes the design system; the repository owns every value, so draft with these tokens and components and never invent new values.
When a design needs a value that is missing, propose it as a new token instead of hard-coding it.

## Content fundamentals

Write like a calm, trusted notebook, not a productivity tool.
Favor reflection over pressure: never use streaks, countdowns, exclamation marks, or urgency to push the user.
Speak to the user as "you", and refer to the product as MemoTrail when it is the one that failed.
Keep every sentence short and plain, and say one thing per sentence.

Use sentence case for titles, labels, buttons, and menus.
Capitalize MemoTrail's named places and record types, because they are product terms: Dashboard, Inbox, Timeline, Library, Map, Trash, Settings, Entry, Home, Vehicle, First Time, Someday, Moment, and Period.
Keep generic nouns lowercase, such as tag, photo, date, and draft.
Start a button with a verb and name what it acts on, such as "Save to Library" or "Move to Trash".
Write a toast as one finished sentence in the past tense, and an error as what failed, what is still safe, and what to do next.
Give an empty state an inviting title and one sentence about what will appear there, not an instruction to do work.
Preserve uncertainty: offer "Not sure" and approximate dates, and never show a day or month the user did not give.
Mark required form fields with `*` and leave optional fields unmarked.
Use the typographic apostrophe (’) in interface text.

Real copy from the app:

- "Save to Library"
- "Move to Trash"
- "Retry now"
- "What’s on your mind?"
- "Your trail starts here"
- "Entries you save to Library will appear here, ready to return to."
- "Life is still unfolding"
- "As your archive grows, an older dated Entry will find its way back here."
- "Changes saved."
- "Entry moved to Trash."
- "Saved on this device. Waiting for a connection."
- "Could not connect. Your changes are still here to retry."
- "MemoTrail could not save your preferred name. Try again."
- "Export saved. Keep this private copy somewhere safe."
- "This record may have moved to Trash or no longer be accessible."
- "A phrase, date, or question about your life..."

## Visual foundations

### Color

Every color is a semantic role with a light and a dark value; use the role, never a raw color.
Set pages on `mt-color-canvas`, cards and fields on `mt-color-surface`, and raised cards, dialogs, and menus on `mt-color-surface-raised`.
Write primary text in `mt-color-ink`, secondary text in `mt-color-ink-muted`, and only placeholders and decorative metadata in `mt-color-ink-faint`.
Reserve `mt-color-accent`, the brand green, for the one primary action in a view, links, selection, and focus.
Use `mt-color-warm`, the clay accent, for eyebrows, dates, and warm badges; danger shares its clay value, so never use warm for anything that could read as an error.
Draw borders with `mt-color-border`, and control borders with `mt-color-border-strong`.
Use the status roles (`mt-color-success`, `mt-color-warning`, `mt-color-danger`, `mt-color-info`) with their `-subtle` backgrounds, and only for status.
Translucent and mixed colors, such as `mt-color-accent-tint`, are listed as their exact rgba values; the Web app writes them as the `color-mix()` named in their usage.
Put text only on the grounds its token lists; contrast.json holds those pairs to WCAG AA in both themes, with these named exceptions:

{{contrastExceptions}}

The main roles:

{{colorRoles}}

### Type

MemoTrail loads no web fonts: it uses the system fonts, so text matches each platform.

{{fontFamilies}}

Set titles of pages, sections, cards, and dialogs, and the wordmark, in the serif; set everything else in the sans; use the mono only for date stamps and code.
Use the text roles below instead of picking sizes; on Web each role is the set of `--mt-type-<role>-*` variables in bundle.css.
Keep one `mt-type-display` or `mt-type-title` per page, and use uppercase only through the roles that set it.

{{textRoles}}

### Spacing

Space in 4px steps with the `mt-space-*` tokens.
Use `mt-space-1` to `mt-space-3` inside controls and between a label and its field, `mt-space-4` and `mt-space-5` between related items, and `mt-space-6` to `mt-space-16` between sections.

{{spacing}}

### Radius

Round corners with the `mt-radius-*` tokens, larger for larger surfaces.

{{radius}}

### Shadow and elevation

Keep surfaces flat and quiet: most cards sit on the page with a border and no shadow.
Lift a surface only as far as its role needs, with the matching elevation pair of surface and shadow.
Shadows are tinted with ink and stay soft; never add a shadow the elevation scale lacks.

{{elevation}}

### Materials

Use glass only for controls that float over content, such as the workspace dock, the quick capture panel, and badges over photos.
Each material pairs a tint with a backdrop blur; bundle.css holds the ready `--mt-material-<name>-backdrop-filter` values.

{{materials}}

### Motion

Keep motion brief and functional: fade and slide a few pixels, never bounce.
Use `mt-motion-quick` for hover, press, and focus, and `mt-motion-standard` for dialogs and popovers as they open.
Honor reduced motion: stop shimmer and movement, and keep only opacity changes.

{{motion}}

### States

Show keyboard focus with a `mt-state-focus-ring-width` outline in `mt-state-focus-ring`, offset by `mt-state-focus-ring-offset`; never remove it.
Show hover with a surface change rather than movement, and selection with the accent.
Dim disabled controls with their family's `mt-state-disabled-opacity-*` value, and keep loading controls in place with a spinner.

{{states}}

### Layout and breakpoints

Wrap each page in PageFrame and choose the narrowest width that fits its content.
On phones, content runs full width inside the page gutters.

{{layout}}

Web media queries use max-width at a breakpoint and min-width one pixel above it.
Breakpoints are named by value: `mt-layout-breakpoint-720` is 720px.

{{breakpoints}}

Stack overlays only with the layers below; local layers order siblings inside one component.

{{layers}}

## Iconography

Draw icons from the shared set: each name is a Web line icon and an SF Symbol on iOS.
Web icons are 24 by 24 line drawings in `currentColor`, with round caps and joins and a `mt-size-stroke-icon` stroke; render them with `MemoTrail.Icon`.
Size icons from 14 to 24px, usually 16px in small controls and 18px in medium ones.
Icons are decorative: pair each with visible text, or give an IconButton a label.
Never draw a new icon inline; add it to icons.json in the repository.

{{icons}}

## Web and iOS

Both apps share these tokens, icons, and semantic intent, and each follows its platform's conventions where identical behavior would be worse.

- Text roles on iOS scale with Dynamic Type from the style each role names, with the sizes listed under Type.
- Glass on iOS is a system material, such as ultraThin, instead of the Web blur and tint.
- iOS draws SF Symbols where Web draws the line icons.
- iOS shadows have no spread or inset, so tokens that need them are Web only.
- Breakpoints, container widths, stacking layers, and the map colors are Web only.
- Web dialogs are centered over a blurred scrim; iOS presents the same content as a sheet.
- Web puts Search and New entry in a glass dock at the bottom, and its desktop sidebar can collapse to an icon rail; iPhone uses a tab bar with Dashboard, Inbox, Timeline, Library, and More.
- The Web components here have native counterparts: Button and IconButton are `mtButtonStyle` and `MTIconButton`, Badge is `MTBadge`, PageHeader is `MTPageHeader`, SectionHeader is `MTSectionHeader` and `MTListHeader`, EmptyState is `MTEmptyState`, Checkbox is `MTCheckbox`, Skeleton is `MTLoadingSkeleton`, and SeparatedList is `MTFlowLayout`.

## Components

Each component below is the real Web component, bundled as `window.MemoTrail`, with a README and a preview in its folder.

{{components}}
