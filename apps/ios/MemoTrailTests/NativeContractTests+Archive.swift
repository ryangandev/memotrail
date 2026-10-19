import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// Tags, Settings, and Trash against the local stack.
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

  func testTrashShowsDatesInTheProfileZoneAndKnowsWhetherReviewsExist() async throws {
    let (client, ownerID) = try await client()
    let settings = SettingsController(client: client, ownerID: ownerID)
    let saved = await settings.saveTimezone("Asia/Tokyo")
    XCTAssertTrue(saved.isSaved)
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    XCTAssertEqual(trash.timezone, "Asia/Tokyo")
    XCTAssertNil(trash.loadErrorMessage)
    // A new account has no Reviews or Chapter suggestions for Delete forever to mention.
    XCTAssertFalse(trash.reviewsExist)
    let restored = await settings.saveTimezone("UTC")
    XCTAssertTrue(restored.isSaved)
  }

  func testTagsRenameMergeAndDeleteOnlyUnusedTags() async throws {
    let (client, ownerID) = try await client()
    let marker = UUID().uuidString.prefix(8).lowercased()
    let actions = OrganizationActions(client: client, ownerID: ownerID)
    let api = EntryAPI(client: client, ownerID: ownerID)
    let taken = "This name already exists. Choose a different name; nothing was merged or overwritten."
    func saveEntry(_ body: String, tags: [String]) async throws {
      _ = try await api.save(
        SaveEntryParameters(
          entryID: UUID(), expectedRevision: nil, title: nil, body: body, richText: nil,
          occurrence: EntryOccurrence(precision: .unknown, timezone: "UTC"), tagNames: tags,
          location: nil, marks: .none))
    }
    func tag(_ name: String) async throws -> TagItem {
      let matches = try await actions.load(query: name)
      return try XCTUnwrap(matches.first { $0.name == name }, name)
    }

    // Two used tags come from Entries; a third is created on its own and starts unused.
    let renaming = "renaming \(marker)"
    let keeping = "keeping \(marker)"
    let spare = "spare \(marker)"
    for index in 1...6 { try await saveEntry("Keep \(index) \(marker)", tags: [keeping]) }
    try await saveEntry("Rename me \(marker)", tags: [renaming])
    let created = await actions.save(TagSaveRequest(name: spare, id: nil, expectedRevision: nil))
    XCTAssertNil(created)
    let invalid = await actions.save(TagSaveRequest(name: "  ", id: nil, expectedRevision: nil))
    XCTAssertEqual(invalid, TagSaveRequest.invalidMessage)
    let duplicate = await actions.save(TagSaveRequest(name: spare, id: nil, expectedRevision: nil))
    XCTAssertEqual(duplicate, taken)

    // Rename keeps the assignments; a stale revision and a taken name change nothing.
    let source = try await tag(renaming)
    XCTAssertEqual(source.entryCount, 1)
    let renamed = "renamed \(marker)"
    let clash = await actions.save(
      TagSaveRequest(name: keeping, id: source.id, expectedRevision: source.revision))
    XCTAssertEqual(clash, taken)
    let renameResult = await actions.save(
      TagSaveRequest(name: renamed, id: source.id, expectedRevision: source.revision))
    XCTAssertNil(renameResult)
    let stale = await actions.save(
      TagSaveRequest(name: "stale \(marker)", id: source.id, expectedRevision: source.revision))
    XCTAssertEqual(stale, "This tag changed on another device. Refresh before editing again.")
    let afterRename = try await tag(renamed)
    XCTAssertEqual(afterRename.id, source.id)
    XCTAssertEqual(afterRename.entryCount, 1)

    // The tag editor lists up to five of a tag's Entries.
    guard case .success(let previews) = await actions.tagEntryPreviews(keeping) else {
      return XCTFail("The first Entries using a tag should load.")
    }
    XCTAssertEqual(previews.count, 5)
    XCTAssertTrue(previews.allSatisfy { $0.tagNames.contains(keeping) })

    // Merging moves every assignment to the destination and removes the source.
    let destination = try await tag(keeping)
    XCTAssertEqual(destination.entryCount, 6)
    let intoItself = await actions.mergeTags(destination, into: destination)
    XCTAssertEqual(intoItself, "Choose a different destination tag.")
    let merged = await actions.mergeTags(afterRename, into: destination)
    XCTAssertNil(merged)
    let afterMerge = try await tag(keeping)
    XCTAssertEqual(afterMerge.entryCount, 7)
    let removed = try await actions.load(query: renamed)
    XCTAssertTrue(removed.isEmpty)
    let again = await actions.mergeTags(afterRename, into: destination)
    XCTAssertEqual(again, "One of these tags changed on another device. Refresh before merging.")

    // Only an unused tag can be deleted.
    let refused = await actions.deleteUnusedTag(afterMerge)
    XCTAssertEqual(
      refused,
      "This tag is still used by an Entry or changed elsewhere. Merge it or remove it from those Entries first."
    )
    let stillUsed = try await tag(keeping)
    XCTAssertEqual(stillUsed.entryCount, 7)
    let unused = try await tag(spare)
    XCTAssertEqual(unused.entryCount, 0)
    let deleted = await actions.deleteUnusedTag(unused)
    XCTAssertNil(deleted)
    let gone = try await actions.load(query: spare)
    XCTAssertTrue(gone.isEmpty)
  }
}
