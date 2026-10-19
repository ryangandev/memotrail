import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// Settings and Trash against the local stack. Carried over for P8 (Settings, Trash, and
// Export), which owns and verifies them.
extension NativeContractTests {
  func testSettingsSaveAndClearTheProfileLikeWeb() async throws {
    let (client, ownerID) = try await client()
    let settings = SettingsController(client: client, ownerID: ownerID)
    await settings.load()
    XCTAssertNil(settings.loadErrorMessage)
    XCTAssertNotNil(settings.profile)

    let named = await settings.savePreferredName("  River  Gan ")
    XCTAssertEqual(named, .init(isSaved: true, message: "Preferred name saved."))
    let born = await settings.saveBirthDate("1994-04-18")
    XCTAssertEqual(born, .init(isSaved: true, message: "Birth date saved."))
    let zoned = await settings.saveTimezone("Asia/Tokyo")
    XCTAssertEqual(zoned, .init(isSaved: true, message: "Default time zone saved."))
    let future = await settings.saveBirthDate("2999-01-01")
    XCTAssertFalse(future.isSaved)

    let reloaded = SettingsController(client: client, ownerID: ownerID)
    await reloaded.load()
    XCTAssertEqual(
      reloaded.profile,
      ProfileSettings(preferredName: "River Gan", birthDate: "1994-04-18", timezone: "Asia/Tokyo"))

    let cleared = await reloaded.savePreferredName("")
    XCTAssertEqual(cleared, .init(isSaved: true, message: "Preferred name cleared."))
    let removed = await reloaded.saveBirthDate("")
    XCTAssertEqual(removed, .init(isSaved: true, message: "Birth date removed."))
    await settings.load()
    XCTAssertNil(settings.profile?.preferredName)
    XCTAssertNil(settings.profile?.birthDate)
  }

  func testTrashKeepsARestoreWhenAnEarlierRefreshReturnsLast() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let saved = try await savedEntry("Native refresh Trash", client: client, ownerID: ownerID)
    let entryID = saved.entryID
    try await EntryAPI(client: client, ownerID: ownerID).moveToTrash(
      id: entryID, revision: saved.revision)
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    let trashed = try XCTUnwrap(trash.items.first { $0.itemID == entryID })

    // Pull to refresh reads Trash before the restore, but its response arrives last.
    HeldResponseProtocol.gate.holdNextResponse(toRPC: "trash_workspace")
    defer { HeldResponseProtocol.gate.releaseHeldResponse() }
    let refresh = Task { await trash.load() }
    try await waitForHeldResponse()

    let restored = await trash.restore(trashed)
    XCTAssertEqual(restored, TrashController.Notice(message: "Item restored.", tone: .success))
    XCTAssertFalse(trash.items.contains { $0.itemID == entryID })
    HeldResponseProtocol.gate.releaseHeldResponse()
    await refresh.value
    XCTAssertFalse(trash.items.contains { $0.itemID == entryID })
    XCTAssertFalse(trash.isLoading)
    XCTAssertNil(trash.loadErrorMessage)
  }

  // Delete forever removes the record first; a file removal it could not finish is finished
  // the next time Trash opens, and nothing deleted can be restored in between.
  func testTrashDeletesTheRecordBeforeItsPhotoFilesAndFinishesAnInterruptedRemoval() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let (entryID, path) = try await trashedPhotoEntry(
      "Native Delete Forever Photo", client: client, ownerID: ownerID)
    let folder = (path as NSString).deletingLastPathComponent
    let file = (path as NSString).lastPathComponent
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    let item = try XCTUnwrap(trash.items.first { $0.itemID == entryID })
    let parameters = TrashItemMutationParameters(item: item)

    // Storage keeps a restorable original even when a client asks to remove it early.
    let early = try await client.storage.from("entry-media").remove(paths: [path])
    XCTAssertTrue(early.isEmpty)
    let kept = try await storedNames(in: folder, client: client)
    XCTAssertTrue(kept.contains(file))

    HeldResponseProtocol.gate.failNextStorageRemoval()
    defer { HeldResponseProtocol.gate.failNextStorageRemoval(false) }
    let deleted = await trash.deleteForever(item)
    XCTAssertEqual(
      deleted,
      .init(message: "Item permanently deleted. \(MediaPurge.pendingMessage)", tone: .success))
    XCTAssertFalse(trash.items.contains { $0.itemID == entryID })
    let restored: [RestoredTrashItem] = try await client.rpc(
      "restore_trash_item", params: parameters
    ).execute().value
    XCTAssertEqual(restored, [])
    let recorded = try await storedNames(in: folder, client: client)
    XCTAssertTrue(recorded.contains(file))
    let pending: [TrashStoragePath] = try await client.rpc(
      "pending_media_purge_paths", params: MediaPurge.Request(limit: MediaPurge.batchSize)
    ).execute().value
    XCTAssertTrue(pending.contains(TrashStoragePath(objectPath: path)))

    let finished = await trash.finishPendingMediaRemoval()
    XCTAssertTrue(finished)
    let removed = try await storedNames(in: folder, client: client)
    XCTAssertFalse(removed.contains(file))
    let finishedAgain = await trash.finishPendingMediaRemoval()
    XCTAssertTrue(finishedAgain)
  }

  func testEmptyTrashRemovesPhotoFilesOnceAfterItsRecords() async throws {
    let (client, ownerID) = try await client()
    let (entryID, path) = try await trashedPhotoEntry(
      "Native Empty Trash Photo", client: client, ownerID: ownerID)
    let folder = (path as NSString).deletingLastPathComponent
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    let prepared = await trash.prepareEmptyTrash()
    XCTAssertNil(prepared)
    XCTAssertTrue(trash.emptySnapshot?.contains { $0.itemID == entryID } == true)
    let emptied = await trash.emptyTrash()
    let notice = try XCTUnwrap(emptied)
    XCTAssertEqual(notice.tone, .success, notice.message)
    XCTAssertTrue(
      notice.message.hasSuffix("Anything added to Trash later was not included."), notice.message)
    let remaining = try await storedNames(in: folder, client: client)
    XCTAssertFalse(remaining.contains((path as NSString).lastPathComponent))
    let pending: [TrashStoragePath] = try await client.rpc(
      "pending_media_purge_paths", params: MediaPurge.Request(limit: MediaPurge.batchSize)
    ).execute().value
    XCTAssertEqual(pending, [])
  }
}
