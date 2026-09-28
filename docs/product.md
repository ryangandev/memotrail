# MemoTrail Product Contract

Last reviewed: 2026-09-24.

## Product in one minute

MemoTrail is a private, single-user record of a life in progress.
It combines free-form writing with structured life facts so the user can capture something immediately, organize it later, and retrieve it years afterward.

The product has a native iOS client for fast capture and a responsive Web client for capture, organization, browsing, search, analysis, and export.
Both clients share the same information model and core behavior.

The interface is initially English, while Entry content and search support English, Chinese, and mixed-language text.

## Product principles

- Capture first, organize later.
- Use one Entry in many views instead of duplicating content.
- Let AI suggest, never silently decide or overwrite.
- Preserve the uncertainty the user supplied, especially for old dates.
- Keep specialized areas part of one coherent life archive.
- Make deletion recoverable and data portable.
- Favor calm reflection over task-management pressure.

## Core information model

MemoTrail centers on Entries.
Quick Capture creates an unreviewed Entry in Inbox; organizing it saves that Entry to Library without asking for a type.
Notes, journals, reflections, lessons, ideas, stories, memories, milestones, and trips are descriptive tags or Collections when the user wants them.
They do not change the Entry's structure.

Focused records keep structure only when the experience needs specific fields or actions.
Home and Vehicle are Entities; Goal has its own lifecycle; First Time has a focused Entry form.
Timeline has an intentional point Moment and an interval Period, plus spans from focused records.
An Entry's date alone does not put it on Timeline.
Timeline tracks control presentation, not the record's identity.

Every Entry may have writing, best-known time, media, Collections, tags, links, history, and retrieval behavior where those capabilities make sense.
Focused forms add typed facts to the same record without duplicating its common content.
Cross-form actions create and link another record rather than silently changing an existing record's identity.

Dates support exact timestamp, day, month, year, age or age range, date range, approximate description, and Unknown.
The system must preserve the recorded precision and timezone without inventing a calendar anchor.
Web date forms share one calendar control with day, month, year, optional hour-and-minute, editable numeric-entry, picker-only, and size variants.
Editable date fields accept digits and add their own separators; the first-visit birth-date prompt is picker-only, while Settings also permits numeric editing.
Settings owns the user's default timezone for new exact Timeline timestamps.
An exact Timeline timestamp shows a directly editable timezone select, may override the Settings default on its Entry, and labels every option with the UTC offset for the relevant date.
Date-only and uncertain Timeline forms keep timezone controls out of the primary form.
Changing the default never rewrites an existing Entry's recorded timezone.

## Capture and Inbox

- Global capture starts with one flexible writing field and may include photos, voice-to-text, and a best-known date.
- New captures remain untitled until Inbox review or later editing adds a title.
- The New Entry modal is a compact single-surface composer whose writing field grows with its content and does not expose native resize controls.
- Entry writing offers lightweight rich text for emphasis, links, lists, quotes, inline code, and code blocks without turning capture into a document editor.
  Formatting survives later edits and appears on full note surfaces.
- Rich formatting never replaces the Entry's clean plaintext body, so search, AI, export, and clients that do not render formatting still receive readable writing.
- The composer keeps a recoverable local draft.
- Offline captures remain visible and retryable until synchronization is confirmed.
- An ordinary online save shows progress in the composer; its brief local queue stage does not open a Pending sync list.
- Voice capture produces editable text and never retains the original audio.
- Every new free-form Capture enters Inbox, even when AI suggestions are available.
- Inbox review keeps AI suggestions hidden for now; people organize the Entry manually.
- AI suggestions are paused; retained implementation may suggest title, Collections, tags, date, and photo-derived date or Location context when the product is re-enabled.
- Suggestions remain editable and require explicit adoption.
- AI may propose a Collection but cannot create it without confirmation.
- The Capture remains in Inbox until the user selects `Save to Library`, completes another explicit organization action, or moves it to Trash.
- An unwanted Capture can move directly from Inbox review to Trash before it is organized, with confirmation and the normal restore path.
- Dashboard owns the persistent Quick Capture surface and shows up to three recent captures waiting for organization. Inbox is the dedicated review workspace and relies on the global New Entry action for additional capture.
- `Save to Library` marks organization complete but never prevents later editing.
- Inbox review saves the same Entry without a Kind or subtype choice.
- Focused forms are reached from Timeline or their focused views rather than the Quick Capture chooser.
- An existing Entry may still be linked as source material for a new focused record through an explicit action.

Original photos remain private and unchanged.
Photo metadata may be offered as a date or Location suggestion but is never adopted automatically.

## Organization, history, and relationships

- An Entry may belong to several Collections and tags.
- Collections are curated, browsable groupings of records.
- Tags are lightweight descriptors for filtering and discovery.
- People are reusable Entities linked to other Wiki Items, not alternate tags.
- Locations are private address and coordinate snapshots owned by individual Entries, not Library items or reusable personal records.
- A Location does not require a personal name; an Entry, Home, Vehicle, or First Time can carry its address or coordinates.
- Inbox, Timeline, Dashboard, and Library are views or workflow states, not organization labels.
- Library is the primary all-items entry point for the Life Wiki.
  Its default browser presents organized Entries, Entities, and Goals as paginated rows and opens focused records in their own views.
  Unreviewed captures remain in Inbox and do not appear in the default Library browser or its item count until `Save to Library`.
  Library search also finds Inbox captures, labels them clearly, and supports record, date, Collection, and tag filters with match context.
  Library avoids duplicating the sidebar's focused and organizing destinations; the global Version history index has a link below Library results.
- Opening a general Wiki Item shows its current content and primary actions first.
  Version history is an explicit secondary action, while focused records open their own read-only detail pages.
  A pencil-and-Edit action changes the fields on that detail page into an inline form; Add remains a modal creation flow.
- Current Wiki Item detail supports moving the item to Trash, where it remains restorable.
- Collections and tags are created and managed from separate Library destinations without a second in-page switcher, and remain available in every compatible Wiki Item editor.
- Collection and tag management opens in viewport-level dialogs. The Tags Library uses compact usage-count badges that open tag management, recent linked Entries, and a path to the complete filtered result set.
- Renaming a Collection or tag preserves its identity and linked Wiki Items.
- Moving a Collection to Trash never deletes its Wiki Items or photos.
- A used tag must be merged into another tag or removed from its Entries before deletion, so organization is never silently lost.
- Entries may link to other Entries and expose incoming backlinks without copying writing.
- Reusable People are canonical Entity Wiki Items with typed detail records and may link to many other Wiki Items.
- Important content, organization, relationship, specialized-field, and photo-membership changes remain recoverable through version history.
- Restoring history creates a new revision and does not erase later history.

## Retrieval and AI

Earlier AI requirements and exploratory directions remain in the [AI direction record](./ai-direction-record.md) for future reconsideration; they do not reactivate the retired UI.

- One search experience supports literal keyword search; the AI question action is paused.
- Keyword search covers canonical Wiki Items, including People, and uses linked Location data as searchable context.
- Filters include date, record category, focused form, Collection, and tag where each applies.
- Search results explain matches and open the original source.
- AI answers are grounded in bounded source evidence and cite the Entries used.
- The original Entry is never changed by an AI answer.
- The retained `Explore with AI` implementation creates a separate conversation attached to its source Entry, but is not exposed while AI is paused.
- `Save as Entry` creates an editable, independent Inbox Entry with a bidirectional source link.
- AI defaults off, and manual capture, organization, browsing, and keyword search continue without it.
- Web AI capabilities are Beta, off, and unavailable to enable while their use cases and UI are reconsidered.
- Settings retains only a paused AI status; organizing, AI search, photo understanding, and Explore entry points are hidden.
- Keyword search and manual organization remain available; previous AI data and business logic are retained.
- Previous AI UI designs are retired and removed; revisiting AI requires a new interface rather than restoring those components.
- Future decision-model actions are an exploration direction, not an approved feature or permission to act for the user.
- Photo understanding requires separate consent from text features.

## Timeline and Dashboard

Timeline shows deliberately created Moments and Periods, plus contextual focused-record spans, on customizable tracks.
Web Timeline opens in the existing track view by default and offers Vertical Spine and Sticky Year styles through Settings; the chosen style is remembered for the signed-in account in that browser.
The first Timeline visit asks for a private birth date, uses it as the story's starting point, and keeps it editable in Settings.
Default tracks cover Education, Career, Homes, Vehicles, Relationships, Health, First Times, and Other Moments.
The user can create, order, rename, hide, and restore tracks without deleting content.
Timeline's global Add moment flow asks what the user is recording before opening the matching focused editor.
The record form determines its fields, while Track only determines presentation.
The Homes, Vehicles, and First Times track shortcuts open their specialized editors directly; other track shortcuts open the generic Moment editor with that track preselected.
Opening an existing Home, Vehicle, or First Time from Timeline navigates to its read-only focused detail page.
Unanchored Age, Approximate, and Unknown moments remain visible without a fabricated calendar position.

Web Dashboard is ordered around:

1. A personal greeting and compact archive counts linking to their destinations.
2. Quick Capture alongside up to three captures ready to organize.
3. A quiet resurfaced memory alongside current life chapters.
4. Full-width Recent Entries with single-line titles and summaries, Collection prefixes, and optional tags.

Narrow screens stack these sections in the same reading order.
Search stays available in the shared workspace header.

Resurfacing uses organized, active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Inbox content, Trash, and Life Stages do not appear as resurfaced memory cards.

## Specialized areas

### First Times

A First Time is a focused Entry form.
It requires only a title and accepts the full date-precision model, optional writing, photos, Location, People, Goal, Collections, tags, and Timeline context.
It is created intentionally from Timeline or the First Times view.
An existing Entry may be linked as source material without changing that Entry.

### Homes and Vehicles

Homes and Vehicles are Entity presets with the full date-precision model, optional facts, writing, photos, Location, relationships, and Timeline context.
Their dates describe when the Entity was part of the user's life.
An absent end means that relationship is current, not that the Entity is automatically a Chapter.
Duration labels must not imply more precision than the recorded dates.
Property operations, vehicle maintenance, fuel, expenses, insurance, and document storage are outside the current scope.

### Goals, Bucket List, and Ideas

Goals are low-pressure Entries with Short-term, Long-term, or Someday horizons and Considering, Active, Paused, Achieved, or Let Go states.
They may have a target date, progress notes, and related Entries, but never require a percentage, subtasks, deadlines, overdue warnings, or productivity scores.

An idea remains an Entry until the user explicitly creates a linked Goal from it.
The Entry remains intact as the source.

Bucket List items are Goals with a stable Collection role and Someday default.
An explicit achievement action may atomically mark one Achieved and create a linked First Time using the best-known date without copying the Goal writing.

### Locations and People

On Web, First Time, Home, and Vehicle cards prefer a photo, then a map when their Location has coordinates, then their original fallback.

Locations store address context, optional provider provenance, and private coordinates for one Wiki Item at a time.
The same physical address may appear in several Items, but each Item keeps an independent snapshot so later edits never change another Item.
Locations have no user-authored name or notes, no Saved Location catalog, and no Library destination.
Replaced Location snapshots remain private history for their owning Item, while permanently deleting the Item also deletes all of its Location snapshots.
Editors show a formatted address and map preview when coordinates exist; a photo's GPS position may be saved without an inferred address.
Homes may be saved without a Location; manually editing an address clears any provider-backed coordinate preview until another address is selected.
Both maps cluster current Entry coordinates, filter by Kind and occurred year, and open the records associated with a selected point.
The native iOS Map uses MapKit, including native annotation clustering and a record list that provides an alternative to selecting a marker.
When records span several cities, both maps offer shortcuts to the most recorded areas within the current filters and a way to return to the full map.
The Web Map and Location previews follow the effective Web appearance, including System mode and changes while a map is open.
The iOS Map follows the app's System, Light, or Dark appearance.
Photo GPS Locations retain their source photo identity as provenance after explicit adoption.
People contain a name plus optional relationship label and notes.
People remain reusable across Entries.
Web Entry, Home, Vehicle, and First Time editors can search Geoapify for an address, preview its coordinates, and save it as that record's Location.
Web address search supports keyboard selection and authenticated server-side usage limits.
Provider-backed Location editing on native iOS remains deferred until the Web flow is accepted.

## Experience and navigation

Soft Ledger is the visual direction: minimal, archival, modern, calm, and approachable.
Both clients support light and dark appearance, share semantic design intent, and still follow native platform conventions where identical interaction would reduce usability.
Web appearance is a per-browser choice between System, Light, and Dark; System remains the default and follows operating-system changes.
iOS appearance is an app-local choice with the same three options.

Mobile uses Dashboard, Inbox, Timeline, Library, and More in its bottom navigation.
Library opens with the same all-items Life Wiki browser as Web, including debounced keyword search and Kind filters.
More opens a compact menu for Map, focused record views, Collections, tags, archive tools, and Settings.
Settings is also reached from the profile control.
Settings lets the user choose a preferred name for Dashboard greetings, or clear it to use the Google account name.

Desktop treats Library as a primary destination beside Dashboard, Timeline, and Map; Search is part of Library.
Its sidebar omits Inbox, keeps optional focused views separate from Collections, tags, Trash, and the single Settings entry point.
The desktop sidebar can collapse to a compact icon rail from the top-bar panel control; the width change animates, and the choice persists in this browser without changing mobile navigation.
The collapsed rail shows the MemoTrail logo without its wordmark above square navigation targets and keeps keyboard focus indicators inside the controls.
On collapse, the logo's outer ring and accent rotate 90 degrees together while the inner ring turns in the opposite direction over 320ms; expanding reverses the rotation, and reduced motion keeps the mark still.
The persistent top bar places Back and Forward history controls, then the desktop sidebar panel control, before the accent-tinted `New` control; unavailable history directions are disabled.
Neutral Search and an icon-only Inbox control sit at the far right; Inbox shows a notification count only when captures are waiting.
A customizable Command Palette opens from the global search control or Command K, debounces live owner-scoped Entry and People results in place, supports keyboard navigation, and opens Library for full search with filters.
New Entry opens from the top bar or Command J.
Home, Vehicle, and First Time results share one reusable card shell while preserving subtype-specific content and responsive layouts.
Specialized editors share one unboxed photo field with consistent previews, progress, limits, and controls.
On Web, selecting a photo thumbnail in an editor or capture draft opens a single-photo dialog without removing it; the separate X control removes the photo.
Form labels mark required fields with `*` and leave optional fields unmarked.

## Privacy, deletion, and portability

- Initial authentication is Google Sign-In only.
- All personal data and media are private to the authenticated owner.
- Deletion first moves supported content to Trash for 30 days.
- `Delete forever` and `Empty Trash` require explicit confirmation.
- Complete export includes canonical JSON, readable Markdown, structured CSV, relationships, and original media.

## Product boundaries

MemoTrail is private and single-user.
It is not a social network, publishing platform, collaboration system, generic task manager, property manager, or vehicle operations tool.

Deferred or undecided work includes:

- Habits and reminders;
- a native iOS Share Extension;
- bulk Inbox review;
- optional PWA enhancements;
- Chinese interface localization;
- Sign in with Apple and App Store distribution;
- a native macOS client;
- the default Collection set, which should evolve from real use rather than an invented taxonomy.
