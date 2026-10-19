import XCTest

@testable import MemoTrail

/// Decoding the Entry reads against fixtures copied from the migration return shapes
/// (`editable_entry`, `entry_detail`, `save_entry`, `chapter_entries`, `chapter_overlaps`, and
/// the `entry_locations` read). Keys the app does not use are kept in, so a new column never
/// breaks a read.
final class EntryContractModelTests: XCTestCase {
  func testEditableEntryDecodesTheRowTagsLocationAndFormatting() throws {
    let entry = try decode(EditableEntry.self, editableJSON)
    XCTAssertEqual(entry.id, UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(entry.title, "Moving to Lisbon")
    XCTAssertEqual(entry.body, "Harbor lights")
    XCTAssertEqual(entry.richText?.text, "Harbor lights")
    XCTAssertEqual(entry.subtype, .chapter)
    XCTAssertTrue(entry.isFirstTime)
    XCTAssertEqual(entry.marks, EntryMarks(isChapter: true, isFirstTime: true))
    XCTAssertEqual(entry.revision, 4)
    XCTAssertEqual(entry.datePrecision, .month)
    XCTAssertEqual(entry.occurredStart, try date("2022-02-01T12:00:00Z"))
    XCTAssertEqual(entry.occurredEnd, try date("2022-11-01T12:00:00Z"))
    XCTAssertEqual(entry.occurredTimezone, "Europe/Lisbon")
    XCTAssertEqual(entry.tagNames, ["lisbon", "moves"])
    XCTAssertEqual(entry.createdAt, try date("2022-02-02T09:00:00.123Z"))
    XCTAssertEqual(entry.updatedAt, try date("2026-10-18T19:00:00Z"))
    XCTAssertEqual(entry.displayTitle, "Moving to Lisbon")
    XCTAssertEqual(entry.occurrence().spanLabel, "Feb 2022 - Nov 2022")

    let location = try XCTUnwrap(entry.primaryLocation)
    XCTAssertEqual(
      location,
      EntryLocation(
        id: UUID(uuidString: "40000000-0000-4000-8000-000000000004")!, revision: 3,
        formattedAddress: "Rua Augusta 1, 1100-048 Lisboa, Portugal", address: "Rua Augusta 1",
        city: "Lisboa", postalCode: "1100-048", country: "Portugal", countryCode: "PT",
        latitude: 38.7097, longitude: -9.1365, timezone: "Europe/Lisbon", resultType: "address"))
    XCTAssertEqual(location.label, "Rua Augusta 1, 1100-048 Lisboa, Portugal")
  }

  func testEditableEntryWithoutOptionalFieldsReadsAsAPlainUndatedEntry() throws {
    let entry = try decode(
      EditableEntry.self,
      #"{"id":"10000000-0000-4000-8000-000000000002","title":null,"body":"Only a note","revision":1,"metadata":null,"item_subtype":"someday","date_precision":"never","occurred_start":null,"occurred_timezone":null,"tag_names":null,"primary_location":null}"#
    )
    XCTAssertNil(entry.title)
    XCTAssertNil(entry.richText)
    XCTAssertEqual(entry.subtype, .entry)
    XCTAssertFalse(entry.isFirstTime)
    XCTAssertEqual(entry.marks, .none)
    XCTAssertEqual(entry.datePrecision, .unknown)
    XCTAssertEqual(entry.tagNames, [])
    XCTAssertNil(entry.primaryLocation)
    XCTAssertEqual(entry.displayTitle, "Undated entry")
    XCTAssertEqual(entry.occurrence(fallbackTimezone: "Asia/Tokyo").timezone, "Asia/Tokyo")
  }

  func testFormattingIsKeptOnlyWhenItDescribesTheNote() throws {
    var edited = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(editableJSON.utf8)) as? [String: Any])
    edited["body"] = "Harbor lights, edited"
    let entry = try JSONDecoder().decode(
      EditableEntry.self, from: JSONSerialization.data(withJSONObject: edited))
    XCTAssertNil(entry.richText)
    XCTAssertEqual(entry.body, "Harbor lights, edited")
  }

  func testEntryDetailDecodesTagsLocationsAndTrash() throws {
    let detail = try decode(EntryDetail.self, detailJSON)
    XCTAssertEqual(detail.title, nil)
    XCTAssertEqual(detail.body, "Harbor lights")
    XCTAssertEqual(detail.richText?.text, "Harbor lights")
    XCTAssertEqual(detail.subtype, .entry)
    XCTAssertEqual(detail.marks, .firstTime)
    XCTAssertEqual(detail.marks.identityLabel, "First Time")
    XCTAssertEqual(detail.revision, 2)
    XCTAssertEqual(
      detail.tags.map(\.name), ["harbor", "night walks"])
    XCTAssertEqual(detail.locations.map(\.relationship), [.photo, .primary])
    let primary = try XCTUnwrap(detail.primaryLocation)
    XCTAssertEqual(primary.locationID, UUID(uuidString: "40000000-0000-4000-8000-000000000004"))
    XCTAssertEqual(primary.label, "Rua Augusta 1, Lisboa")
    XCTAssertEqual(detail.locations.first?.label, "38.70970, -9.13650")
    XCTAssertTrue(detail.isInTrash)
    // An untitled Entry is named by its date in its recorded zone, so the Date fact adds
    // nothing.
    XCTAssertEqual(detail.displayTitle, "Monday, May 10, 2021")
    XCTAssertFalse(detail.dateAddsToTitle)
    XCTAssertEqual(detail.dateLabel, "May 10, 2021")
  }

  func testEntryDetailDateFactsFollowWeb() throws {
    let start = try date("2020-03-12T12:00:00Z")
    let end = try date("2026-09-03T12:00:00Z")
    let chapter = EntryDetail(
      id: UUID(), title: "Studio years", body: "", subtype: .chapter, revision: 1,
      occurredStart: start, occurredEnd: end, occurredTimezone: "America/Los_Angeles",
      datePrecision: .month)
    XCTAssertEqual(chapter.marks.identityLabel, "Chapter")
    XCTAssertTrue(chapter.dateAddsToTitle)
    XCTAssertEqual(chapter.dateLabel, "Mar 2020 to Sep 2026")
    XCTAssertEqual(chapter.chapterDateFacts().span, "Mar 2020 - Sep 2026")
    XCTAssertEqual(chapter.chapterDateFacts().duration, "About 6 years 6 months")

    let undated = EntryDetail(
      id: UUID(), title: "Someday", body: "", subtype: .chapter, revision: 1)
    XCTAssertEqual(undated.chapterDateFacts().span, "Date unknown")
    XCTAssertNil(undated.chapterDateFacts().duration)
    XCTAssertEqual(undated.dateLabel, "Unknown")

    // An untitled Entry dated by a day range still shows its end.
    let untitledRange = EntryDetail(
      id: UUID(), title: nil, body: "x", revision: 1, occurredStart: start, occurredEnd: end,
      occurredTimezone: "UTC", datePrecision: .day)
    XCTAssertTrue(untitledRange.dateAddsToTitle)
    let described = EntryDetail(
      id: UUID(), title: nil, body: "x", revision: 1, occurredLabel: "Age 7",
      datePrecision: .age)
    XCTAssertFalse(described.dateAddsToTitle)
    XCTAssertEqual(described.dateLabel, "Age 7")
  }

  func testSavedEntryDecodesTheSaveEntryRow() throws {
    let rows = try decode(
      [SavedEntry].self,
      #"[{"entry_id":"10000000-0000-4000-8000-000000000001","revision":5}]"#)
    XCTAssertEqual(
      rows,
      [SavedEntry(entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, revision: 5)])
  }

  func testChapterEntriesDecodeWithTheirCoverPhotoAndCount() throws {
    let rows = try decode([ChapterEntry].self, chapterEntriesJSON)
    XCTAssertEqual(rows.count, 2)
    let first = rows[0]
    XCTAssertEqual(first.id, UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(first.title, "")
    XCTAssertEqual(first.displayTitle, "Monday, May 10, 2021")
    XCTAssertTrue(first.isFirstTime)
    XCTAssertEqual(first.tagNames, ["harbor"])
    XCTAssertEqual(first.totalCount, 2)
    XCTAssertEqual(
      first.coverPhoto?.id, UUID(uuidString: "20000000-0000-4000-8000-000000000001"))
    XCTAssertEqual(first.coverPhoto?.bucketID, "entry-media")
    XCTAssertEqual(first.coverPhoto?.mimeType, "image/jpeg")
    XCTAssertEqual(first.coverPhoto?.pixelWidth, 1200)
    // `total_count` may arrive as a string, and a row may have no photo.
    let second = rows[1]
    XCTAssertEqual(second.title, "Second week")
    XCTAssertNil(second.coverPhoto)
    XCTAssertEqual(second.tagNames, [])
    XCTAssertEqual(second.totalCount, 2)
    XCTAssertEqual(second.datePrecision, .unknown)
  }

  func testChapterOverlapsDecodeTheirWindow() throws {
    let rows = try decode(
      [ChapterOverlap].self,
      #"[{"entry_id":"10000000-0000-4000-8000-000000000003","title":"Lisbon","is_first_time":false,"occurred_start":"2021-04-01T12:00:00+00:00","occurred_end":null,"date_precision":"month","occurred_label":null,"occurred_timezone":"Europe/Lisbon","window_start":"2021-04-01","window_end":null}]"#
    )
    XCTAssertEqual(rows.map(\.title), ["Lisbon"])
    XCTAssertEqual(rows.first?.windowStart, "2021-04-01")
    XCTAssertNil(rows.first?.windowEnd)
    XCTAssertEqual(rows.first?.occurrence.spanLabel, "Since Apr 2021")
    XCTAssertEqual(
      ChapterOverlapsParameters(chapterID: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!)
        .encodedKeys, ["p_chapter_id"])
    XCTAssertEqual(
      ChapterEntriesParameters(chapterID: UUID(), limit: ChapterContents.pageSize, offset: 50)
        .encodedKeys, ["p_chapter_id", "p_limit", "p_offset"])
  }

  func testPrimaryLocationsAssembleOneLocationPerEntry() throws {
    let rows = try decode(
      [EntryPrimaryLocations.Row].self,
      #"[{"entry_id":"10000000-0000-4000-8000-000000000001","location":{"id":"40000000-0000-4000-8000-000000000004","revision":1,"formatted_address":null,"address":null,"city":null,"region":null,"postal_code":null,"country":null,"country_code":null,"latitude":38.7097,"longitude":-9.1365,"timezone_id":null,"result_type":null}},{"entry_id":"10000000-0000-4000-8000-000000000002","location":null}]"#
    )
    let locations = EntryPrimaryLocations.assemble(rows)
    XCTAssertEqual(Array(locations.keys), [UUID(uuidString: "10000000-0000-4000-8000-000000000001")!])
    // A photo's GPS position has no address, so it reads as its coordinates.
    XCTAssertEqual(locations.values.first?.label, "38.70970, -9.13650")
    XCTAssertEqual(EntryLocation(id: UUID(), revision: 1).label, "Location not set")
  }

  func testUnknownSubtypesAndPrecisionsReadAsTheirDefaults() throws {
    XCTAssertEqual(EntrySubtype(stored: "chapter"), .chapter)
    XCTAssertEqual(EntrySubtype(stored: "first_time"), .entry)
    XCTAssertEqual(EntrySubtype(stored: nil), .entry)
    XCTAssertEqual(try decode([EntrySubtype].self, #"["period","chapter"]"#), [.entry, .chapter])
    XCTAssertEqual(DatePrecision(stored: "someday"), .unknown)
    XCTAssertEqual(DatePrecision(stored: "range"), .range)
  }

  func testMarksNameTheRecord() {
    XCTAssertEqual(EntryMarks.none.identityLabel, "Entry")
    XCTAssertEqual(EntryMarks.chapter.identityLabel, "Chapter")
    XCTAssertEqual(EntryMarks.firstTime.identityLabel, "First Time")
    XCTAssertEqual(
      EntryMarks(isChapter: true, isFirstTime: true).identityLabel, "Chapter · First Time")
    XCTAssertEqual(EntryMarks(subtype: .chapter, isFirstTime: false), .chapter)
    XCTAssertEqual(EntryMarks.chapter.subtype, .chapter)
    XCTAssertEqual(EntryMarks.firstTime.subtype, .entry)
    XCTAssertEqual(
      EntryRecordFilter.allCases.map(\.title), ["Entries", "Chapters", "First Times"])
    XCTAssertEqual(EntryRecordFilter.firstTime.rawValue, "first_time")
  }

  func testTimestampsReadEveryFormThePostgresReadsWrite() throws {
    let expected = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-10-18T19:00:00Z"))
    for text in [
      "2026-10-18T19:00:00Z", "2026-10-18T19:00:00+00:00", "2026-10-18 19:00:00+00",
      "2026-10-18T19:00:00.000000+00:00", "2026-10-18T12:00:00-07:00",
    ] {
      XCTAssertEqual(EntryTimestamp.date(from: text), expected, text)
    }
    // Postgres keeps microseconds; the app keeps milliseconds.
    let fractional = try date("2026-10-18T19:00:00.123456+00:00")
    XCTAssertEqual(fractional.timeIntervalSince(expected), 0.123, accuracy: 0.0001)
    XCTAssertNil(EntryTimestamp.date(from: "not a date"))
    XCTAssertEqual(EntryTimestamp.string(from: expected), "2026-10-18T19:00:00.000Z")
    // A timestamp that cannot be read fails the row instead of reading as undated.
    XCTAssertThrowsError(
      try decode(
        EditableEntry.self,
        #"{"id":"10000000-0000-4000-8000-000000000002","body":"x","revision":1,"occurred_start":"soon"}"#
      ))
  }

  func testCountLabelsAndExcerptsFollowWeb() {
    XCTAssertEqual(countLabel(1, "Entry"), "1 Entry")
    XCTAssertEqual(countLabel(3, "Entry"), "3 Entries")
    XCTAssertEqual(countLabel(2, "photo"), "2 photos")
    XCTAssertEqual(countLabel(2, "person", plural: "people"), "2 people")
    XCTAssertEqual(" Harbor \n\n lights ".compactExcerpt, "Harbor lights")
    let long = String(repeating: "a ", count: 100).compactExcerpt
    XCTAssertEqual(long.count, 140)
    XCTAssertTrue(long.hasSuffix("..."))
  }

  // MARK: Helpers

  private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  private func date(_ value: String) throws -> Date {
    try XCTUnwrap(EntryTimestamp.date(from: value), value)
  }

  /// `editable_entry`: the whole `entries` row, `tag_names`, and the whole `locations` row.
  private let editableJSON = """
    {"id":"10000000-0000-4000-8000-000000000001","owner_id":"30000000-0000-4000-8000-000000000003",\
    "title":"Moving to Lisbon","body":"Harbor lights","item_kind":"entry",\
    "item_subtype":"chapter","is_first_time":true,"revision":4,\
    "occurred_start":"2022-02-01T12:00:00+00:00","occurred_end":"2022-11-01T12:00:00+00:00",\
    "date_precision":"month","occurred_label":null,"occurred_timezone":"Europe/Lisbon",\
    "source_language":"en","client_id":"web:1","embedding_model":null,\
    "embedding_updated_at":null,"metadata":{"source":"web","body_rich":{"version":1,\
    "text":"Harbor lights","document":{"type":"doc","content":[{"type":"paragraph",\
    "content":[{"type":"text","text":"Harbor","marks":[{"type":"bold"}]},\
    {"type":"text","text":" lights"}]}]}}},\
    "created_at":"2022-02-02T09:00:00.123456+00:00","updated_at":"2026-10-18T19:00:00+00:00",\
    "deleted_at":null,"tag_names":["lisbon","moves"],\
    "primary_location":{"id":"40000000-0000-4000-8000-000000000004",\
    "owner_id":"30000000-0000-4000-8000-000000000003",\
    "formatted_address":"Rua Augusta 1, 1100-048 Lisboa, Portugal","address":"Rua Augusta 1",\
    "city":"Lisboa","region":null,"postal_code":"1100-048","country":"Portugal",\
    "country_code":"PT","latitude":38.7097,"longitude":-9.1365,"provider":"mapkit",\
    "provider_location_id":null,"metadata":{},"revision":3,\
    "created_at":"2022-02-02T09:00:00+00:00","updated_at":"2022-02-02T09:00:00+00:00",\
    "timezone_id":"Europe/Lisbon","result_type":"address","bound_entry_id":null,\
    "coordinate_source":"provider","source_attachment_id":null}}
    """

  /// `entry_detail`: the row without `embedding` and `search_document`, plus tags, locations,
  /// and links.
  private let detailJSON = """
    {"id":"10000000-0000-4000-8000-000000000001","owner_id":"30000000-0000-4000-8000-000000000003",\
    "title":null,"body":"Harbor lights","item_kind":"entry","item_subtype":"entry",\
    "is_first_time":true,"revision":2,"occurred_start":"2021-05-10T11:00:00+00:00",\
    "occurred_end":null,"date_precision":"day","occurred_label":null,\
    "occurred_timezone":"Europe/Lisbon","source_language":null,"client_id":null,\
    "embedding_model":null,"embedding_updated_at":null,"metadata":{"body_rich":{"version":1,\
    "text":"Harbor lights","document":{"type":"doc","content":[{"type":"paragraph",\
    "content":[{"type":"text","text":"Harbor lights"}]}]}}},\
    "created_at":"2021-05-10T11:00:00+00:00","updated_at":"2021-05-10T11:00:00+00:00",\
    "deleted_at":"2026-10-18T19:00:00.5+00:00",\
    "tags":[{"id":"50000000-0000-4000-8000-000000000001","name":"harbor"},\
    {"id":"50000000-0000-4000-8000-000000000002","name":"night walks"}],\
    "locations":[{"location_id":"40000000-0000-4000-8000-000000000005","relationship":"photo",\
    "formatted_address":null,"latitude":38.7097,"longitude":-9.1365},\
    {"location_id":"40000000-0000-4000-8000-000000000004","relationship":"primary",\
    "formatted_address":"Rua Augusta 1, Lisboa","latitude":null,"longitude":null}],"links":[]}
    """

  /// `chapter_entries`: one page, with the Entry's first photo and the total count.
  private let chapterEntriesJSON = """
    [{"entry_id":"10000000-0000-4000-8000-000000000001","title":"","excerpt":"Harbor lights",\
    "is_first_time":true,"occurred_start":"2021-05-10T11:00:00+00:00","occurred_end":null,\
    "date_precision":"day","occurred_label":null,"occurred_timezone":"Europe/Lisbon",\
    "tag_names":["harbor"],"cover_photo":{"attachment_id":"20000000-0000-4000-8000-000000000001",\
    "bucket_id":"entry-media","object_path":"a/b/c.jpg","original_filename":"IMG_1.jpg",\
    "mime_type":"image/jpeg","byte_size":120000,"pixel_width":1200,"pixel_height":800},\
    "total_count":2},\
    {"entry_id":"10000000-0000-4000-8000-000000000002","title":"Second week","excerpt":"",\
    "is_first_time":false,"occurred_start":null,"occurred_end":null,"date_precision":null,\
    "occurred_label":null,"occurred_timezone":null,"tag_names":null,"cover_photo":null,\
    "total_count":"2"}]
    """
}

extension Encodable {
  /// The top-level keys this value encodes, sorted.
  fileprivate var encodedKeys: [String] {
    guard let data = try? JSONEncoder().encode(self),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }
    return object.keys.sorted()
  }
}
