import XCTest

@testable import MemoTrail

final class LibraryDestinationTests: XCTestCase {
  func testGoalConversionPreservesIdentityAndExplicitNullTarget() throws {
    let id = UUID()
    let input = GoalConversionRequest(
      entryID: id, expectedRevision: 5, title: " 学习 ", horizon: .someday, status: .considering,
      targetDate: nil)
    XCTAssertTrue(input.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertEqual(json["p_entry_id"] as? String, id.uuidString)
    XCTAssertEqual(json["p_title"] as? String, "学习")
    XCTAssertEqual(json["p_expected_revision"] as? Int, 5)
    XCTAssertEqual(json["p_horizon"] as? String, "someday")
    XCTAssertTrue(json["p_target_date"] is NSNull)
    XCTAssertNil(json["p_body"])
    XCTAssertFalse(
      GoalConversionRequest(
        entryID: id, expectedRevision: 0, title: "Idea", horizon: .someday, status: .active,
        targetDate: nil
      ).isValid)
    XCTAssertFalse(
      GoalConversionRequest(
        entryID: id, expectedRevision: 1, title: " ", horizon: .someday, status: .active,
        targetDate: nil
      ).isValid)
    XCTAssertFalse(
      GoalConversionRequest(
        entryID: id, expectedRevision: 1, title: "Idea", horizon: .someday, status: .active,
        targetDate: "2026-02-30"
      ).isValid)
  }
  func testOrganizationInputAndCollectionTrashPreserveRPCContracts() throws {
    let request = OrganizationSaveRequest(
      kind: .collection, name: " 学习 ", sortOrder: -1, id: nil, expectedRevision: nil)
    XCTAssertTrue(request.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(json["p_name"] as? String, "学习")
    XCTAssertEqual(json["p_kind"] as? String, "collection")
    XCTAssertTrue(json["p_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertFalse(
      OrganizationSaveRequest(kind: .tag, name: "A", sortOrder: 1, id: nil, expectedRevision: nil)
        .isValid)
    XCTAssertFalse(
      OrganizationSaveRequest(kind: .tag, name: " ", sortOrder: 0, id: nil, expectedRevision: nil)
        .isValid)
    XCTAssertEqual(TrashItemKind(rawValue: "collection")?.displayName, "Collection")
  }
  func testTrackSettingsPreserveVisibilityIdentityAndRevision() throws {
    let data = Data(
      "{\"id\":\"95000000-0000-4000-8000-000000000001\",\"name\":\"学习\",\"system_key\":null,\"sort_order\":-3,\"is_hidden\":true,\"revision\":2,\"entry_count\":1,\"total_count\":5}"
        .utf8)
    let track = try JSONDecoder().decode(TimelineTrackSetting.self, from: data)
    XCTAssertTrue(track.isHidden)
    XCTAssertEqual(track.sortOrder, -3)
    let request = TrackSaveRequest(
      name: "  学习  ", sortOrder: -3, isHidden: true, trackID: track.id, expectedRevision: 2)
    XCTAssertTrue(request.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(json["p_name"] as? String, "学习")
    XCTAssertEqual(json["p_expected_revision"] as? Int, 2)
    let create = TrackSaveRequest(
      name: "New", sortOrder: 0, isHidden: false, trackID: nil, expectedRevision: nil)
    XCTAssertTrue(create.isValid)
    let newJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(create)) as? [String: Any])
    XCTAssertTrue(newJSON["p_track_id"] is NSNull)
    XCTAssertTrue(newJSON["p_expected_revision"] is NSNull)
    XCTAssertFalse(
      TrackSaveRequest(
        name: " ", sortOrder: 0, isHidden: false, trackID: nil, expectedRevision: nil
      ).isValid)
    XCTAssertFalse(
      TrackSaveRequest(
        name: "New", sortOrder: 1_000_001, isHidden: false, trackID: nil, expectedRevision: nil
      ).isValid)
    XCTAssertFalse(
      TrackSaveRequest(
        name: "New", sortOrder: 0, isHidden: false, trackID: track.id, expectedRevision: nil
      ).isValid)
  }
  func testHistorySupportsLegacySnapshotsAndPreservesExactRPCIdentity() throws {
    let legacy: [String: HistoryJSON] = [
      "body": .string("学习记录"), "title": .null, "revision": .number(1),
    ]
    var current = legacy
    current["collections"] = .array([.object(["name": .string("New collection")])])
    XCTAssertEqual(HistoryPresentation.title(legacy), "学习记录")
    XCTAssertEqual(
      HistoryPresentation.date([
        "occurred_start": .string("2021-01-01T01:00:00Z"),
        "occurred_timezone": .string("America/New_York"), "date_precision": .string("year"),
      ]), "2020")
    XCTAssertEqual(HistoryPresentation.date(legacy), "Unknown")
    XCTAssertEqual(HistoryPresentation.differences(current: current, previous: legacy), [])
    current["body"] = .string("Changed")
    XCTAssertEqual(HistoryPresentation.differences(current: current, previous: legacy), ["body"])
    let id = UUID()
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
          HistoryRestoreRequest(entryID: id, version: 1, expectedRevision: 3))) as? [String: Any])
    XCTAssertEqual(json["p_entry_id"] as? String, id.uuidString)
    XCTAssertEqual(json["p_expected_revision"] as? Int, 3)
    let decoded = try JSONDecoder().decode(
      [String: HistoryJSON].self, from: JSONEncoder().encode(legacy))
    XCTAssertEqual(decoded, legacy)
  }
  func testAISuggestionDecodesPendingAndBilingualProposedResults() throws {
    let pending = Data(
      "{\"suggestion\":{\"id\":\"93000000-0000-4000-8000-000000000001\",\"entry_revision\":1,\"status\":\"generating\",\"suggestions\":{}}}"
        .utf8)
    let decoded = try JSONDecoder().decode(EntryAISuggestionResponse.self, from: pending)
    XCTAssertEqual(decoded.suggestion?.status, "generating")
    XCTAssertNil(decoded.suggestion?.suggestions)
    XCTAssertNil(decoded.photoCount)
    let photoResponse = try JSONDecoder().decode(
      EntryAISuggestionResponse.self, from: Data("{\"suggestion\":null,\"photoCount\":2}".utf8))
    XCTAssertEqual(photoResponse.photoCount, 2)
    let proposed = Data(
      "{\"title\":\"牙套的原理\",\"entryType\":\"standard\",\"collections\":[\"Learning\"],\"tags\":[\"牙齿\"],\"dateText\":null,\"rationale\":\"学习记录\",\"confidence\":0.9}"
        .utf8)
    XCTAssertEqual(try JSONDecoder().decode(EntryAISuggestions.self, from: proposed).title, "牙套的原理")
  }
  func testAIPreferencesRequireOptInAndBoundedBudget() throws {
    var preferences = AIPreferences()
    XCTAssertFalse(preferences.enabled)
    XCTAssertFalse(preferences.photoAnalysis)
    XCTAssertTrue(preferences.isValid)
    preferences.monthlyBudgetMicros = -1
    XCTAssertFalse(preferences.isValid)
    preferences.monthlyBudgetMicros = 100_000_001
    XCTAssertFalse(preferences.isValid)
    preferences.monthlyBudgetMicros = 0
    XCTAssertTrue(preferences.isValid)
    let data = try JSONEncoder().encode(
      AISettingsInput(preferences: preferences, expectedRevision: 0))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["p_expected_revision"] as? Int, 0)
    XCTAssertEqual(AIAPI.cost(29), "$0.000029")
  }
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
