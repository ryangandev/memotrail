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

  func testItemLinksOpenTheItemPageByEntry() {
    let id = UUID()
    XCTAssertEqual(ItemLink(entryID: id), ItemLink(entryID: id))
    XCTAssertEqual(ItemLink(entryID: id).id, id)
    XCTAssertNotEqual(ItemLink(entryID: id), ItemLink(entryID: UUID()))
  }

  // MARK: Tags

  func testTagSaveRequestValidatesLikeWebAndSendsExplicitNulls() throws {
    let create = TagSaveRequest(name: " 学习 ", id: nil, expectedRevision: nil)
    XCTAssertTrue(create.isValid)
    let json = try object(create)
    XCTAssertEqual(Set(json.keys), ["p_name", "p_id", "p_expected_revision"])
    XCTAssertEqual(json["p_name"] as? String, "学习")
    XCTAssertTrue(json["p_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)

    let id = UUID()
    XCTAssertTrue(TagSaveRequest(name: "Coast", id: id, expectedRevision: 2).isValid)
    XCTAssertFalse(TagSaveRequest(name: "Coast", id: id, expectedRevision: nil).isValid)
    XCTAssertFalse(TagSaveRequest(name: "Coast", id: id, expectedRevision: 0).isValid)
    XCTAssertFalse(TagSaveRequest(name: "Coast", id: nil, expectedRevision: 1).isValid)
    XCTAssertFalse(TagSaveRequest(name: " ", id: nil, expectedRevision: nil).isValid)
    XCTAssertTrue(
      TagSaveRequest(
        name: String(repeating: "界", count: EntryLimits.tagName), id: nil, expectedRevision: nil
      ).isValid)
    XCTAssertFalse(
      TagSaveRequest(
        name: String(repeating: "界", count: EntryLimits.tagName + 1), id: nil,
        expectedRevision: nil
      ).isValid)
    XCTAssertEqual(TagSaveRequest.invalidMessage, "Use a tag name up to 80 characters.")
  }

  func testTagMergeAndDeleteRequestsKeepRevisionsAndRejectAMergeIntoItself() throws {
    let source = UUID()
    let target = UUID()
    let request = TagMergeRequest(
      sourceID: source, sourceRevision: 2, targetID: target, targetRevision: 5)
    XCTAssertTrue(request.isValid)
    let json = try object(request)
    XCTAssertEqual(json["p_source_id"] as? String, source.uuidString)
    XCTAssertEqual(json["p_source_revision"] as? Int, 2)
    XCTAssertEqual(json["p_target_id"] as? String, target.uuidString)
    XCTAssertEqual(json["p_target_revision"] as? Int, 5)
    XCTAssertFalse(
      TagMergeRequest(sourceID: source, sourceRevision: 2, targetID: source, targetRevision: 2)
        .isValid)
    XCTAssertFalse(
      TagMergeRequest(sourceID: source, sourceRevision: 0, targetID: target, targetRevision: 2)
        .isValid)

    let delete = try object(TagDeleteRequest(id: source, expectedRevision: 3))
    XCTAssertEqual(Set(delete.keys), ["p_id", "p_expected_revision"])
    XCTAssertEqual(delete["p_expected_revision"] as? Int, 3)
  }

  func testTagsPageAndRowsMatchTheWorkspaceRPC() throws {
    let page = try object(
      TagsPageRequest(query: "  " + String(repeating: "q", count: 250), offset: 50))
    XCTAssertEqual(Set(page.keys), ["p_query", "p_offset", "p_limit"])
    XCTAssertEqual((page["p_query"] as? String)?.count, 200)
    XCTAssertEqual(page["p_offset"] as? Int, 50)
    XCTAssertEqual(page["p_limit"] as? Int, TagsPageRequest.pageSize)

    let rows = try JSONDecoder().decode(
      [TagItem].self,
      from: Data(
        """
        [{"id":"98900000-0000-4000-8000-000000000021","name":"Coast","revision":2,"entry_count":3,"total_count":"12"}]
        """.utf8))
    XCTAssertEqual(rows.first?.name, "Coast")
    XCTAssertEqual(rows.first?.entryCount, 3)
    XCTAssertEqual(rows.first?.totalCount, 12)
  }

  func testTagOptionsAreMostUsedFirstAndTypedNamesReuseExistingSpelling() throws {
    let rows = try JSONDecoder().decode(
      [TagUsageRow].self,
      from: Data(
        """
        [{"name":"coast","entry_tags":[{"count":1}]},{"name":"Lisbon","entry_tags":[{"count":4}]},
        {"name":"Beach","entry_tags":[{"count":1}]},{"name":"unused","entry_tags":[]}]
        """.utf8))
    XCTAssertEqual(TagUsageRow.optionsByUse(rows), ["Lisbon", "Beach", "coast", "unused"])
    XCTAssertEqual(existingTagName("  LISBON ", options: ["Lisbon"]), "Lisbon")
    XCTAssertEqual(existingTagName("  Porto ", options: ["Lisbon"]), "Porto")
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
