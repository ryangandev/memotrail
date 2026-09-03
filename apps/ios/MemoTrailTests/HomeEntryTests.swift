import XCTest

@testable import MemoTrail

final class HomeEntryTests: XCTestCase {
  func testSnapshotDecodesCountsStagesEntriesAndPrivateAttachmentMetadata() throws {
    let snapshot = try decodeSnapshot()

    XCTAssertEqual(snapshot.snapshotDate, "2026-09-03")
    XCTAssertEqual(snapshot.profileDisplayName, "Ryan Home")
    XCTAssertEqual(snapshot.inboxCount, 2)
    XCTAssertEqual(snapshot.entryCount, 4)
    XCTAssertEqual(snapshot.firstTimeCount, 1)
    XCTAssertEqual(snapshot.collectionCount, 1)
    XCTAssertEqual(snapshot.completedHabitCount, 1)
    XCTAssertEqual(snapshot.currentStages.first?.title, "Living in California")
    XCTAssertEqual(snapshot.recentEntries.first?.collectionNames, ["Things I Learned"])
    XCTAssertEqual(snapshot.recentEntries.first?.tagNames, ["curiosity"])
    XCTAssertEqual(snapshot.recentEntries.first?.coverAttachment?.bucketID, "entry-media")
    XCTAssertNil(snapshot.recentEntries.first?.coverAttachment?.signedURL)
  }

  func testRecentEntryPresentsTypeDateExcerptAndOrganization() throws {
    let entry = try XCTUnwrap(decodeSnapshot().recentEntries.first)

    XCTAssertEqual(entry.displayType, "Entry")
    XCTAssertEqual(entry.displayDate, "Sep 3, 2026")
    XCTAssertEqual(
      entry.displayExcerpt,
      "A steady, gentle force encourages bone to remodel around a tooth over time."
    )
  }

  func testStagePresentsOpenRangeInOccurrenceTimezone() throws {
    let stage = try XCTUnwrap(decodeSnapshot().currentStages.first)

    XCTAssertEqual(stage.displayDate, "2025 - Present")
  }

  func testHumanLabelsTakePriorityOverDates() throws {
    let snapshot = try decodeSnapshot(
      entryOccurredLabel: "The first warm weekend",
      stageOccurredLabel: "My California chapter"
    )

    XCTAssertEqual(snapshot.recentEntries.first?.displayDate, "The first warm weekend")
    XCTAssertEqual(snapshot.currentStages.first?.displayDate, "My California chapter")
  }

  func testRequestUsesTheSelectedTimezoneCalendarDate() throws {
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-03T01:00:00Z"))
    let losAngeles = try HomeWorkspaceRequest(
      date: date,
      timezone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    )
    let tokyo = try HomeWorkspaceRequest(
      date: date,
      timezone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    )

    XCTAssertEqual(losAngeles.localDate, "2026-09-02")
    XCTAssertEqual(tokyo.localDate, "2026-09-03")
  }

  func testRequestRejectsInvalidTimezoneAndLimits() throws {
    let date = Date(timeIntervalSince1970: 0)

    XCTAssertThrowsError(
      try HomeWorkspaceRequest(date: date, timezoneIdentifier: "Not/A-Timezone")
    ) { error in
      XCTAssertEqual(error as? HomeWorkspaceError, .invalidTimezone)
    }
    XCTAssertThrowsError(
      try HomeWorkspaceRequest(date: date, timezone: .gmt, recentLimit: 11)
    ) { error in
      XCTAssertEqual(error as? HomeWorkspaceError, .invalidRecentLimit)
    }
  }

  func testRequestParametersUseSharedRPCNames() throws {
    let request = try HomeWorkspaceRequest(
      date: Date(timeIntervalSince1970: 0),
      timezone: .gmt,
      recentLimit: 10
    )
    let data = try JSONEncoder().encode(request.parameters)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(object["p_local_date"] as? String, "1970-01-01")
    XCTAssertEqual(object["p_timezone"] as? String, "GMT")
    XCTAssertEqual(object["p_recent_limit"] as? Int, 10)
  }

  func testPresentationUsesLocalGreetingAndFirstName() throws {
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-03T15:00:00Z"))
    let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))

    XCTAssertEqual(HomePresentation.greeting(at: date, timezone: losAngeles), "Good morning")
    XCTAssertEqual(HomePresentation.greeting(at: date, timezone: london), "Good afternoon")
    XCTAssertEqual(HomePresentation.firstName("  Ryan Gan  "), "Ryan")
    XCTAssertEqual(HomePresentation.firstName("   "), "MemoTrail")
  }

  func testHabitProgressExplainsDueSkippedAndEmptyStates() throws {
    let snapshot = try decodeSnapshot()

    XCTAssertEqual(snapshot.habitProgressLabel, "1 of 1 due")
  }

  func testRootTabsMatchTheFiveDestinationProductContract() {
    XCTAssertEqual(
      RootTabDestination.allCases,
      [.home, .inbox, .timeline, .habits, .library]
    )
    XCTAssertEqual(
      RootTabDestination.allCases.map(\.title),
      [
        "Home", "Inbox", "Timeline", "Habits", "Library",
      ])
    XCTAssertFalse(RootTabDestination.allCases.map(\.systemImage).contains(where: \.isEmpty))
    XCTAssertEqual(
      RootTabDestination.allCases.filter(\.usesGlobalCaptureButton),
      [.timeline, .habits, .library]
    )
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func decodeSnapshot(
    entryOccurredLabel: String? = nil,
    stageOccurredLabel: String? = nil
  ) throws -> HomeSnapshot {
    let object: [[String: Any]] = [
      [
        "snapshot_date": "2026-09-03",
        "profile_display_name": "Ryan Home",
        "inbox_count": 2,
        "entry_count": 4,
        "first_time_count": 1,
        "collection_count": 1,
        "active_habit_count": 1,
        "due_habit_count": 1,
        "completed_habit_count": 1,
        "skipped_habit_count": 0,
        "current_stage_count": 1,
        "recent_entries": [
          [
            "entry_id": "10000000-0000-4000-8000-000000000001",
            "title": "Why clear aligners move teeth",
            "body":
              "A steady, gentle force encourages bone to remodel around a tooth over time.",
            "entry_type": "standard",
            "inbox_status": "unreviewed",
            "occurred_start": "2026-09-03T19:00:00Z",
            "occurred_end": NSNull(),
            "date_precision": "day",
            "occurred_label": entryOccurredLabel.map { $0 as Any } ?? NSNull(),
            "occurred_timezone": "America/Los_Angeles",
            "revision": 1,
            "created_at": "2026-09-03T02:00:00Z",
            "updated_at": "2026-09-03T02:00:00Z",
            "collection_names": ["Things I Learned"],
            "tag_names": ["curiosity"],
            "attachments": [
              [
                "attachment_id": "20000000-0000-4000-8000-000000000001",
                "bucket_id": "entry-media",
                "object_path": "owner/entry/photo.png",
                "original_filename": "photo.png",
                "mime_type": "image/png",
                "byte_size": 2048,
                "pixel_width": 1200,
                "pixel_height": 800,
              ]
            ],
          ]
        ],
        "current_stages": [
          [
            "entry_id": "30000000-0000-4000-8000-000000000001",
            "title": "Living in California",
            "body": "A chapter out west.",
            "track_id": "40000000-0000-4000-8000-000000000001",
            "track_name": "Places",
            "occurred_start": "2025-01-01T08:00:00Z",
            "occurred_end": NSNull(),
            "date_precision": "year",
            "occurred_label": stageOccurredLabel.map { $0 as Any } ?? NSNull(),
            "occurred_timezone": "America/Los_Angeles",
          ]
        ],
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try XCTUnwrap(decoder.decode([HomeSnapshot].self, from: data).first)
  }
}
