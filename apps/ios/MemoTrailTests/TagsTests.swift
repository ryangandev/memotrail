import XCTest

@testable import MemoTrail

/// Tags like Web `organization.ts`, `organization-workspace.ts`, and `app/organization/actions.ts`.
final class TagsTests: XCTestCase {
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

  func testTagEntryPreviewAsksForTheFirstFiveEntriesOfOneTagByRelevance() throws {
    let request = try EntrySearchRequest.validate(query: "", tagNames: [" coast "], limit: 5)
    let json = try object(request.parameters)

    XCTAssertEqual(
      Set(json.keys),
      [
        "p_query", "p_item_classifications", "p_tag_names", "p_date_from", "p_date_to",
        "p_limit", "p_offset", "p_order",
      ])
    XCTAssertEqual(json["p_tag_names"] as? [String], ["coast"])
    XCTAssertEqual(json["p_query"] as? String, "")
    XCTAssertEqual(json["p_limit"] as? Int, 5)
    XCTAssertEqual(json["p_offset"] as? Int, 0)
    XCTAssertEqual(json["p_order"] as? String, "relevance")
    XCTAssertEqual(json["p_item_classifications"] as? [String], [])
    XCTAssertTrue(json["p_date_from"] is NSNull)
    XCTAssertTrue(json["p_date_to"] is NSNull)
  }

  func testTagEditorNamesItsEntriesLikeWebAndLeavesAnUntitledOneToItsDate() throws {
    let day = try XCTUnwrap(EntryTimestamp.date(from: "2026-09-03T12:00:00+00:00"))
    func entry(_ title: String?) -> SearchEntry {
      SearchEntry(
        id: UUID(), title: title, body: "Sat by the water.", occurredAt: day,
        datePrecision: .day, occurredTimezone: "UTC", tagNames: ["coast"])
    }

    let titled = entry("A quiet afternoon by the coast")
    XCTAssertEqual(titled.displayTitle, "A quiet afternoon by the coast")
    XCTAssertEqual(titled.displayDate, "Sep 3, 2026")
    XCTAssertEqual(titled.identityLabel, "Entry")
    // An untitled Entry is already named by its date, so the editor does not repeat it.
    let untitled = entry(nil)
    XCTAssertEqual(untitled.displayTitle, "Thursday, September 3, 2026")
    XCTAssertNil(untitled.title)
  }

  private func object(_ value: some Encodable) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
