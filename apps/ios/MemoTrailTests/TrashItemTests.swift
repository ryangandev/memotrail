import XCTest

@testable import MemoTrail

final class TrashItemTests: XCTestCase {
  func testEmptyTrashSnapshotPreservesExactTargetsAndRejectsDuplicates() throws {
    let target = EmptyTrashTarget(
      kind: .entry, itemID: UUID(), deletedAt: "2026-09-01T12:00:00.123456Z", revision: 2)
    XCTAssertTrue(EmptyTrashTarget.isValid([target]))
    XCTAssertFalse(EmptyTrashTarget.isValid([target, target]))
    XCTAssertFalse(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(
          kind: .attachment, itemID: UUID(), deletedAt: target.deletedAt, revision: 2)
      ]))
    XCTAssertFalse(
      EmptyTrashTarget.isValid([
        EmptyTrashTarget(kind: .person, itemID: UUID(), deletedAt: "tomorrow", revision: 1)
      ]))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(TrashItemMutationParameters(target: target))) as? [String: Any])
    XCTAssertEqual(object["p_expected_deleted_at"] as? String, target.deletedAt)
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
        kind: .collection, itemID: UUID(), deletedAt: "2026-09-01T12:00:00Z", revision: 1)
    ]
    let result = await EmptyTrashOutcome.run(targets: targets, remove: { _ in }, progress: { _ in })
    XCTAssertTrue(result.complete)
    XCTAssertTrue(result.message.contains("later was not included"))
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

  func testDecodesEveryTrashKindAndPreservesOptimisticTimestamp() throws {
    let items = try decodeItems()

    XCTAssertEqual(items.map(\.kind), [.entry, .attachment, .place])
    XCTAssertEqual(items[0].deletedAt, "2026-09-02T12:34:56.123456+00:00")
    XCTAssertEqual(items[0].revision, 4)
    XCTAssertNil(items[1].revision)
    XCTAssertEqual(items[1].storagePaths, ["21000000/photo.png"])
    XCTAssertEqual(items[0].totalCount, 3)
  }

  func testCompositeIdentityCannotCollideAcrossTables() throws {
    let items = try decodeItems()

    XCTAssertEqual(Set(items.map(\.id)).count, 3)
    XCTAssertTrue(items[0].id.hasPrefix("entry-"))
    XCTAssertTrue(items[1].id.hasPrefix("attachment-"))
    XCTAssertTrue(items[2].id.hasPrefix("place-"))
  }

  func testDisplayMetadataDistinguishesFirstTimesAndRemovesDuplicateDetail() throws {
    let items = try decodeItems()

    XCTAssertEqual(items[0].displayKind, "First Time")
    XCTAssertEqual(items[1].displayKind, "Photo")
    XCTAssertEqual(items[2].displayKind, "Place")
    XCTAssertNil(items[0].displayDetail)
    XCTAssertEqual(items[1].displayDetail, "Photo from First ski trip")
  }

  func testRetentionLabelUsesExactRemainingDuration() throws {
    let item = try decodeItems()[0]
    let referenceDate = try XCTUnwrap(
      TrashTimestamp.date(from: "2026-09-02T12:34:56.123456Z")
    )
    let expiredDate = try XCTUnwrap(TrashTimestamp.date(from: "2026-10-03T12:34:57Z"))

    XCTAssertTrue(item.retentionLabel(referenceDate: referenceDate).hasPrefix("30 days to restore"))
    XCTAssertTrue(item.retentionLabel(referenceDate: expiredDate).hasPrefix("Eligible for cleanup"))
  }

  func testTimestampParserAcceptsPostgresPrecisionAndWholeSeconds() {
    XCTAssertNotNil(TrashTimestamp.date(from: "2026-09-02T12:34:56.123456+00:00"))
    XCTAssertNotNil(TrashTimestamp.date(from: "2026-09-02T12:34:56Z"))
    XCTAssertNil(TrashTimestamp.date(from: "not-a-timestamp"))
  }

  func testPageRequestValidatesSharedDatabaseBounds() throws {
    let request = try TrashPageRequest.validate(offset: 25)

    XCTAssertEqual(request.limit, 25)
    XCTAssertEqual(request.offset, 25)
    XCTAssertThrowsError(try TrashPageRequest.validate(limit: 101))
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
          "entry_type": "first_time",
          "parent_entry_id": null,
          "storage_paths": ["21000000/entry/photo.png"],
          "total_count": 3
        },
        {
          "item_kind": "attachment",
          "item_id": "21000000-0000-4000-8000-000000000001",
          "title": "photo.png",
          "detail": "Photo from First ski trip",
          "deleted_at": "2026-09-02T12:36:56.123456+00:00",
          "expires_at": "2026-10-02T12:36:56.123456+00:00",
          "revision": null,
          "entry_type": "attachment",
          "parent_entry_id": "31000000-0000-4000-8000-000000000001",
          "storage_paths": ["21000000/photo.png"],
          "total_count": 3
        },
        {
          "item_kind": "place",
          "item_id": "21000000-0000-4000-8000-000000000001",
          "title": "Golden Gate Park",
          "detail": "San Francisco, California",
          "deleted_at": "2026-09-02T12:37:56.123456+00:00",
          "expires_at": "2026-10-02T12:37:56.123456+00:00",
          "revision": 3,
          "entry_type": null,
          "parent_entry_id": null,
          "storage_paths": [],
          "total_count": 3
        }
      ]
      """#

    return try JSONDecoder().decode([TrashItem].self, from: Data(json.utf8))
  }
}
