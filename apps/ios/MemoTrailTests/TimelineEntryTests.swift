import XCTest

@testable import MemoTrail

/// `timeline_workspace` and `first_times_workspace` rows, shaped like
/// `supabase/migrations/202610190015_chapter_timeline.sql`, and Web `timelineItems`.
final class TimelineEntryTests: XCTestCase {
  func testTimelineRowDecodesAChapterWithTheDaysItCovers() throws {
    let item = try decodeItem(
      title: "Living in Lisbon", isChapter: true, isFirstTime: false, precision: "month",
      start: "2021-03-01T12:00:00+00:00", end: "2021-08-31T12:00:00+00:00",
      windowStart: "2021-03-01", windowEnd: "2021-09-01")

    XCTAssertEqual(item.id, UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(item.marks, .chapter)
    XCTAssertEqual(item.displayTitle, "Living in Lisbon")
    XCTAssertEqual(item.dateLabel, "Mar 2021 - Aug 2021")
    XCTAssertEqual(item.windowStart, "2021-03-01")
    XCTAssertEqual(item.windowEnd, "2021-09-01")
    XCTAssertEqual(item.revision, 3)
    XCTAssertEqual(item.tagNames, ["Lisbon"])
    XCTAssertNotNil(item.updatedAt)
  }

  func testTimelineRowNamesAnUntitledFirstTimeByItsDateInItsRecordedZone() throws {
    let item = try decodeItem(
      title: "", isChapter: false, isFirstTime: true, precision: "day",
      start: "2021-05-10T23:30:00+00:00", windowStart: "2021-05-11", windowEnd: "2021-05-12",
      timezone: "Asia/Tokyo")

    XCTAssertEqual(item.marks, .firstTime)
    XCTAssertEqual(item.displayTitle, "Tuesday, May 11, 2021")
    XCTAssertEqual(item.dateLabel, "May 11, 2021")
  }

  func testOngoingAndUnanchoredItemsKeepTheirLabels() throws {
    let ongoing = try decodeItem(
      title: "Learning Portuguese", isChapter: true, isFirstTime: true, precision: "year",
      start: "2020-01-01T12:00:00+00:00", windowStart: "2020-01-01")
    XCTAssertEqual(ongoing.marks, EntryMarks(isChapter: true, isFirstTime: true))
    XCTAssertNil(ongoing.windowEnd)
    XCTAssertEqual(ongoing.dateLabel, "Since 2020")

    let unanchored = try decodeItem(
      title: "", isChapter: false, isFirstTime: true, precision: "age", label: "Age 7")
    XCTAssertNil(unanchored.windowStart)
    XCTAssertEqual(unanchored.displayTitle, "Age 7")
    XCTAssertEqual(unanchored.dateLabel, "Age 7")

    let undated = try decodeItem(
      title: "", isChapter: true, isFirstTime: false, precision: "unknown")
    XCTAssertEqual(undated.displayTitle, "Undated entry")
    XCTAssertEqual(undated.dateLabel, "Date unknown")
  }

  func testSplitPutsFirstTimeChaptersOnlyInChaptersAndOrdersByFirstDay() {
    let early = item("Early chapter", chapter: true, firstTime: false, window: "2019-01-01")
    let later = item("Later chapter", chapter: true, firstTime: true, window: "2021-06-01")
    let firstTime = item("First swim", chapter: false, firstTime: true, window: "2020-07-04")
    let undatedB = item("B undated", chapter: false, firstTime: true, window: nil)
    let undatedA = item("A undated", chapter: false, firstTime: true, window: nil)
    let sameDayB = item("Beta", chapter: true, firstTime: false, window: "2022-01-01")
    let sameDayA = item("alpha", chapter: true, firstTime: false, window: "2022-01-01")

    let split = TimelineItems.split([
      undatedB, sameDayB, later, firstTime, undatedA, early, sameDayA,
    ])

    XCTAssertEqual(split.chapters, [early, later, sameDayA, sameDayB])
    XCTAssertEqual(split.firstTimes, [firstTime, undatedA, undatedB])
  }

  func testFirstTimeRowDecodesPhotosAndShowsAChaptersSpan() throws {
    let row = try decodeFirstTime(isChapter: true, precision: "month")

    XCTAssertEqual(row.marks, EntryMarks(isChapter: true, isFirstTime: true))
    XCTAssertEqual(row.displayTitle, "First apartment")
    XCTAssertEqual(row.dateLabel, "Since Mar 2021")
    XCTAssertEqual(row.tagNames, ["Lisbon"])
    XCTAssertNil(row.location)
    let photo = try XCTUnwrap(row.attachments.first)
    XCTAssertEqual(photo.id, UUID(uuidString: "20000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(photo.variant, "original")
    XCTAssertEqual(photo.bucketID, "entry-media")
    XCTAssertEqual(photo.objectPath, "owner/entry/key.jpg")
    XCTAssertEqual(photo.mimeType, .jpeg)
    XCTAssertEqual(photo.byteSize, 4096)
    XCTAssertEqual(photo.pixelWidth, 1600)
    XCTAssertNil(photo.pixelHeight)
    XCTAssertNotNil(photo.createdAt)
  }

  func testFirstTimeRowDefaultsAndPlainFirstTimeDate() throws {
    let row = try decodeFirstTime(isChapter: nil, precision: "day", withPhoto: false)

    XCTAssertFalse(row.isChapter)
    XCTAssertEqual(row.marks, .firstTime)
    XCTAssertEqual(row.dateLabel, "Mar 1, 2021")
    XCTAssertTrue(row.attachments.isEmpty)
    XCTAssertThrowsError(
      try decodeFirstTime(isChapter: false, precision: "day", mimeType: "image/gif"))
  }

  // MARK: Helpers

  private func item(_ title: String, chapter: Bool, firstTime: Bool, window: String?)
    -> TimelineItem
  {
    TimelineItem(
      id: UUID(), isChapter: chapter, isFirstTime: firstTime, title: title,
      datePrecision: window == nil ? .unknown : .day, windowStart: window)
  }

  private func nullable(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }

  private func decodeItem(
    title: String, isChapter: Bool, isFirstTime: Bool, precision: String,
    start: String? = nil, end: String? = nil, label: String? = nil,
    windowStart: String? = nil, windowEnd: String? = nil, timezone: String = "UTC"
  ) throws -> TimelineItem {
    let object: [String: Any] = [
      "entry_id": "10000000-0000-4000-8000-000000000001",
      "title": title,
      "is_chapter": isChapter,
      "is_first_time": isFirstTime,
      "occurred_start": nullable(start),
      "occurred_end": nullable(end),
      "date_precision": precision,
      "occurred_label": nullable(label),
      "occurred_timezone": timezone,
      "window_start": nullable(windowStart),
      "window_end": nullable(windowEnd),
      "revision": 3,
      "updated_at": "2026-10-18T19:00:00.123456+00:00",
      "tag_names": ["Lisbon"],
    ]
    return try JSONDecoder().decode(
      TimelineItem.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func decodeFirstTime(
    isChapter: Bool?, precision: String, mimeType: String = "image/jpeg", withPhoto: Bool = true
  ) throws -> FirstTimeRow {
    var object: [String: Any] = [
      "entry_id": "30000000-0000-4000-8000-000000000001",
      "title": "First apartment",
      "body": "Keys on a red ribbon.",
      "occurred_start": "2021-03-01T12:00:00+00:00",
      "occurred_end": NSNull(),
      "date_precision": precision,
      "occurred_label": NSNull(),
      "occurred_timezone": "Europe/Lisbon",
      "revision": 2,
      "updated_at": "2026-10-18T19:00:00+00:00",
      "tag_names": ["Lisbon"],
    ]
    if let isChapter { object["is_chapter"] = isChapter }
    if withPhoto {
      object["attachments"] = [
        [
          "id": "20000000-0000-4000-8000-000000000001",
          "parentAttachmentId": NSNull(),
          "variant": "original",
          "bucketId": "entry-media",
          "objectPath": "owner/entry/key.jpg",
          "originalFilename": "key.jpg",
          "mimeType": mimeType,
          "byteSize": 4096,
          "pixelWidth": 1600,
          "pixelHeight": NSNull(),
          "createdAt": "2026-10-18T19:00:00.5+00:00",
        ]
      ]
    }
    return try JSONDecoder().decode(
      FirstTimeRow.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
