import XCTest

@testable import MemoTrail

/// The Item page's facts and rows, and a Chapter's saved review read from the `chapter_review`
/// return shape, against Web `entry-detail.ts`, `chapter-contents.ts`, and `review-panel.tsx`.
final class ItemPageTests: XCTestCase {
  // MARK: Facts

  func testDateFactAppearsOnlyWhenItSaysMoreThanTheHeading() throws {
    let start = try date("2021-05-10T11:00:00Z")
    let end = try date("2021-05-14T11:00:00Z")
    func entry(
      title: String? = nil, precision: DatePrecision, start: Date? = start, end: Date? = nil,
      label: String? = nil
    ) -> EntryDetail {
      EntryDetail(
        id: UUID(), title: title, body: "x", revision: 1, occurredStart: start, occurredEnd: end,
        occurredLabel: label, occurredTimezone: "UTC", datePrecision: precision)
    }
    func dateFact(_ entry: EntryDetail) -> String? {
      entry.facts().first { $0.label == "Date" }?.value
    }

    // An untitled Entry is headed by its date, so a plain day, month, or year adds nothing.
    XCTAssertEqual(entry(precision: .day).displayTitle, "Monday, May 10, 2021")
    XCTAssertNil(dateFact(entry(precision: .day)))
    XCTAssertNil(dateFact(entry(precision: .month)))
    XCTAssertNil(dateFact(entry(precision: .year)))
    // The heading is a description or "Undated entry", so the Date fact would repeat it.
    XCTAssertNil(dateFact(entry(precision: .approximate, label: "Late 1990s")))
    XCTAssertNil(dateFact(entry(precision: .unknown, start: nil)))
    XCTAssertNil(dateFact(entry(precision: .range, end: end)))
    // The time of an exact moment, and an end the heading leaves out, are new information.
    XCTAssertNotNil(dateFact(entry(precision: .exact)))
    XCTAssertTrue(try XCTUnwrap(dateFact(entry(precision: .exact))).hasPrefix("May 10, 2021, "))
    XCTAssertEqual(dateFact(entry(precision: .day, end: end)), "May 10, 2021 to May 14, 2021")
    // A titled Entry's heading says nothing of its date.
    XCTAssertEqual(dateFact(entry(title: "Harbor lights", precision: .day)), "May 10, 2021")
    XCTAssertEqual(dateFact(entry(title: "Harbor lights", precision: .year)), "2021")
    XCTAssertEqual(dateFact(entry(title: "Someday", precision: .unknown, start: nil)), "Unknown")
    XCTAssertEqual(
      dateFact(entry(title: "Memory", precision: .age, start: nil, label: "Age 7")), "Age 7")
  }

  func testAChapterDateFactNamesItsSpanAndHowLongItLasted() throws {
    let studio = EntryDetail(
      id: UUID(), title: "Studio years", body: "", subtype: .chapter, revision: 1,
      occurredStart: try date("2020-03-12T12:00:00Z"),
      occurredEnd: try date("2026-09-03T12:00:00Z"), occurredTimezone: "UTC",
      datePrecision: .month)
    XCTAssertEqual(
      studio.facts(now: try date("2030-01-01T00:00:00Z")).map(\.value),
      ["Mar 2020 - Sep 2026 · About 6 years 6 months"])

    // An open Chapter runs to today, and one with no calendar date has no duration to measure.
    let open = EntryDetail(
      id: UUID(), title: "Maple Street", body: "", subtype: .chapter, revision: 1,
      occurredStart: try date("2024-06-01T12:00:00Z"), occurredTimezone: "UTC",
      datePrecision: .day)
    XCTAssertEqual(
      open.facts(now: try date("2026-09-15T12:00:00Z")).map(\.value),
      ["Since Jun 1, 2024 · 2 years 3 months"])
    let undated = EntryDetail(
      id: UUID(), title: "Someday", body: "", subtype: .chapter, revision: 1)
    XCTAssertEqual(undated.facts().map(\.value), ["Date unknown"])
  }

  func testTagsAndLocationsFollowTheDateAndCapitalizeEachWord() throws {
    let entry = EntryDetail(
      id: UUID(), title: "Harbor", body: "x", revision: 1, occurredStart: try date("2021-05-10T11:00:00Z"),
      occurredTimezone: "UTC", datePrecision: .day,
      tags: [
        .init(id: UUID(), name: "road trip"), .init(id: UUID(), name: "NASA"),
        .init(id: UUID(), name: "beach-day"),
      ],
      locations: [
        .init(
          locationID: UUID(), relationship: .primary, formattedAddress: "rua augusta 1, lisboa",
          latitude: nil, longitude: nil)
      ])
    let facts = entry.facts()
    XCTAssertEqual(facts.map(\.label), ["Date", "Tags", "Locations"])
    XCTAssertEqual(facts[0].displayValue, "May 10, 2021")
    XCTAssertEqual(facts[1].displayValue, "Road Trip, NASA, Beach-Day")
    XCTAssertEqual(facts[2].displayValue, "Rua Augusta 1, Lisboa")
    // Without tags or locations, the facts name neither.
    XCTAssertEqual(
      EntryDetail(id: UUID(), title: "Plain", body: "x", revision: 1).facts().map(\.label),
      ["Date"])
    XCTAssertEqual(
      EntryDetail(id: UUID(), title: nil, body: "x", revision: 1).facts().map(\.label), [])
  }

  // MARK: A Chapter's Entries

  func testChapterEntryRowsShowTheirDateOnlyWhenTheyHaveATitle() throws {
    let entries = try JSONDecoder().decode(
      [ChapterEntry].self, from: Data(chapterEntriesJSON.utf8))
    XCTAssertEqual(entries.count, 2)
    let untitled = entries[0].row(coverURL: nil)
    // An untitled Entry is already named by its date, so the row repeats nothing.
    XCTAssertEqual(untitled.title, "Monday, May 10, 2021")
    XCTAssertNil(untitled.date)
    XCTAssertTrue(untitled.isFirstTime)
    XCTAssertEqual(untitled.excerpt, "Harbor lights")
    let titled = entries[1].row(coverURL: URL(string: "https://example.test/cover"))
    XCTAssertEqual(titled.title, "Second week")
    XCTAssertEqual(titled.date, "Date unknown")
    XCTAssertFalse(titled.isFirstTime)
    XCTAssertEqual(titled.coverURL, URL(string: "https://example.test/cover"))
    XCTAssertEqual(entries[0].totalCount, 2)
    XCTAssertEqual(entries[1].totalCount, 2)
  }

  func testALaterPageAddsOnlyEntriesNotAlreadyListed() throws {
    let entries = try JSONDecoder().decode(
      [ChapterEntry].self, from: Data(chapterEntriesJSON.utf8))
    XCTAssertEqual(
      ItemPageController.appending(entries, to: [entries[0]]).map(\.id), entries.map(\.id))
    XCTAssertEqual(ItemPageController.appending([], to: entries).map(\.id), entries.map(\.id))
  }

  // MARK: Reviews

  func testChapterReviewDecodesWhatWebReads() throws {
    let page = try JSONDecoder().decode(ChapterReview.self, from: Data(reviewJSON.utf8))
    let review = try XCTUnwrap(page.shown)
    XCTAssertEqual(review.id, UUID(uuidString: "83000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(review.title, "Review")
    XCTAssertEqual(review.entriesInPeriod, 6)
    XCTAssertEqual(review.entriesRead, 6)
    XCTAssertEqual(review.readLabel, "Read all 6 Entries")
    XCTAssertEqual(
      review.madeLabel(timezone: try XCTUnwrap(TimeZone(identifier: "UTC"))), "Made Oct 18, 2026")
    XCTAssertEqual(review.language, "en")
    XCTAssertEqual(review.quoteAvailable, [true, false])
    XCTAssertEqual(review.sources.count, 3)
    XCTAssertEqual(review.sources.filter(\.isTrashed).count, 1)
    XCTAssertEqual(review.changes, .init(newEntries: 0, editedEntries: 1, trashedEntries: 1))
    let content = try XCTUnwrap(review.content)
    XCTAssertEqual(content.overview, "From worry to relief.")
    XCTAssertEqual(content.phases.count, 1)
    XCTAssertEqual(content.themes.count, 1)
    XCTAssertEqual(content.quotes.count, 2)

    let facts = try XCTUnwrap(page.facts)
    XCTAssertEqual(facts.entryCount, 6)
    XCTAssertEqual(facts.firstTimes.map(\.displayTitle), ["First offer"])
    XCTAssertEqual(facts.topTags, [.init(name: "interviews", count: 3), .init(name: "family", count: 1)])
    XCTAssertEqual(facts.busiestMonthLine, "Most writing: March 2026 (2 Entries)")
    XCTAssertEqual(
      facts.stats(spanLabel: "Mar 2026 - Jun 2026"),
      ["6 Entries", "Mar 2026 - Jun 2026", "1 First Time"])
  }

  func testAReviewHidesCitationsAndQuotesWhoseEntryIsInTrashOrEditedAway() throws {
    let review = try XCTUnwrap(
      JSONDecoder().decode(ChapterReview.self, from: Data(reviewJSON.utf8)).shown)
    let display = ReviewDisplay(review)
    XCTAssertEqual(display.overview, "From worry to relief.")
    // The phase cited two Entries; the one in Trash is left out, the other stays.
    XCTAssertEqual(display.phases.count, 1)
    XCTAssertEqual(display.phases[0].cited.map(\.title), ["First rejection"])
    XCTAssertEqual(display.phases[0].range, "March 2026")
    XCTAssertEqual(display.themes[0].cited.map(\.title), ["First rejection", "Second round"])
    // The second quote's words are no longer in its Entry, which `quoteAvailable` says.
    XCTAssertEqual(display.quotes.map(\.text), ["anxious about the first interview"])
    XCTAssertEqual(display.quotes[0].source.displayTitle, "First rejection")
    XCTAssertEqual(display.quotes[0].source.dateLabel, "Mar 5, 2026")
    XCTAssertEqual(display.hiddenQuoteCount, 1)
    XCTAssertEqual(
      display.hiddenQuotesNote,
      "1 quote is hidden because its Entry was edited or moved to Trash.")
  }

  func testAPhaseOrThemeWithNoVisibleCitationIsLeftOut() throws {
    let trashed = ReviewEntryRef(id: UUID(), title: "Gone", isTrashed: true)
    let review = StoredReview(
      id: UUID(),
      content: ReviewContent(
        summary: "s", overview: "o",
        phases: [
          .init(
            feeling: "Low", description: "d", entryIDs: [trashed.id], windowStart: "2026-03-05",
            windowEnd: "2026-03-21")
        ],
        themes: [.init(name: "Work", description: "d", entryIDs: [trashed.id, UUID()])],
        quotes: [.init(entryID: trashed.id, start: 0, end: 1, text: "x", why: "y")]),
      entriesInPeriod: 6, entriesRead: 6, quoteAvailable: [true], sources: [trashed])
    let display = ReviewDisplay(review)
    XCTAssertTrue(display.phases.isEmpty)
    XCTAssertTrue(display.themes.isEmpty)
    // A quote needs its Entry active; Trash hides it even when its words still match.
    XCTAssertTrue(display.quotes.isEmpty)
    XCTAssertEqual(display.hiddenQuoteCount, 1)
  }

  func testReviewNoticesSayWhatChangedSinceItWasMade() throws {
    let review = try XCTUnwrap(
      JSONDecoder().decode(ChapterReview.self, from: Data(reviewJSON.utf8)).shown)
    XCTAssertEqual(
      review.notices,
      [
        "1 Entry in this Chapter is new or changed since this review.",
        "1 Entry this review read is in Trash, so what came from it is hidden. Restore it, or make a new review without it on the Web.",
      ])
    let sampled = StoredReview(
      id: UUID(), content: ReviewContent(summary: "s"), entriesInPeriod: 80, entriesRead: 40,
      trimmedEntries: 3)
    XCTAssertEqual(sampled.readLabel, "Read 40 of 80 Entries")
    XCTAssertEqual(
      sampled.notices,
      [
        "This Chapter holds more writing than one review reads. This review read 40 of 80 Entries, spread evenly across the period, and the first 6,000 characters of longer ones."
      ])
    let longer = StoredReview(
      id: UUID(), content: ReviewContent(summary: "s"), entriesInPeriod: 6, entriesRead: 6,
      trimmedEntries: 2)
    XCTAssertEqual(
      longer.notices,
      [
        "This Chapter holds more writing than one review reads. This review read the first 6,000 characters of longer Entries."
      ])
    XCTAssertEqual(
      StoredReview(id: UUID(), content: ReviewContent(summary: "s"), isOngoing: true).title,
      "Review so far")
    XCTAssertTrue(
      StoredReview(id: UUID(), content: ReviewContent(summary: "s"), entriesInPeriod: 6, entriesRead: 6)
        .notices.isEmpty)
  }

  func testAChapterWithoutAReadableReviewShowsNone() throws {
    // No review yet, a job still writing the first one, and content of the wrong shape.
    for json in [
      #"{"eligibility":{"status":"eligible"},"facts":null,"review":null}"#,
      #"{"facts":null,"review":{"id":"83000000-0000-4000-8000-000000000002","content":null,"job":{"status":"generating"}}}"#,
      #"{"facts":null,"review":{"id":"83000000-0000-4000-8000-000000000002","content":{"summary":3}}}"#,
      #"{"facts":null,"review":{"content":{"summary":"s","feelings":{}}}}"#,
    ] {
      let page = try JSONDecoder().decode(ChapterReview.self, from: Data(json.utf8))
      XCTAssertNil(page.shown, json)
    }
  }

  func testReviewDecodingDropsPartsWithTheWrongShapeInsteadOfFailing() throws {
    let json = """
      {"facts":{"entryCount":"6","firstTimes":[{"title":"No id"},\
      {"id":"82000000-0000-4000-8000-000000000014","title":" First offer ","datePrecision":"day",\
      "occurredStart":"2026-04-25T12:00:00+00:00","occurredTimezone":"Not/AZone"}],\
      "topTags":[{"name":"a","count":"2"},{"count":1}],"busiestMonth":{"month":"March","count":1}},\
      "review":{"id":"83000000-0000-4000-8000-000000000003","generatedAt":"never",\
      "entriesInPeriod":"6","entriesRead":6,"quoteAvailable":[true,"yes",null],\
      "content":{"summary":"s","feelings":{"overview":"o","phases":[{"feeling":"f"},\
      {"feeling":"Calm","description":"d","entryIds":["not-an-id"],"windowStart":"2026-03-05",\
      "windowEnd":"2026-03-21"}]},"themes":[{"name":"t"}],"quotes":[{"entryId":"x","start":1,\
      "end":2,"text":"q","why":"w"}]}}}
      """
    let page = try JSONDecoder().decode(ChapterReview.self, from: Data(json.utf8))
    let facts = try XCTUnwrap(page.facts)
    XCTAssertEqual(facts.entryCount, 6)
    XCTAssertEqual(facts.firstTimes.count, 1)
    // A first-useful recorded zone that does not exist reads as UTC.
    XCTAssertEqual(facts.firstTimes[0].occurrence.timezone, "UTC")
    XCTAssertEqual(facts.firstTimes[0].title, "First offer")
    XCTAssertEqual(facts.topTags, [.init(name: "a", count: 2)])
    XCTAssertNil(facts.busiestMonth)
    let review = try XCTUnwrap(page.shown)
    XCTAssertNil(review.generatedAt)
    XCTAssertEqual(review.entriesInPeriod, 6)
    XCTAssertEqual(review.quoteAvailable, [true, false, false])
    let content = try XCTUnwrap(review.content)
    XCTAssertEqual(content.phases.count, 1)
    XCTAssertTrue(content.phases[0].entryIDs.isEmpty)
    XCTAssertTrue(content.themes.isEmpty)
    XCTAssertTrue(content.quotes.isEmpty)
  }

  func testPhaseRangesNameTheYearOnceOrEveryYearLikeWeb() {
    // The end is exclusive, so a window ending June 1 covers through May.
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "2026-03-05", windowEnd: "2026-06-01", withYears: false),
      "March - May 2026")
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "2026-03-05", windowEnd: "2026-06-01", withYears: true),
      "March 2026 - May 2026")
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "2026-03-05", windowEnd: "2026-03-21", withYears: false),
      "March 2026")
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "2025-11-03", windowEnd: "2026-02-01", withYears: false),
      "November 2025 - January 2026")
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "2026-03-05", windowEnd: "", withYears: false),
      "March 2026")
    XCTAssertEqual(
      ReviewDates.phaseRange(windowStart: "soon", windowEnd: "2026-03-21", withYears: false), "")
    XCTAssertTrue(
      ReviewDates.phasesSpanYears([("2025-11-03", "2026-02-01")]))
    XCTAssertFalse(
      ReviewDates.phasesSpanYears([("2026-03-05", "2026-06-01"), ("2026-06-01", "2026-09-01")]))
    XCTAssertEqual(ReviewDates.monthLabel("2026-03"), "March 2026")
  }

  func testTheReviewReadsTodayInThePersonsTimeZone() throws {
    let instant = try date("2026-10-18T23:30:00Z")
    XCTAssertEqual(
      ReviewDates.localDate(instant, timezone: try XCTUnwrap(TimeZone(identifier: "UTC"))),
      "2026-10-18")
    XCTAssertEqual(
      ReviewDates.localDate(instant, timezone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))),
      "2026-10-19")
    XCTAssertEqual(
      ChapterReviewParameters(
        chapterID: UUID(uuidString: "82000000-0000-4000-8000-000000000001")!,
        localDate: "2026-10-18"
      ).itemEncodedKeys, ["p_chapter_id", "p_local_date"])
  }

  // MARK: Helpers

  private func date(_ value: String) throws -> Date {
    try XCTUnwrap(EntryTimestamp.date(from: value), value)
  }

  private let chapterEntriesJSON = """
    [{"entry_id":"10000000-0000-4000-8000-000000000001","title":"","excerpt":"Harbor lights",\
    "is_first_time":true,"occurred_start":"2021-05-10T11:00:00+00:00","occurred_end":null,\
    "date_precision":"day","occurred_label":null,"occurred_timezone":"UTC",\
    "tag_names":["harbor"],"cover_photo":null,"total_count":2},\
    {"entry_id":"10000000-0000-4000-8000-000000000002","title":"Second week","excerpt":"",\
    "is_first_time":false,"occurred_start":null,"occurred_end":null,"date_precision":null,\
    "occurred_label":null,"occurred_timezone":null,"tag_names":null,"cover_photo":null,\
    "total_count":"2"}]
    """

  /// `chapter_review`: the eligibility, settings, live facts, and the stored review with the
  /// checks that run every time it is read.
  private let reviewJSON = """
    {"eligibility":{"status":"eligible","entryCount":6,"minimum":5,"ongoing":false},\
    "settings":{"reviewsEnabled":true,"disclosureVersion":"2026-10-18"},\
    "facts":{"entryCount":6,"firstWindowStart":"2026-03-05","lastWindowStart":"2026-06-01",\
    "firstTimes":[{"id":"82000000-0000-4000-8000-000000000014","title":"First offer",\
    "occurredStart":"2026-04-25T12:00:00+00:00","occurredEnd":null,"datePrecision":"day",\
    "occurredLabel":null,"occurredTimezone":"UTC"}],\
    "topTags":[{"name":"interviews","count":3},{"name":"family","count":1}],\
    "busiestMonth":{"month":"2026-03","count":2},"chapters":[]},\
    "review":{"id":"83000000-0000-4000-8000-000000000001","content":{"summary":"A tense few \
    months that ended well.","feelings":{"overview":"From worry to relief.","phases":[\
    {"feeling":"Anxious, then steadier","description":"It eased.",\
    "entryIds":["82000000-0000-4000-8000-000000000011","82000000-0000-4000-8000-000000000012"],\
    "windowStart":"2026-03-05","windowEnd":"2026-03-21"}]},\
    "themes":[{"name":"Interviews","description":"They kept coming.",\
    "entryIds":["82000000-0000-4000-8000-000000000011","82000000-0000-4000-8000-000000000013"]}],\
    "quotes":[{"entryId":"82000000-0000-4000-8000-000000000011","start":10,"end":43,\
    "text":"anxious about the first interview","why":"It names the worry."},\
    {"entryId":"82000000-0000-4000-8000-000000000013","start":0,"end":9,\
    "text":"went better","why":"A turn."}]},\
    "model":"claude-sonnet-5-5","language":"en","ongoing":false,\
    "generatedAt":"2026-10-18T10:00:00.123456+00:00","entriesInPeriod":6,"entriesRead":6,\
    "trimmedEntries":0,"quoteAvailable":[true,false],\
    "sources":[{"entryId":"82000000-0000-4000-8000-000000000011","title":"First rejection",\
    "occurredStart":"2026-03-05T12:00:00+00:00","occurredEnd":null,"datePrecision":"day",\
    "occurredLabel":null,"occurredTimezone":"UTC","trashed":false},\
    {"entryId":"82000000-0000-4000-8000-000000000012","title":"Practice",\
    "occurredStart":"2026-03-20T12:00:00+00:00","occurredEnd":null,"datePrecision":"day",\
    "occurredLabel":null,"occurredTimezone":"UTC","trashed":true},\
    {"entryId":"82000000-0000-4000-8000-000000000013","title":"Second round",\
    "occurredStart":"2026-04-10T12:00:00+00:00","occurredEnd":null,"datePrecision":"day",\
    "occurredLabel":null,"occurredTimezone":"UTC","trashed":false}],\
    "changes":{"newEntries":0,"editedEntries":1,"trashedEntries":1},\
    "job":{"status":"idle","error":null,"done":0,"total":0}}}
    """
}

extension Encodable {
  /// The top-level keys this value encodes, sorted.
  fileprivate var itemEncodedKeys: [String] {
    guard let data = try? JSONEncoder().encode(self),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }
    return object.keys.sorted()
  }
}
