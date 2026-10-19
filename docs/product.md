# MemoTrail Product Contract

Last reviewed: 2026-10-18.

## Product in one minute

MemoTrail is the one private place a life is written down.
The user jots down a thought, a mood, something learned, or something lived in seconds, finds it again from any half-remembered clue, and gets each chapter of their life back.
[positioning.md](./positioning.md) explains why it exists, who it is for, and the filter every feature must pass; this document says how the product behaves.

The product rests on three ideas: Entries hold everything the user records, Chapters give that record its shape in time, and Returns bring it back through search and reviews.

The responsive Web client comes first and covers capture, browsing, search, Timeline, reviews, import, and export.
A native iOS client for fast capture on the phone follows the finished Web behavior with the same information model.

The interface is initially English, while Entry content and both keyword and semantic search support English, Chinese, and mixed-language text.

## Principles

Every feature passes the [decision filter](./positioning.md#decision-filter).
In addition:

- Let AI find and give back, never silently decide, organize, or overwrite.
- Preserve the uncertainty the user supplied, especially for old dates.
- Make deletion recoverable and data portable.
- Favor calm reflection over task-management pressure: no streaks, backlogs, counts of unorganized Entries, or daily nags.

## Core information model

Everything the user records is an Entry in one stream.
Moods, quotes, lessons, ideas, long reflections, and life events are all Entries, and notes, journals, stories, memories, or trips are descriptive tags when the user wants them.
Tags never change an Entry's structure.

Every Entry may have writing, a best-known date, photos, tags, and a Location.
Two marks give an Entry more meaning without making it a different kind of record: First Time and Chapter.
Any Entry's editor can check or uncheck First Time, and can turn the Entry into a Chapter or back into an ordinary Entry, without losing its writing, photos, tags, or Location.

### Chapters

A Chapter is an Entry that names a stretch of the user's life, such as "2026 job search", "Studying in Philadelphia", or "Driving the old Civic".
It has a name, a start, and an optional end; a Chapter without an end is still going on.
Chapters may overlap, and one may lie inside another.

A Chapter contains every Entry dated inside its span, with no tagging or filing.
An Entry is inside when its recorded date falls within the span.
An Entry whose date cannot be placed, such as Unknown or a year the span covers only in part, is not counted inside.
Opening a Chapter shows its own writing and photos, then the whole of life during that period: every Entry dated inside it, whatever it is about, and the other Chapters that overlap it.

Like any Entry, a Chapter has its own writing, photos, tags, and optional Location, and it appears in search, Library, Trash, and export in the same way.
Moving a Chapter to Trash, or giving it an end, never changes the Entries dated inside it.

Where the user lived, what they drove, a job, a school, or a relationship is a Chapter.
Details such as an address, a make and model, or a color are written in its note rather than kept as typed fields.

The user creates Chapters from Timeline or from any Entry's editor.
MemoTrail may also suggest one, as described in [Chapter suggestions](#chapter-suggestions); a suggestion becomes a Chapter only after the user confirms it.

### First Times

First Time is a checkbox on an Entry that marks the first time the user did something.
The First Times view lists every Entry with the mark, and adding one there opens the Entry editor with First Time already checked.
It lists them newest first as rows, like Library: the date, the title, a line of its writing, where it happened, its photo count and tags, and its first photo or a map of its Location.
An untitled First Time is named by its date, so its row leaves the date column empty.
Unchecking First Time takes the Entry out of First Times without changing anything else about it.

### Dates

Dates support exact timestamp, day, month, year, age or age range, date range, approximate description, and Unknown.
The system must preserve the recorded precision and timezone without inventing a calendar anchor.
Web date forms ask how well the date is known with four choices: Day, Month, Year, and Not sure.
Day offers Add time for an exact timestamp and, outside a Chapter, Add end date for a date range; the two do not combine outside a Chapter.
A Chapter always offers an end date and Present, so its Day keeps its own end without becoming a date range.
Not sure stores an approximate description, with an optional rough date and an optional end date.
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

Capture happens in two modes, and both must feel effortless: a mood or sudden realization on the phone in well under a minute, and long-form writing on the computer.

- Global capture starts with one flexible writing field and may include photos, voice-to-text, and a date.
- Recording a thought needs no decision: open the composer, write, and save, with no required field, choice, or extra dialog on the way.
- Every capture is saved straight to Library with no review step; organizing is optional and happens whenever the Entry is edited.
- A capture is dated by the moment it is saved unless Date picks a calendar day, with an optional time, in the browser's time zone.
  Month, year, uncertain, and ranged dates, time zones, and date descriptions are set later in the Entry editor.
- New captures remain untitled until later editing adds a title.
- An untitled Entry is named by its date wherever a title is shown; its stored title stays empty.
  The name follows the date's recorded precision: a day or exact time reads "Sunday, October 18, 2026", a month "October 2026", a year "2026", and a range names both ends.
  A Not sure date uses its description, and an Entry without a date reads "Undated entry".
  The date is read in the time zone it was recorded in, so every device and the server show the same name.
  Lists show the note's first useful line as the summary, and the Entry page shows the date as its heading and the note once.
  The Entry page's Date fact appears only when it says more than that heading, such as the time of an exact moment or an end the heading leaves out.
  Because the date already names it, an untitled Entry does not repeat its date beside the title.
- A Chapter needs a name, so the Entry editor asks for a title when it turns an Entry into a Chapter.
- On Web the Dashboard holds the composer as one quiet card.
  Its placeholder asks "What’s on your mind?", and below it sit a Today chip for the date, a Voice chip, a Photos chip, and Save with its Command Return shortcut beside it.
  The formatting toolbar appears when the person engages the editor or has written something.
  On a phone the Voice chip shows only its icon.
- Away from the Dashboard, the Web dock's New Entry control opens Quick Capture, a dialog anchored to the bottom of the workspace; its writing field grows with its content and does not expose native resize controls.
  The Dashboard already holds a composer, so there the dock keeps Search alone and Command J opens the same Quick Capture dialog.
- Entry writing offers lightweight rich text for emphasis, links, lists, quotes, inline code, and code blocks without turning capture into a document editor.
  Formatting survives later edits in the rich Entry editor and appears on full note surfaces.
- Rich formatting never replaces the Entry's clean plaintext body, so search, reviews, export, and clients that do not render formatting still receive readable writing.
- Saving a note trims the spaces and blank lines around it while keeping its formatting and the blank lines inside it.
- The composer keeps a recoverable local draft.
- The Dashboard composer and Quick Capture edit one shared draft, including its date and photos, so saving or clearing it in either empties both and a draft is saved once.
- On Web, a voice capture in progress belongs to that draft too, and every open tab in a browser follows the same draft.
- Voice capture produces editable text and never retains the original audio.
- Editing an Entry saves the same Entry without a Kind or subtype choice.
- MemoTrail does not suggest titles, tags, or filing; the user organizes Entries only when they want to.
- An unwanted Capture moves to Trash from its Entry page, with confirmation and the normal restore path.

Original photos remain private and unchanged.
Photo metadata may be offered as a date or Location suggestion but is never adopted automatically.

### Offline and sync

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
- Every open tab in a browser shows the same pending captures, and each capture is saved once.
- An ordinary online save shows progress in the composer; its brief local queue stage does not open a Pending sync list or the header count.

### Import

Importing from Apple Journal, Apple Notes, and Notion gives a new user a past to search and review on the first day.

- Each imported note becomes an ordinary Entry with its original date, writing, and photos where the source provides them.
- Nothing in the imported content is lost: anything without a direct place in an Entry is kept as text in its note.
- Importing the same content again does not create duplicates.
- Import never changes or removes the user's existing Entries.
- Import opens from the sidebar, the More list, and Your data in Settings.

## Organization

- An Entry may have several tags.
- Tags are the one organization label: they group related Entries, such as travel, family, or a trip, for browsing, filtering, and discovery.
  Tags are always optional, and nothing in MemoTrail depends on them to find an Entry.
- The Entry editor shows Tags right under the Note, before Photos and the date, as a labeled tag field.
  While the field is focused, or while the Entry has no tags, it offers the person's most used tags as one-click suggestions, counting only Entries outside Trash.
  Typing finds existing tags or creates a new one.
- Tags are unique regardless of case, so a typed name that differs from an existing tag only by case adds that tag as it is already written.
- An Entry can have up to 70 tags; the editor shows the count only once an Entry nears that limit.
- Tags are managed from the Tags destination, and the Entry editor can add existing tags or create new ones.
- Tag management opens in viewport-level dialogs.
  The Tags Library uses compact usage-count badges that open tag management, recent linked Entries, and a path to the complete filtered result set.
- Renaming a tag preserves its identity and linked Entries.
- A used tag must be merged into another tag or removed from its Entries before deletion, so organization is never silently lost.
- MemoTrail has no links between Entries; dates, Chapters, and tags already connect related Entries.
- MemoTrail keeps only the current version of each Entry.
  An edit replaces the earlier writing, and Trash is the only way to undo, for a whole Entry or one photo.
- Adding or removing photos never makes an open Entry editor stale: its Save and Move to Trash still apply.
  Writing or other content changed elsewhere since the editor opened still reports a conflict instead of being overwritten.

### Library and Entry pages

- Timeline, Dashboard, and Library are views, not organization labels.
- Library is the primary place to browse every Entry.
  It lists every Entry by the date it happened, newest first, grouped by month, with undated Entries last under Undated.
  Each row shows the date, the title, an icon for a Chapter or a First Time, one line of writing, the Entry's tags, and its first photo when it has one.
  An untitled Entry is titled by its date, and a Chapter's row says how many Entries it holds.
  Rows are paginated, and a new capture appears there, and in the Entry count, as soon as it is saved.
- Library search runs as you type, ranks the best match first, and highlights the matching words in each row with the fields they matched.
  One row of filters sits under the search field: All, Entries, Chapters, or First Times, plus Tags and Dates panels that apply as soon as a choice is complete.
  Clear all removes the search and every filter at once.
  Library avoids duplicating the sidebar's destinations.
- Opening an Entry shows its Entry page with its current content and primary actions.
  An Entry page shows its photos below its writing as soon as it opens; selecting one opens a preview that pages through them with Previous, Next, and the arrow keys.
  Photos are added and removed in the Entry editor, not on the Entry page.
  Edit opens the Entry editor in a dialog over the page, the same editor that adds a new Entry.
  Below the photos, each Chapter the Entry falls inside gets an In Chapter row, innermost first, with the Chapter's name, its span, and a link to its page.
- A Chapter's Entry page also lists the Entries and overlapping Chapters described in [Chapters](#chapters), and its review when one exists.
- Entry pages support moving the Entry to Trash, where it remains restorable.

### Locations

Entry Locations remain in the current scope, but MemoTrail has no Map destination; place is not a primary retrieval clue.

- Locations are private address and coordinate snapshots owned by individual Entries, not Library Entries or reusable places.
- Any Entry, including a Chapter or a First Time, can carry an address or coordinates without a personal name.
- The same physical address may appear in several Entries, but each keeps an independent snapshot so later edits never change another Entry.
- Locations have no user-authored name or notes, no Saved Location catalog, and no Library destination.
- A replaced or removed Location snapshot is deleted, and permanently deleting the Entry also deletes all of its Location snapshots.
- The Web Entry editor can search Geoapify for an address, with keyboard selection and authenticated server-side usage limits, preview its coordinates, and save it as that Entry's Location.
- Editors show a formatted address and map preview when coordinates exist; a photo's GPS position may be saved without an inferred address.
- An Entry may be saved without a Location; manually editing an address clears any provider-backed coordinate preview until another address is selected.
- Photo GPS Locations retain their source photo identity as provenance after explicit adoption.
- First Time cards prefer a photo, then a map preview when their Location has coordinates, then their original fallback.
- Location previews follow the effective Web appearance, including System mode and changes while a preview is open.
- Keyword search uses an Entry's Location as searchable context.

## Retrieval and AI

AI earns its place in finding and giving back, not in organizing.
Finding things never sends Entry content to a third party; generating a review does so only after the user's explicit choice.
Earlier AI requirements and exploration remain in the [AI direction record](./ai-direction-record.md) as background, not as part of the product.

### Search

- One search experience combines keyword search with semantic search.
- Keyword search finds literal words and names across every Entry, including its title, writing, tags, and Location context.
- Semantic search finds Entries by meaning, so the user can describe a person or situation without the name, or a feeling without the exact words, and still find what they wrote.
- Semantic search is on by default and uses an embedding model MemoTrail runs itself, so neither Entry content nor search queries are sent to a third party for search.
- Settings can turn semantic search off; keyword search always remains.
- Filters include date, tag, and mark, such as Chapters or First Times, so a rough time narrows any search.
- Search results explain why they matched and open the original Entry.
- The Command Palette shows live results from the same search and opens Library for full search with filters.

### Chapter and year reviews

When a Chapter ends or a year passes, a review shows what that period held.

- Reviews are off until the user turns them on.
- A review is generated by a third-party model.
  Before any review is generated, MemoTrail states which content is sent, to which provider, and that provider's data policy as it actually is: that the provider does not train on the content, and how long the provider retains it.
  MemoTrail never describes retention as zero unless the provider contractually guarantees it.
- A review shows how the user's feelings changed over the period, which themes kept returning, and the user's own words from that time.
- Every quote links to the Entry it came from.
- A review is separate from the Entries it draws on, and the original Entries are never changed.
- A Chapter's review appears on its Entry page under "Looking back".
- Reviews is a destination that lists, newest first, each ended year with at least 5 dated Entries and each Chapter whose review has been made.
- Each year's page is titled "2025 in review", links back to Reviews, and switches between the years Reviews lists.
- A Chapter's review and a year's review read the same way: how it felt as serif prose, what kept coming up as rows with how many Entries each came from, the user's own words as quotes with a link to their date, and facts from the user's records.
- A finished review says once, beside its title, that it was written by AI, how many Entries it read, and when; it ends with Write again and Delete review.

### Chapter suggestions

- Chapter suggestions are off until the user turns them on.
- A suggestion proposes a name and a span from what the user has been writing about.
- A suggestion appears on Timeline, marked as suggested by AI, with Claude's reason and the Entries it is based on.
- A suggestion becomes a Chapter only after the user confirms it, and the user may edit its name and dates first.
- Suggestions never count, badge, or nag; dismissing one does not bring it back.

## Timeline and Dashboard

Timeline is a time view over Chapters and First Times, not a separate structure to maintain.
Each Chapter is a bar across its span, and each First Time is a point on its date.
Overlapping Chapters stack automatically so every bar stays readable; there are no lanes to choose, name, reorder, or hide.
Ordinary Entries are not drawn on Timeline; opening a Chapter shows them.
Web Timeline has one view; there is no style setting.
It opens on today, with today in the right third and a Today line across the board, and Today brings the view back there.
Years and Months set the scale, keeping the date in view where it was; Timeline opens in Months.
A Chapter still going on fades out past Today.
On narrow screens Timeline reads as a vertical list grouped by year, newest first, with a Today rule between what has happened and what is still ahead.
An optional private birth date becomes Timeline's starting point; Set birth date on Timeline and Settings add it, and Timeline never asks for it unprompted.
Without one, Timeline starts from the earliest dated Entry, and an empty Timeline shows the current year.
Adding to Timeline never waits on a birth date.
Add to Timeline asks whether the user is adding a Chapter or a First Time, and opens the Entry editor with that mark already set.
Selecting anything on Timeline opens its Entry page.
Chapters and First Times without a calendar date, such as Age, Approximate, and Unknown, are never given a fabricated position: Timeline counts them in one line that leads to Library.
Year reviews are reached from Reviews, not from Timeline.

Dashboard is ordered around:

1. A serif greeting such as "Good evening, Ryan", with no trailing period, over one muted line of today's date and compact counts linking to their destinations.
2. Full-width Quick Capture.
3. Now beside From your past, a quiet resurfaced memory on a warm tint.
4. Full-width Recent, the latest Entries as Library rows with single-line titles and summaries and optional tags; an untitled Entry is named by its date.

Narrow screens and iOS stack these sections in the same reading order.
Search stays available in the Web bottom dock, labeled "Search everything", which holds Search alone on the Dashboard and rests above the tab bar on a phone, and in the header of each iOS primary tab as a shortcut to Library.
The counts are Entries, Chapters now, First Times, and Tags, and open Library, Timeline, First Times, or Tags; a count of zero is left out, and a new Library shows only the date.
A new Library shows an invitation to write the first Entry or import notes in place of Now, From your past, and Recent.
Now lists the current Chapters: those that have started and have no end.
Each shows how long it has been going on and opens its Entry page, and Now links to Timeline.
Duration labels must not imply more precision than the recorded dates.

Resurfacing uses active, dated Entries only.
It prefers the nearest prior On This Day match and otherwise uses a stable daily rotation of older Entries.
Trashed Entries and Chapters do not appear as resurfaced memory cards.

## Notifications

MemoTrail sends no daily notifications, reminders, streaks, or "one year ago" pushes.
Retrieval on demand comes first.
Reviews are made only when the user asks for one.
The only notice is an occasional one on the Dashboard that a Chapter or year review can be made, and only while reviews are on.

## Experience and navigation

Soft Ledger is the visual direction: minimal, archival, modern, calm, and approachable.
The Web workspace follows its Quiet ledger layout.
Every page starts at the same left edge beside the sidebar, at a reading, list, or full width, so titles never move sideways between pages.
A page header is a serif title with at most one muted meta line and one primary action, with no eyebrow or description.
Warm is kept for the First Time mark and the logo, dates are muted ink, and the danger color marks only destructive actions and errors.
Both clients support light and dark appearance, share semantic design intent, and still follow native platform conventions where identical interaction would reduce usability.
Web appearance is a per-browser choice between System, Light, and Dark; System remains the default and follows operating-system changes.
iOS appearance is an app-local choice with the same three options.

Mobile uses Dashboard, Timeline, Library, and More in its bottom navigation.
Library opens with the same browser of every Entry as Web, including debounced search and filters.
More opens a plain list of First Times, Reviews, Tags, Import, Trash, and Settings.
On mobile Web, a 48px top bar shows the logo, the sync status, and the profile avatar, which opens Settings.
Settings lets the user choose a preferred name for Dashboard greetings, or clear it to use the Google account name.
Settings is one reading column of sections under serif titles and rules: Profile, Time, Appearance, Reviews, Your data, and Account.
Each setting is a row with its label on the left and its control on the right, and a field saves as the user changes it and says Saved beside itself, with no Save buttons.
Appearance is a System, Light, and Dark segmented choice, and the review switches stay switches.
Search by meaning appears in its own Search section only while an embedding service is configured.
Your data holds rows that open Import, Export, and Tags, and Account ends the page with Sign out as a secondary button.
Import, Export, and the signed-out and sign-in error pages use the same reading column, with a title-only header and rows between rules instead of stacked cards.

Desktop treats Library as a primary destination beside Dashboard and Timeline; Search is part of Library.
Desktop Web has no top bar.
Its sidebar lists Dashboard, Timeline, and Library; then, after a rule, First Times, Reviews, and Tags; and Import, Trash, and Settings at its foot, without group labels.
An account row at the bottom of the sidebar shows the profile name and the sync status.
The current destination is a raised row with a hairline ring.
A page that belongs to a destination marks it: an Entry page marks Library, a Chapter Timeline, a First Time First Times, and an Entry in Trash Trash, and its header links back there; a page that does not exist marks none.
The desktop sidebar can collapse to a compact icon rail from the panel control in its header; the width change animates, and the choice persists in this browser without changing mobile navigation.
Command B (Control B on Windows) also toggles the desktop sidebar when focus is outside text inputs and editors; inside the rich-text editor it retains its Bold behavior.
The collapsed rail shows the MemoTrail logo without its wordmark above square navigation targets and keeps keyboard focus indicators inside the controls.
On collapse, the logo's outer ring and accent rotate 90 degrees together while the inner ring turns in the opposite direction over 320ms; expanding reverses the rotation, and reduced motion keeps the mark still.
The pending sync count appears beside the profile when captures are waiting on this device.
A customizable Command Palette opens from the global search control or Command K, debounces live owner-scoped Entry results in place, supports keyboard navigation, and opens Library for full search with filters.
It also starts a New Entry and goes to every destination, including Reviews, Import, and Export.
Toasts appear above the dock and the mobile tab bar, never over them.
On Web, the glass bottom dock holds the New Entry control, a sparkle beside `What’s on your mind?` and its Command J hint, and then Search everything with its Command K hint.
On the Dashboard, whose page already holds the composer, the dock holds Search alone.
On a phone the dock rests one gap above the tab bar, Search shrinks to a round icon button, the shortcut hints hide, and on the Dashboard Search sits alone at the trailing edge.
The controls keep text and shortcut hints readable over page content.
New Entry also opens with Command J (Control J on Windows) when focus is outside a text input or editor.
It opens Quick Capture, a bottom-anchored dialog headed `What’s on your mind?` with the composer below, keeping rich text, photos, dates, local drafts, and Save.
The dialog uses one frosted surface across its header, writing area, and action row.
Web Capture saves to Library with Command Return (Control Enter on Windows), using the same validation and offline behavior as the Save button.
Hovering or focusing Save displays a tooltip with the Command Return shortcut.
Enter starts a new paragraph, and Shift+Enter inserts a line break; input method composition and nested editing controls do not trigger the save shortcut.
Escape or the close control collapses it and restores focus to the bottom control without discarding the draft.
On mobile Web the collapsed control sits above navigation; the expanded composer stays within the visible viewport and scrolls when needed.
Result cards share one reusable card shell while preserving their specific content and responsive layouts.
Every photo field shares one unboxed design with consistent previews, progress, limits, and controls.
When an Entry, including a new one, saves but some photos do not attach, the editor stays open with those photos selected, and Save again updates that Entry and retries them, even when it was created with a chosen address.
On Web, selecting a photo thumbnail in an editor or capture draft opens a single-photo dialog without removing it; the separate X control removes the photo.
Form labels mark required fields with `*` and leave optional fields unmarked.

Older links keep working: `/goals`, `/map`, Inbox, Needs organizing, People, and Explore links open Library; `/homes` and `/vehicles` open Timeline; Collection links open Tags, and an older Library Collection filter reads as a tag filter; an older link to one Entry, such as a Someday, Home, Vehicle, First Time, Inbox review, or version history link, opens its Entry page.

## Privacy, deletion, and portability

- Initial authentication is Google Sign-In only.
- All personal data and media are private to the authenticated owner.
- Deletion first moves supported content to Trash for 30 days.
- `Delete forever` and `Empty Trash` require explicit confirmation.
- A permanently deleted Entry or photo can never be restored, and its private photo files are removed right after; if that removal cannot finish, MemoTrail says so and finishes it the next time Trash opens.
- An Entry whose original photos are missing cannot be restored, and MemoTrail explains why; it can still be deleted forever.
- An Entry deleted forever cannot be brought back by a capture still waiting on another device.
  To enforce this, MemoTrail keeps only the deleted Entry's ID and deletion time, with no writing, photos, or other content, until the account is deleted.
  This record is not visible in the app and is not part of an export.
- Complete export includes canonical JSON, readable Markdown, structured CSV, relationships, and original media, with Chapters and First Times exported as the Entries they are.
  On Web, one Export everything action prepares a consistent copy and downloads it as a ZIP.
  Recent exports can be downloaded again for 24 hours and keep the copy made at export time; up to two are kept, and discarding one deletes its copy sooner.

## Product boundaries

MemoTrail is private and single-user.
It is not a social network, publishing platform, collaboration system, knowledge base, task manager, wish list, property manager, or vehicle operations tool.
Habits, People records, version history, an Inbox or review step, links between Entries, and typed records such as Homes or Vehicles stay out of the product.

Undecided, and not to be settled without Ryan:

- whether the Dashboard keeps one writing entrance and frames capture as today's journal ([issue #94](https://github.com/ryangandev/memotrail/issues/94));
- whether the Dashboard keeps a small daily resurfaced memory or gives that space to Chapters;
- whether Entry Locations stay;
- the exact wording of each review provider's retention policy;
- how each import source is read, and which one matters most;
- how Chapter suggestions are presented without becoming nags.

Deferred work includes:

- a native iOS Share Extension;
- bulk editing of several Entries at once;
- optional PWA enhancements;
- Chinese interface localization;
- Sign in with Apple and App Store distribution;
- a native macOS client;
- a starter tag set, which should evolve from real use rather than an invented taxonomy.
