# MemoTrail Positioning

Settled with Ryan on 2026-10-18 through a product-positioning discussion.
This document says why MemoTrail exists, who it serves, and which ideas belong in it.
Use it as the filter for every new feature and every removal.
[product.md](./product.md) describes the product behavior that follows from it.

## In one sentence

MemoTrail is the one place your life is written down: jot down a thought, a mood, something learned, or something lived in seconds, find it again from any half-remembered clue, and get back the story of each chapter of your life.

How a user should describe it to a friend:

> I drop everything into it, what I think, what I learn, what I do for the first time.
> When I need to know when something happened, I find it in a second, and at the end of a chapter it shows me what I was going through.

## The problem

Memory fades, and the moment we need it back is unpredictable.
Someone asks when you started skiing or climbing, and you cannot remember.
A person, a conversation, or an idea comes to mind, and you cannot find what you wrote about it.

People already write these things down, but in scattered places:

| What people record                        | Where it lives today | Why it falls short                                                       |
| ----------------------------------------- | -------------------- | ------------------------------------------------------------------------ |
| Moods, diary entries                      | Apple Journal        | Separate from everything else, weak retrieval, no sense of life chapters |
| Things learned, interesting quotes, ideas | Apple Notes          | No time or memory dimension; a note is a fact, not a moment in your life |
| A stretch of life, such as a job search   | Notion               | Needs manual structure up front; disconnected from moods and daily life  |

No single tool can answer "what was I going through in the first half of 2026?", because that period is split across three apps.
The real competitor is fragmentation, not any one app.

## Who it is for

MemoTrail is for anyone who jots down moments of their life and wants them back later.

The first group to focus on is people going through a life transition: a job search, a move to a new city, graduation, or the start or end of a relationship.
They record the most during those periods and care the most about looking back on them.
Focusing the message on them does not exclude everyday users who simply want a calm place to write things down.

## The promise: three returns

Recording is the most frequent action, but recording alone is not the value.
The value is what comes back, in three strengths:

1. **Kept safe.** Whatever was written is preserved, private, and exportable. This is the only return available on day one.
2. **Found.** Anything can be found from a keyword, a person's name, a description of a person or situation without the name, or a rough time.
3. **Given back.** When a chapter ends or a year passes, MemoTrail shows what that period held: how feelings changed, which themes kept returning, and the user's own words from that time.

Returns are rare and earned.
Retrieval on demand comes first.
Notifications are acceptable only when infrequent; a daily "one year ago" push is not part of the product.

## Core model

The product reduces to three ideas.

### Entry

One record: writing, optional photos, a date, and optional tags.
Moods, quotes, insights from conversations, learning notes, long reflections, and life events are all Entries in one stream.
Knowledge notes need no separate knowledge-base features; they matter because they bring back the moment of learning.
A First Time is a mark on an Entry, not a separate record type.

### Chapter

A named stretch of time, such as "2026 job search", "Studying in Philadelphia", or "Driving the old Civic".
It has a name, a start, and an optional end, and chapters may overlap.
A chapter contains every Entry dated inside it, with no tagging or filing, so opening it shows the whole of life during that period.
The user can create a chapter, and MemoTrail may suggest one from what the user has been writing about; a suggestion becomes a chapter only after the user confirms it.
Chapters replace dedicated record forms such as Homes and Vehicles: where you lived or what you drove is a chapter or an Entry, found through search.

### Return

Search across every Entry, and reviews of a chapter or a year.
Timeline is a way to view chapters and Entries in time, not a separate structure to maintain.

## Decision filter

A feature belongs in MemoTrail only when it passes these tests.

1. **Capture asks for no decision.** Nothing is required beyond writing, and nothing treats an unorganized Entry as unfinished.
2. **Retrieval never depends on prior organizing.** If finding something only works after the user filed it correctly, the design is wrong.
3. **Structure comes from time, not forms.** Prefer chapters and dates over typed records with fields.
4. **Returns are rare and earned.** No daily nags, streaks, or backlogs.
5. **One stream for everything.** No separate areas that split a life back into pieces.
6. **Privacy is layered.** Finding things never sends content to a third party; generating reviews does so only with the user's explicit choice.

## AI and privacy

AI earns its place in finding and giving back, not in organizing.

| Capability                         | Approach                                                                                                                     |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Keyword search                     | No AI                                                                                                                        |
| Semantic search                    | On by default, using an embedding model MemoTrail runs itself, so content does not go to a third party                       |
| Chapter and year reviews           | Opt-in; uses a third-party model that does not train on the data, states its retention honestly, and says what is sent first |
| Chapter suggestions                | Opt-in, confirmed by the user before a chapter exists                                                                        |
| Title, tag, and filing suggestions | Not a priority                                                                                                               |

## Cold start

Reviews need months of data, so day-one value must come from fast capture and excellent search alone.
Importing existing Apple Journal, Apple Notes, and Notion content is the best way to give a new user a past to search and review immediately.
The feasibility of each import source still needs to be verified.

## Recording moments

Recording happens in two modes, and both must feel effortless:

- **On the phone:** short and immediate, such as a mood or a sudden realization, in well under a minute.
- **On the computer:** long-form writing while studying or reading.

Short capture on the phone is the most frequent action, so mobile capture speed matters.
Web still comes first; native iOS follows the finished Web behavior.

## Keep, change, and cut

Compared with the product as of 2026-10-18:

| Current area                                                  | Decision                                                                 |
| ------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Quick Capture, rich text, photos                              | Keep; this is the core action                                            |
| Tags                                                          | Keep as optional; never required for retrieval                           |
| Keyword search                                                | Keep, and add semantic search as the next core capability                |
| Trash, export                                                 | Keep; part of "kept safe"                                                |
| First Times                                                   | Keep as a mark on Entries and a filtered view                            |
| Timeline lanes, Now                                           | Change into chapters and a time view over them                           |
| Homes, Vehicles                                               | Change into chapters or ordinary Entries; retire the dedicated forms     |
| Dashboard resurfaced memory                                   | Demote; chapter and year reviews become the main way the past comes back |
| Someday                                                       | Cut: a list of intentions is not part of recording a life                |
| Map                                                           | Cut: place is not a primary retrieval clue                               |
| Habits, People records, version history, Inbox, general links | Stay out                                                                 |

## Open questions

- How each import source can be read, and which one matters most.
- How chapter suggestions are presented without becoming nags.
- How often, if ever, MemoTrail should send a notification.
- Whether the Dashboard keeps a small daily memory or gives that space to chapters.
