import XCTest

@testable import MemoTrail

final class LibraryDestinationTests: XCTestCase {
  func testPersonSavePreservesExplicitNewIdentityAndValidatesLimits() throws {
    let input = PersonSaveInput(
      p_person_id: nil, p_expected_revision: nil,
      p_name: " Friend ", p_relationship_label: " Mentor ", p_notes: " Notes ",
      p_related_entry_ids: [])
    XCTAssertTrue(input.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertTrue(json["p_person_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertEqual(json["p_name"] as? String, "Friend")
    XCTAssertFalse(
      PersonSaveInput(
        p_person_id: UUID(), p_expected_revision: nil,
        p_name: "Friend", p_relationship_label: "", p_notes: "", p_related_entry_ids: []
      ).isValid)
    XCTAssertFalse(
      PersonSaveInput(
        p_person_id: nil, p_expected_revision: nil,
        p_name: " ", p_relationship_label: "", p_notes: "", p_related_entry_ids: []
      ).isValid)
  }

  func testPeopleWorkspacePreservesTrashedLinksForExplicitRemoval() throws {
    let data = Data(
      """
      [{"id":"92000000-0000-4000-8000-000000000001","name":"Friend","relationship_label":"Mentor",
        "notes":null,"revision":2,"total_count":1,"linked_entries":[
        {"id":"91000000-0000-4000-8000-000000000001","title":null,"body":"A shared memory",
          "entry_type":"standard","is_deleted":true}]}]
      """.utf8)
    let row = try XCTUnwrap(JSONDecoder().decode([PersonRecord].self, from: data).first)
    XCTAssertEqual(row.linked_entries.first?.displayTitle, "A shared memory")
    XCTAssertEqual(row.linked_entries.first?.is_deleted, true)
    XCTAssertEqual(TrashItemKind(rawValue: "person")?.displayName, "Person")
  }

  func testAvailableDestinationsContainOnlyImplementedArchives() {
    XCTAssertEqual(
      LibraryDestination.available,
      [.collections, .firstTimes, .homes, .places, .people, .vehicles, .goals, .trash]
    )
    XCTAssertTrue(LibraryDestination.available.allSatisfy(\.isAvailable))
  }

  func testPlannedDestinationsRemainVisibleButUnavailable() {
    XCTAssertEqual(
      LibraryDestination.planned,
      []
    )
    XCTAssertTrue(LibraryDestination.planned.allSatisfy { !$0.isAvailable })
  }

  func testEveryDestinationHasDistinctStableIdentity() {
    XCTAssertEqual(Set(LibraryDestination.allCases.map(\.id)).count, 8)
    XCTAssertEqual(LibraryDestination.allCases.count, 8)
  }

  func testEveryDestinationHasUserFacingMetadata() {
    for destination in LibraryDestination.allCases {
      XCTAssertFalse(destination.title.isEmpty)
      XCTAssertFalse(destination.summary.isEmpty)
      XCTAssertFalse(destination.systemImage.isEmpty)
    }
  }
}
