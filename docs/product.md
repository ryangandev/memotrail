# MemoTrail Product Contract

Last reviewed: 2026-09-13.

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

`Entry` is the user-facing term for independently searchable content.
An Entry may have:

- a title and body;
- a separate creation time and best-known occurrence;
- one Type and multiple Collections and tags;
- original photos and other attachments;
- links to Places, People, and other Entries;
- an Inbox or organized state.

Specialized Types add structure without creating a separate content silo:

- Standard Entry, including journal writing, reflections, learning, moods, and Ideas;
- First Time;
- Life Stage or Timeline event;
- Home;
- Vehicle;
- Goal.

Collections are reusable areas of meaning.
Tags are granular descriptors.
People and Places are lightweight reusable records, not contact or location-management systems.

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
- Quick Capture offers lightweight rich text for emphasis, links, lists, quotes, inline code, and code blocks without turning capture into a document editor.
- Rich formatting never replaces the Entry's clean plaintext body, so search, AI, export, and clients that do not render formatting still receive readable writing.
- The composer keeps a recoverable local draft.
- Offline captures remain visible and retryable until synchronization is confirmed.
- Voice capture produces editable text and never retains the original audio.
- Every new free-form Entry enters Inbox, even when AI suggestions are available.
- AI may suggest title, Type, Collections, tags, date, and photo-derived date or Place context.
- Suggestions remain editable and require explicit adoption.
- AI may propose a Collection but cannot create it without confirmation.
- The Entry remains in Inbox until the user selects `Done`.
- `Done` marks organization complete but never prevents later editing.

Original photos remain private and unchanged.
Photo metadata may be offered as a date or Place suggestion but is never adopted automatically.

## Organization, history, and relationships

- An Entry has one Type and may belong to several Collections and tags.
- Type defines the Entry's structure, while a Timeline track only defines where a generic moment is shown.
- Collections are curated, browsable chapters that may contain Entries of different Types.
- Tags are lightweight cross-Type descriptors for filtering and discovery.
- People and Places are reusable entities linked to Entries, not alternate tags.
- Inbox, Timeline, Home, Search, and Library are views or workflow states, not organization labels.
- Collections and tags are created and managed from separate Library destinations without a second in-page switcher, and remain available in every Entry editor.
- Renaming a Collection or tag preserves its identity and linked Entries.
- Moving a Collection to Trash never deletes its Entries or photos.
- A used tag must be merged into another tag or removed from its Entries before deletion, so organization is never silently lost.
- Entries may link to other Entries and expose incoming backlinks without copying writing.
- Reusable People and Places may link to many Entries.
- Important content, organization, relationship, specialized-field, and photo-membership changes remain recoverable through version history.
- Restoring history creates a new revision and does not erase later history.

## Retrieval and AI

- One search experience supports literal keyword search and an explicit AI question action.
- Keyword search covers Entries plus standalone People and Places.
- Entry filters include date, Type, Collection, and tag and do not pretend to apply to unrelated entity kinds.
- Search results explain matches and open the original source.
- AI answers are grounded in bounded source evidence and cite the Entries used.
- The original Entry is never changed by an AI answer.
- `Explore with AI` creates a separate conversation attached to its source Entry.
- `Save as Entry` creates an editable, independent Inbox Entry with a bidirectional source link.
- AI defaults off, and manual capture, organization, browsing, and keyword search continue without it.
- Web offers one master permission, one optional organizing-suggestions control, and separate photo understanding consent. AI Search and Explore run only after an explicit user action.
- Photo understanding requires separate consent from text features.

## Timeline and Home

Timeline shows point events and overlapping life periods on customizable tracks.
The first Timeline visit asks for a private birth date, uses it as the story's starting point, and keeps it editable in Settings.
Default tracks cover Places, Education, Career, Homes, Vehicles, Relationships, Health, First Times, and Other Events.
The user can create, order, rename, hide, and restore tracks without deleting content.
Timeline's global Add moment flow asks for the Entry type before opening details: a generic Moment, Home, Vehicle, or First Time.
Entry type determines the data model and editor, while Track only determines where a generic Moment appears on Timeline.
The Homes, Vehicles, and First Times track shortcuts open their specialized editors directly; other track shortcuts open the generic Moment editor with that track preselected.
Opening an existing Home, Vehicle, or First Time from Timeline keeps the user on Timeline and uses the same specialized editor as its Records page.
Unanchored Age, Approximate, and Unknown moments remain visible without a fabricated calendar position.

Home is ordered around:

1. Search.
2. Quick Capture.
3. Current life stages.
4. A quiet resurfaced memory.
5. Recent Entries.

Resurfacing uses organized, active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Inbox content, Trash, and Life Stages do not appear as resurfaced memory cards.

## Specialized areas

### First Times

A First Time requires only a title and accepts the full date-precision model, optional writing, photos, Place, People, Goal, Collections, tags, and Timeline context.
It may be created directly or by converting an existing Entry without duplicating content.

### Homes and Vehicles

Homes and Vehicles are personal-history periods with the full date-precision model, optional facts, writing, photos, relationships, and Timeline context.
An absent end means the chapter is current.
Duration labels must not imply more precision than the recorded dates.
Property operations, vehicle maintenance, fuel, expenses, insurance, and document storage are outside the current scope.

### Goals, Bucket List, and Ideas

Goals are low-pressure Entries with Short-term, Long-term, or Someday horizons and Considering, Active, Paused, Achieved, or Let Go states.
They may have a target date, progress notes, and related Entries, but never require a percentage, subtasks, deadlines, overdue warnings, or productivity scores.

Ideas remain Standard Entries until the user explicitly converts one into a Goal.
Conversion preserves Entry identity, writing, occurrence, photos, organization, links, Inbox state, and restorable history.

Bucket List items are Goals with a stable Collection role and Someday default.
An explicit achievement action may atomically mark one Achieved and create a linked First Time using the best-known date without copying the Goal writing.

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
Library contains Collections, First Times, Goals, Homes, Vehicles, Places, and People.
Settings is reached from the profile control.

Desktop uses a persistent sidebar for the primary areas, Trash, and one Settings entry point separated from Library.
Compact icon-and-shortcut Search and New Entry controls share one translucent hover treatment at the right of the persistent top bar on every primary screen.
A customizable Command Palette opens from the global search control or Command K, debounces live owner-scoped Entry, People, and Place results in place, supports keyboard navigation, and keeps full-page Search with filters and AI as an explicit destination.
New Entry opens from the top bar or Command J.

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
