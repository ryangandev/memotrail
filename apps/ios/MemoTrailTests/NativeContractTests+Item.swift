import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// The Item page against the local stack: a Chapter's Entries and overlapping Chapters, its
// saved review, and moving an Entry to Trash. Each test dates its Entries in its own year, so
// the Entries other contract tests save never fall inside its Chapters.
extension NativeContractTests {
  func testChapterEntriesListsEntriesFullyInsideTheSpanAndPages() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let tag = "item \(marker)"

    let chapterID = try await saveItem(
      api, title: "Item Chapter \(marker)", body: "A month.", marks: .chapter,
      .day, "1987-03-01", end: "1987-03-31")
    // Inside, saved out of order: the page lists them oldest first.
    let late = try await saveItem(
      api, title: "Late \(marker)", body: "Third.", .day, "1987-03-20")
    let early = try await saveItem(
      api, title: nil, body: "First light.", tags: [tag], marks: .firstTime, .day, "1987-03-05")
    let middle = try await saveItem(
      api, title: "Middle \(marker)", body: "Second.", .day, "1987-03-12")
    // Not inside: before, after, no date, in Trash, and a Chapter nested in the span.
    _ = try await saveItem(api, title: "Before", body: "x", .day, "1987-02-20")
    _ = try await saveItem(api, title: "After", body: "x", .day, "1987-04-02")
    _ = try await saveItem(api, title: "Undated", body: "x", .unknown, nil)
    let trashed = try await saveItem(api, title: "Trashed", body: "x", .day, "1987-03-10")
    _ = try await saveItem(
      api, title: "Nested \(marker)", body: "x", marks: .chapter, .day, "1987-03-02",
      end: "1987-03-09")
    let trashedRevision = try await XCTUnwrapAsync(await api.detail(trashed)).revision
    try await api.moveToTrash(id: trashed, revision: trashedRevision)

    let page = try await api.chapterEntries(id: chapterID, offset: 0)
    XCTAssertEqual(page.map(\.id), [early, middle, late])
    XCTAssertEqual(page.map(\.totalCount), [3, 3, 3])
    // The untitled First Time is named by its date and carries its note as the excerpt.
    XCTAssertEqual(page[0].title, "")
    XCTAssertEqual(page[0].displayTitle, "Thursday, March 5, 1987")
    XCTAssertEqual(page[0].excerpt, "First light.")
    XCTAssertTrue(page[0].isFirstTime)
    XCTAssertEqual(page[0].tagNames, [tag])
    XCTAssertEqual(page[1].displayTitle, "Middle \(marker)")
    XCTAssertFalse(page[1].isFirstTime)
    XCTAssertNil(page[1].coverPhoto)
    XCTAssertNil(page[0].row(coverURL: nil).date)
    XCTAssertEqual(page[1].row(coverURL: nil).date, "Mar 12, 1987")

    // Pages continue where the last one ended, and the total stays the same.
    let first = try await api.chapterEntries(id: chapterID, offset: 0, limit: 2)
    XCTAssertEqual(first.map(\.id), [early, middle])
    XCTAssertEqual(first.first?.totalCount, 3)
    let second = try await api.chapterEntries(id: chapterID, offset: 2, limit: 2)
    XCTAssertEqual(second.map(\.id), [late])
    XCTAssertEqual(second.first?.totalCount, 3)
    let beyond = try await api.chapterEntries(id: chapterID, offset: 3, limit: 2)
    XCTAssertTrue(beyond.isEmpty)
    XCTAssertEqual(
      ItemPageController.appending(second, to: first).map(\.id), [early, middle, late])

    // An Entry is not a Chapter, so it holds nothing; neither does a Chapter without dates.
    let entriesOfAnEntry = try await api.chapterEntries(id: early, offset: 0)
    XCTAssertTrue(entriesOfAnEntry.isEmpty)
    let undatedChapter = try await saveItem(
      api, title: "Undated Chapter \(marker)", body: "", marks: .chapter, .unknown, nil)
    let entriesOfUndated = try await api.chapterEntries(id: undatedChapter, offset: 0)
    XCTAssertTrue(entriesOfUndated.isEmpty)

    // The Item page controller shows the same first page and the total.
    let controller = ItemPageController(client: client, ownerID: ownerID, entryID: chapterID)
    await controller.load()
    XCTAssertEqual(controller.entry?.subtype, .chapter)
    XCTAssertEqual(controller.chapterEntries.map(\.id), [early, middle, late])
    XCTAssertEqual(controller.chapterEntryCount, 3)
    XCTAssertFalse(controller.hasMoreEntries)
    XCTAssertNil(controller.chapterErrorMessage)
    XCTAssertNil(controller.review)
  }

  func testChapterOverlapsListsNestedAndPartlyOverlappingChapters() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()

    let main = try await saveItem(
      api, title: "Main \(marker)", body: "", marks: .chapter, .day, "1988-03-01",
      end: "1988-09-30")
    let partlyAfter = try await saveItem(
      api, title: "Partly after \(marker)", body: "", marks: .chapter, .day, "1988-08-15",
      end: "1989-02-01")
    let nested = try await saveItem(
      api, title: "Nested \(marker)", body: "", marks: .chapter, .day, "1988-04-01",
      end: "1988-05-31")
    let firstTime = try await saveItem(
      api, title: "Also a First Time \(marker)", body: "",
      marks: EntryMarks(isChapter: true, isFirstTime: true), .day, "1988-06-01",
      end: "1988-06-30")
    let partlyBefore = try await saveItem(
      api, title: "Partly before \(marker)", body: "", marks: .chapter, .day, "1987-11-01",
      end: "1988-03-01")
    // The same days as another year, a Chapter in Trash, an undated one, and an ordinary Entry
    // inside the span are not Chapters beside this one.
    _ = try await saveItem(
      api, title: "Earlier \(marker)", body: "", marks: .chapter, .day, "1987-01-01",
      end: "1988-02-29")
    _ = try await saveItem(
      api, title: "Later \(marker)", body: "", marks: .chapter, .day, "1988-10-01",
      end: "1988-12-31")
    let trashed = try await saveItem(
      api, title: "Trashed \(marker)", body: "", marks: .chapter, .day, "1988-05-01",
      end: "1988-05-10")
    _ = try await saveItem(
      api, title: "Undated \(marker)", body: "", marks: .chapter, .unknown, nil)
    let plainEntry = try await saveItem(
      api, title: "An Entry \(marker)", body: "x", .day, "1988-05-05")
    let trashedRevision = try await XCTUnwrapAsync(await api.detail(trashed)).revision
    try await api.moveToTrash(id: trashed, revision: trashedRevision)

    // Oldest window first; a Chapter that shares only its last day with this one still counts.
    let overlaps = try await api.chapterOverlaps(id: main)
    XCTAssertEqual(
      overlaps.map(\.id), [partlyBefore, nested, firstTime, partlyAfter],
      "\(overlaps.map(\.displayTitle))")
    XCTAssertEqual(overlaps.map(\.isFirstTime), [false, false, true, false])
    XCTAssertEqual(overlaps[1].displayTitle, "Nested \(marker)")
    XCTAssertEqual(overlaps[1].windowStart, "1988-04-01")
    XCTAssertEqual(overlaps[1].occurrence.spanLabel, "Apr 1, 1988 - May 31, 1988")
    // A Chapter never overlaps itself, and an Entry or an undated Chapter overlaps nothing.
    let ofNested = try await api.chapterOverlaps(id: nested)
    XCTAssertEqual(ofNested.map(\.id), [main])
    let ofAnEntry = try await api.chapterOverlaps(id: plainEntry)
    XCTAssertTrue(ofAnEntry.isEmpty)

    let controller = ItemPageController(client: client, ownerID: ownerID, entryID: main)
    await controller.load()
    XCTAssertEqual(controller.chapterOverlaps.map(\.id), [partlyBefore, nested, firstTime, partlyAfter])
    XCTAssertTrue(controller.chapterEntries.isEmpty)
    XCTAssertEqual(controller.chapterEntryCount, 0)
    XCTAssertNil(controller.chapterErrorMessage)
  }

  func testAChapterShowsItsSavedReviewAndHidesWhatItNoLongerRests() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let today = ReviewDates.localDate()

    let chapterID = try await saveItem(
      api, title: "Reviewed \(marker)", body: "The year I looked for work.", marks: .chapter,
      .day, "1989-03-01", end: "1989-06-20")
    let worry = try await saveItem(
      api, title: "First rejection", body: "I felt anxious about the first interview today.",
      tags: ["review \(marker)"], .day, "1989-03-05")
    let practice = try await saveItem(
      api, title: "Practice", body: "Practiced questions with my brother.", .day, "1989-03-20")
    let second = try await saveItem(
      api, title: "Second round", body: "It went better than I expected.", .day, "1989-04-10")
    let offer = try await saveItem(
      api, title: "First offer", body: "My first ever offer arrived.", marks: .firstTime, .day,
      "1989-04-25")
    let decision = try await saveItem(
      api, title: "Decision", body: "I decided to accept the offer.", .day, "1989-06-01")

    // A review is made on Web with Claude, so this stores one the way the Web job does, with
    // no model call: switch reviews on, claim a job, and store grounded content.
    let settings: AnyJSON = try await client.rpc("review_settings").execute().value
    let revision = settings.objectValue?["revision"]?.intValue ?? 0
    let preferences: [String: AnyJSON] = [
      "p_reviews": true, "p_suggestions": false, "p_disclosure_version": "2026-10-18",
      "p_expected_revision": .integer(revision),
    ]
    let saved: AnyJSON = try await client.rpc("save_review_preferences", params: preferences)
      .execute().value
    XCTAssertEqual(saved.objectValue?["reviewsEnabled"]?.boolValue, true)

    let ids = [worry, practice, second, offer, decision]
    let plan: [String: AnyJSON] = [
      "disclosureVersion": "2026-10-18", "planHash": .string(String(repeating: "a", count: 64)),
      "mode": "single", "entryIds": .array(ids.map { .string($0.uuidString.lowercased()) }),
      "sources": [], "entriesInPeriod": .integer(ids.count), "trimmedEntries": 0,
      "language": "en", "ongoing": false,
      "steps": [
        [
          "index": 0, "kind": "review",
          "entryIds": .array(ids.map { .string($0.uuidString.lowercased()) }),
        ]
      ],
    ]
    let claimParameters: [String: AnyJSON] = [
      "p_scope": "chapter", "p_chapter_id": .string(chapterID.uuidString.lowercased()),
      "p_year": .null, "p_local_date": .string(today), "p_plan": .object(plan),
    ]
    let job: AnyJSON = try await client.rpc("claim_entry_review", params: claimParameters)
      .execute().value
    let reviewID = try XCTUnwrap(job.objectValue?["reviewId"]?.stringValue)
    let startedAt = try XCTUnwrap(job.objectValue?["jobStartedAt"]?.stringValue)
    let stepParameters: [String: AnyJSON] = [
      "p_review_id": .string(reviewID), "p_job_started_at": .string(startedAt), "p_max": 6,
    ]
    let claim: AnyJSON = try await client.rpc("claim_review_steps", params: stepParameters)
      .execute().value
    XCTAssertEqual(claim.objectValue?["claimed"]?.arrayValue?.compactMap(\.intValue), [0])

    func id(_ entry: UUID) -> AnyJSON { .string(entry.uuidString.lowercased()) }
    let content: AnyJSON = [
      "summary": "A tense few months that ended well.",
      "feelings": [
        "overview": "From worry to relief.",
        "phases": [
          [
            "feeling": "Anxious, then steadier", "description": "It eased.",
            "entryIds": [id(worry), id(practice)], "windowStart": "1989-03-05",
            "windowEnd": "1989-03-21",
          ]
        ],
      ],
      "themes": [
        [
          "name": "Interviews", "description": "They kept coming.",
          "entryIds": [id(worry), id(second)],
        ]
      ],
      "quotes": [
        [
          "entryId": id(worry), "start": 7, "end": 40,
          "text": "anxious about the first interview", "why": "It names the worry.",
        ],
        [
          "entryId": id(second), "start": 0, "end": 14, "text": "It went better",
          "why": "A turn.",
        ],
      ],
    ]
    var sources: [AnyJSON] = []
    for entry in [chapterID] + ids {
      let revision = try await XCTUnwrapAsync(await api.detail(entry)).revision
      sources.append(["entryId": id(entry), "revision": .integer(revision)])
    }
    let storeParameters: [String: AnyJSON] = [
      "p_review_id": .string(reviewID), "p_job_started_at": .string(startedAt),
      "p_content": content, "p_model": "claude-sonnet-5-5", "p_entries_read": 5,
      "p_sources": .array(sources),
    ]
    let stored: Bool = try await client.rpc("store_entry_review", params: storeParameters)
      .execute().value
    XCTAssertTrue(stored)

    // The Item page reads it: both quotes, every citation, and the live facts.
    let controller = ItemPageController(client: client, ownerID: ownerID, entryID: chapterID)
    await controller.load()
    let review = try XCTUnwrap(controller.review)
    let display = ReviewDisplay(review)
    XCTAssertEqual(review.title, "Review")
    XCTAssertEqual(review.readLabel, "Read all 5 Entries")
    XCTAssertEqual(display.overview, "From worry to relief.")
    XCTAssertEqual(display.phases.map(\.range), ["March 1989"])
    XCTAssertEqual(display.phases.first?.cited.map(\.id), [worry, practice])
    XCTAssertEqual(display.themes.first?.cited.map(\.displayTitle), ["First rejection", "Second round"])
    XCTAssertEqual(display.quotes.map(\.text), ["anxious about the first interview", "It went better"])
    XCTAssertEqual(display.quotes.map(\.source.id), [worry, second])
    XCTAssertEqual(display.hiddenQuoteCount, 0)
    XCTAssertTrue(review.notices.isEmpty)
    let facts = try XCTUnwrap(controller.reviewFacts)
    XCTAssertEqual(facts.entryCount, 5)
    XCTAssertEqual(facts.firstTimes.map(\.id), [offer])
    XCTAssertEqual(facts.topTags, [.init(name: "review \(marker)", count: 1)])
    XCTAssertEqual(facts.busiestMonthLine, "Most writing: March 1989 (2 Entries)")

    // Editing a quote's words away, or moving a cited Entry to Trash, hides them again without
    // touching the stored review.
    let editable = try await XCTUnwrapAsync(await api.editable(second))
    _ = try await api.save(
      SaveEntryParameters(
        entryID: second, expectedRevision: editable.revision, title: editable.title,
        body: "It was fine.", richText: nil, occurrence: editable.occurrence(),
        tagNames: editable.tagNames, location: nil, marks: editable.marks))
    let practiceRevision = try await XCTUnwrapAsync(await api.detail(practice)).revision
    try await api.moveToTrash(id: practice, revision: practiceRevision)
    await controller.load()
    let changed = try XCTUnwrap(controller.review)
    let changedDisplay = ReviewDisplay(changed)
    XCTAssertEqual(changedDisplay.quotes.map(\.source.id), [worry])
    XCTAssertEqual(changedDisplay.hiddenQuoteCount, 1)
    XCTAssertEqual(changedDisplay.phases.first?.cited.map(\.id), [worry])
    XCTAssertEqual(changed.changes.trashedEntries, 1)
    XCTAssertEqual(changed.changes.editedEntries, 1)
    XCTAssertEqual(changed.notices.count, 2)

    // A Chapter with no review shows none, and an Entry never asks.
    let plain = ItemPageController(client: client, ownerID: ownerID, entryID: decision)
    await plain.load()
    XCTAssertNil(plain.review)
    let other = try await saveItem(
      api, title: "Other \(marker)", body: "", marks: .chapter, .day, "1990-01-01",
      end: "1990-02-01")
    let without = ItemPageController(client: client, ownerID: ownerID, entryID: other)
    await without.load()
    XCTAssertNil(without.review)
    XCTAssertNotNil(without.reviewFacts)
  }

  func testMovingAnEntryToTrashFromItsItemPageKeepsItRestorable() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let id = try await saveItem(
      api, title: "Trash me \(marker)", body: "Gone for now.", .day, "1991-05-05")

    let controller = ItemPageController(client: client, ownerID: ownerID, entryID: id)
    await controller.load()
    XCTAssertEqual(controller.entry?.displayTitle, "Trash me \(marker)")
    XCTAssertFalse(try XCTUnwrap(controller.entry).isInTrash)
    let failure = await controller.moveToTrash()
    XCTAssertNil(failure)

    // Item still reads from Trash, marked as deleted, and shows no photos or Chapter parts.
    await controller.load()
    XCTAssertTrue(try XCTUnwrap(controller.entry).isInTrash)
    XCTAssertTrue(controller.photos.isEmpty)
    // The same version cannot be moved twice, so a stale page learns it changed.
    let again = await controller.moveToTrash()
    XCTAssertEqual(again, EntryTrashError.changed.errorDescription)
    // Editing it is refused while it is in Trash.
    let editable = await controller.editableEntry()
    XCTAssertNil(editable)
  }

  // MARK: Helpers

  /// Saves an Entry or Chapter dated in the days given (`yyyy-MM-dd`, UTC, at noon).
  private func saveItem(
    _ api: EntryAPI, title: String?, body: String, tags: [String] = [],
    marks: EntryMarks = .none, _ precision: DatePrecision, _ start: String?, end: String? = nil
  ) async throws -> UUID {
    func noon(_ day: String?) throws -> Date? {
      try day.map { try XCTUnwrap(EntryTimestamp.date(from: "\($0)T12:00:00Z"), $0) }
    }
    let id = UUID()
    _ = try await api.save(
      SaveEntryParameters(
        entryID: id, expectedRevision: nil, title: title, body: body, richText: nil,
        occurrence: EntryOccurrence(
          precision: precision, start: try noon(start), end: try noon(end), label: nil,
          timezone: "UTC"),
        tagNames: tags, location: nil, marks: marks))
    return id
  }
}
