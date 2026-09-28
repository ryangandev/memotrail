import XCTest

@testable import MemoTrail

final class GoalEntryTests: XCTestCase {
  func testBucketListRoleSurvivesRenamingAndCanBeExplicitlyRemoved() throws {
    var row = makeRow()
    row.bucketListRole = true
    XCTAssertTrue(row.entry.isBucketList)
    row.bucketListRole = false
    XCTAssertFalse(row.entry.isBucketList)
    let renamedJSON = workspaceJSON.replacingOccurrences(
      of: "\"collection_names\":[\"Bucket List\"]",
      with: "\"collection_names\":[\"Someday adventures\"],\"is_bucket_list\":true")
    let decoded = try decoder.decode([GoalWorkspaceRow].self, from: Data(renamedJSON.utf8))
    XCTAssertEqual(decoded.first?.entry.bucketListRole, true)
    XCTAssertEqual(decoded.first?.entry.isBucketList, true)
  }
  func testWorkspaceDecodesGoalContextRelationshipsAndPrivatePhoto() throws {
    let rows = try decoder.decode([GoalWorkspaceRow].self, from: Data(workspaceJSON.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.title, "Learn to ski")
    XCTAssertEqual(entry.horizon, .longTerm)
    XCTAssertEqual(entry.status, .active)
    XCTAssertEqual(entry.targetLabel, "Target Jul 3, 2027")
    XCTAssertTrue(entry.isBucketList)
    XCTAssertEqual(entry.editableRelatedEntries.first?.displayTitle, "Winter notes")
    XCTAssertEqual(entry.achievementEntries.first?.itemKind, .entry)
    XCTAssertEqual(entry.achievementEntries.first?.itemSubtype, "first_time")
    XCTAssertEqual(entry.attachments.first?.mimeType, .jpeg)
    XCTAssertNil(entry.attachments.first?.signedURL)
  }

  func testWorkspaceSortsByReflectiveStateTargetAndRecency() {
    let activeLater = makeRow(title: "Later", status: .active, targetDate: "2027-01-01")
    let activeSoon = makeRow(title: "Soon", status: .active, targetDate: "2026-10-01")
    let considering = makeRow(title: "Maybe", status: .considering)
    let achieved = makeRow(title: "Done", status: .achieved)

    XCTAssertEqual(
      GoalWorkspace.entries(from: [achieved, considering, activeLater, activeSoon]).map(\.title),
      ["Soon", "Later", "Maybe", "Done"]
    )
  }

  func testWorkspaceFiltersClosedChaptersWithoutChangingOrder() {
    let achieved = makeRow(title: "Achieved", status: .achieved)
    let letGo = makeRow(title: "Released", status: .letGo)
    let active = makeRow(title: "Active", status: .active)

    XCTAssertEqual(
      GoalWorkspace.entries(
        [letGo.entry, active.entry, achieved.entry],
        matching: [.achieved, .letGo]
      ).map(\.title),
      ["Achieved", "Released"]
    )
  }

  func testValidationNormalizesContentOrganizationAndRelatedEntries() throws {
    let firstID = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
    let secondID = UUID(uuidString: "10000000-0000-4000-8000-000000000012")!
    let input = try makeInput(
      title: "  Learn to ski  ",
      body: "  Keep it joyful.  ",
      collectionNames: [" Bucket List ", "bucket list", "Growth"],
      tagNames: [" Winter ", "winter", "Outside"],
      relatedEntryIDs: [firstID, firstID, secondID]
    )

    XCTAssertEqual(input.title, "Learn to ski")
    XCTAssertEqual(input.body, "Keep it joyful.")
    XCTAssertEqual(input.collectionNames, ["Bucket List", "Growth"])
    XCTAssertEqual(input.tagNames, ["Winter", "Outside"])
    XCTAssertEqual(input.relatedEntryIDs, [firstID, secondID])
  }

  func testValidationRejectsMissingTitleInvalidDateAndSelfLink() {
    XCTAssertThrowsError(try makeInput(title: " ")) { error in
      XCTAssertEqual(error as? GoalEntryError, .titleRequired)
    }
    XCTAssertThrowsError(try makeInput(targetDate: "2026-02-30")) { error in
      XCTAssertEqual(error as? GoalEntryError, .invalidTargetDate)
    }
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    XCTAssertThrowsError(
      try makeInput(entryID: entryID, expectedRevision: 2, relatedEntryIDs: [entryID])
    ) { error in
      XCTAssertEqual(error as? GoalEntryError, .invalidRelatedEntries)
    }
  }

  func testValidationRequiresRevisionOnlyForExistingGoal() {
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? GoalEntryError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeInput(
        entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testSaveParametersUseRPCNamesAndExplicitNulls() throws {
    let input = try makeInput(targetDate: nil)
    let data = try JSONEncoder().encode(SaveGoalEntryParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_target_date"] is NSNull)
    XCTAssertEqual(json["p_horizon"] as? String, "short_term")
    XCTAssertEqual(json["p_status"] as? String, "considering")
    XCTAssertEqual(json["p_related_entry_ids"] as? [String], [])
  }

  func testCaptureExtractionParametersUseSourceIdentityAndGoalFields() throws {
    let entryID = UUID(uuidString: "93000000-0000-4000-8000-000000000001")!
    let entry = InboxEntry(
      id: entryID, title: "Learn to ski", body: "Try this winter", createdAt: Date(),
      occurredStart: nil, revision: 6)
    let source = CaptureExtractionSource(
      entry: entry, title: "Learn to ski", body: "Try this winter",
      occurrence: entry.occurrence, collectionNames: ["Someday"], tagNames: ["skiing"])
    let input = try makeInput(
      collectionNames: source.collectionNames, tagNames: source.tagNames,
      relatedEntryIDs: [UUID(uuidString: "93000000-0000-4000-8000-000000000002")!])
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(SaveGoalEntryParameters(input: input, source: source)))
        as? [String: Any])

    XCTAssertEqual(json["p_capture_id"] as? String, entryID.uuidString)
    XCTAssertEqual(json["p_capture_revision"] as? Int, 6)
    XCTAssertEqual(json["p_horizon"] as? String, "short_term")
    XCTAssertEqual(json["p_target_date"] as? String, "2027-07-03")
    XCTAssertNil(json["p_entry_id"])
  }

  func testAchievementValidationNormalizesContextAndRejectsInvalidTimezone() throws {
    let input = try GoalAchievementInput.validate(
      goalEntryID: UUID(),
      expectedRevision: 3,
      occurredStart: Date(timeIntervalSince1970: 100),
      datePrecision: .approximate,
      occurredLabel: "  First snow trip  ",
      occurredTimezone: "America/Los_Angeles"
    )
    XCTAssertEqual(input.occurredLabel, "First snow trip")
    XCTAssertThrowsError(
      try GoalAchievementInput.validate(
        goalEntryID: UUID(),
        expectedRevision: 3,
        occurredStart: Date(),
        datePrecision: .day,
        occurredLabel: "",
        occurredTimezone: "Mars/Olympus"
      )
    ) { error in
      XCTAssertEqual(error as? GoalEntryError, .invalidTimezone)
    }
  }

  func testAchievementParametersUseRPCNamesAndExplicitNullLabel() throws {
    let input = try GoalAchievementInput.validate(
      goalEntryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      expectedRevision: 4,
      occurredStart: Date(timeIntervalSince1970: 100),
      datePrecision: .day,
      occurredLabel: "",
      occurredTimezone: "America/Los_Angeles"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(GoalAchievementParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_goal_entry_id"] as? String, input.goalEntryID.uuidString.lowercased())
    XCTAssertEqual(json["p_expected_revision"] as? Int, 4)
    XCTAssertEqual(json["p_date_precision"] as? String, "day")
    XCTAssertTrue(json["p_occurred_label"] is NSNull)
  }

  func testCalendarDateRoundTripsWithoutTimezoneDrift() throws {
    let date = try XCTUnwrap(GoalCalendarDate.date(from: "2027-07-03"))
    XCTAssertEqual(GoalCalendarDate.string(from: date), "2027-07-03")
    XCTAssertFalse(GoalCalendarDate.isValid("2027-7-3"))
  }

  func testAchievementSupportsAllPrecisionsAndNullableBounds() throws {
    XCTAssertEqual(GoalAchievementPrecision.allCases.count, 8)
    for precision in [GoalAchievementPrecision.age, .approximate, .unknown] {
      let input = try GoalAchievementInput.validate(
        goalEntryID: UUID(), expectedRevision: 1, occurredStart: nil, datePrecision: precision,
        occurredLabel: precision == .unknown ? "" : "17岁", occurredTimezone: "UTC")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(
          with: JSONEncoder().encode(GoalAchievementParameters(input: input))) as? [String: Any])
      XCTAssertTrue(json["p_occurred_start"] is NSNull)
      XCTAssertTrue(json["p_occurred_end"] is NSNull)
    }
    let start = Date(timeIntervalSince1970: 100)
    let end = Date(timeIntervalSince1970: 200)
    let input = try GoalAchievementInput.validate(
      goalEntryID: UUID(), expectedRevision: 1, occurredStart: start, datePrecision: .range,
      occurredLabel: "", occurredTimezone: "UTC", occurredEnd: end)
    XCTAssertEqual(input.occurredEnd, end)
    XCTAssertThrowsError(
      try GoalAchievementInput.validate(
        goalEntryID: UUID(), expectedRevision: 1, occurredStart: end, datePrecision: .range,
        occurredLabel: "", occurredTimezone: "UTC", occurredEnd: start))
    XCTAssertThrowsError(
      try GoalAchievementInput.validate(
        goalEntryID: UUID(), expectedRevision: 1, occurredStart: nil, datePrecision: .age,
        occurredLabel: "", occurredTimezone: "UTC"))
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeInput(
    entryID: UUID? = nil,
    expectedRevision: Int? = nil,
    title: String = "Learn to ski",
    body: String = "Reflection",
    targetDate: String? = "2027-07-03",
    collectionNames: [String] = [],
    tagNames: [String] = [],
    relatedEntryIDs: [UUID] = []
  ) throws -> GoalEntryInput {
    try GoalEntryInput.validate(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      horizon: .shortTerm,
      status: .considering,
      targetDate: targetDate,
      collectionNames: collectionNames,
      tagNames: tagNames,
      relatedEntryIDs: relatedEntryIDs
    )
  }

  private func makeRow(
    title: String = "Learn to ski",
    status: GoalStatus = .active,
    targetDate: String? = nil
  ) -> GoalWorkspaceRow {
    GoalWorkspaceRow(
      entryID: UUID(),
      title: title,
      body: "Reflection",
      revision: 1,
      createdAt: Date(timeIntervalSince1970: 50),
      updatedAt: Date(timeIntervalSince1970: 100),
      horizon: .longTerm,
      status: status,
      targetDate: targetDate,
      collectionNames: [],
      tagNames: [],
      relatedEntries: [],
      attachments: [],
      totalCount: 1
    )
  }

  private var workspaceJSON: String {
    """
    [{
      "entry_id":"10000000-0000-4000-8000-000000000001",
      "title":"Learn to ski","body":"Stay curious.","revision":3,
      "created_at":"2026-09-03T19:00:00Z","updated_at":"2026-09-03T20:00:00Z",
      "horizon":"long_term","status":"active","target_date":"2027-07-03",
      "collection_names":["Bucket List"],"tag_names":["winter"],
      "related_entries":[{
        "id":"20000000-0000-4000-8000-000000000001","title":"Winter notes",
        "body":"What I learned.","item_kind":"entry","item_subtype":"entry","occurred_start":null,
        "occurred_label":null,"occurred_timezone":null,"revision":2,
        "updated_at":"2026-09-03T20:00:00Z","relationship":"related"
      },{
        "id":"20000000-0000-4000-8000-000000000002","title":"First ski day",
        "body":"","item_kind":"entry","item_subtype":"first_time","occurred_start":"2027-07-03T19:00:00Z",
        "occurred_label":null,"occurred_timezone":"America/Los_Angeles","revision":1,
        "updated_at":"2027-07-03T20:00:00Z","relationship":"achievement"
      }],"attachments":[{
        "id":"30000000-0000-4000-8000-000000000001","bucket_id":"entry-media",
        "object_path":"owner/entry/goal.jpg","original_filename":"goal.jpg",
        "mime_type":"image/jpeg","byte_size":2048,"pixel_width":1200,
        "pixel_height":800,"created_at":"2026-09-03T20:00:00Z"
      }],"total_count":1
    }]
    """
  }
}
