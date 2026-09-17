# MemoTrail Product Contract

Last reviewed: 2026-09-16.

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

MemoTrail is a Capture First Life Wiki.
A raw Capture is an Inbox workflow source, not a permanent semantic Type.
Organizing a Capture may finalize it as one Wiki Item or extract several linked Wiki Items while retaining the source as provenance.

Every durable Wiki Item has one structural Kind:

- Writing records what the user wrote, including Notes, Journals, Reflections, Lessons, and Ideas;
- Entity records a person, place, or thing in the user's life, including People, Places, Homes, Vehicles, and future optional presets;
- Event records something that happened, including Memories, First Times, Milestones, Trips, and other point or ranged events;
- Story organizes a deliberately authored narrative or Chapter without treating every dated record as a story;
- Goal records an intention and its lifecycle without turning the archive into a task manager.

A subtype or preset adds structure within one Kind.
Subtype changes are allowed only when their data remains compatible.
Kind is an identity boundary, not a flexible label.
Cross-Kind organization creates and links another Wiki Item instead of mutating an established Writing, Entity, Event, Story, or Goal.

Home and Vehicle are Entities.
Their date range describes when they were part of the user's life and does not make them a Chapter.
A Chapter is an explicitly authored Story that may link Entities, Events, Writings, and Goals.
A Memory is an Event preset rather than a separate primitive.

Every Wiki Item may have common writing, best-known time, media, Collections, tags, links, history, and retrieval behavior where those capabilities make sense.
Specialized presets add typed facts without duplicating the common item.

Collections are reusable areas of meaning, not automatically inferred Chapters.
Tags are granular descriptors.
Timeline is a projection of dated Wiki Items, not a Kind.
Timeline tracks control presentation and are not semantic Types.

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
- Voice capture produces editable text and never retains the original audio.
- Every new free-form Capture enters Inbox, even when AI suggestions are available.
- AI may suggest title, Kind, subtype, Collections, tags, date, and photo-derived date or Place context.
- Suggestions remain editable and require explicit adoption.
- AI may propose a Collection but cannot create it without confirmation.
- The Capture remains in Inbox until the user selects `Save to Library` or completes another explicit organization action.
- Home owns the persistent Quick Capture surface and shows up to three recent captures waiting for organization. Inbox is the dedicated review workspace and relies on the global New Entry action for additional capture.
- `Save to Library` marks organization complete but never prevents later editing.
- An unorganized Capture may be finalized as Writing, Event, or Story when its content already represents that one item.
- Creating an Entity or Goal from a Capture uses its specialized form and links the result to the Capture instead of bypassing required structure.
- Once a durable Wiki Item exists, cross-Kind actions use Extract, Create and Link, or another explicit workflow instead of a generic Type selector.

Original photos remain private and unchanged.
Photo metadata may be offered as a date or Place suggestion but is never adopted automatically.

## Organization, history, and relationships

- A Wiki Item has one Kind and subtype and may belong to several Collections and tags.
- Kind defines the identity boundary, subtype selects compatible structure, and a Timeline track only controls where a dated item is shown.
- Collections are curated, browsable groupings that may contain Wiki Items of different Kinds.
- Tags are lightweight cross-Kind descriptors for filtering and discovery.
- People and Places are reusable Entities linked to other Wiki Items, not alternate tags.
- Inbox, Timeline, Home, Search, and Library are views or workflow states, not organization labels.
- Library is the primary all-items entry point for the Life Wiki.
  It presents Writing, Events, Entities, Stories, and Goals as the main browsing lenses, keeps source Captures available as provenance rather than a peer content choice, supports Kind and keyword filters, and links each preset to its appropriate editor or detail surface.
- Opening a general Wiki Item shows its current content and primary actions first.
  Version history is an explicit secondary action, while typed Entities continue to open their focused editors.
- Current Wiki Item detail supports moving the item to Trash, where it remains restorable.
- Collections and tags are created and managed from separate Library destinations without a second in-page switcher, and remain available in every compatible Wiki Item editor.
- Collection and tag management opens in viewport-level dialogs. The Tags Library uses compact usage-count badges that open tag management, recent linked Entries, and a path to the complete filtered result set.
- Renaming a Collection or tag preserves its identity and linked Wiki Items.
- Moving a Collection to Trash never deletes its Wiki Items or photos.
- A used tag must be merged into another tag or removed from its Entries before deletion, so organization is never silently lost.
- Entries may link to other Entries and expose incoming backlinks without copying writing.
- Reusable People and Places are canonical Entity Wiki Items with typed detail records and may link to many other Wiki Items.
- Important content, organization, relationship, specialized-field, and photo-membership changes remain recoverable through version history.
- Restoring history creates a new revision and does not erase later history.

## Retrieval and AI

- One search experience supports literal keyword search and an explicit AI question action.
- Keyword search covers Wiki Items, including People and Places.
- Filters include date, Kind, subtype, Collection, and tag and do not pretend to apply where a field is irrelevant.
- Search results explain matches and open the original source.
- AI answers are grounded in bounded source evidence and cite the Entries used.
- The original Entry is never changed by an AI answer.
- `Explore with AI` creates a separate conversation attached to its source Entry.
- `Save as Entry` creates an editable, independent Inbox Entry with a bidirectional source link.
- AI defaults off, and manual capture, organization, browsing, and keyword search continue without it.
- Web offers one master permission, one optional organizing-suggestions control, and separate photo understanding consent. AI Search and Explore run only after an explicit user action.
- Photo understanding requires separate consent from text features.

## Timeline and Home

Timeline shows dated Wiki Items, including point Events and contextual Entity spans, on customizable tracks.
The first Timeline visit asks for a private birth date, uses it as the story's starting point, and keeps it editable in Settings.
Default tracks cover Places, Education, Career, Homes, Vehicles, Relationships, Health, First Times, and Other Events.
The user can create, order, rename, hide, and restore tracks without deleting content.
Timeline's global Add moment flow asks what the user is recording before opening the matching Event or Entity editor.
Kind and subtype determine the data model and editor, while Track only determines presentation.
The Homes, Vehicles, and First Times track shortcuts open their specialized editors directly; other track shortcuts open the generic Moment editor with that track preselected.
Opening an existing Home, Vehicle, or First Time from Timeline keeps the user on Timeline and uses the same specialized editor as its Records page.
Unanchored Age, Approximate, and Unknown moments remain visible without a fabricated calendar position.

Home is ordered around:

1. Search.
2. Quick Capture.
3. A compact preview of captures ready to organize.
4. Current life stages.
5. A quiet resurfaced memory.
6. Recent Entries.

Resurfacing uses organized, active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Inbox content, Trash, and Life Stages do not appear as resurfaced memory cards.

## Specialized areas

### First Times

A First Time is an Event preset.
It requires only a title and accepts the full date-precision model, optional writing, photos, Place, People, Goal, Collections, tags, and Timeline context.
It may be created directly, finalized from a raw Capture, or extracted and linked from established Writing without changing the Writing's identity.

### Homes and Vehicles

Homes and Vehicles are Entity presets with the full date-precision model, optional facts, writing, photos, relationships, and Timeline context.
Their dates describe when the Entity was part of the user's life.
An absent end means that relationship is current, not that the Entity is automatically a Chapter.
Duration labels must not imply more precision than the recorded dates.
Property operations, vehicle maintenance, fuel, expenses, insurance, and document storage are outside the current scope.

### Goals, Bucket List, and Ideas

Goals are low-pressure Entries with Short-term, Long-term, or Someday horizons and Considering, Active, Paused, Achieved, or Let Go states.
They may have a target date, progress notes, and related Entries, but never require a percentage, subtasks, deadlines, overdue warnings, or productivity scores.

Ideas are Writing until the user explicitly creates a linked Goal from one.
The Writing remains intact as the source instead of changing its Kind.

Bucket List items are Goals with a stable Collection role and Someday default.
An explicit achievement action may atomically mark one Achieved and create a linked completion Event using the best-known date without copying the Goal writing.

### Places and People

Places contain a name plus optional address, coordinates, and notes.
People contain a name plus optional relationship label and notes.
Both remain reusable across Entries.
The data model preserves future Map capability, but Map UI is deferred.

## Experience and navigation

Soft Ledger is the visual direction: minimal, archival, modern, calm, and approachable.
Both clients support light and dark appearance, share semantic design intent, and still follow native platform conventions where identical interaction would reduce usability.
Web appearance is a per-browser choice between System, Light, and Dark; System remains the default and follows operating-system changes.

Mobile uses Home, Inbox, Timeline, and Library as its primary destinations.
Library opens with the same all-items Life Wiki browser as Web, including debounced keyword search and Kind filters.
Focused record destinations for Collections, First Times, Goals, Homes, Vehicles, Places, and People remain available below the all-items browser.
Settings is reached from the profile control.

Desktop treats Library as a primary destination beside Home, Timeline, and Search.
Its sidebar omits Inbox, keeps optional focused views separate from Collections, tags, Trash, and the single Settings entry point.
The persistent top bar places the warm-accented New Entry control at the far left, with neutral Search followed by an icon-only Inbox control at the far right; Inbox shows a notification count only when captures are waiting.
A customizable Command Palette opens from the global search control or Command K, debounces live owner-scoped Entry, People, and Place results in place, supports keyboard navigation, and keeps full-page Search with filters and AI as an explicit destination.
New Entry opens from the top bar or Command J.
Home, Vehicle, First Time, and Place results share one reusable card shell while preserving subtype-specific content and responsive layouts.
Specialized editors share one unboxed photo field with consistent previews, progress, limits, and controls.
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

- Map UI;
- Habits and reminders;
- a native iOS Share Extension;
- bulk Inbox review;
- optional PWA enhancements;
- Chinese interface localization;
- Sign in with Apple and App Store distribution;
- a native macOS client;
- the default Collection set, which should evolve from real use rather than an invented taxonomy.
