import XCTest

@testable import MemoTrail

final class LibraryDestinationTests: XCTestCase {
  func testGoalExtractionPreservesSourceAndTargetIdentityWithExplicitNullTarget() throws {
    let sourceID = UUID()
    let goalID = UUID()
    let input = GoalExtractionRequest(
      sourceEntryID: sourceID, sourceRevision: 5, goalID: goalID, title: " 学习 ",
      horizon: .someday, status: .considering, targetDate: nil)
    XCTAssertTrue(input.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertEqual(json["p_source_entry_id"] as? String, sourceID.uuidString)
    XCTAssertEqual(json["p_goal_id"] as? String, goalID.uuidString)
    XCTAssertEqual(json["p_title"] as? String, "学习")
    XCTAssertEqual(json["p_source_revision"] as? Int, 5)
    XCTAssertEqual(json["p_horizon"] as? String, "someday")
    XCTAssertTrue(json["p_target_date"] is NSNull)
    XCTAssertNil(json["p_body"])
    XCTAssertFalse(
      GoalExtractionRequest(
        sourceEntryID: sourceID, sourceRevision: 0, goalID: goalID, title: "Idea",
        horizon: .someday, status: .active, targetDate: nil
      ).isValid)
    XCTAssertFalse(
      GoalExtractionRequest(
        sourceEntryID: sourceID, sourceRevision: 1, goalID: goalID, title: " ",
        horizon: .someday, status: .active, targetDate: nil
      ).isValid)
    XCTAssertFalse(
      GoalExtractionRequest(
        sourceEntryID: sourceID, sourceRevision: 1, goalID: goalID, title: "Idea",
        horizon: .someday, status: .active, targetDate: "2026-02-30"
      ).isValid)
    XCTAssertFalse(
      GoalExtractionRequest(
        sourceEntryID: sourceID, sourceRevision: 1, goalID: sourceID, title: "Idea",
        horizon: .someday, status: .active, targetDate: nil
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
    // Web `validOrganizationInput`: tags keep to 60 characters and Collections to 80.
    let tag = { (name: String) in
      OrganizationSaveRequest(kind: .tag, name: name, sortOrder: 0, id: nil, expectedRevision: nil)
    }
    XCTAssertTrue(tag(String(repeating: "界", count: 60)).isValid)
    XCTAssertFalse(tag(String(repeating: "界", count: 61)).isValid)
    XCTAssertTrue(
      OrganizationSaveRequest(
        kind: .collection, name: String(repeating: "a", count: 80), sortOrder: 0, id: nil,
        expectedRevision: nil
      ).isValid)
    XCTAssertEqual(tag("").invalidMessage, "Use a tag name up to 60 characters.")
    XCTAssertEqual(OrganizationKind.tag.label, "Tag")
    XCTAssertEqual(TrashItemKind(rawValue: "collection")?.displayName, "Collection")
  }
  func testTagMergeRequestKeepsBothRevisionsAndRejectsItself() throws {
    let source = UUID()
    let target = UUID()
    let request = TagMergeRequest(
      sourceID: source, sourceRevision: 2, targetID: target, targetRevision: 5)
    XCTAssertTrue(request.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(json["p_source_id"] as? String, source.uuidString)
    XCTAssertEqual(json["p_source_revision"] as? Int, 2)
    XCTAssertEqual(json["p_target_id"] as? String, target.uuidString)
    XCTAssertEqual(json["p_target_revision"] as? Int, 5)
    XCTAssertFalse(
      TagMergeRequest(sourceID: source, sourceRevision: 2, targetID: source, targetRevision: 2)
        .isValid)
    XCTAssertEqual(countLabel(1, "Entry"), "1 Entry")
    XCTAssertEqual(countLabel(3, "Entry"), "3 Entries")
    XCTAssertEqual(countLabel(2, "tag"), "2 tags")
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
    XCTAssertEqual(HistoryPresentation.differences(current: current, previous: legacy), ["Writing"])
    XCTAssertEqual(HistoryPresentation.title(title: "  ", body: " \n "), "Untitled item")
    XCTAssertEqual(
      HistoryPresentation.date([
        "occurred_start": .string("2021-01-01T15:30:00Z"), "occurred_end": .null,
        "occurred_timezone": .string("Asia/Shanghai"), "date_precision": .string("exact"),
      ]), "Jan 1, 2021, 11:30\u{202F}PM")
    XCTAssertEqual(
      HistoryPresentation.date([
        "occurred_start": .string("2021-03-01T00:00:00Z"),
        "occurred_end": .string("2021-04-01T00:00:00Z"), "date_precision": .string("month"),
      ]), "Mar 2021 to Apr 2021")
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
      "{\"title\":\"牙套的原理\",\"classification\":{\"itemKind\":\"writing\",\"itemSubtype\":\"note\"},\"collections\":[\"Learning\"],\"tags\":[\"牙齿\"],\"dateText\":null,\"rationale\":\"学习记录\",\"confidence\":0.9}"
        .utf8)
    XCTAssertEqual(try JSONDecoder().decode(EntryAISuggestions.self, from: proposed).title, "牙套的原理")
  }
  func testEntryRelationsDecodeBacklinksAndEncodeBoundedPages() throws {
    let id = UUID()
    let target = UUID()
    let data = Data(
      "{\"revision\":3,\"total_count\":25,\"items\":[{\"entry_id\":\"\(target)\",\"title\":null,\"excerpt\":\"牙套笔记\",\"item_kind\":\"entry\",\"item_subtype\":\"entry\",\"is_deleted\":true}]}"
        .utf8)
    let result = try JSONDecoder().decode(EntryRelationsResult.self, from: data)
    XCTAssertEqual(result.revision, 3)
    XCTAssertEqual(result.totalCount, 25)
    XCTAssertEqual(result.items.first?.displayTitle, "牙套笔记")
    XCTAssertEqual(result.items.first?.isDeleted, true)
    let request = EntryRelationsRequest(entryID: id, mode: .incoming, query: "  牙套  ", page: 2)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(json["p_mode"] as? String, "incoming")
    XCTAssertEqual(json["p_query"] as? String, "牙套")
    XCTAssertEqual(json["p_offset"] as? Int, 40)
    XCTAssertEqual(json["p_limit"] as? Int, 20)
  }
  func testEntryRelationChangesRequireDistinctTargetsAndValidRevision() throws {
    let id = UUID()
    let target = UUID()
    XCTAssertFalse(
      EntryRelationChange(entryID: id, targetID: id, expectedRevision: 1, linked: true).isValid)
    XCTAssertFalse(
      EntryRelationChange(entryID: id, targetID: target, expectedRevision: 0, linked: false).isValid
    )
    let request = EntryRelationChange(
      entryID: id, targetID: target, expectedRevision: 3, linked: false)
    XCTAssertTrue(request.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(json["p_linked"] as? Bool, false)
    XCTAssertEqual(json["p_expected_revision"] as? Int, 3)
    XCTAssertFalse(EntryRelationsRequest(entryID: id, mode: .outgoing, query: "", page: -1).isValid)
    XCTAssertFalse(
      EntryRelationsRequest(
        entryID: id, mode: .outgoing, query: String(repeating: "a", count: 201), page: 0
      ).isValid)
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
    let linked = UUID()
    let input = PersonSaveInput(
      personID: nil, expectedRevision: nil, name: " Friend ", relationshipLabel: " Mentor ",
      notes: " Notes ", relatedEntryIDs: [linked, linked])
    XCTAssertTrue(input.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertTrue(json["p_person_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertEqual(json["p_name"] as? String, "Friend")
    XCTAssertEqual(json["p_relationship_label"] as? String, "Mentor")
    XCTAssertEqual(json["p_related_entry_ids"] as? [String], [linked.uuidString])
    XCTAssertFalse(
      PersonSaveInput(
        personID: UUID(), expectedRevision: nil, name: "Friend", relationshipLabel: "",
        notes: "", relatedEntryIDs: []
      ).isValid)
    XCTAssertFalse(
      PersonSaveInput(
        personID: nil, expectedRevision: nil, name: " ", relationshipLabel: "", notes: "",
        relatedEntryIDs: []
      ).isValid)
    XCTAssertFalse(
      PersonSaveInput(
        personID: nil, expectedRevision: nil, name: "Friend", relationshipLabel: "", notes: "",
        relatedEntryIDs: (0...PersonSaveInput.linkLimit).map { _ in UUID() }
      ).isValid)
  }

  func testPeopleWorkspacePreservesTrashedLinksForExplicitRemoval() throws {
    let data = Data(
      """
      [{"id":"92000000-0000-4000-8000-000000000001","name":"Friend","relationship_label":"Mentor",
        "notes":null,"revision":2,"total_count":1,"linked_entries":[
        {"id":"91000000-0000-4000-8000-000000000001","title":null,"body":"A shared memory",
          "item_kind":"entry","item_subtype":"moment","is_deleted":true}]}]
      """.utf8)
    let row = try XCTUnwrap(JSONDecoder().decode([PersonRecord].self, from: data).first)
    XCTAssertEqual(row.relationshipLabel, "Mentor")
    XCTAssertEqual(row.linkedEntries.first?.displayTitle, "A shared memory")
    XCTAssertEqual(row.linkedEntries.first?.isDeleted, true)
    XCTAssertEqual(TrashItemKind(rawValue: "person")?.displayName, "Person")
  }

  func testWikiItemSummaryDecodesCanonicalAndSpecializedIdentity() throws {
    let json = """
      {
        "record_source": "person",
        "item_id": "98900000-0000-4000-8000-000000000001",
        "canonical_item_id": "98900000-0000-4000-8000-000000000011",
        "item_kind": "entity",
        "item_subtype": "person",
        "title": "Marina",
        "excerpt": "Friend from the harbor",
        "inbox_status": "organized",
        "occurred_start": null,
        "occurred_end": null,
        "updated_at": "2026-09-15T12:00:00Z",
        "total_count": 14
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let item = try decoder.decode(WikiItemSummary.self, from: Data(json.utf8))

    XCTAssertEqual(item.id.uuidString, "98900000-0000-4000-8000-000000000011")
    XCTAssertEqual(item.recordID.uuidString, "98900000-0000-4000-8000-000000000001")
    XCTAssertEqual(item.recordSource, .person)
    XCTAssertEqual(item.itemKind, .entity)
    XCTAssertEqual(item.identityLabel, "Person")
    XCTAssertEqual(item.totalCount, 14)
    XCTAssertEqual(item.dateLabel, "Updated Sep 15, 2026")
  }

  func testWikiItemDateLabelsReadStoredDatesInUTCLikeWeb() throws {
    let json = """
      {
        "record_source": "entry",
        "item_id": "98900000-0000-4000-8000-000000000002",
        "canonical_item_id": "98900000-0000-4000-8000-000000000002",
        "item_kind": "entry",
        "item_subtype": "period",
        "title": "Evening walks",
        "excerpt": "",
        "inbox_status": "organized",
        "occurred_start": "2025-04-01T00:30:00Z",
        "occurred_end": "2025-06-30T23:30:00Z",
        "updated_at": "2026-09-15T12:00:00Z",
        "total_count": 1
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let item = try decoder.decode(WikiItemSummary.self, from: Data(json.utf8))

    XCTAssertEqual(item.dateLabel, "Apr 1, 2025 to Jun 30, 2025")
    XCTAssertEqual(item.subtypeLabel, "Period")
  }

  func testWikiItemsPageParametersUseTheBoundedRPCContract() throws {
    let parameters = WikiItemsPageParameters(
      pQuery: "harbor",
      pItemKinds: ["entity"],
      pItemSubtypes: ["person"],
      pLimit: 36,
      pOffset: 72
    )
    let values = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])

    XCTAssertEqual(values["p_query"] as? String, "harbor")
    XCTAssertEqual(values["p_item_kinds"] as? [String], ["entity"])
    XCTAssertEqual(values["p_item_subtypes"] as? [String], ["person"])
    XCTAssertEqual(values["p_limit"] as? Int, 36)
    XCTAssertEqual(values["p_offset"] as? Int, 72)
  }

  @MainActor
  func testWikiItemLinksFollowWebRoutingAndLibraryFilters() {
    let navigator = AppNavigator()
    var pushed: [WikiItemLink] = []
    let capture = WikiItemLink(entryID: UUID(), kind: .entry, subtype: "entry", isInInbox: true)
    navigator.open(capture) { pushed.append($0) }
    XCTAssertEqual(navigator.selectedTab, .inbox)
    XCTAssertEqual(navigator.inboxReviewRequest, capture.entryID)

    let period = WikiItemLink(entryID: UUID(), kind: .entry, subtype: "period")
    navigator.open(period) { pushed.append($0) }
    XCTAssertEqual(navigator.selectedTab, .timeline)
    XCTAssertEqual(navigator.timelineEntryRequest, period.entryID)

    let person = WikiItemLink(entryID: UUID(), kind: .entity, subtype: "person", personID: UUID())
    navigator.open(person) { pushed.append($0) }
    XCTAssertEqual(pushed, [person])

    navigator.openLibrary(tag: "coast")
    XCTAssertEqual(navigator.selectedTab, .library)
    XCTAssertEqual(navigator.libraryFilterRequest, .tag("coast"))
    navigator.openLibrary(collection: "Summer 2025")
    XCTAssertEqual(navigator.libraryFilterRequest, .collection("Summer 2025"))
  }
}
