import Foundation
@preconcurrency import Supabase
import UIKit
import XCTest

@testable import MemoTrail

// Quick Capture against the local stack: the offline queue, refusals, and photo uploads.
// Carried over from the Inbox contracts for P2 (Capture), which owns and verifies them.
extension NativeContractTests {
  #if DEBUG
    func testOfflineCaptureIsConfirmedOnceAndAnnouncedAgainOnlyWhenItSyncs() async throws {
      let (client, ownerID) = try await client(session: NativeReviewNetwork.session())
      defer { NativeReviewNetwork.isOffline = false }
      let suiteName = "NativeContractTests.\(UUID().uuidString)"
      addTeardownBlock {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
      }
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
      let controller = CaptureController(
        client: client, ownerID: ownerID, queueStore: CaptureQueueStore(defaults: defaults))
      // Let the connectivity monitor's first update pass, so each save starts its own sync.
      try await Task.sleep(for: .milliseconds(500))
      let center = MTToastCenter.shared

      // Without a connection the capture stays on this iPhone, confirmed by one toast rather
      // than a problem in the composer.
      NativeReviewNetwork.isOffline = true
      let note = "Offline capture \(UUID().uuidString)"
      var shown = Set(center.toasts.map(\.id))
      let didSave = await controller.save(title: "", body: note)
      XCTAssertTrue(didSave)
      var announced = try await toasts(after: shown, from: controller)
      XCTAssertEqual(
        announced.map(\.message),
        ["Saved on this iPhone. MemoTrail will sync when you are online."])
      XCTAssertEqual(announced.map(\.tone), [.info])
      XCTAssertNil(controller.captureError)
      XCTAssertEqual(controller.pendingEntries.map(\.body), [note])

      // Retrying while still offline announces it nowhere again.
      shown = Set(center.toasts.map(\.id))
      let retried = await controller.synchronizePendingEntries()
      XCTAssertFalse(retried)
      XCTAssertTrue(center.toasts.allSatisfy { shown.contains($0.id) })
      XCTAssertNil(controller.captureError)
      XCTAssertEqual(controller.pendingEntries.map(\.body), [note])

      // Back online, the waiting capture syncs and is announced as saved.
      NativeReviewNetwork.isOffline = false
      shown = Set(center.toasts.map(\.id))
      let synced = await controller.synchronizePendingEntries()
      XCTAssertTrue(synced)
      announced = center.toasts.filter { !shown.contains($0.id) }
      XCTAssertEqual(announced.map(\.message), ["Saved to Library."])
      XCTAssertTrue(controller.pendingEntries.isEmpty)
      let reachedLibrary: [ExistingRow] =
        try await client.from("entries").select("id").eq("body", value: note).execute().value
      XCTAssertEqual(reachedLibrary.count, 1)

      // An online save is announced once, after it syncs, without an offline confirmation.
      let onlineNote = "Online capture \(UUID().uuidString)"
      shown = Set(center.toasts.map(\.id))
      let didSaveOnline = await controller.save(title: "", body: onlineNote)
      XCTAssertTrue(didSaveOnline)
      announced = try await toasts(after: shown, from: controller)
      XCTAssertEqual(announced.map(\.message), ["Saved to Library."])
      XCTAssertNil(controller.captureError)
      XCTAssertTrue(controller.pendingEntries.isEmpty)
    }

    func testRefusedCapturesStayOnThisIPhoneWithoutBlockingLaterCaptures() async throws {
      let (client, ownerID) = try await client(session: NativeReviewNetwork.session())
      defer { NativeReviewNetwork.isOffline = false }
      let suiteName = "NativeContractTests.\(UUID().uuidString)"
      let photoRoot = FileManager.default.temporaryDirectory.appending(
        path: "NativeContractTests.\(UUID().uuidString)", directoryHint: .isDirectory)
      addTeardownBlock {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: photoRoot)
      }
      let queueStore = CaptureQueueStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
      let photoStore = CapturePhotoStore(rootURL: photoRoot)
      let controller = CaptureController(
        client: client, ownerID: ownerID, queueStore: queueStore, photoStore: photoStore)
      // Let the connectivity monitor's first update pass, so each save starts its own sync.
      try await Task.sleep(for: .milliseconds(500))
      let center = MTToastCenter.shared

      // Offline, queue a note Postgres text cannot store, a photo capture whose photo then
      // changes on this iPhone, and a valid capture saved after both.
      NativeReviewNetwork.isOffline = true
      let marker = UUID().uuidString
      let refusedNote = "Pasted from a terminal \u{0000} log \(marker)"
      let photo = try photoDraft()
      try photoStore.save(photo, ownerID: ownerID)
      for (title, body, photos) in [
        ("", refusedNote, []), ("Harbor photo \(marker)", "", [photo]),
        ("", "A later capture \(marker)", []),
      ] as [(String, String, [PhotoDraft])] {
        let shown = Set(center.toasts.map(\.id))
        let didSave = await controller.save(title: title, body: body, photos: photos)
        XCTAssertTrue(didSave)
        _ = try await toasts(after: shown, from: controller)
      }
      let queued = controller.pendingEntries
      XCTAssertEqual(queued.count, 3)
      XCTAssertEqual(controller.waitingEntryCount, 3)
      // A capture that may still sync is never discarded.
      let keptWaiting = await controller.discardRejected(queued[0].id)
      XCTAssertFalse(keptWaiting)
      XCTAssertEqual(controller.pendingEntries.map(\.id), queued.map(\.id))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let changedData = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6), format: format)
        .pngData { context in
          UIColor.systemOrange.setFill()
          context.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
        }
      try photoStore.save(
        try PhotoDraft.validate(
          id: photo.id, data: changedData, mimeType: .png, originalFilename: "kept.png",
          pixelWidth: 6, pixelHeight: 6),
        ownerID: ownerID)

      // Online, MemoTrail refuses the first two once, each kept with why, while the later
      // capture still syncs. Neither is reported as offline.
      NativeReviewNetwork.isOffline = false
      let shown = Set(center.toasts.map(\.id))
      let synced = await controller.synchronizePendingEntries()
      XCTAssertTrue(synced)
      let announced = center.toasts.filter { !shown.contains($0.id) }
      XCTAssertEqual(
        announced.map(\.message),
        ["MemoTrail did not accept 2 Entries. Review them in Pending sync.", "Saved to Library."])
      XCTAssertEqual(announced.map(\.tone), [.error, .success])
      XCTAssertNil(controller.captureError)
      XCTAssertEqual(controller.pendingEntries.map(\.id), Array(queued.map(\.id).prefix(2)))
      XCTAssertEqual(controller.pendingEntries.map(\.body), [refusedNote, ""])
      XCTAssertEqual(
        controller.pendingEntries.map { $0.rejection?.message },
        [
          "MemoTrail cannot accept this Entry, so it will not sync. "
            + "Copy its text to keep it, then discard it.",
          "This Entry is in your Library, but one of its photos changed on this iPhone, "
            + "so they will not sync. Discard to remove them from this iPhone.",
        ])
      XCTAssertEqual(controller.waitingEntryCount, 0)
      XCTAssertEqual(controller.pendingSummary, "2 Entries not accepted")

      // The refused note never reached MemoTrail, while the photo capture's Entry did.
      struct StoredEntry: Decodable { let id: UUID }
      let stored: [StoredEntry] =
        try await client.from("entries").select("id")
        .in("id", values: queued.map { $0.id.uuidString })
        .execute().value
      XCTAssertEqual(Set(stored.map(\.id)), Set(queued.map(\.id).suffix(2)))

      // After a relaunch, refused captures are still marked and are never sent again.
      let relaunched = CaptureController(
        client: client, ownerID: ownerID, queueStore: queueStore, photoStore: photoStore)
      XCTAssertEqual(relaunched.pendingEntries, controller.pendingEntries)
      NativeReviewNetwork.isOffline = true
      let quiet = Set(center.toasts.map(\.id))
      let resent = await relaunched.synchronizePendingEntries()
      XCTAssertFalse(resent)
      XCTAssertTrue(center.toasts.allSatisfy { quiet.contains($0.id) })
      XCTAssertNil(relaunched.captureError)
      NativeReviewNetwork.isOffline = false

      // Discarding removes the capture's photo files first, then the capture itself.
      let discardedPhoto = await relaunched.discardRejected(queued[1].id)
      XCTAssertTrue(discardedPhoto)
      XCTAssertFalse(try photoStore.load(ownerID: ownerID).contains { $0.id == photo.id })
      let discardedNote = await relaunched.discardRejected(queued[0].id)
      XCTAssertTrue(discardedNote)
      XCTAssertTrue(relaunched.pendingEntries.isEmpty)
      XCTAssertTrue(queueStore.load(ownerID: ownerID).isEmpty)
    }

    func testCapturesWhoseEntryIsInTrashOrDeletedForeverStopInsteadOfRetrying() async throws {
      let (client, ownerID) = try await client(session: NativeReviewNetwork.session())
      defer { NativeReviewNetwork.isOffline = false }
      let (controller, photoStore) = try await isolatedCapture(client: client, ownerID: ownerID)
      let center = MTToastCenter.shared

      // Offline, queue a note, a photo capture, and a note that will be deleted forever.
      NativeReviewNetwork.isOffline = true
      let marker = UUID().uuidString
      let photo = try photoDraft()
      try photoStore.save(photo, ownerID: ownerID)
      for (body, photos) in [
        ("Trashed note \(marker)", []), ("Trashed photo \(marker)", [photo]),
        ("Deleted forever \(marker)", []),
      ] as [(String, [PhotoDraft])] {
        let shown = Set(center.toasts.map(\.id))
        let didSave = await controller.save(title: "", body: body, photos: photos)
        XCTAssertTrue(didSave)
        _ = try await toasts(after: shown, from: controller)
      }
      let queued = controller.pendingEntries
      XCTAssertEqual(queued.count, 3)

      // Each Entry reached MemoTrail on an attempt whose answer never came back, then went to
      // Trash on another device, where the last one was deleted forever.
      NativeReviewNetwork.isOffline = false
      for capture in queued {
        try await client.from("entries").insert(CaptureInsert(capture, ownerID: ownerID)).execute()
        try await moveToTrashElsewhere(capture.id, client: client)
      }
      let trash = TrashController(client: client, ownerID: ownerID)
      await trash.load()
      let deletedNote = try XCTUnwrap(trash.items.first { $0.itemID == queued[2].id })
      let deleted = await trash.deleteForever(deletedNote)
      XCTAssertEqual(deleted, .init(message: "Item permanently deleted.", tone: .success))

      // Each stops for good with why instead of retrying, and a later capture still syncs.
      let shown = Set(center.toasts.map(\.id))
      let didSave = await controller.save(title: "", body: "A later capture \(marker)")
      XCTAssertTrue(didSave)
      let announced = try await toasts(after: shown, from: controller)
      XCTAssertEqual(
        announced.map(\.message),
        ["MemoTrail did not accept 3 Entries. Review them in Pending sync.", "Saved to Library."])
      XCTAssertNil(controller.captureError)
      XCTAssertEqual(controller.pendingEntries.map(\.id), queued.map(\.id))
      XCTAssertEqual(
        controller.pendingEntries.map { $0.rejection?.message },
        [
          "This Entry is already in Trash, so it will not sync again. "
            + "Restore it from Trash to keep it, then discard this copy.",
          "This Entry is in Trash, so its photos will not be attached. "
            + "Discard to remove them from this iPhone.",
          "This Entry was deleted forever, so MemoTrail will not create it again. "
            + "Copy its text to keep it, then discard it.",
        ])
      XCTAssertEqual(controller.pendingSummary, "3 Entries not accepted")

      // The Entry deleted forever never came back, and no photo went to the one in Trash.
      struct StoredEntry: Decodable {
        let id: UUID
        let deleted_at: String?
      }
      let stored: [StoredEntry] =
        try await client.from("entries").select("id,deleted_at")
        .in("id", values: queued.map { $0.id.uuidString })
        .execute().value
      XCTAssertEqual(Set(stored.map(\.id)), Set(queued.prefix(2).map(\.id)))
      XCTAssertTrue(stored.allSatisfy { $0.deleted_at != nil })
      let photoFolder = "\(ownerID.uuidString.lowercased())/\(queued[1].id.uuidString.lowercased())"
      let uploaded = try await storedNames(in: photoFolder, client: client)
      XCTAssertEqual(uploaded, [])

      // Discard keeps working for these, like any refused capture.
      for capture in queued {
        let discarded = await controller.discardRejected(capture.id)
        XCTAssertTrue(discarded)
      }
      XCTAssertTrue(controller.pendingEntries.isEmpty)
    }

    func testRefusedPhotoUploadsStopWhileOneWhoseAnswerWasLostAttaches() async throws {
      let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
      defer { HeldResponseProtocol.gate.answerNextUpload(nil) }
      let (controller, photoStore) = try await isolatedCapture(client: client, ownerID: ownerID)
      let center = MTToastCenter.shared
      let marker = UUID().uuidString

      // Storage refuses one photo as too large, and denies another for a person still signed
      // in, which the session check confirms is a refusal rather than an expired session.
      for (body, statusCode) in [("Too large \(marker)", "413"), ("Denied \(marker)", "403")] {
        let photo = try photoDraft()
        try photoStore.save(photo, ownerID: ownerID)
        HeldResponseProtocol.gate.answerNextUpload(.refuse(statusCode: statusCode))
        let shown = Set(center.toasts.map(\.id))
        let didSave = await controller.save(title: "", body: body, photos: [photo])
        XCTAssertTrue(didSave)
        let announced = try await toasts(after: shown, from: controller)
        XCTAssertEqual(
          announced.map(\.message), ["MemoTrail did not accept 1 Entry. Review it in Pending sync."])
      }
      XCTAssertEqual(
        controller.pendingEntries.map { $0.rejection?.message },
        [
          "This Entry is in your Library, but one of its photos is too large for MemoTrail, "
            + "so they will not sync. Discard to remove them from this iPhone.",
          "This Entry is in your Library, but MemoTrail cannot accept one of its photos, "
            + "so they will not sync. Discard to remove them from this iPhone.",
        ])
      let refusedEntries = controller.pendingEntries.map(\.id)
      let reached: [ExistingRow] =
        try await client.from("entries").select("id")
        .in("id", values: refusedEntries.map(\.uuidString)).execute().value
      XCTAssertEqual(Set(reached.map(\.id)), Set(refusedEntries))
      let refusedPhotos = try await attachmentCount(entryIDs: refusedEntries, client: client)
      XCTAssertEqual(refusedPhotos, 0)

      // The next photo reaches Storage, but its answer is lost, so it waits on this iPhone.
      let photo = try photoDraft()
      try photoStore.save(photo, ownerID: ownerID)
      HeldResponseProtocol.gate.answerNextUpload(.loseResponse)
      let didSave = await controller.save(title: "", body: "Lost upload \(marker)", photos: [photo])
      XCTAssertTrue(didSave)
      let offline = "Photos are saved on this iPhone. MemoTrail will retry when you are online."
      for _ in 0..<150 where controller.isSyncing || controller.captureError != offline {
        try await Task.sleep(for: .milliseconds(100))
      }
      XCTAssertEqual(controller.captureError, offline)
      XCTAssertEqual(controller.waitingEntryCount, 1)
      let waiting = try XCTUnwrap(controller.pendingEntries.last)
      let waitingPhotos = try await attachmentCount(entryIDs: [waiting.id], client: client)
      XCTAssertEqual(waitingPhotos, 0)

      // A retry finds the stored original in Storage and attaches it.
      let shown = Set(center.toasts.map(\.id))
      let synced = await controller.synchronizePendingEntries()
      XCTAssertTrue(synced)
      XCTAssertEqual(
        center.toasts.filter { !shown.contains($0.id) }.map(\.message),
        ["Saved to Library with 1 photo."])
      XCTAssertNil(controller.captureError)
      XCTAssertEqual(controller.waitingEntryCount, 0)
      let attached = try await attachmentCount(entryIDs: [waiting.id], client: client)
      XCTAssertEqual(attached, 1)
      XCTAssertFalse(try photoStore.load(ownerID: ownerID).contains { $0.id == photo.id })
    }

    func testPhotoThatArrivesAfterDeleteForeverIsRefusedAndItsUploadRemoved() async throws {
      let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
      defer {
        HeldResponseProtocol.gate.answerNextUpload(nil)
        HeldResponseProtocol.gate.releaseHeldResponse()
      }
      let (controller, photoStore) = try await isolatedCapture(client: client, ownerID: ownerID)
      let center = MTToastCenter.shared

      // The original is stored, and its answer waits while another device deletes the Entry
      // forever.
      let photo = try photoDraft()
      try photoStore.save(photo, ownerID: ownerID)
      HeldResponseProtocol.gate.answerNextUpload(.hold)
      let shown = Set(center.toasts.map(\.id))
      let didSave = await controller.save(
        title: "", body: "Deleted forever during its upload \(UUID().uuidString)",
        photos: [photo])
      XCTAssertTrue(didSave)
      try await waitForHeldResponse()
      let capture = try XCTUnwrap(controller.pendingEntries.first)
      try await moveToTrashElsewhere(capture.id, client: client)
      let trash = TrashController(client: client, ownerID: ownerID)
      await trash.load()
      let trashed = try XCTUnwrap(trash.items.first { $0.itemID == capture.id })
      let deleted = await trash.deleteForever(trashed)
      XCTAssertEqual(deleted, .init(message: "Item permanently deleted.", tone: .success))
      HeldResponseProtocol.gate.releaseHeldResponse()

      let announced = try await toasts(after: shown, from: controller)
      XCTAssertEqual(
        announced.map(\.message), ["MemoTrail did not accept 1 Entry. Review it in Pending sync."])
      XCTAssertEqual(
        controller.pendingEntries.map { $0.rejection?.message },
        [
          "This Entry was deleted forever, so MemoTrail will not create it again. "
            + "Copy its text to keep it, then discard it."
        ])
      let stored: [ExistingRow] =
        try await client.from("entries").select("id")
        .eq("id", value: capture.id.uuidString).execute().value
      XCTAssertEqual(stored.count, 0)
      // The unregistered original does not outlive its Entry.
      let folder = "\(ownerID.uuidString.lowercased())/\(capture.id.uuidString.lowercased())"
      let remaining = try await storedNames(in: folder, client: client)
      XCTAssertEqual(remaining, [])
    }
  #endif
}
