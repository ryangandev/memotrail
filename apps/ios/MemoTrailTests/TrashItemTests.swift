@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

/// Trash rows, shaped like `trash_workspace` in
/// `supabase/migrations/202610180087_entry_date_titles.sql`, and Web `trash.ts`.
final class TrashItemTests: XCTestCase {
  func testEmptyTrashSnapshotPreservesExactTargetsAndRejectsDuplicates() throws {
    let target = EmptyTrashTarget(
      kind: .entry, itemID: UUID(), deletedAt: "2026-09-01T12:00:00.123456Z", revision: 2)
    XCTAssertTrue(EmptyTrashTarget.isValid([target]))
    XCTAssertFalse(EmptyTrashTarget.isValid([target, target]))
    // A photo has no revision, an Entry needs one, and every target needs a real timestamp.
    XCTAssertFalse(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(
          kind: .attachment, itemID: UUID(), deletedAt: target.deletedAt, revision: 2)
      ]))
    XCTAssertTrue(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(
          kind: .attachment, itemID: target.itemID, deletedAt: target.deletedAt, revision: nil),
        target,
      ]))
    XCTAssertFalse(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(kind: .entry, itemID: UUID(), deletedAt: target.deletedAt, revision: nil)
      ]))
    XCTAssertFalse(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(kind: .entry, itemID: UUID(), deletedAt: "tomorrow", revision: 1)
      ]))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(TrashItemMutationParameters(target: target))) as? [String: Any])
    XCTAssertEqual(object["p_expected_deleted_at"] as? String, target.deletedAt)
    XCTAssertEqual(object["p_expected_revision"] as? Int, 2)
  }

  @MainActor func testEmptyTrashStopsAfterUncertainDeletionWithoutTouchingRemainingTargets() async {
    let targets = (0..<3).map { _ in
      EmptyTrashTarget(kind: .entry, itemID: UUID(), deletedAt: "2026-09-01T12:00:00Z", revision: 1)
    }
    var attempted = [UUID]()
    var progress = [Int]()
    let result = await EmptyTrashOutcome.run(
      targets: targets,
      remove: { target in
        attempted.append(target.itemID)
        if attempted.count == 2 { throw URLError(.networkConnectionLost) }
      }, progress: { progress.append($0) })
    XCTAssertEqual(attempted, Array(targets.prefix(2)).map(\.itemID))
    XCTAssertEqual(progress, [1])
    XCTAssertEqual(result, EmptyTrashOutcome(deleted: 1, total: 3))
    XCTAssertFalse(result.complete)
    XCTAssertTrue(result.message.contains("could not be confirmed"))
  }

  @MainActor func testEmptyTrashReportsOnlyConfirmedSnapshotCompletion() async {
    let targets = [
      EmptyTrashTarget(
        kind: .attachment, itemID: UUID(), deletedAt: "2026-09-01T12:00:00Z", revision: nil)
    ]
    let result = await EmptyTrashOutcome.run(targets: targets, remove: { _ in }, progress: { _ in })
    XCTAssertTrue(result.complete)
    XCTAssertTrue(result.message.hasPrefix("1 confirmed item permanently deleted."))
    XCTAssertTrue(result.message.contains("later was not included"))
    XCTAssertTrue(
      EmptyTrashOutcome(deleted: 0, total: 1).message.hasPrefix("0 of 1 item confirmed deleted."))
  }

  func testEmptyTrashSaysWhenPhotoFilesFinishRemovingLater() {
    let removed = EmptyTrashOutcome(deleted: 2, total: 2)
    XCTAssertFalse(removed.message.contains(MediaPurge.pendingMessage))
    let pending = EmptyTrashOutcome(deleted: 2, total: 2, filesRemoved: false)
    XCTAssertEqual(pending.message, "\(removed.message) \(MediaPurge.pendingMessage)")
    XCTAssertEqual(
      MediaPurge.pendingMessage,
      "MemoTrail will finish removing private photo files the next time you open Trash.")
    let object = try? JSONSerialization.jsonObject(
      with: JSONEncoder().encode(MediaPurge.Request(limit: MediaPurge.batchSize)))
    XCTAssertEqual(object as? [String: Int], ["p_limit": 100])
  }

  @MainActor func testRestoreFailuresMatchWeb() {
    XCTAssertEqual(
      TrashController.Notice.restoreFailure(
        PostgrestError(code: "P0001", message: "trash_media_unavailable")),
      .init(
        message:
          "This item's original photos are missing, so it cannot be restored. You can still delete it forever.",
        tone: .error))
    XCTAssertEqual(
      TrashController.Notice.restoreFailure(
        PostgrestError(code: "23505", message: "duplicate key value")),
      .init(message: "MemoTrail could not restore this item. Try again.", tone: .error))
    XCTAssertEqual(
      TrashController.Notice.restoreFailure(URLError(.notConnectedToInternet)),
      .init(message: "MemoTrail could not restore this item. Try again.", tone: .error))
  }

  @MainActor func testCancelledEmptyTrashStartsNoDeletion() async {
    let target = EmptyTrashTarget(
      kind: .entry, itemID: UUID(), deletedAt: "2026-09-01T12:00:00Z", revision: 1)
    var attempts = 0
    let task = Task { @MainActor in
      await EmptyTrashOutcome.run(
        targets: [target], remove: { _ in attempts += 1 }, progress: { _ in })
    }
    task.cancel()
    let result = await task.value
    XCTAssertEqual(attempts, 0)
    XCTAssertEqual(result.deleted, 0)
    XCTAssertFalse(result.complete)
  }

  func testDecodesBothTrashKindsAndPreservesOptimisticTimestamp() throws {
    let items = try decodeItems()

    XCTAssertEqual(items.map(\.kind), [.entry, .attachment, .entry])
    XCTAssertEqual(items[0].deletedAt, "2026-09-02T12:34:56.123456+00:00")
    XCTAssertEqual(items[0].revision, 4)
    XCTAssertNil(items[1].revision)
    XCTAssertEqual(items[1].parentEntryID?.uuidString, "31000000-0000-4000-8000-000000000001")
    XCTAssertEqual(items[1].storagePaths, ["21000000/photo.png"])
    XCTAssertEqual(items[0].totalCount, 3)
    XCTAssertEqual(items[2].totalCount, 3)
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        TrashItem.self,
        from: Data(
          #"{"item_kind":"collection","item_id":"21000000-0000-4000-8000-000000000001","deleted_at":"2026-09-02T12:34:56Z","expires_at":"2026-10-02T12:34:56Z","total_count":1}"#
            .utf8)))
  }

  func testCompositeIdentityCannotCollideAcrossTables() throws {
    let items = try decodeItems()

    XCTAssertEqual(Set(items.map(\.id)).count, 3)
    XCTAssertEqual(items[0].id, "entry-21000000-0000-4000-8000-000000000001")
    XCTAssertEqual(items[1].id, "attachment-21000000-0000-4000-8000-000000000001")
  }

  func testEntriesAreNamedLikeEverywhereElseAndPhotosKeepTheirFileName() throws {
    let items = try decodeItems()

    XCTAssertEqual(items[0].title, "First ski trip")
    XCTAssertEqual(items[0].displayKind, "Entry")
    XCTAssertNil(items[0].displayDetail)
    XCTAssertEqual(items[1].title, "photo.png")
    XCTAssertEqual(items[1].displayKind, "Photo")
    // The photo's Entry is untitled, so it is named by its date in its recorded zone.
    XCTAssertEqual(items[1].displayDetail, "Photo from Tuesday, September 1, 2026")
    XCTAssertEqual(items[2].title, "Living in Lisbon")
    XCTAssertEqual(items[2].displayKind, "Chapter")
    XCTAssertEqual(items[2].displayDetail, "A year by the river.")
  }

  func testRetentionUsesExactRemainingDuration() throws {
    let item = try decodeItems()[0]
    let referenceDate = try XCTUnwrap(EntryTimestamp.date(from: "2026-09-02T12:34:56.123456Z"))
    let expiredDate = try XCTUnwrap(EntryTimestamp.date(from: "2026-10-03T12:34:57Z"))

    let restorable = item.retention(referenceDate: referenceDate, timezone: "UTC")
    XCTAssertEqual(restorable.status, "30 days to restore · through")
    XCTAssertEqual(restorable.date, "Oct 2, 2026")
    let expired = item.retention(referenceDate: expiredDate, timezone: "UTC")
    XCTAssertEqual(expired.status, "Eligible for cleanup since")
    XCTAssertEqual(expired.date, "Oct 2, 2026")
  }

  func testDatesUseTheProfileZoneAndFallBackToUTC() throws {
    let item = try decodeItems()[0]

    XCTAssertEqual(item.deletionDateLabel(timezone: "Asia/Tokyo"), "Sep 2, 2026")
    XCTAssertEqual(item.deletionDateLabel(timezone: "Pacific/Kiritimati"), "Sep 3, 2026")
    XCTAssertEqual(item.deletionDateLabel(timezone: "Not/AZone"), "Sep 2, 2026")
    XCTAssertEqual(TrashItem.displayDate("not-a-timestamp", timezone: "UTC"), "Date unavailable")
  }

  func testDeletionDescriptionsFollowWeb() throws {
    let items = try decodeItems()

    XCTAssertEqual(
      items[0].deletionDescription,
      "The Entry, private photos, relationships, and specialized details will be removed.")
    XCTAssertEqual(
      items[1].deletionDescription,
      "The private photo file and its attachment record will be removed.")
  }

  func testDeleteForeverSaysReviewsGoWithTheEntriesTheyReadOnlyWhenTheyExist() throws {
    let items = try decodeItems()
    let sentence = "Reviews that read these Entries are deleted too."

    XCTAssertEqual(
      items[0].deletionConfirmation(reviewsExist: false),
      "The Entry, private photos, relationships, and specialized details will be removed. This cannot be undone."
    )
    XCTAssertEqual(
      items[0].deletionConfirmation(reviewsExist: true),
      "The Entry, private photos, relationships, and specialized details will be removed. \(sentence) This cannot be undone."
    )
    // A photo is no Entry, so no Review read it.
    XCTAssertEqual(
      items[1].deletionConfirmation(reviewsExist: true),
      "The private photo file and its attachment record will be removed. This cannot be undone.")

    func settings(_ json: String) throws -> ReviewDeletion {
      try JSONDecoder().decode(ReviewDeletion.self, from: Data(json.utf8))
    }
    XCTAssertFalse(
      try settings(
        #"{"reviewsEnabled":true,"reviewCount":0,"pendingSuggestionCount":0,"revision":2}"#
      ).exist)
    XCTAssertTrue(
      try settings(#"{"reviewsEnabled":false,"reviewCount":2,"pendingSuggestionCount":0}"#).exist)
    XCTAssertTrue(
      try settings(#"{"reviewCount":0,"pendingSuggestionCount":1}"#).exist)
    XCTAssertFalse(try settings(#"{"reviewCount":"3","pendingSuggestionCount":null}"#).exist)
  }

  @MainActor func testEmptyTrashSaysWhenThePersonLeftTrash() async {
    let targets = (0..<3).map { _ in
      EmptyTrashTarget(kind: .entry, itemID: UUID(), deletedAt: "2026-09-01T12:00:00Z", revision: 1)
    }
    var attempts = 0
    let task = Task { @MainActor in
      await EmptyTrashOutcome.run(
        targets: targets,
        remove: { _ in
          attempts += 1
          if attempts == 2 { withUnsafeCurrentTask { $0?.cancel() } }
        }, progress: { _ in })
    }
    let result = await task.value

    XCTAssertEqual(result, EmptyTrashOutcome(deleted: 2, total: 3, left: true))
    XCTAssertEqual(
      result.message,
      "2 of 3 items confirmed deleted. Stopped because you left Trash. Review Trash before trying again."
    )
    XCTAssertEqual(
      EmptyTrashOutcome(deleted: 1, total: 3, filesRemoved: false, left: true).message,
      "1 of 3 items confirmed deleted. Stopped because you left Trash. Review Trash before trying again. \(MediaPurge.pendingMessage)"
    )
  }

  func testTimestampParserAcceptsPostgresPrecisionAndWholeSeconds() {
    XCTAssertNotNil(EntryTimestamp.date(from: "2026-09-02T12:34:56.123456+00:00"))
    XCTAssertNotNil(EntryTimestamp.date(from: "2026-09-02T12:34:56Z"))
    XCTAssertNil(EntryTimestamp.date(from: "not-a-timestamp"))
  }

  func testPageRequestValidatesSharedDatabaseBounds() throws {
    let request = try TrashPageRequest.validate(offset: 25)

    XCTAssertEqual(request.limit, 25)
    XCTAssertEqual(request.offset, 25)
    XCTAssertEqual(request.parameters, TrashPageParameters(limit: 25, offset: 25))
    XCTAssertThrowsError(try TrashPageRequest.validate(limit: 101))
    XCTAssertThrowsError(try TrashPageRequest.validate(limit: 0))
    XCTAssertThrowsError(try TrashPageRequest.validate(offset: 10_001))
  }

  func testAttachmentMutationEncodesExplicitNullRevisionAndOriginalTimestamp() throws {
    let attachment = try decodeItems()[1]
    let data = try JSONEncoder().encode(TrashItemMutationParameters(item: attachment))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(object["p_item_kind"] as? String, "attachment")
    XCTAssertEqual(
      object["p_item_id"] as? String,
      "21000000-0000-4000-8000-000000000001"
    )
    XCTAssertEqual(
      object["p_expected_deleted_at"] as? String,
      "2026-09-02T12:36:56.123456+00:00"
    )
    XCTAssertTrue(object.keys.contains("p_expected_revision"))
    XCTAssertTrue(object["p_expected_revision"] is NSNull)
  }

  private func decodeItems() throws -> [TrashItem] {
    let json = #"""
      [
        {
          "item_kind": "entry",
          "item_id": "21000000-0000-4000-8000-000000000001",
          "title": "First ski trip",
          "detail": "First ski trip",
          "deleted_at": "2026-09-02T12:34:56.123456+00:00",
          "expires_at": "2026-10-02T12:34:56.123456+00:00",
          "revision": 4,
          "wiki_item_kind": "entry",
          "wiki_item_subtype": "entry",
          "parent_entry_id": null,
          "storage_paths": ["21000000/entry/photo.png"],
          "entry_title": "First ski trip",
          "occurred_start": "2026-01-10T12:00:00+00:00",
          "occurred_end": null,
          "date_precision": "day",
          "occurred_label": null,
          "occurred_timezone": "UTC",
          "total_count": 3
        },
        {
          "item_kind": "attachment",
          "item_id": "21000000-0000-4000-8000-000000000001",
          "title": "photo.png",
          "detail": "Photo from Untitled Entry",
          "deleted_at": "2026-09-02T12:36:56.123456+00:00",
          "expires_at": "2026-10-02T12:36:56.123456+00:00",
          "revision": null,
          "wiki_item_kind": null,
          "wiki_item_subtype": null,
          "parent_entry_id": "31000000-0000-4000-8000-000000000001",
          "storage_paths": ["21000000/photo.png"],
          "entry_title": "",
          "occurred_start": "2026-09-02T03:00:00+00:00",
          "occurred_end": null,
          "date_precision": "day",
          "occurred_label": null,
          "occurred_timezone": "America/Los_Angeles",
          "total_count": 3
        },
        {
          "item_kind": "entry",
          "item_id": "41000000-0000-4000-8000-000000000001",
          "title": "Living in Lisbon",
          "detail": "A year by the river.",
          "deleted_at": "2026-09-02T12:37:56+00:00",
          "expires_at": "2026-10-02T12:37:56+00:00",
          "revision": 3,
          "wiki_item_kind": "entry",
          "wiki_item_subtype": "chapter",
          "parent_entry_id": null,
          "storage_paths": [],
          "entry_title": "Living in Lisbon",
          "occurred_start": "2021-03-01T12:00:00+00:00",
          "occurred_end": "2022-02-28T12:00:00+00:00",
          "date_precision": "month",
          "occurred_label": null,
          "occurred_timezone": "Europe/Lisbon",
          "total_count": "3"
        }
      ]
      """#

    return try JSONDecoder().decode([TrashItem].self, from: Data(json.utf8))
  }
}
