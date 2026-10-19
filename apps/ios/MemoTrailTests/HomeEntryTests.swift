import SwiftUI
import XCTest

@testable import MemoTrail

/// The Dashboard's `home_workspace` and `home_resurfaced_memory` rows, shaped like
/// `supabase/migrations/202610190016_chapter_dashboard.sql`, and the app navigator.
final class HomeEntryTests: XCTestCase {
  func testSnapshotDecodesCountsRecentEntriesNowItemsAndPrivateAttachmentMetadata() throws {
    let snapshot = try decodeSnapshot()

    XCTAssertEqual(snapshot.snapshotDate, "2026-09-03")
    XCTAssertEqual(snapshot.profileDisplayName, "Ryan Home")
    XCTAssertEqual(snapshot.entryCount, 4)
    XCTAssertEqual(snapshot.firstTimeCount, 1)
    XCTAssertEqual(snapshot.tagCount, 3)
    XCTAssertEqual(snapshot.nowCount, 1)
    let entry = try XCTUnwrap(snapshot.recentEntries.first)
    XCTAssertEqual(entry.tagNames, ["curiosity"])
    XCTAssertEqual(entry.coverAttachment?.bucketID, "entry-media")
    XCTAssertEqual(entry.coverAttachment?.byteSize, 2048)
    XCTAssertNil(entry.coverAttachment?.signedURL)
    let now = try XCTUnwrap(snapshot.nowItems.first)
    XCTAssertEqual(now.displayTitle, "Living in California")
    XCTAssertTrue(now.isFirstTime)
  }

  func testCountsMayArriveAsStringsButMustBeWholeAndNonNegative() throws {
    XCTAssertEqual(try decodeSnapshot(entryCount: "12").entryCount, 12)
    XCTAssertThrowsError(try decodeSnapshot(entryCount: -1))
    XCTAssertThrowsError(try decodeSnapshot(entryCount: "many"))
  }

  func testRecentEntryPresentsWebIdentityDateAndTitle() throws {
    let entry = try XCTUnwrap(decodeSnapshot().recentEntries.first)

    XCTAssertEqual(entry.identityLabel, "Entry")
    XCTAssertEqual(entry.occurrence.displayLabel, "Sep 3, 2026")
    XCTAssertEqual(entry.displayTitle, "Why clear aligners move teeth")

    let chapter = try XCTUnwrap(
      decodeSnapshot(entryTitle: "  ", entrySubtype: "chapter").recentEntries.first)
    XCTAssertEqual(chapter.identityLabel, "Chapter")
    XCTAssertEqual(chapter.displayTitle, "Thursday, September 3, 2026")
  }

  func testNowItemPresentsAnOngoingSpanInItsRecordedZone() throws {
    let now = try XCTUnwrap(decodeSnapshot().nowItems.first)

    XCTAssertEqual(now.occurrence.timezone, "America/Los_Angeles")
    XCTAssertEqual(now.occurrence.spanLabel, "Since 2025")
    let untitled = try XCTUnwrap(decodeSnapshot(nowTitle: NSNull()).nowItems.first)
    XCTAssertEqual(untitled.displayTitle, "2025")
  }

  func testHumanLabelsTakePriorityOverDates() throws {
    let snapshot = try decodeSnapshot(
      entryOccurredLabel: "The first warm weekend",
      nowOccurredLabel: "My California chapter"
    )

    XCTAssertEqual(
      snapshot.recentEntries.first?.occurrence.displayLabel, "The first warm weekend")
    XCTAssertEqual(snapshot.nowItems.first?.occurrence.spanLabel, "My California chapter")
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

    XCTAssertEqual(Set(object.keys), ["p_local_date", "p_timezone", "p_recent_limit"])
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

    XCTAssertEqual(Set(object.keys), ["p_local_date", "p_timezone"])
    XCTAssertEqual(object["p_local_date"] as? String, "1970-01-01")
    XCTAssertEqual(object["p_timezone"] as? String, "GMT")
  }

  func testOnThisDayMemoryDecodesCompleteEntryContext() throws {
    let memory = try decodeMemory()

    XCTAssertEqual(memory.kind, .onThisDay)
    XCTAssertEqual(memory.yearsAgo, 1)
    XCTAssertEqual(memory.entry.displayTitle, "First coastal train ride")
    XCTAssertEqual(memory.entry.identityLabel, "Entry")
    XCTAssertEqual(memory.entry.tagNames, ["coast"])
    XCTAssertEqual(memory.entry.coverAttachment?.objectPath, "owner/entry/coast.png")
  }

  func testArchiveMemoryDecodesWithoutAnniversary() throws {
    let memory = try decodeMemory(kind: "from_your_archive", yearsAgo: nil)

    XCTAssertEqual(memory.kind, .fromArchive)
    XCTAssertNil(memory.yearsAgo)
  }

  func testMemoryRejectsInvalidSelectionCombinations() throws {
    XCTAssertThrowsError(try decodeMemory(yearsAgo: 0))
    XCTAssertThrowsError(try decodeMemory(kind: "from_your_archive", yearsAgo: 1))
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
    XCTAssertEqual(HomePresentation.firstName("   "), "there")
  }

  @MainActor
  func testNavigatorOpensTabsRoutesLibraryFiltersAndCapture() {
    let navigator = AppNavigator()
    navigator.show(.tags)
    XCTAssertEqual(navigator.selectedTab, .more)
    XCTAssertEqual(navigator.morePath, NavigationPath([WorkspaceRoute.tags]))
    navigator.openLibrary(tag: "coast")
    XCTAssertEqual(navigator.selectedTab, .library)
    XCTAssertEqual(navigator.libraryFilterRequest, .tag("coast"))
    navigator.openLibrary(record: .chapter)
    XCTAssertEqual(navigator.libraryFilterRequest, .record(.chapter))
    navigator.show(.timeline)
    XCTAssertEqual(navigator.selectedTab, .timeline)
    navigator.searchLibrary()
    XCTAssertTrue(navigator.librarySearchRequested)
    XCTAssertEqual(navigator.selectedTab, .library)
    XCTAssertFalse(navigator.isShowingQuickCapture)
    navigator.startCapture()
    XCTAssertTrue(navigator.isShowingQuickCapture)
    navigator.showPendingCaptures()
    XCTAssertTrue(navigator.isShowingPendingCaptures)
    let revision = navigator.entriesRevision
    navigator.entriesChanged()
    XCTAssertEqual(navigator.entriesRevision, revision + 1)
  }

  func testRootTabsAreTheFourNativeDestinations() {
    XCTAssertEqual(RootTabDestination.allCases, [.home, .timeline, .library, .more])
    XCTAssertEqual(
      RootTabDestination.allCases.map(\.title), ["Dashboard", "Timeline", "Library", "More"])
    XCTAssertFalse(RootTabDestination.allCases.map(\.systemImage).contains(where: \.isEmpty))
  }

  func testMoreGroupsMatchWebsMobileMenu() {
    XCTAssertEqual(
      WorkspaceRoute.groups.map { $0.title }, ["Focused views", "Organize", "Trash and settings"])
    XCTAssertEqual(WorkspaceRoute.groups.flatMap { $0.routes }, WorkspaceRoute.allCases)
    XCTAssertEqual(
      WorkspaceRoute.allCases.map(\.title), ["First Times", "Tags", "Trash", "Settings"])
  }

  private var decoder: JSONDecoder { JSONDecoder() }

  private func decodeSnapshot(
    entryCount: Any = 4,
    entryTitle: String = "Why clear aligners move teeth",
    entrySubtype: String = "entry",
    entryOccurredLabel: String? = nil,
    nowTitle: Any = "Living in California",
    nowOccurredLabel: String? = nil
  ) throws -> HomeSnapshot {
    let object: [[String: Any]] = [
      [
        "snapshot_date": "2026-09-03",
        "profile_display_name": "Ryan Home",
        "entry_count": entryCount,
        "first_time_count": 1,
        "tag_count": 3,
        "now_count": 1,
        "recent_entries": [
          [
            "entry_id": "10000000-0000-4000-8000-000000000001",
            "title": entryTitle,
            "body":
              "A steady, gentle force encourages bone to remodel around a tooth over time.",
            "item_kind": "entry",
            "item_subtype": entrySubtype,
            "occurred_start": "2026-09-03T19:00:00+00:00",
            "occurred_end": NSNull(),
            "date_precision": "day",
            "occurred_label": entryOccurredLabel.map { $0 as Any } ?? NSNull(),
            "occurred_timezone": "America/Los_Angeles",
            "revision": 1,
            "created_at": "2026-09-03T02:00:00.123456+00:00",
            "updated_at": "2026-09-03T02:00:00.123456+00:00",
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
        "now_items": [
          [
            "entry_id": "30000000-0000-4000-8000-000000000001",
            "title": nowTitle,
            "is_first_time": true,
            "occurred_start": "2025-01-01T08:00:00+00:00",
            "occurred_end": NSNull(),
            "date_precision": "year",
            "occurred_label": nowOccurredLabel.map { $0 as Any } ?? NSNull(),
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
    occurredStart: String? = "2025-09-03T19:00:00+00:00"
  ) throws -> HomeResurfacedMemory {
    let object: [[String: Any]] = [
      [
        "resurfacing_kind": kind,
        "years_ago": yearsAgo.map { $0 as Any } ?? NSNull(),
        "entry_id": "50000000-0000-4000-8000-000000000001",
        "title": "First coastal train ride",
        "body": "A quiet afternoon on the coast.",
        "item_kind": "entry",
        "item_subtype": "entry",
        "occurred_start": occurredStart.map { $0 as Any } ?? NSNull(),
        "occurred_end": NSNull(),
        "date_precision": "day",
        "occurred_label": NSNull(),
        "occurred_timezone": "America/Los_Angeles",
        "revision": 1,
        "created_at": "2025-09-03T19:00:00+00:00",
        "updated_at": "2025-09-03T19:00:00+00:00",
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
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try XCTUnwrap(decoder.decode([HomeResurfacedMemory].self, from: data).first)
  }
}
