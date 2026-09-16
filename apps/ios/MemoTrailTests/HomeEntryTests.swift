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

  func testResurfacingParametersUseSharedRPCNames() throws {
    let request = try HomeWorkspaceRequest(
      date: Date(timeIntervalSince1970: 0),
      timezone: .gmt
    )
    let data = try JSONEncoder().encode(request.resurfacingParameters)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(object["p_local_date"] as? String, "1970-01-01")
    XCTAssertEqual(object["p_timezone"] as? String, "GMT")
    XCTAssertNil(object["p_recent_limit"])
  }

  func testOnThisDayMemoryDecodesCompleteEntryContext() throws {
    let memory = try decodeMemory()

    XCTAssertEqual(memory.kind, .onThisDay)
    XCTAssertEqual(memory.yearsAgo, 1)
    XCTAssertEqual(memory.contextLabel, "On this day, 1 year ago")
    XCTAssertEqual(memory.entry.title, "First coastal train ride")
    XCTAssertEqual(memory.entry.displayType, "First Time")
    XCTAssertEqual(memory.entry.collectionNames, ["Journeys"])
    XCTAssertEqual(memory.entry.tagNames, ["coast"])
    XCTAssertEqual(memory.entry.coverAttachment?.objectPath, "owner/entry/coast.png")
  }

  func testArchiveMemoryUsesQuietFallbackContext() throws {
    let memory = try decodeMemory(kind: "from_your_archive", yearsAgo: nil)

    XCTAssertEqual(memory.kind, .fromArchive)
    XCTAssertNil(memory.yearsAgo)
    XCTAssertEqual(memory.contextLabel, "A quiet note from your archive")
  }

  func testMemoryRejectsInvalidSelectionCombinations() throws {
    XCTAssertThrowsError(try decodeMemory(yearsAgo: 0))
    XCTAssertThrowsError(try decodeMemory(kind: "from_your_archive", yearsAgo: 1))
    XCTAssertThrowsError(try decodeMemory(inboxStatus: "unreviewed"))
    XCTAssertThrowsError(try decodeMemory(occurredStart: nil))
    XCTAssertThrowsError(try decodeMemory(kind: "unsupported"))
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

  func testRootTabsMatchTheFourDestinationProductContract() {
    XCTAssertEqual(
      RootTabDestination.allCases,
      [.home, .inbox, .timeline, .library]
    )
    XCTAssertEqual(
      RootTabDestination.allCases.map(\.title),
      [
        "Home", "Inbox", "Timeline", "Library",
      ])
    XCTAssertFalse(RootTabDestination.allCases.map(\.systemImage).contains(where: \.isEmpty))
    XCTAssertEqual(
      RootTabDestination.allCases.filter(\.usesGlobalCaptureButton),
      [.timeline, .library]
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
        "current_stage_count": 1,
        "recent_entries": [
          [
            "entry_id": "10000000-0000-4000-8000-000000000001",
            "title": "Why clear aligners move teeth",
            "body":
              "A steady, gentle force encourages bone to remodel around a tooth over time.",
            "item_kind": "writing",
            "item_subtype": "note",
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

  private func decodeMemory(
    kind: String = "on_this_day",
    yearsAgo: Int? = 1,
    inboxStatus: String = "organized",
    occurredStart: String? = "2025-09-03T19:00:00Z"
  ) throws -> HomeResurfacedMemory {
    let object: [[String: Any]] = [
      [
        "entry_id": "50000000-0000-4000-8000-000000000001",
        "title": "First coastal train ride",
        "body": "A quiet afternoon on the coast.",
        "item_kind": "event",
        "item_subtype": "first_time",
        "inbox_status": inboxStatus,
        "occurred_start": occurredStart.map { $0 as Any } ?? NSNull(),
        "occurred_end": NSNull(),
        "date_precision": "day",
        "occurred_label": NSNull(),
        "occurred_timezone": "America/Los_Angeles",
        "revision": 1,
        "created_at": "2025-09-03T19:00:00Z",
        "updated_at": "2025-09-03T19:00:00Z",
        "collection_names": ["Journeys"],
        "tag_names": ["coast"],
        "attachments": [
          [
            "attachment_id": "60000000-0000-4000-8000-000000000001",
            "bucket_id": "entry-media",
            "object_path": "owner/entry/coast.png",
            "original_filename": "coast.png",
            "mime_type": "image/png",
            "byte_size": 2048,
            "pixel_width": 1200,
            "pixel_height": 800,
          ]
        ],
        "resurfacing_kind": kind,
        "years_ago": yearsAgo.map { $0 as Any } ?? NSNull(),
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    let rows = try decoder.decode([HomeResurfacedMemory].self, from: data)
    guard let memory = rows.first else {
      throw DecodingError.valueNotFound(
        HomeResurfacedMemory.self,
        .init(codingPath: [], debugDescription: "Expected one memory fixture.")
      )
    }
    return memory
  }
}
