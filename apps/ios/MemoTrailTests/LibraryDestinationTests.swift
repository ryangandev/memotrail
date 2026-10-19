import XCTest

@testable import MemoTrail

/// Library's `wiki_items_workspace` rows, shaped like
/// `supabase/migrations/202610190017_chapter_search.sql`, and the tag requests from Web
/// `organization.ts`.
final class LibraryDestinationTests: XCTestCase {
  func testLibraryRowDecodesTheCanonicalEntryAndItsMarks() throws {
    let row = try decodeRow(subtype: "chapter", isFirstTime: true, totalCount: 14)

    XCTAssertEqual(row.id.uuidString, "98900000-0000-4000-8000-000000000011")
    XCTAssertEqual(row.subtype, .chapter)
    XCTAssertEqual(row.marks, EntryMarks(isChapter: true, isFirstTime: true))
    XCTAssertEqual(row.identityLabel, "Chapter · First Time")
    XCTAssertEqual(row.displayTitle, "Evening walks")
    XCTAssertEqual(row.excerpt, "Along the river")
    XCTAssertEqual(row.totalCount, 14)
    XCTAssertNotNil(row.updatedAt)
    XCTAssertEqual(try decodeRow(totalCount: "36").totalCount, 36)
    XCTAssertEqual(try decodeRow(subtype: "someday", isFirstTime: nil).marks, .none)
  }

  func testLibraryDateLabelsFollowWeb() throws {
    // A Chapter shows the span it covers in its recorded zone.
    XCTAssertEqual(
      try decodeRow(subtype: "chapter", precision: "month").dateLabel, "Mar 2025 - Jun 2025")
    // A range reads in its recorded zone, so the late-evening end stays on June 30.
    XCTAssertEqual(
      try decodeRow(precision: "range").dateLabel, "Mar 31, 2025 to Jun 30, 2025")
    // An unreadable zone falls back to UTC.
    XCTAssertEqual(
      try decodeRow(precision: "range", timezone: "Not/AZone").dateLabel,
      "Apr 1, 2025 to Jul 1, 2025")
    // An untitled row is already named by its date, and an undated row has none.
    let untitled = try decodeRow(title: " ", precision: "day")
    XCTAssertNil(untitled.dateLabel)
    XCTAssertEqual(untitled.displayTitle, "Monday, March 31, 2025")
    XCTAssertNil(try decodeRow(precision: "unknown", start: nil, end: nil).dateLabel)
    // A description is a date label even without a calendar date.
    XCTAssertEqual(
      try decodeRow(precision: "approximate", start: nil, end: nil, label: "That spring")
        .dateLabel, "That spring")
  }

  @MainActor
  func testLibraryPageParametersUseTheBoundedRPCContract() throws {
    let values = try object(
      LibraryPageParameters(limit: LibraryController.pageSize, offset: 72))

    XCTAssertEqual(
      Set(values.keys), ["p_query", "p_item_kinds", "p_item_subtypes", "p_limit", "p_offset"])
    XCTAssertEqual(values["p_query"] as? String, "")
    XCTAssertEqual(values["p_item_kinds"] as? [String], [])
    XCTAssertEqual(values["p_item_subtypes"] as? [String], [])
    XCTAssertEqual(values["p_limit"] as? Int, 36)
    XCTAssertEqual(values["p_offset"] as? Int, 72)
  }

  func testEveryRowOpensTheItemPage() throws {
    // Entries, Chapters, First Times, and both marks at once open the canonical Entry, never the
    // `item_id` of the row.
    for (subtype, isFirstTime) in [
      ("entry", false), ("chapter", false), ("entry", true), ("chapter", true),
    ] {
      let row = try decodeRow(subtype: subtype, isFirstTime: isFirstTime)
      XCTAssertEqual(row.link, ItemLink(entryID: row.id))
      XCTAssertEqual(row.link.entryID.uuidString, "98900000-0000-4000-8000-000000000011")
    }
    let result = SearchEntry(id: UUID(), title: "Result", body: "")
    XCTAssertEqual(result.link, ItemLink(entryID: result.id))
  }

  func testOnlyChaptersAndFirstTimesAreBadgedAndAnUntitledEntryShowsNoDate() throws {
    // Web `EntryList`: an ordinary Entry has no badge, so its row has no meta line without a date.
    let plain = try decodeRow(precision: "unknown", start: nil, end: nil)
    XCTAssertFalse(plain.hasMeta)
    XCTAssertEqual(plain.accessibilityLabel, "Evening walks")

    let untitledDay = try decodeRow(title: "", precision: "day")
    XCTAssertFalse(untitledDay.hasMeta)
    XCTAssertEqual(untitledDay.accessibilityLabel, "Monday, March 31, 2025")

    let dated = try decodeRow(precision: "day", end: nil)
    XCTAssertTrue(dated.hasMeta)
    XCTAssertEqual(dated.accessibilityLabel, "Evening walks, Mar 31, 2025")

    let firstTime = try decodeRow(isFirstTime: true, precision: "unknown", start: nil, end: nil)
    XCTAssertTrue(firstTime.hasMeta)
    XCTAssertEqual(firstTime.accessibilityLabel, "First Time, Evening walks")
    let both = try decodeRow(
      subtype: "chapter", isFirstTime: true, precision: "unknown", start: nil, end: nil)
    XCTAssertEqual(both.accessibilityLabel, "Chapter · First Time, Evening walks")
  }

  func testItemLinksOpenTheItemPageByEntry() {
    let id = UUID()
    XCTAssertEqual(ItemLink(entryID: id), ItemLink(entryID: id))
    XCTAssertEqual(ItemLink(entryID: id).id, id)
    XCTAssertNotEqual(ItemLink(entryID: id), ItemLink(entryID: UUID()))
  }

  func testCountLabelsPluralizeLikeWeb() {
    XCTAssertEqual(countLabel(1, "Entry"), "1 Entry")
    XCTAssertEqual(countLabel(3, "Entry"), "3 Entries")
    XCTAssertEqual(countLabel(2, "tag"), "2 tags")
    // Web pluralizes only a consonant and "y" as "ies", and takes irregular plurals explicitly.
    XCTAssertEqual(countLabel(2, "journey"), "2 journeys")
    XCTAssertEqual(countLabel(2, "person", plural: "people"), "2 people")
    XCTAssertEqual(countLabel(1, "person", plural: "people"), "1 person")
  }

  // MARK: Helpers

  private func decodeRow(
    title: String = "Evening walks", subtype: String = "entry", isFirstTime: Bool? = false,
    precision: String = "range", start: String? = "2025-04-01T00:30:00+00:00",
    end: String? = "2025-07-01T03:30:00+00:00", label: String? = nil,
    timezone: String = "America/Los_Angeles", totalCount: Any = 1
  ) throws -> LibraryRow {
    var object: [String: Any] = [
      "item_id": "98900000-0000-4000-8000-000000000001",
      "canonical_item_id": "98900000-0000-4000-8000-000000000011",
      "item_kind": "entry",
      "item_subtype": subtype,
      "title": title,
      "excerpt": "Along the river",
      "occurred_start": start.map { $0 as Any } ?? NSNull(),
      "occurred_end": end.map { $0 as Any } ?? NSNull(),
      "date_precision": precision,
      "occurred_label": label.map { $0 as Any } ?? NSNull(),
      "occurred_timezone": timezone,
      "updated_at": "2026-09-15T12:00:00.654321+00:00",
      "total_count": totalCount,
    ]
    if let isFirstTime { object["is_first_time"] = isFirstTime }
    return try JSONDecoder().decode(
      LibraryRow.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func object(_ value: some Encodable) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
