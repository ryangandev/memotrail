import XCTest

@testable import MemoTrail

final class FormFieldTests: XCTestCase {
  func testTimeZoneLabelsMatchTheWebSelect() {
    XCTAssertEqual(TimeZoneOptions.label("UTC"), "UTC")
    XCTAssertEqual(TimeZoneOptions.label("America/Los_Angeles"), "Los Angeles - America")
    XCTAssertEqual(
      TimeZoneOptions.label("America/Argentina/Buenos_Aires"),
      "Argentina / Buenos Aires - America")
    XCTAssertEqual(
      TimeZoneOptions.optionLabel("Asia/Kathmandu", reference: "2026-09-17"),
      "(UTC+05:45) Kathmandu - Asia")
    XCTAssertEqual(
      TimeZoneOptions.optionLabel("America/Los_Angeles", reference: "2026-01-15"),
      "(UTC-08:00) Los Angeles - America")
    XCTAssertEqual(
      TimeZoneOptions.optionLabel("America/Los_Angeles", reference: "2026-07-15T09:30:00"),
      "(UTC-07:00) Los Angeles - America")
    XCTAssertEqual(TimeZoneOptions.optionLabel("UTC", reference: ""), "(UTC+00:00) UTC")
    XCTAssertEqual(TimeZoneOptions.optionLabel("Not/AZone", reference: ""), "AZone - Not")
  }

  func testTimeZoneOptionsListCommonZonesFirstWithoutDuplicates() {
    XCTAssertEqual(
      Array(TimeZoneOptions.all.prefix(TimeZoneOptions.common.count)), TimeZoneOptions.common)
    XCTAssertEqual(Set(TimeZoneOptions.all).count, TimeZoneOptions.all.count)
    XCTAssertTrue(TimeZoneOptions.all.contains("Europe/Paris"))
  }

  func testDateTextRoundTripsEachGranularityAndRejectsImpossibleDates() throws {
    for (text, granularity, includesTime) in [
      ("2026-09-17", MTDateFieldGranularity.day, false), ("2026-09", .month, false),
      ("2026", .year, false), ("2026-09-17T14:30:27", .day, true),
    ] {
      let date = try XCTUnwrap(
        MTDateText.date(text, granularity: granularity, includesTime: includesTime))
      XCTAssertEqual(
        MTDateText.text(date, granularity: granularity, includesTime: includesTime), text)
    }
    XCTAssertEqual(
      MTDateText.date("2026-09-17T14:30", granularity: .day, includesTime: true).map {
        MTDateText.text($0, granularity: .day, includesTime: true)
      }, "2026-09-17T14:30:00")
    XCTAssertNil(MTDateText.date("2025-02-29", granularity: .day, includesTime: false))
    XCTAssertNil(MTDateText.date("0000", granularity: .year, includesTime: false))
    XCTAssertNil(MTDateText.date("2026-9", granularity: .month, includesTime: false))
    XCTAssertNil(MTDateText.date("", granularity: .day, includesTime: false))
  }

  func testDateTextReadsTodayInTheRecordedTimeZone() throws {
    // 2026-09-17 23:30 UTC is already the next morning in Kathmandu.
    let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T23:30:00Z"))
    let kathmandu = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
    XCTAssertEqual(
      MTDateText.text(
        MTDateText.now(in: kathmandu, now: instant), granularity: .day, includesTime: true),
      "2026-09-18T05:15:00")
  }

  func testPresentEndModeKeepsAnOngoingPeriodOpen() throws {
    var draft = OccurrenceDraft(
      EntryOccurrence(precision: .range, start: nil, end: nil, label: nil, timezone: "UTC"))
    XCTAssertEqual(draft.endMode, .date)
    draft.start = "2020-01-02"
    draft.end = "2021-03-04"
    XCTAssertNotNil(try draft.resolve().end)
    draft.endMode = .present
    let ongoing = try draft.resolve()
    XCTAssertNil(ongoing.end)
    XCTAssertEqual(OccurrenceDraft(ongoing).endMode, .present)
  }

  func testUndatedRecordsEditInTheDefaultTimeZone() {
    // Undated records store no zone and decode as UTC; editors start from the default instead.
    let undated = EntryOccurrence(
      precision: .unknown, start: nil, end: nil, label: nil, timezone: "UTC")
    XCTAssertEqual(
      OccurrenceDraft(undated, undatedTimezone: "America/Los_Angeles").timezone,
      "America/Los_Angeles")
    let dated = EntryOccurrence(
      precision: .day, start: Date(timeIntervalSince1970: 0), end: nil, label: nil,
      timezone: "Asia/Tokyo")
    XCTAssertEqual(
      OccurrenceDraft(dated, undatedTimezone: "America/Los_Angeles").timezone, "Asia/Tokyo")
  }

  func testChangingDateTypeReplacesTheCalendarValues() {
    var draft = OccurrenceDraft(
      EntryOccurrence(
        precision: .range, start: nil, end: nil, label: "Grad school", timezone: "UTC"))
    draft.start = "2020-01-02"
    draft.end = "2021-03-04"
    draft.endMode = .present
    draft.changePrecision(to: .range)
    XCTAssertEqual(draft.start, "2020-01-02")
    draft.changePrecision(to: .year)
    XCTAssertEqual(draft.precision, .year)
    XCTAssertEqual([draft.start, draft.end], ["", ""])
    XCTAssertEqual(draft.endMode, .date)
    XCTAssertEqual(draft.label, "Grad school")
  }

  func testCaptureDraftSavedBeforeEndModeStillLoads() throws {
    let legacy = Data(
      #"{"precision":"range","start":"2020-01-02","end":"","label":"","timezone":"UTC"}"#.utf8)
    let draft = try JSONDecoder().decode(OccurrenceDraft.self, from: legacy)
    XCTAssertEqual(draft.endMode, .date)
    XCTAssertEqual(draft.start, "2020-01-02")
    let encoded = try JSONEncoder().encode(draft)
    XCTAssertEqual(try JSONDecoder().decode(OccurrenceDraft.self, from: encoded), draft)
  }

  func testPhotoCalendarDateReplacesAnOngoingEndMode() throws {
    var previous = OccurrenceDraft(
      EntryOccurrence(precision: .unknown, start: nil, end: nil, label: "Soon", timezone: "UTC"))
    previous.endMode = .present
    let metadata = try JSONDecoder().decode(
      PhotoCameraMetadata.self,
      from: Data(
        #"{"attachmentId":"6F9619FF-8B86-D011-B42D-00C04FC964FF","sourceVersion":"v1","calendarDate":"2024-05-06"}"#
          .utf8))
    let draft = try metadata.calendarDraft(previous: previous)
    XCTAssertEqual(draft.precision, .day)
    XCTAssertEqual(draft.start, "2024-05-06")
    XCTAssertEqual(draft.endMode, .date)
  }
}
