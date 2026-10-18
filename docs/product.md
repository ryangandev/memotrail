# MemoTrail Product Contract

Last reviewed: 2026-10-04.

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
Quick Capture saves an Entry straight to Library without asking for a type; a title and tags can be added then or later.
Notes, journals, reflections, lessons, ideas, stories, memories, milestones, and trips are descriptive tags when the user wants them.
They do not change the Entry's structure.

Focused records keep structure only when the experience needs specific fields or actions.
Home and Vehicle are Entities, and a Someday item (a Goal in data) has its own lifecycle.
A milestone is a mark on an ordinary Entry, not a record type: it puts that Entry on Timeline as a Moment or a Period.
First Time is a flag on a milestone, so a First Time is an Entry like any other.
An Entry's date alone does not put it on Timeline.

Every Entry may have writing, best-known time, media, tags, links, and retrieval behavior where those capabilities make sense.
Focused forms add typed facts to the same record without duplicating its common content.
Cross-form actions create and link another record rather than silently changing an existing record's identity.

Dates support exact timestamp, day, month, year, age or age range, date range, approximate description, and Unknown.
The system must preserve the recorded precision and timezone without inventing a calendar anchor.
Web date forms ask how well the date is known with four choices: Day, Month, Year, and Not sure.
Day offers Add time for an exact timestamp and, outside a Period, Add end date for a date range; the two do not combine outside a Period.
A Period, Home, or Vehicle always offers an end date and Present, so its Day keeps its own end without becoming a date range.
Not sure stores an approximate description, with an optional rough date and, outside a Moment, an optional end date.
An age recorded before Not sure existed stays an age when its Entry is edited.
Leaving the date empty stores Unknown, so Unknown is not a separate choice.
Moving to a coarser choice keeps what is known, and moving to a finer one starts empty rather than inventing a day or month.
Web date forms share one calendar control with day, month, year, optional hour-and-minute, editable numeric-entry, picker-only, and size variants.
Editable date fields accept digits and add their own separators; the Timeline birth-date prompt is picker-only, while Settings also permits numeric editing.
Settings owns the user's default timezone for new exact timestamps.
In every date editor, an exact timestamp in the Settings default shows that zone as text with a Change action, so the default needs no decision.
Change, or a timestamp recorded in another zone, shows the timezone select, which may override the Settings default on its Entry and labels every option with the UTC offset for the relevant date.
Date-only and uncertain dates keep timezone controls out of the primary form.
Changing the default never rewrites an existing Entry's recorded timezone.

## Capture

- Global capture starts with one flexible writing field and may include photos, voice-to-text, and a date.
- Recording a thought needs no decision: open the composer, write, and save, with no required field, choice, or extra dialog on the way.
- A capture is dated by the moment it is saved unless Date picks a calendar day, with an optional time, in the browser's time zone.
  Month, year, uncertain, and ranged dates, time zones, and date descriptions are set later in the Entry editor.
- New captures remain untitled until later editing adds a title.
- The Web New Entry composer expands from a floating input-style control at the bottom center of the workspace; its writing field grows with its content and does not expose native resize controls.
- Entry writing offers lightweight rich text for emphasis, links, lists, quotes, inline code, and code blocks without turning capture into a document editor.
  Formatting survives later edits in the rich Entry editor and appears on full note surfaces.
  Focused record editors edit plain text: keeping the writing keeps its formatting, while changing it removes the formatting rather than keeping an outdated formatted copy.
- Rich formatting never replaces the Entry's clean plaintext body, so search, AI, export, and clients that do not render formatting still receive readable writing.
- Saving a note trims the spaces and blank lines around it while keeping its formatting and the blank lines inside it.
- The composer keeps a recoverable local draft.
- The Dashboard composer and Quick Capture edit one shared draft, including its date and photos, so saving or clearing it in either empties both and a draft is saved once.
- On Web, a voice capture in progress belongs to that draft too, and every open tab in a browser follows the same draft.
- Offline captures remain visible and retryable until synchronization is confirmed.
- Pending captures sync from any signed-in page once MemoTrail can be reached, whether or not a composer is open.
- On Web, waiting captures keep retrying on their own while the browser reports a connection, less often the longer MemoTrail stays unreachable.
  A connection that returns before it actually works, or a brief MemoTrail outage, therefore never leaves captures waiting until a reload.
- A capture MemoTrail cannot accept, such as text with a character Postgres cannot store, is never reported as offline and never retried automatically.
  It stays in Pending sync on that device with its original content, marked Not accepted with a reason, and later captures still sync.
  Copy text keeps its title and note, and Discard asks for confirmation before removing it and its photos from the device.
  If only its photos were refused, the Entry is already in the Library and Discard removes only the local copy.
- A capture is also not accepted when its Entry was moved to Trash or deleted forever on another device.
  An Entry in Trash is never overwritten or given new photos; restoring it from Trash keeps it, and Discard removes only this device's copy.
  An Entry deleted forever is never created again, so Copy text is the way to keep its writing.
- A photo is not accepted when MemoTrail refuses it, such as one that is too large, a file type it does not accept, or one that left the device before it was uploaded.
  A photo whose upload reached MemoTrail but whose answer was lost keeps waiting and attaches on the next retry.
- An expired session keeps captures waiting and asks the person to sign in again instead of reporting them as offline.
- On Web, the workspace header counts the captures waiting on this device and, separately, the ones not accepted, on desktop and mobile; selecting it retries now and lists them with the latest sync problem.
- On iOS, the retired Inbox screen still lists the same Pending sync captures until native follows Web, and the Dashboard and Quick Capture say how many wait and how many were not accepted.
- Every open tab in a browser shows the same pending captures, and each capture is saved once.
- An ordinary online save shows progress in the composer; its brief local queue stage does not open a Pending sync list or the header count.
- Voice capture produces editable text and never retains the original audio.
- Every new free-form Capture is saved straight to Library; MemoTrail has no Inbox or review step.
  Separate review made every capture a chore, so organizing is optional and happens whenever the Entry is edited.
- AI suggestions are hidden for now; people organize Entries manually.
- AI suggestions are paused; retained implementation may suggest title, tags, date, and photo-derived date or Location context when the product is re-enabled.
- While paused, new Captures and their photos are not processed for suggestions, even when earlier AI consent remains saved.
- Suggestions remain editable and require explicit adoption.
- AI may propose a tag but cannot add it without confirmation.
- An Entry needs organizing while it has neither a title nor a tag; giving it either takes it off that list.
  Library offers a Needs organizing view of those Entries, and Dashboard shows up to three of them beside Quick Capture.
  Needs organizing is a derived view, not a stored state, and Entries on it already belong to the Library.
- An unwanted Capture moves to Trash from its Item page, with confirmation and the normal restore path.
- Editing an Entry saves the same Entry without a Kind or subtype choice.
- Links saved before Inbox was retired still work: an Inbox link opens Needs organizing, and an Inbox review link opens that Entry's Item page.
- Focused forms are reached from Timeline or their focused views rather than the Quick Capture chooser.
- Any Entry's editor can mark it as a milestone, unmark it, or change its shape, lane, and First Time flag.
- An existing Entry may still be linked as source material for a new focused record through an explicit action.

Original photos remain private and unchanged.
Photo metadata may be offered as a date or Location suggestion but is never adopted automatically.

## Organization and relationships

- An Entry may have several tags.
- Tags are the one organization label: they group related Entries, such as travel, family, or a trip, for browsing, filtering, and discovery.
- The Entry editor shows Tags right under the Note, before Photos and the date, as a labeled tag field.
  While the field is focused, or while the Entry has no tags, it offers the person's most used tags as one-click suggestions, counting only Entries outside Trash.
  Typing finds existing tags or creates a new one.
- Tags are unique regardless of case, so a typed name that differs from an existing tag only by case adds that tag as it is already written.
- An Entry can have up to 70 tags; the editor shows the count only once an Entry nears that limit.
- MemoTrail has no separate Collections.
  Each earlier Collection became a tag with the same name and kept its Entries; older Collection links open Tags, and an older Library Collection filter reads as a tag filter.
- MemoTrail does not keep People records.
  Maintaining people as structured records cost more than it gave back, so earlier People and their links were deleted; older People links open Library.
- Locations are private address and coordinate snapshots owned by individual Entries, not Library items or reusable personal records.
- A Location does not require a personal name; an Entry, Home, Vehicle, or First Time can carry its address or coordinates.
- Timeline, Dashboard, Library, and Needs organizing are views, not organization labels.
- Library is the primary all-items entry point for the Life Wiki.
  Its default browser presents Entries, Entities, and Someday items as paginated rows and opens focused records in their own views.
  A new capture appears there, and in its item count, as soon as it is saved.
  Library search supports record, date, and tag filters with match context.
  Library avoids duplicating the sidebar's focused and organizing destinations.
- Opening a general Wiki Item shows its current content and primary actions, while focused records open their own read-only detail pages.
  An Item page shows its photos below its writing as soon as it opens; selecting one opens a preview that pages through them with Previous, Next, and the arrow keys.
  Photos are added and removed in the Entry editor, not on the Item page.
  A pencil-and-Edit action changes the fields on that detail page into an inline form; Add remains a modal creation flow.
- Current Wiki Item detail supports moving the item to Trash, where it remains restorable.
- Tags are managed from the Tags destination, and every compatible Wiki Item editor can add existing tags or create new ones.
- Tag management opens in viewport-level dialogs. The Tags Library uses compact usage-count badges that open tag management, recent linked Entries, and a path to the complete filtered result set.
- Renaming a tag preserves its identity and linked Wiki Items.
- A used tag must be merged into another tag or removed from its Entries before deletion, so organization is never silently lost.
- Web does not offer general links between Entries, because tags already connect related records.
  Entries stay connected only through purpose-specific links: the source link of an item added to Someday and the First Time that marking an item done creates.
  General links saved earlier, including those older Goals carried, are deleted.
- MemoTrail keeps only the current version of each Entry.
  It has no version history: an edit replaces the earlier writing, and Trash is the only way to undo, for a whole Entry or one photo.
  Earlier versions saved before this change were deleted, and older version history links open the Item page or Library.
- Adding or removing photos never makes an open Entry, Home, Vehicle, or Someday editor stale: its Save, Move to Trash, and Mark done still apply.
  Writing or other content changed elsewhere since the editor opened still reports a conflict instead of being overwritten.

## Retrieval and AI

Earlier AI requirements and exploratory directions remain in the [AI direction record](./ai-direction-record.md) for future reconsideration; they do not reactivate the retired UI.

- One search experience supports literal keyword search; the AI question action is paused.
- Keyword search covers canonical Wiki Items and uses linked Location data as searchable context.
- Filters include date, record category, focused form, and tag where each applies.
- Search results explain matches and open the original source.
- AI answers are grounded in bounded source evidence and cite the Entries used.
- The original Entry is never changed by an AI answer.
- The retained `Explore with AI` implementation creates a separate conversation attached to its source Entry, but is not exposed while AI is paused.
- `Save as Entry` creates an editable, independent Library Entry with a bidirectional source link.
- AI defaults off, and manual capture, organization, browsing, and keyword search continue without it.
- Web AI capabilities are Beta, off, and unavailable to enable while their use cases and UI are reconsidered.
- Settings retains only a paused AI status; organizing, AI search, photo understanding, and Explore entry points are hidden.
- Keyword search and manual organization remain available; previous AI data and business logic are retained.
- Previous AI UI designs are retired and removed; revisiting AI requires a new interface rather than restoring those components.
- Future decision-model actions are an exploration direction, not an approved feature or permission to act for the user.
- Photo understanding requires separate consent from text features.

## Timeline and Dashboard

Timeline shows the milestones of the user's life: Entries marked as milestones, every Home, and every Vehicle.
A milestone is a Moment, one point in time, or a Period, a stretch of time that may still be going on.
Homes and Vehicles appear as Periods without being marked, from when they became part of the user's life.
Timeline has four fixed lanes, in this order: Places lived, Vehicles, Work and study, and Other milestones.
Homes fill Places lived and Vehicles fill Vehicles; each milestone chooses Work and study or Other milestones.
There are no custom tracks, and lanes cannot be renamed, reordered, or hidden.
Web Timeline has one view, the lanes; there is no style setting.
An optional private birth date becomes the story's starting point; Set birth date on Timeline and Settings add it, and Timeline never asks for it unprompted.
Without one, Timeline starts from the earliest dated item, and an empty Timeline shows the current year.
Adding to Timeline never waits on a birth date.
Add to Timeline asks whether the user is adding a milestone, a First Time, a Home, or a Vehicle.
A milestone or First Time opens the Entry editor with the milestone already marked; a Home or Vehicle opens its focused editor.
Each lane's add shortcut does the same for that lane, and a milestone added to Work and study starts as a Period.
Selecting anything on Timeline opens its Item page.
Unanchored Age, Approximate, and Unknown milestones remain visible without a fabricated calendar position.

Dashboard is ordered around:

1. A personal greeting and compact archive counts linking to their destinations.
2. Quick Capture alongside up to three Entries that need organizing.
3. A quiet resurfaced memory alongside Now.
4. Full-width Recent Entries with single-line titles and summaries and optional tags.

Narrow screens and iOS stack these sections in the same reading order.
Search stays available in the Web bottom dock, and in the header of each iOS primary tab as a shortcut to Library.
Archive counts open Timeline, Library, First Times, Tags, or Needs organizing; an Entry that needs organizing opens its Item page.
Now lists what is still going on: Periods, Homes, and Vehicles that have started and have no end.
Each shows its lane and how long it has been going on, opens its Item page, and Now links to Timeline.

Resurfacing uses active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Trashed Entries and Periods do not appear as resurfaced memory cards.

## Specialized areas

### First Times

A First Time is an Entry whose milestone is flagged as a First Time.
The First Times view lists those Entries, and adding one there opens the Entry editor as a First Time Moment in Other milestones.
Unchecking First Time, or removing the milestone, takes the Entry out of First Times without changing anything else about it.
Older First Time links open the Entry's Item page.

### Homes and Vehicles

Homes and Vehicles are Entity presets with the full date-precision model, optional facts, writing, photos, Location, relationships, and Timeline context.
Their dates describe when the Entity was part of the user's life.
An absent end means that relationship is current, so the Home or Vehicle appears in Now.
Duration labels must not imply more precision than the recorded dates.
Property operations, vehicle maintenance, fuel, expenses, insurance, and document storage are outside the current scope.

### Someday

Someday is a low-pressure list of things the user wants to do someday.
Each item needs only a title; a target date, notes, tags, and photos are optional.
An item is Not yet, Done, or Let go, and every new item starts as Not yet.
There are no horizons, Bucket List, percentages, subtasks, deadlines, overdue warnings, or productivity scores.
In data and routes an item is still a Goal (`item_kind = 'goal'`, `/goals`); Someday is its user-facing name, and one item is a Someday item.

An idea remains an Entry until the user explicitly adds it to Someday from its Item page.
That secondary action creates a separate item linked back to its source, and the Entry remains intact.

Marking an item done is the moment it can become a First Time.
That action atomically marks the item Done and creates a linked First Time using the best-known date without copying the notes.
Changing the status to Done in the editor records it without a First Time.

Someday items do not keep general links to other Entries.

### Locations

On Web, First Time, Home, and Vehicle cards prefer a photo, then a map when their Location has coordinates, then their original fallback.

Locations store address context, optional provider provenance, and private coordinates for one Wiki Item at a time.
The same physical address may appear in several Items, but each Item keeps an independent snapshot so later edits never change another Item.
Locations have no user-authored name or notes, no Saved Location catalog, and no Library destination.
A replaced or removed Location snapshot is deleted, and permanently deleting the Item also deletes all of its Location snapshots.
Editors show a formatted address and map preview when coordinates exist; a photo's GPS position may be saved without an inferred address.
Homes may be saved without a Location; manually editing an address clears any provider-backed coordinate preview until another address is selected.
Both maps cluster current Entry coordinates, filter by Kind and occurred year, and open the records associated with a selected point.
The native iOS Map uses MapKit, including native annotation clustering and a record list that provides an alternative to selecting a marker.
When records span several cities, both maps offer shortcuts to the most recorded areas within the current filters and a way to return to the full map.
The Web Map and Location previews follow the effective Web appearance, including System mode and changes while a map is open.
The iOS Map follows the app's System, Light, or Dark appearance.
Photo GPS Locations retain their source photo identity as provenance after explicit adoption.
Web Entry, Home, and Vehicle editors can search Geoapify for an address, preview its coordinates, and save it as that record's Location.
Web address search supports keyboard selection and authenticated server-side usage limits.
Provider-backed Location editing on native iOS remains deferred until the Web flow is accepted.
Until then, native Home, Vehicle, and First Time editors show the saved Location with its map and can remove it.

## Experience and navigation

Soft Ledger is the visual direction: minimal, archival, modern, calm, and approachable.
Both clients support light and dark appearance, share semantic design intent, and still follow native platform conventions where identical interaction would reduce usability.
Web appearance is a per-browser choice between System, Light, and Dark; System remains the default and follows operating-system changes.
iOS appearance is an app-local choice with the same three options.

Mobile uses Dashboard, Timeline, Library, Map, and More in its bottom navigation.
Library opens with the same all-items Life Wiki browser as Web, including debounced keyword search and Kind filters.
More opens a compact menu for focused record views, Tags, archive tools, and Settings.
Settings is also reached from the profile control.
Settings lets the user choose a preferred name for Dashboard greetings, or clear it to use the Google account name.

Desktop treats Library as a primary destination beside Dashboard, Timeline, and Map; Search is part of Library.
Its sidebar keeps optional focused views separate from Tags, Trash, and the single Settings entry point.
The desktop sidebar can collapse to a compact icon rail from the top-bar panel control; the width change animates, and the choice persists in this browser without changing mobile navigation.
Command B (Control B on Windows) also toggles the desktop sidebar when focus is outside text inputs and editors; inside the rich-text editor it retains its Bold behavior.
The collapsed rail shows the MemoTrail logo without its wordmark above square navigation targets and keeps keyboard focus indicators inside the controls.
On collapse, the logo's outer ring and accent rotate 90 degrees together while the inner ring turns in the opposite direction over 320ms; expanding reverses the rotation, and reduced motion keeps the mark still.
The persistent top bar places Back and Forward history controls, then the desktop sidebar panel control; unavailable history directions are disabled.
The profile control sits at the far right, after the pending sync count when captures are waiting on this device.
A customizable Command Palette opens from the global search control or Command K, debounces live owner-scoped Entry results in place, supports keyboard navigation, and opens Library for full search with filters.
On Web, the glass-effect bottom dock places the New Entry control labeled `What’s on your mind?` with a sparkle icon on the left and global Search on the right.
The controls keep text and shortcut hints readable over page content, and hovering highlights the border with a subtle accent glow that fades back when the pointer leaves without changing the background color.
New Entry also opens with Command J (Control J on Windows) when focus is outside a text input or editor.
It expands into a bottom-anchored composer with the editor below the prompt, keeping rich text, photos, dates, local drafts, and Save.
The expanded composer uses one consistent frosted surface across its header, writing area, and action row.
Web Capture saves to Library with Command Return (Control Enter on Windows), using the same validation and offline behavior as the Save button.
Hovering or focusing Save displays a tooltip with the Command Return shortcut.
Enter starts a new paragraph, and Shift+Enter inserts a line break; input method composition and nested editing controls do not trigger the save shortcut.
Escape or the close control collapses it and restores focus to the bottom control without discarding the draft.
On mobile Web the collapsed control sits above navigation; the expanded composer stays within the visible viewport and scrolls when needed.
Home, Vehicle, and First Time results share one reusable card shell while preserving subtype-specific content and responsive layouts.
The Entry editor and specialized editors share one unboxed photo field with consistent previews, progress, limits, and controls.
When a record, including a new Entry, saves but some photos do not attach, the editor stays open with those photos selected, and Save again updates that record and retries them, even when it was created with a chosen address.
On Web, selecting a photo thumbnail in an editor or capture draft opens a single-photo dialog without removing it; the separate X control removes the photo.
Form labels mark required fields with `*` and leave optional fields unmarked.

## Privacy, deletion, and portability

- Initial authentication is Google Sign-In only.
- All personal data and media are private to the authenticated owner.
- Deletion first moves supported content to Trash for 30 days.
- `Delete forever` and `Empty Trash` require explicit confirmation.
- A permanently deleted item can never be restored, and its private photo files are removed right after; if that removal cannot finish, MemoTrail says so and finishes it the next time Trash opens.
- An item whose original photos are missing cannot be restored, and MemoTrail explains why; it can still be deleted forever.
- An Entry deleted forever cannot be brought back by a capture still waiting on another device.
  To enforce this, MemoTrail keeps only the deleted Entry's ID and deletion time, with no writing, photos, or other content, until the account is deleted.
  This record is not visible in the app and is not part of an export.
- Complete export includes canonical JSON, readable Markdown, structured CSV, relationships, and original media.
  On Web, one Export everything action prepares a consistent copy and downloads it as a ZIP.
  Recent exports can be downloaded again for 24 hours and keep the copy made at export time; up to two are kept, and discarding one deletes its copy sooner.

## Product boundaries

MemoTrail is private and single-user.
It is not a social network, publishing platform, collaboration system, generic task manager, property manager, or vehicle operations tool.

Deferred or undecided work includes:

- Habits and reminders;
- a native iOS Share Extension;
- bulk organizing of Entries that need it;
- optional PWA enhancements;
- Chinese interface localization;
- Sign in with Apple and App Store distribution;
- a native macOS client;
- a starter tag set, which should evolve from real use rather than an invented taxonomy.
