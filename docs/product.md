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

## Capture and Inbox

- Global capture starts with one flexible text field and may include a title, photos, voice-to-text, and a best-known date.
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
- Renaming a Collection or tag preserves its identity and linked Entries.
- Moving a Collection to Trash never deletes its Entries or photos.
- Entries may link to other Entries and expose incoming backlinks without copying writing.
- Reusable People and Places may link to many Entries.
- Important content, organization, relationship, specialized-field, and photo-membership changes remain recoverable through version history.
- Restoring history creates a new revision and does not erase later history.

## Retrieval and AI

- One search experience supports literal keyword search and an explicit AI question action.
- Keyword search covers Entries plus standalone People, Places, and Habits.
- Entry filters include date, Type, Collection, and tag and do not pretend to apply to unrelated entity kinds.
- Search results explain matches and open the original source.
- AI answers are grounded in bounded source evidence and cite the Entries used.
- The original Entry is never changed by an AI answer.
- `Explore with AI` creates a separate conversation attached to its source Entry.
- `Save as Entry` creates an editable, independent Inbox Entry with a bidirectional source link.
- AI features are individually disableable and manual capture, organization, browsing, and keyword search continue without them.
- Photo analysis requires separate consent from text features.

## Timeline and Home

Timeline shows point events and overlapping life periods on customizable tracks.
Default tracks cover Places, Education, Career, Homes, Vehicles, Relationships, Health, First Times, and Other Events.
The user can create, order, rename, hide, and restore tracks without deleting content.
Unanchored Age, Approximate, and Unknown moments remain visible without a fabricated calendar position.

Home is ordered around:

1. Search.
2. Quick Capture.
3. Today's Habits.
4. A quiet resurfaced memory.
5. Recent Entries.

Resurfacing uses organized, active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Inbox content, Trash, and Life Stages do not appear as resurfaced memory cards.

## Specialized areas

### First Times

A First Time requires only a title and accepts the full date-precision model, optional writing, photos, Place, People, Goal, Collections, tags, and Timeline context.
It may be created directly or by converting an existing Entry without duplicating content.

### Habits

Habits support Check and Measure modes, daily, weekday, weekly-target, and custom-interval schedules, optional notes, and optional Entry context.
States are Completed, Missed, Intentionally skipped, and Not scheduled.
Intentional skips are neutral for streak and completion-rate calculations.
Analytics include current and longest streaks, completion rate, missed days, monthly summaries, a yearly chart, and weekday patterns.
Habit reminders are outside the current scope.

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

Mobile uses Home, Inbox, Timeline, Habits, and Library as its five primary destinations.
Library contains Collections, First Times, Goals, Homes, Vehicles, Places, and People.
Settings is reached from the profile control.

Desktop uses a persistent sidebar with direct access to capture, search, the primary areas, Trash, and Settings.
A global capture control remains available from every primary screen.

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
- a native iOS Share Extension;
- bulk Inbox review;
- optional PWA enhancements;
- Chinese interface localization;
- Sign in with Apple and App Store distribution;
- a native macOS client;
- the default Collection set, which should evolve from real use rather than an invented taxonomy.
