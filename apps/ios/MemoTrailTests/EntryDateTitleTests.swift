import XCTest

@testable import MemoTrail

/// Mirrors Web `apps/web/src/lib/data/occurrence.test.ts`: what an Entry is called, the span and
/// length of a Chapter, and how a date typed in the editor becomes an instant.
final class EntryDateTitleTests: XCTestCase {
  private let losAngeles = "America/Los_Angeles"

  // MARK: Date titles

  func testUntitledEntryIsNamedByItsDateAtTheRecordedPrecision() throws {
    let day = try day()
    XCTAssertEqual(day.title, "Sunday, October 18, 2026")
    // A late-evening moment stays on the day it was recorded in its own zone.
    var late = day
    late.precision = .exact
    late.start = try date("2026-10-19T06:30:00Z")
    XCTAssertEqual(late.title, "Sunday, October 18, 2026")
    var month = day
    month.precision = .month
    XCTAssertEqual(month.title, "October 2026")
    var year = day
    year.precision = .year
    XCTAssertEqual(year.title, "2026")
  }

  func testDateRangesAreNamedByBothEndsOrByTheirStartWhileOpen() throws {
    var range = try day()
    range.precision = .range
    range.end = try date("2026-10-20T19:00:00Z")
    XCTAssertEqual(range.title, "October 18 - October 20, 2026")
    range.end = try date("2027-01-02T20:00:00Z")
    XCTAssertEqual(range.title, "October 18, 2026 - January 2, 2027")
    range.end = nil
    XCTAssertEqual(range.title, "October 18, 2026 onward")
  }

  func testUncertainDatesUseTheirDescriptionAndUnknownOnesSaySo() throws {
    var approximate = try day()
    approximate.precision = .approximate
    approximate.label = " The summer after college "
    XCTAssertEqual(approximate.title, "The summer after college")
    var age = try day()
    age.precision = .age
    age.start = nil
    age.label = "Age 7"
    XCTAssertEqual(age.title, "Age 7")
    var unknown = try day()
    unknown.precision = .unknown
    unknown.start = nil
    XCTAssertEqual(unknown.title, "Undated entry")
    // A stored date that cannot be read leaves the Entry undated.
    var unreadable = try day()
    unreadable.start = EntryTimestamp.date(from: "not a date")
    XCTAssertEqual(unreadable.title, "Undated entry")
  }

  func testStoredTitleWinsAndStoredRowsReadInTheViewersZoneWhenNeeded() throws {
    let day = try day()
    XCTAssertEqual(entryDisplayTitle(" First snow ", day), "First snow")
    XCTAssertEqual(entryDisplayTitle("", day), "Sunday, October 18, 2026")
    XCTAssertEqual(entryDisplayTitle(nil, day), "Sunday, October 18, 2026")
    XCTAssertEqual(entryDisplayTitle("  ", day), "Sunday, October 18, 2026")

    let start = try date("2026-10-18T22:00:00Z")
    let stored = EntryOccurrence(
      storedPrecision: "exact", start: start, end: nil, label: nil, timezone: nil,
      fallbackTimezone: "Asia/Tokyo")
    XCTAssertEqual(
      stored,
      EntryOccurrence(
        precision: .exact, start: start, end: nil, label: nil, timezone: "Asia/Tokyo"))
    XCTAssertEqual(stored.title, "Monday, October 19, 2026")
    let unknown = EntryOccurrence(
      storedPrecision: "someday", start: start, end: nil, label: nil, timezone: nil,
      fallbackTimezone: "Not/AZone")
    XCTAssertEqual(unknown.precision, .unknown)
    XCTAssertEqual(unknown.timezone, "UTC")
    // A recorded zone wins over the fallback; an invalid one falls back.
    XCTAssertEqual(
      EntryOccurrence(
        storedPrecision: "day", start: start, end: nil, label: nil, timezone: losAngeles,
        fallbackTimezone: "Asia/Tokyo"
      ).timezone, losAngeles)
    XCTAssertEqual(
      EntryOccurrence(
        storedPrecision: "day", start: start, end: nil, label: nil, timezone: "Mars/Olympus",
        fallbackTimezone: "Asia/Tokyo"
      ).timezone, "Asia/Tokyo")
  }

  // MARK: Chapter span and length

  func testChapterBoundsAndDurationsAreOnlyAsPreciseAsRecorded() throws {
    var chapter = EntryOccurrence(
      precision: .month, start: try date("2020-03-12T12:00:00Z"),
      end: try date("2026-09-03T12:00:00Z"), label: nil, timezone: losAngeles)
    XCTAssertEqual(chapter.spanLabel, "Mar 2020 - Sep 2026")
    XCTAssertEqual(chapter.durationLabel(), "About 6 years 6 months")
    chapter.precision = .year
    XCTAssertEqual(chapter.spanLabel, "2020 - 2026")
    XCTAssertEqual(chapter.durationLabel(), "About 6 years")
    chapter.precision = .range
    XCTAssertEqual(chapter.durationLabel(), "6 years 5 months")

    var unknown = chapter
    unknown.precision = .unknown
    unknown.start = nil
    unknown.end = nil
    XCTAssertEqual(unknown.durationLabel(), "Duration unavailable")
    XCTAssertEqual(unknown.spanLabel, "Date unknown")
    var ages = unknown
    ages.precision = .age
    ages.label = "Ages 17 to 23"
    XCTAssertEqual(ages.spanLabel, "Ages 17 to 23")

    // A Chapter still going on runs from its start.
    var ongoing = chapter
    ongoing.precision = .month
    ongoing.end = nil
    XCTAssertEqual(ongoing.spanLabel, "Since Mar 2020")
    XCTAssertEqual(
      ongoing.durationLabel(now: try date("2021-04-01T12:00:00Z")), "About 1 year 1 month")
  }

  // MARK: Editing a date

  func testUnchangedInstantKeepsSecondsMillisecondsAndTheLaterRepeatedHour() throws {
    let original = EntryOccurrence(
      precision: .exact, start: try date("2026-11-01T09:30:27.123Z"), end: nil, label: nil,
      timezone: losAngeles)
    let draft = OccurrenceDraft(original)
    XCTAssertEqual(draft.start, "2026-11-01T01:30:27")
    XCTAssertEqual(try draft.resolve(original: original), original)
    XCTAssertEqual(
      OccurrenceDraft.wallTimeToDate("2026-11-01T01:30:27", timezone: losAngeles),
      try date("2026-11-01T08:30:27Z"))
  }

  func testFractionalZonesWorkAndNonexistentWallTimesAreRefused() throws {
    XCTAssertEqual(
      OccurrenceDraft.wallTimeToDate("2026-09-12T12:00", timezone: "Asia/Kathmandu"),
      try date("2026-09-12T06:15:00Z"))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2026-03-08T02:30", timezone: losAngeles))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2025-02-29T12:00", timezone: "UTC"))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2026-09-12T25:00", timezone: "UTC"))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2026-09-12T12:00", timezone: "not-a-zone"))
  }

  func testPartialDatesKeepTheirPrecisionInLabelsAndTheRecordedZone() throws {
    for (precision, start, label) in [
      (DatePrecision.year, "2017", "2017"), (.month, "2017-07", "Jul 2017"),
      (.day, "2017-07-08", "Jul 8, 2017"),
    ] {
      let resolved = try draft(precision, start: start, timezone: "Pacific/Auckland").resolve()
      XCTAssertEqual(resolved.displayLabel, label)
      XCTAssertEqual(OccurrenceDraft(resolved).start, start)
    }
  }

  func testAgeAndApproximateDescriptionsInferNoCalendarAnchor() throws {
    for precision in [DatePrecision.age, .approximate] {
      let resolved = try draft(precision, label: "17岁，第一次去日本").resolve()
      XCTAssertNil(resolved.start)
      XCTAssertNil(resolved.end)
      XCTAssertEqual(resolved.label, "17岁，第一次去日本")
      XCTAssertEqual(resolved.precision, precision)
      XCTAssertEqual(resolved.displayLabel, "17岁，第一次去日本")
    }
    var suggestion = OccurrenceDraft(EntryOccurrence(precision: .unknown, timezone: "UTC"))
    suggestion.useDateSuggestion("The winter we moved")
    XCTAssertEqual(try suggestion.resolve().precision, .approximate)
    XCTAssertEqual(try suggestion.resolve().label, "The winter we moved")
  }

  func testUnknownAndOpenRangesWorkWhileReversedRangesAndMissingDescriptionsAreRefused()
    throws
  {
    let unknown = EntryOccurrence(precision: .unknown, timezone: "UTC")
    XCTAssertEqual(unknown.displayLabel, "Date unknown")
    XCTAssertNoThrow(try unknown.validate())
    var dated = unknown
    dated.start = try date("2026-11-01T09:30:27Z")
    XCTAssertThrowsError(try dated.validate())

    let range = draft(.range, start: "2020-01-01")
    XCTAssertEqual(try range.resolve().displayLabel, "Jan 1, 2020 onward")
    var reversed = range
    reversed.end = "2019-01-01"
    XCTAssertThrowsError(try reversed.resolve())
    var age = range
    age.precision = .age
    age.start = ""
    XCTAssertThrowsError(try age.resolve())
    var long = range
    long.label = String(repeating: "x", count: 201)
    XCTAssertThrowsError(try long.resolve())
  }

  func testOptionalEndDateAndExplicitPresentMode() throws {
    let range = draft(.range, start: "2020-01-01")
    XCTAssertNil(try draft(.range, start: "2020-01-01", endMode: .present).resolve().end)
    XCTAssertNil(try range.resolve().end)
    var ended = range
    ended.end = "2023-01-01"
    XCTAssertEqual(try ended.resolve().end, try date("2023-01-01T12:00:00Z"))
    // Present clears the end date, as the editor and Web do.
    ended.setPresent(true)
    XCTAssertNil(try ended.resolve().end)
  }

  func testChapterEndsKeepTheirPrecisionWithoutRelaxingOrdinaryEntries() throws {
    for (precision, start, end) in [
      (DatePrecision.year, "2017", "2023"), (.month, "2017-07", "2023-06"),
      (.exact, "2017-07-08T01:30:01", "2023-06-01T02:00:01"),
    ] {
      let resolved = try draft(precision, start: start, end: end, timezone: "Asia/Kathmandu")
        .resolve(span: true)
      XCTAssertNotNil(resolved.end, "\(precision)")
      XCTAssertNoThrow(try resolved.validate(span: true))
      XCTAssertThrowsError(try resolved.validate())
      XCTAssertThrowsError(
        try draft(precision, start: end, end: start).resolve(span: true), "\(precision)")
    }
  }

  func testInvalidPartialDatesAreRefusedRatherThanConverted() {
    for (precision, start) in [
      (DatePrecision.year, "20"), (.month, "2017-13"), (.day, "2017-02-30"),
    ] {
      XCTAssertThrowsError(try draft(precision, start: start).resolve(), start)
    }
  }

  /// Web `resolveOccurrenceDraft`: every caller, Capture included, stores an empty calendar
  /// date as Unknown and keeps its description, instead of refusing it as missing.
  func testEmptyCalendarDateResolvesToUnknownWithItsDescriptionLikeWeb() throws {
    for precision in [DatePrecision.exact, .day, .month, .year, .range] {
      let resolved = try draft(precision, label: " Sometime that spring ").resolve()
      XCTAssertEqual(resolved.precision, .unknown, "\(precision)")
      XCTAssertNil(resolved.start)
      XCTAssertEqual(resolved.label, "Sometime that spring")
    }
  }

  // MARK: Helpers

  /// Web's `day` fixture.
  private func day() throws -> EntryOccurrence {
    EntryOccurrence(
      precision: .day, start: try date("2026-10-18T19:00:00Z"), end: nil, label: nil,
      timezone: losAngeles)
  }

  private func date(_ value: String) throws -> Date {
    try XCTUnwrap(EntryTimestamp.date(from: value), value)
  }

  private func draft(
    _ precision: DatePrecision, start: String = "", end: String = "", label: String = "",
    timezone: String = "UTC", endMode: OccurrenceDraft.EndMode = .date
  ) -> OccurrenceDraft {
    var draft = OccurrenceDraft(EntryOccurrence(precision: precision, timezone: timezone))
    draft.start = start
    draft.end = end
    draft.label = label
    draft.endMode = endMode
    return draft
  }
}
