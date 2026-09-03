# MemoTrail Product Definition

> Status: Phase 1 foundation approved
>
> Version: 0.14
>
> Audience: Ryan only
>
> Last updated: 2026-08-30

## 1. Product idea

MemoTrail is a private personal wiki and life-tracking app built around one person's actual life.

It should make it easy to capture something immediately, organize it later, and find or revisit it years afterward.

The product combines two kinds of personal information:

- Structured life facts, such as life stages, first-time experiences, habits, homes, and vehicles.
- Unstructured thoughts, such as journal entries, moods, ideas, things learned, and short-term or long-term intentions.

The product should feel like a coherent record of a life, not a bundle of unrelated trackers.

## 2. Product promise

When something matters to me, I can put it into MemoTrail without first deciding exactly where it belongs.

MemoTrail helps me organize it, connect it to the rest of my life, and retrieve it later through browsing or search.

## 3. Core loop

1. Capture something quickly.
2. Let MemoTrail suggest what it is and where it belongs.
3. Review or correct the organization when convenient.
4. Rediscover it later through collections, timelines, summaries, and search.

The capture step must remain fast even if the organization system becomes sophisticated.

## 4. Current product principles

### 4.1 Capture first, organize later

The user should never need to choose the perfect category before saving something.

A universal quick-capture action should accept a title, optional body text, optional photos, and a relevant date.

The initial capture interface begins with one flexible text field rather than requiring a title and body before saving.

After capture, AI may suggest a title and organization metadata.

### 4.2 One memory, multiple views

The same item may appear in several places without being duplicated.

For example, a first-time experience can also appear on the life timeline, inside a travel collection, and in search results.

### 4.3 AI assists, the user remains in control

Automatic classification and tagging should reduce manual work.

The user must be able to inspect, correct, remove, or replace every suggested category and tag.

In the initial version, every new free-form entry remains in the Inbox until the user reviews it.

High-confidence automatic filing may be introduced later, but it must remain visible, reversible, and manually editable.

### 4.4 Personal meaning matters more than rigid schemas

MemoTrail is initially designed for one person's needs.

It can use opinionated modules and fields instead of trying to become a generic knowledge-management platform.

### 4.5 Long-term retrieval is part of capture

Saving an item is not enough.

The app must make old information easy to search, browse, and understand in context.

## 5. Product areas

### 5.1 Inbox and quick capture

The Inbox is the landing place for thoughts that have not been fully organized.

Examples include:

- A diary entry.
- A passing mood or feeling.
- An idea.
- Something to do later.
- A short-term goal.
- A long-term thought or aspiration.
- Something newly learned, such as how an electric lighter ignites a candle.
- A short sentence or a long piece of writing.

An entry can contain:

- Title.
- Body text.
- One or more photos.
- The date or time the content refers to.
- Automatically suggested type, collections, and tags.
- User-edited type, collections, and tags.
- An Inbox state such as unreviewed or organized.
- Optional text produced through voice dictation.

Entries can be captured while offline and automatically synchronize when connectivity returns.

The composer continuously saves a recoverable local draft so accidental closing, navigation, or refresh does not lose writing.

Each Entry preserves separate timestamps for when it was created in MemoTrail and when its content occurred.

The occurred-at value defaults to the current time and may be replaced with any supported exact, partial, approximate, age-based, or range date.

Every new free-form entry goes to the Inbox even when AI suggestions are available.

During Inbox review, the user can edit the AI-suggested title, Type, Collections, tags, and date.

An Entry remains in the Inbox until the user explicitly selects `Done`.

Selecting `Done` marks the Entry as organized without preventing future edits.

Voice input is a desired lightweight capture capability.

The user can speak naturally and convert the speech into editable text inside the composer.

MemoTrail does not preserve the original audio.

The resulting text follows the same Inbox and AI organization workflow as typed text.

MemoTrail preserves original uploaded photos and generates optimized derivatives for display.

Photo metadata may be used to suggest an occurred-at date and Place, but the user must confirm those suggestions.

### 5.2 Life timeline

The timeline records overlapping life stages, periods, and meaningful events in chronological context.

Possible content includes:

- Named life stages with a start date and optional end date.
- Important events within a stage.
- First-time experiences.
- Homes and moves.
- Vehicle ownership periods.
- Photos and written reflections.

The timeline should support uncertain or approximate dates because older memories may not have exact dates.

The timeline must support both broad date-range stages and individual point-in-time events.

Life stages may overlap when they represent different dimensions of life.

For example, a university period may overlap with a period of living in Philadelphia.

Timeline uses customizable tracks so that different dimensions of life can overlap without becoming confusing.

Initial default tracks are:

- Places.
- Education.
- Career.
- Homes.
- Vehicles.
- Relationships.
- Health.
- First Times.
- Other Events.

The user can create additional tracks and hide default tracks that are not useful.

### 5.3 First Times

First Times is a dedicated list of experiences the user did, saw, learned, owned, or tried for the first time.

Each First Time Entry may include:

- Title.
- Date or approximate date.
- Optional description or reflection.
- Optional photos.
- Optional Place.
- Optional related People.
- Optional related Goal.
- Optional Collections and tags.
- A link to the relevant Timeline stage.

It should support both tiny firsts and major milestones.

Only the title is required.

The creation flow does not require ratings or a fixed reflection questionnaire.

First Times supports two creation paths:

1. Create a First Time directly from its dedicated area.
2. Capture a regular Inbox Entry and accept an AI suggestion to mark it as a First Time.

Both paths produce the same underlying Entry type.

### 5.4 Collections and automatic organization

Collections provide browsable groupings for captured Entries.

Possible collections include journal, moods, ideas, learning, goals, travel, health, home, and vehicles.

MemoTrail uses three organization layers:

- Type describes the Entry's structure and has one value, such as Standard Entry, First Time, Life Stage, Home, or Vehicle.
- Collections describe human-readable areas of meaning and may have multiple values, such as Reflection, Learning, Health, Travel, or Ideas.
- Tags are granular descriptors, such as motivation, orthodontics, Japan, or skiing.

MemoTrail may suggest Type, Collections, and tags from the Entry's text and photos.

Open design question:

- The initial default Collection set and how it should evolve from real usage.

Confirmed behavior:

- AI suggests Type, Collections, and tags.
- Suggestions remain manually editable.
- The initial version does not automatically remove new entries from the Inbox.
- High-confidence automatic filing can be explored after the manual review workflow has proven trustworthy.
- One Entry may belong to multiple relevant Collections.
- AI classification should understand content written in English, Chinese, or a mixture of both.
- AI may recommend existing Collections.
- AI may propose a new Collection, but it cannot create one without user confirmation.

### 5.5 Global smart search

Search should work across every product area.

The first version should provide one unified search field for both traditional keyword search and natural-language semantic search.

Keyword search covers titles, body text, tags, collections, dates, and structured fields.

Natural-language questions may include:

- When did I first try skiing?
- What was I thinking about before my last move?
- Which supplements do I miss most often?
- Show me things I learned about fire or electricity.

Search results should explain why an item matched and allow filtering by date, type, collection, and tag.

AI-generated answers must link back to the source Entries used to produce the answer.

When a captured Entry contains a question or unfinished thought, MemoTrail saves the user's original content without automatically inserting an AI answer.

An optional `Explore with AI` action may start a separate exploration while preserving a clear boundary between the original Entry and AI-generated content.

The exploration conversation remains attached to its source Entry.

The user can select `Save as Entry` for any durable conclusion.

The saved conclusion becomes a separate Entry with a bidirectional link to the source Entry.

### 5.6 Habits

Habits track repeated behavior over time, including both completed and missed days.

The initial example is taking a supplement.

Habits support two tracking modes:

- Check records whether an action was completed.
- Measure records a numeric quantity and unit, such as liters, minutes, pages, or repetitions.

Each habit may include:

- Name.
- Start date and optional end date.
- Tracking mode.
- Optional measurement unit and target.
- Schedule or frequency.
- Daily or scheduled-occurrence status.
- Optional note for a specific day.
- Optional link from a check-in to a related Entry.
- Current streak.
- Longest streak.
- Missed days.
- Completion rate.
- Monthly summary.
- Yearly contribution-style chart.
- Analysis of which weekdays are missed most often.

Supported schedules include:

- Every day.
- Selected weekdays.
- A target number of times per week.
- A custom interval.

Each calendar day or scheduled occurrence has one of four states:

- Completed.
- Missed.
- Intentionally skipped.
- Not scheduled.

An intentional skip does not reduce the completion rate or break a streak calculated across scheduled occurrences.

Habit reminders are not needed in the initial version.

### 5.7 Homes and moves

The Homes area records where the user has lived and for how long.

Each home may include:

- Name or label.
- City and country.
- Optional exact address.
- Move-in date and move-out date.
- Automatically calculated duration.
- Optional reason for moving in or leaving.
- Description, notes, and memories.
- Photos.
- Related People and Entries.
- Related Timeline stage and events.

Privacy controls will be especially important if exact addresses are stored.

Homes are personal-history Entries rather than property-management records.

A directly created Home requires a name, a reusable Place name, and the best-known move-in date.

The date may use exact, day, month, year, age, range, or approximate precision, while a Home without a move-out date remains an active residence.

Every Home is an organized Home Entry and a Stage on the Homes Timeline track, so the same life chapter appears consistently in Homes, Timeline, Search, Collections, tags, and Trash.

Editing a Home updates its shared Place details intentionally and retains the prior Entry, Home, Place, and Timeline state in version history.

The initial scope excludes rent, utilities, documents, and household tasks.

### 5.8 Vehicles

The Vehicles area records vehicles the user has owned or regularly used.

Each vehicle may include:

- Name or nickname.
- Make, model, and year.
- Optional color.
- Acquired date and sold or retired date.
- Ownership duration.
- Description and memories.
- Photos.
- Related People and Entries.
- Related Timeline stage and events.

Vehicles are personal-history Entries rather than vehicle-management records.

The initial scope excludes maintenance, fuel, expenses, insurance, and documents.

### 5.9 Goals, Bucket List, and Ideas

Goals are specialized Entries for intentions that benefit from a small amount of structure.

MemoTrail keeps Goal tracking reflective and low-pressure rather than becoming a task-management product.

Each Goal may include:

- Title and description.
- Horizon: Short-term, Long-term, or Someday.
- Status: Considering, Active, Paused, Achieved, or Let Go.
- Optional target date.
- Related Entries.
- Progress notes.

Goal progress does not require a percentage.

Progress is primarily represented through related Entries, notes, and status changes.

Things the user wants to do use the Goal Type, belong to the Bucket List Collection, and default to the Someday horizon.

When a Bucket List Goal is completed, the user may select `Mark as Achieved and create First Time`.

This action marks the Goal as Achieved and creates a linked First Time Entry without duplicating the original content.

Ideas remain Standard Entries inside the Ideas Collection without deadlines or task status.

An Idea can be manually converted into a Goal if it becomes an intention the user wants to track.

The initial product does not include subtasks, complex project management, overdue warnings, or productivity scores.

### 5.10 Places, People, and Map

Place and Person are lightweight reusable entities that can be linked across Entries.

A Place may be linked to a First Time, Timeline event, Home, or any Standard Entry.

A Person may be linked to multiple Entries without turning MemoTrail into a contact-management product.

The minimum Place model includes a name, optional address or geographic coordinates, and optional notes.

The minimum Person model includes a name, optional relationship label, and optional notes.

Homes and other meaningful Places may appear in both Timeline and Map views.

Map is not required in the earliest MVP, but the initial data model must preserve the location data needed to add it later.

## 6. Shared information model

All independently searchable content uses one consistent product term: Entry.

Record is not a separate user-facing concept.

An Entry can have one primary type, several tags and collections, attachments, dates, and links to other entries.

Specialized Entry types add their own fields without isolating the content from the rest of MemoTrail.

Examples:

- A First Time is an Entry with first-time-specific fields.
- A Home is an Entry representing a date range and a place.
- A life stage is an Entry representing a date range and a theme.
- A daily habit check-in is structured data that can optionally link to a journal Entry.

This is a product model, not yet a commitment to a database schema.

## 7. Confirmed navigation

### 7.1 Mobile navigation

The mobile bottom navigation contains five primary destinations:

1. Home.
2. Inbox.
3. Timeline.
4. Habits.
5. Library.

Inbox displays a badge with the number of Entries awaiting review.

Habits remains a primary destination because check-ins are frequent actions.

Library contains:

- Collections.
- First Times.
- Goals.
- Homes.
- Vehicles.
- Places.
- People.

Settings is available from the profile control and does not occupy a bottom-navigation position.

### 7.2 Desktop navigation

Desktop uses a persistent sidebar with:

- New Entry.
- Search.
- Home.
- Inbox.
- Timeline.
- Habits.
- Collections.
- First Times.
- Goals.
- Homes.
- Vehicles.
- Places.
- People.
- Trash.
- Settings.

Specialized areas may be visually grouped under Library while remaining directly accessible.

### 7.3 Global capture

A persistent `+` quick-capture control is available from every primary screen.

On iPhone it opens a full-screen composer.

On desktop it opens a wide composer panel.

The composer supports text, speech-to-text, photos, and dates.

Saving immediately creates an Inbox Entry while AI suggestions are generated asynchronously.

## 8. Suggested first usable version

The first version should prove the central capture-to-retrieval loop before implementing every specialized tracker.

Proposed scope:

1. Universal quick capture with text, photos, and dates.
2. Inbox with manual organization status.
3. Automatic type, collection, and tag suggestions that remain manually editable.
4. Manual collections and tags.
5. Global search with useful filters.
6. A basic timeline for life stages and chronological Entries.
7. First Times as the first specialized Entry type.

Habits, Homes, and Vehicles remain important confirmed product areas, but may follow after the shared capture and retrieval foundation works well.

This sequencing is not final and should be changed if another area is more valuable to the user.

Core product features should be available on both native iOS and Web whenever the platform can support them.

The clients may reach parity incrementally, but neither client should become a permanently reduced companion experience.

## 9. Not decided yet

- AI provider and whether AI processing can leave the user's device.
- Whether optional Progressive Web App enhancements add enough value alongside the native iOS app.
- Whether the native iOS Share Extension belongs in the first release or shortly afterward.

## 10. Questions for the next discussion

### Direction-defining questions

1. Should the native iOS Share Extension belong in the first release or shortly afterward?
2. Should the Inbox support bulk review after the item-by-item workflow is established?
3. Which exact Entry fields should remain visible in the collapsed composer before the user asks for more options?

### Questions for later rounds

4. Should platform-specific features be labeled clearly when no true equivalent exists on the other client?

## 11. Current assumptions to validate

- MemoTrail is private and single-user for the foreseeable future.
- The UI should optimize for quick personal capture rather than collaboration or publishing.
- A single piece of content can appear in multiple views without creating copies.
- Automatic organization is assistance, not an irreversible action.
- Exact dates are optional for old memories.
- Photos are important first-class content, not merely decorative attachments.
- The initial product should be intentionally small and grow through actual use.

## 12. Confirmed platform and language direction

### 12.1 Client strategy

- MemoTrail has both a native iOS app and a responsive Web app.
- iPhone is the primary device for quick capture and a regular device for browsing and organizing old Entries.
- The Web app is optimized for desktop organization, search, Timeline exploration, long-form writing, analytics, export, and capture.
- Both clients should provide the same core features whenever technically feasible.
- Platform-specific interaction and system integration may differ when that produces a better native experience.
- Platform-specific implementation differences must not fragment the shared information model or create incompatible data.
- A native macOS app is not required because the Web app covers the primary desktop workflow.
- Progressive Web App support is an optional enhancement to the Web client, not the primary iPhone strategy.
- Both clients share the cloud backend, product model, API contracts, authentication, synchronization rules, AI behavior, and design language.
- Data is stored in a private cloud database to support cross-platform access and synchronization.
- The initial product interface is in English.
- Internationalization, including a Chinese interface, may be added later.
- The iOS bundle identifier is `com.rystudio.memotrail.app`.

### 12.2 Technical stack and repository

- The repository is a monorepo containing both product clients and shared infrastructure.
- The native iOS client uses SwiftUI.
- The Web client uses Next.js and TypeScript.
- Supabase provides Postgres, authentication, private object storage, and vector search infrastructure.
- Vercel deploys the Next.js application from `apps/web` rather than treating the repository root as the Web application.
- Shared cross-platform contracts use language-neutral schemas that can generate or validate TypeScript and Swift models.
- Database migrations, Row Level Security tests, and local Supabase configuration live in a root `supabase` directory.
- The discarded historical Next.js, Prisma, Lessons, and Milestones prototype is not restored as the new foundation.

The intended high-level repository shape is:

```text
apps/
  web/
  ios/
packages/
  contracts/
  design-tokens/
supabase/
  migrations/
  tests/
docs/
PRODUCT.md
SETUP_CHECKLIST.md
```

### 12.3 Visual direction

- The product should feel minimal, archival, and modern.
- Light mode and dark mode are both required in the initial release.
- The interface should use restrained hierarchy, careful typography, generous space, and subtle archival cues.
- Archival character should come from dates, chronology, typography, dividers, and metadata rather than decorative imitation of old paper.
- Soft Ledger is the selected initial visual direction.
- Soft Ledger uses calm geometry, a restrained green signal color, quiet surfaces, and approachable structure.
- The visual direction may evolve later when stronger references or preferences emerge.

### 12.4 Cross-platform design system

- Web and iOS share one semantic design-token source for color intent, spacing, radii, typography roles, motion intent, and elevation intent.
- Generated platform tokens may differ in representation while preserving the same semantic meaning.
- Web implements tokens through generated CSS custom properties and platform-appropriate components.
- iOS implements tokens through generated Swift values and native SwiftUI components.
- Both platforms use the same component names, states, content hierarchy, and interaction intent when technically feasible.
- Native platform conventions take precedence when identical rendering would reduce usability or accessibility.
- Generated token outputs are not edited manually.
- Changes to the design-token source must regenerate both Web and iOS outputs and pass consistency checks.

## 13. Confirmed home experience

The Home screen uses the following content order:

1. Search your life.
2. Quick Capture.
3. Today's Habits.
4. On This Day or another resurfaced memory.
5. Recent Entries.

Search and Quick Capture remain visually distinct so the product never has to guess the user's intent.

Today's Habits supports lightweight check-ins, while complete history and analytics remain in the Habits area.

Timeline remains available as its own major tab rather than dominating the Home screen.

The Home screen also shows a quiet, secondary resurfacing area below the primary actions.

Resurfacing formats may include:

- On This Day.
- One Year Ago.
- A Random Memory.
- You Were Thinking About This.

Resurfacing must not compete visually with quick capture or search.

The initial non-AI resurfacing rules are deterministic and privacy-scoped:

- Only the signed-in owner's organized, non-Trash, dated Entries are eligible.
- Life Stages remain in their dedicated Home context and unreviewed Inbox Entries do not resurface.
- On This Day takes priority and uses the Entry's original occurrence timezone to match month and day.
- When multiple anniversaries match, the nearest prior year is selected.
- When no anniversary matches, one Entry at least thirty days old is selected through a stable daily archive rotation.
- The resurfaced card preserves the original Entry context, organization, and private photos.
- Home quietly omits the section when there is no eligible memory.

## 14. Explicitly out of scope for now

- Social features.
- Public profiles or publishing.
- Multi-user collaboration.
- A marketplace or community template system.
- Complex permissions or team administration.
- Building every imaginable tracker before the central capture and retrieval experience is proven.

## 15. Success criteria to define later

The product is successful when the user trusts it as the default place to save meaningful personal information and can reliably find that information later.

Specific measurable criteria will be defined after the primary device, capture workflow, and first implementation scope are chosen.

## 16. Decision log

### 2026-08-29

- Use a responsive Web app first, optimized for iPhone capture and cross-device browsing and organization.
- Store data in a private cloud database for cross-platform access.
- Make immediate capture and global search the primary Home actions.
- Keep Timeline in a separate main tab.
- Send all new free-form entries to the Inbox in the initial version.
- Let AI suggest categories and tags without removing manual control.
- Consider high-confidence automatic filing only after the review workflow has proven trustworthy.
- Prioritize quick capture, Inbox, automatic organization suggestions, search, Timeline, and First Times.
- Use English for the initial product interface and leave room for future internationalization.
- Use Entry as the single user-facing term for independently searchable content.
- Start quick capture with one flexible text field and let AI suggest a title afterward.
- Support overlapping Timeline stages alongside point-in-time events.
- Treat voice input as a desired capture method.
- Support English, Chinese, and mixed-language content even though the interface is initially English.
- Use one unified search field for both keyword and natural-language search.
- Require AI-generated search answers to cite their source Entries.
- Use voice dictation only and do not retain original audio.
- Keep the user's original Entry separate from optional `Explore with AI` output.
- Use customizable Timeline tracks with a useful default set.
- Include Relationships as an available default Timeline track.
- Support both direct First Time creation and AI-assisted conversion from an Inbox Entry.
- Support exact dates, partial dates, approximate dates, date ranges, and age-based dates.
- Interpret numeric example dates using month-day-year order.
- Use one structural Type, multiple Collections, and multiple granular tags for Entry organization.
- Require confirmation before AI creates a proposed Collection.
- Keep an Entry in the Inbox until the user explicitly selects `Done`.
- Attach `Explore with AI` conversations to their source Entry.
- Save selected AI conclusions as separate, bidirectionally linked Entries.
- Proactively resurface old Entries in a quiet secondary area of Home.
- Support both Check and Measure Habit modes.
- Support daily, selected-weekday, weekly-target, and custom-interval Habit schedules.
- Distinguish Completed, Missed, Intentionally skipped, and Not scheduled Habit states.
- Treat intentional skips as neutral for completion rate and streak calculations.
- Allow optional Habit check-in notes and links to related Entries.
- Include streaks, completion rate, missed days, monthly summaries, yearly charts, and weekday patterns in Habit analytics.
- Do not include Habit reminders in the initial version.
- Use a low-pressure Goal Type with horizon, status, optional target date, related Entries, and progress notes.
- Represent progress without requiring percentages.
- Use the Bucket List Collection and Someday horizon for things the user wants to do.
- Allow an achieved Bucket List Goal to create a linked First Time Entry.
- Keep Ideas as regular Entries that can be converted into Goals.
- Exclude subtasks, complex project management, overdue warnings, and productivity scores from the initial product.
- Keep First Times lightweight, with only title required and no rating questionnaire.
- Keep Homes focused on personal history and exclude property-management features.
- Keep Vehicles focused on personal history and exclude operational vehicle-management features.
- Use reusable lightweight Place and Person entities across Entries.
- Support a future Map view while keeping it outside the earliest MVP.

### 2026-08-30

- Initially selected Apple, Google, and email magic-link authentication, but this was superseded later the same day by the Google-only launch scope below.
- Move deleted content to Trash for 30 days before permanent deletion.
- Require explicit confirmation for permanent deletion and emptying Trash.
- Keep restorable version history for Entry content and important metadata.
- Provide complete exports containing JSON, Markdown, structured CSV files, original media, and relationships.
- Use encrypted transport and cloud storage without end-to-end encryption in the initial version.
- Enforce private media access, server-only secrets, strict single-user access control, safe logging, and regular backups.
- Allow each AI capability to be disabled without breaking non-AI capture, browsing, or keyword search.
- Use Home, Inbox, Timeline, Habits, and Library as the five mobile navigation destinations.
- Use a persistent desktop sidebar with direct access to specialized areas.
- Keep a global quick-capture control available from every primary screen.
- Use a full-screen mobile composer and a wide desktop composer panel.
- Generate AI organization suggestions asynchronously after saving an Inbox Entry.
- Order Home around Search, Quick Capture, Today's Habits, resurfacing, and Recent Entries.
- Support offline capture with visible pending-sync state and automatic synchronization.
- Continuously preserve a recoverable local composer draft.
- Store created-at and occurred-at timestamps separately.
- Preserve original photos while serving optimized display derivatives.
- Use photo metadata only as a user-confirmed date and Place suggestion.
- Keep the responsive Web app requirement while reopening whether iPhone should use that Web client or a dedicated native iOS app.
- Use a native iOS app and a responsive Web app as the confirmed client strategy.
- Keep core feature coverage as consistent as technically feasible across both clients.
- Allow platform-specific interactions and integrations without creating incompatible product behavior or data.
- Treat Progressive Web App support as an optional Web enhancement rather than the primary iPhone client.
- Use SwiftUI, Next.js with TypeScript, and Supabase in a single monorepo.
- Deploy the Web client to Vercel from the `apps/web` root directory.
- Use `com.rystudio.memotrail.app` as the iOS bundle identifier.
- Require both light and dark themes in the first release.
- Use a minimal, archival, and modern visual direction.
- Supersede the earlier multi-provider launch decision and use only Google Sign-In initially.
- Defer Sign in with Apple until an Apple Developer account is available.
- Do not include email magic-link authentication in the initial product.
- Select Soft Ledger as the initial visual direction while allowing later refinement.
- Establish a shared semantic design system that generates platform-specific Web and Swift tokens.
- Approve Phase 1 foundation implementation before external projects and credentials are ready.

### 2026-09-03

- Start Home resurfacing without AI so it remains available before an AI provider is selected.
- Resurface only organized, active, dated Entries and keep Inbox content, Trash, and Life Stages out of the memory card.
- Prefer the nearest prior On This Day anniversary using the Entry's preserved occurrence timezone.
- Use a stable daily rotation across Entries at least thirty days old when no anniversary is available.
- Implement voice capture as live platform-native dictation into the editable Entry body without creating, persisting, or uploading an audio file.
- Prefer on-device iOS speech recognition when the current device and language support it, with the system speech service as the compatibility fallback.
- Keep Web voice capture as progressive enhancement because browser speech-recognition support varies, while preserving text, draft, and no-audio-retention behavior across clients.

## 17. Privacy, security, and data ownership

### 17.1 Authentication

MemoTrail supports the following sign-in methods:

- Sign in with Google.

Sign in with Apple is deferred until an Apple Developer account is available.

Email magic-link authentication is not included in the initial product.

The authentication model must allow additional providers to be added later without changing ownership of existing user data.

### 17.2 Trash and permanent deletion

Deleted Entries, Collections, media, and other recoverable content move to Trash for 30 days.

The user can restore content during that period.

`Delete forever` and `Empty Trash` require explicit confirmation.

Permanent deletion also removes associated version history according to the product's deletion policy.

### 17.3 Version history

Entries preserve restorable history for body content and important metadata changes.

The user can inspect an earlier version and restore it without losing the current version.

### 17.4 Export and portability

A complete export is delivered as a ZIP containing:

- JSON with the complete canonical data and relationships.
- Human-readable Markdown Entries.
- CSV files for structured areas such as Habits, Homes, and Vehicles.
- Original photos and attachments.
- Stable identifiers and relationship data needed for future re-import.

MemoTrail must not lock the user's life data inside a proprietary-only format.

### 17.5 Cloud security

The initial product uses encryption in transit and encryption at rest in its cloud services.

End-to-end encryption is not required for the initial version because server-side AI classification and semantic search need controlled access to content.

Required safeguards include:

- Strict single-user authorization for all data access.
- Server-only AI, database, and storage credentials.
- Private media that cannot be accessed through permanent public URLs.
- Regular database backups.
- Logs that do not contain full private Entry content.

### 17.6 AI controls

The user can individually disable:

- Automatic classification.
- Tag suggestions.
- Semantic search.
- Explore with AI.
- AI-assisted resurfacing suggestions.

Disabling AI does not disable manual capture, organization, browsing, or keyword search.

## 18. Concrete content examples

These examples ground the design in expected real use.

### 18.1 Life stages and periods

- Lived in China from age 1 to age 12.
- Lived in Philadelphia, United States, from age 12 to age 25.
- Lived in California from age 25 to age 26.
- Attended university from age 18 to age 23, overlapping with the Philadelphia period.

These examples confirm that Timeline periods may overlap and may describe different dimensions of life.

### 18.2 First Times

- First time skiing on 2026-07-03.
- First trip to Japan at age 17, on 2017-07-08.

### 18.3 Inbox Entries

- A reflection beginning with the question, "Why do people need to keep learning?", followed by the user's thoughts at that moment.
- A learning note explaining why plastic dental aligners can gradually move hard teeth.

The reflection example may belong to Reflection and Learning at the same time.

The dental aligner example is likely a Learning Entry, but the AI suggestions remain editable.

## 19. Date precision

Entries may use any of the following date precision levels:

- Exact date.
- Month and year.
- Year only.
- Age or age range.
- Date range.
- Approximate date or range.
- Unknown date.

The product should preserve the precision supplied by the user rather than inventing a more exact date.

For current numeric examples, `7.3.26` means July 3, 2026, and `7.8.17` means July 8, 2017.
