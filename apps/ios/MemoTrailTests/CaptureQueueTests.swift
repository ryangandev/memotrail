@preconcurrency import Supabase
import UIKit
import XCTest

@testable import MemoTrail

/// Captures waiting on this iPhone: the queue, its quarantine (#24), the draft, the photo
/// files, how a sync or upload failure is classified, and the row a capture becomes.
final class CaptureQueueTests: XCTestCase {
  // MARK: Quarantine (#24)

  func testLoadKeepsValidCapturesAndQuarantinesOneInvalidCapture() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let owner = UUID()
    let first = makeQueuedEntry(id: UUID(), body: "First")
    let second = makeQueuedEntry(id: UUID(), body: "Second")
    var invalid = try object(makeQueuedEntry(id: UUID(), body: "Lost note"))
    invalid["occurredTimezone"] = ""
    let stored = try queueData(version: 3, entries: [object(first), invalid, object(second)])
    try storage.set(stored, forKey: CaptureQueueStore.storageKey(ownerID: owner))

    // The valid captures load, and the invalid one is listed for Copy text and Discard.
    XCTAssertEqual(store.load(ownerID: owner), [first, second])
    let unreadable = store.unreadableCaptures(ownerID: owner)
    XCTAssertEqual(unreadable.map(\.text), ["Lost note"])
    XCTAssertEqual(unreadable.map(\.photoIDs), [[]])
    // Reading never writes.
    XCTAssertEqual(storage.data(forKey: CaptureQueueStore.storageKey(ownerID: owner)), stored)
    XCTAssertNil(storage.data(forKey: CaptureQueueStore.quarantineKey(ownerID: owner)))

    // The next write sets the invalid capture aside first, exactly as it was stored.
    let third = makeQueuedEntry(id: UUID(), body: "Third")
    XCTAssertEqual(store.enqueue(third, ownerID: owner), [first, second, third])
    XCTAssertEqual(quarantined(storage, owner: owner), [try storedJSON(invalid)])
    XCTAssertEqual(storedQueue(storage, owner: owner).unreadable, [])
    XCTAssertEqual(store.unreadableCaptures(ownerID: owner).map(\.text), ["Lost note"])

    // Another write does not set it aside twice.
    XCTAssertEqual(store.remove(entryID: first.id, ownerID: owner), [second, third])
    XCTAssertEqual(quarantined(storage, owner: owner), [try storedJSON(invalid)])
  }

  func testUnknownQueueVersionIsQuarantinedNotDeleted() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let owner = UUID()
    let future = try object(
      makeQueuedEntry(id: UUID(), title: "From a newer build", body: "Kept"))
    try storage.set(
      queueData(version: 99, entries: [future]),
      forKey: CaptureQueueStore.storageKey(ownerID: owner))

    XCTAssertEqual(store.load(ownerID: owner), [])
    XCTAssertEqual(
      store.unreadableCaptures(ownerID: owner).map(\.text), ["From a newer build\n\nKept"])

    let next = makeQueuedEntry(id: UUID(), body: "After the upgrade")
    XCTAssertEqual(store.enqueue(next, ownerID: owner), [next])
    XCTAssertEqual(quarantined(storage, owner: owner), [try storedJSON(future)])
    XCTAssertEqual(
      store.unreadableCaptures(ownerID: owner).map(\.text), ["From a newer build\n\nKept"])

    // A queue that is not JSON at all is kept the same way.
    let other = UUID()
    try storage.set(Data("not json".utf8), forKey: CaptureQueueStore.storageKey(ownerID: other))
    XCTAssertEqual(store.load(ownerID: other), [])
    XCTAssertEqual(store.unreadableCaptures(ownerID: other).map(\.text), ["not json"])
  }

  func testRepeatedIDWithDifferentContentIsQuarantined() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let owner = UUID()
    let capture = makeQueuedEntry(id: UUID(), body: "The first copy")
    var changed = try object(capture)
    changed["body"] = "A different note under the same id"
    try storage.set(
      queueData(version: 3, entries: [object(capture), changed, object(capture)]),
      forKey: CaptureQueueStore.storageKey(ownerID: owner))

    // An exact repeat is the same capture; the changed copy is set aside, not sent twice.
    XCTAssertEqual(store.load(ownerID: owner), [capture])
    XCTAssertEqual(
      store.unreadableCaptures(ownerID: owner).map(\.text),
      ["A different note under the same id"])
  }

  func testQueueWriteIsRefusedWhenQuarantineCannotBeStored() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let owner = UUID()
    let valid = makeQueuedEntry(id: UUID(), body: "Valid")
    var invalid = try object(makeQueuedEntry(id: UUID(), body: "Unreadable"))
    invalid["queuedAt"] = "yesterday"
    let stored = try queueData(version: 3, entries: [object(valid), invalid])
    try storage.set(stored, forKey: CaptureQueueStore.storageKey(ownerID: owner))
    storage.refusedKeys = [CaptureQueueStore.quarantineKey(ownerID: owner)]

    // No reduced queue is stored over what could not be set aside.
    XCTAssertNil(store.enqueue(makeQueuedEntry(id: UUID(), body: "New"), ownerID: owner))
    XCTAssertNil(store.remove(entryID: valid.id, ownerID: owner))
    XCTAssertNil(
      store.markRejected(
        entryID: valid.id,
        rejection: QueuedCaptureRejection(message: "Refused.", rejectedAt: Date()),
        ownerID: owner))
    XCTAssertEqual(storage.data(forKey: CaptureQueueStore.storageKey(ownerID: owner)), stored)
    XCTAssertEqual(store.load(ownerID: owner), [valid])

    // Once the quarantine can be stored, the same write goes through.
    storage.refusedKeys = []
    XCTAssertEqual(store.remove(entryID: valid.id, ownerID: owner), [])
    XCTAssertEqual(quarantined(storage, owner: owner), [try storedJSON(invalid)])
  }

  func testVersionOneTwoAndThreeQueuesStillLoad() throws {
    let owner = UUID()
    let photo = makeQueuedAttachment()
    var current = makeQueuedEntry(id: UUID(), body: "Version three", attachments: [photo])
    current.occurrence = EntryOccurrence(
      precision: .month, start: Date(timeIntervalSince1970: 1_788_278_400), end: nil,
      label: nil, timezone: "America/Los_Angeles")
    current.rejection = QueuedCaptureRejection(
      message: "MemoTrail cannot accept this Entry, so it will not sync.",
      rejectedAt: Date(timeIntervalSince1970: 1_790_000_000))
    let legacy = LegacyQueuedInboxEntry(
      id: UUID(), title: nil, body: "Version one",
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400))
    let withPhoto = makeQueuedEntry(id: UUID(), body: "Version two", attachments: [photo])

    let queues: [(Int, Any, String)] = [
      (1, try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)), "Version one"),
      (2, try object(withPhoto), "Version two"),
      (3, try object(current), "Version three"),
    ]
    for (version, entry, expected) in queues {
      let storage = MemoryCaptureStorage()
      try storage.set(
        queueData(version: version, entries: [entry]),
        forKey: CaptureQueueStore.storageKey(ownerID: owner))
      let store = CaptureQueueStore(storage: storage)
      let loaded = try XCTUnwrap(store.load(ownerID: owner).first, "version \(version)")
      XCTAssertEqual(loaded.body, expected)
      XCTAssertEqual(store.unreadableCaptures(ownerID: owner), [], "version \(version)")
      switch version {
      case 1:
        // A version one capture has no photos and keeps its exact time.
        XCTAssertEqual(loaded.id, legacy.id)
        XCTAssertEqual(loaded.attachments, [])
        XCTAssertEqual(loaded.effectiveOccurrence.precision, .exact)
        XCTAssertEqual(loaded.effectiveOccurrence.start, legacy.occurredAt)
      case 2:
        XCTAssertEqual(loaded, withPhoto)
      default:
        XCTAssertEqual(loaded, current)
      }
      // Any write stores the newest version.
      XCTAssertNotNil(store.enqueue(makeQueuedEntry(id: UUID()), ownerID: owner))
      let rewritten = try XCTUnwrap(
        JSONSerialization.jsonObject(
          with: XCTUnwrap(storage.data(forKey: CaptureQueueStore.storageKey(ownerID: owner))))
          as? [String: Any])
      XCTAssertEqual(rewritten["version"] as? Int, CaptureQueueStore.currentVersion)
    }
  }

  func testDiscardUnreadableRemovesPhotosBeforeTheEntry() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let owner = UUID()
    let ownPhoto = UUID()
    let sharedPhoto = UUID()
    let valid = makeQueuedEntry(
      id: UUID(), body: "Still waiting",
      attachments: [makeQueuedAttachment(id: sharedPhoto)])
    var broken = try object(
      makeQueuedEntry(
        id: UUID(), body: "Broken photo capture",
        attachments: [makeQueuedAttachment(id: ownPhoto), makeQueuedAttachment(id: sharedPhoto)]))
    broken["occurredTimezone"] = ""
    var other = try object(makeQueuedEntry(id: UUID(), body: "Another broken capture"))
    other["occurredTimezone"] = ""
    try storage.set(
      queueData(version: 3, entries: [object(valid), broken, other]),
      forKey: CaptureQueueStore.storageKey(ownerID: owner))
    let target = try XCTUnwrap(
      store.unreadableCaptures(ownerID: owner).first { $0.text == "Broken photo capture" })
    XCTAssertEqual(target.photoIDs, [ownPhoto, sharedPhoto])

    // A photo that cannot be removed keeps the capture listed for another try.
    var removed: [UUID] = []
    XCTAssertFalse(
      store.discardUnreadable(target, ownerID: owner) { _ in throw CocoaError(.fileNoSuchFile) })
    XCTAssertEqual(store.unreadableCaptures(ownerID: owner).count, 2)

    // Its own photo goes first, never one a waiting capture still names; then the capture.
    XCTAssertTrue(store.discardUnreadable(target, ownerID: owner) { removed.append($0) })
    XCTAssertEqual(removed, [ownPhoto])
    XCTAssertEqual(
      store.unreadableCaptures(ownerID: owner).map(\.text), ["Another broken capture"])
    // The other unreadable capture moved to the quarantine instead of being dropped.
    XCTAssertEqual(quarantined(storage, owner: owner), [try storedJSON(other)])
    XCTAssertEqual(store.load(ownerID: owner), [valid])
    XCTAssertEqual(storedQueue(storage, owner: owner).unreadable, [])

    // Discarding the last one empties the quarantine.
    let last = try XCTUnwrap(store.unreadableCaptures(ownerID: owner).first)
    XCTAssertTrue(store.discardUnreadable(last, ownerID: owner) { removed.append($0) })
    XCTAssertEqual(store.unreadableCaptures(ownerID: owner), [])
    XCTAssertNil(storage.data(forKey: CaptureQueueStore.quarantineKey(ownerID: owner)))
  }

  func testInvalidDraftRestoresWhatItCanAndKeepsTheOriginal() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureDraftStore(storage: storage)
    let owner = UUID()
    let key = CaptureDraftStore.storageKey(ownerID: owner)
    let longTitle = String(repeating: "t", count: CaptureInput.titleLimit + 5)
    let original = try JSONSerialization.data(
      withJSONObject: [
        "title": longTitle, "body": "Kept note", "updatedAt": 1_000.0,
        "occurrenceDraft": "not a date",
      ])
    try storage.set(original, forKey: key)

    // What can be read comes back, cut to today's limits, with Web's notice.
    let reading = store.read(ownerID: owner)
    XCTAssertFalse(reading.isComplete)
    XCTAssertEqual(reading.notice, CaptureDraftReading.partialNotice)
    XCTAssertEqual(reading.draft?.title, String(longTitle.prefix(CaptureInput.titleLimit)))
    XCTAssertEqual(reading.draft?.body, "Kept note")
    XCTAssertNil(reading.draft?.occurrenceDraft)
    // Reading never writes.
    XCTAssertEqual(storage.data(forKey: key), original)
    XCTAssertEqual(store.quarantinedDrafts(ownerID: owner), [])

    // A draft that cannot be set aside is never replaced.
    storage.refusedKeys = [CaptureDraftStore.quarantineKey(ownerID: owner)]
    XCTAssertFalse(store.save(title: "", body: "Edited", ownerID: owner))
    store.clear(ownerID: owner)
    XCTAssertEqual(storage.data(forKey: key), original)

    // Saving over it keeps the original in the quarantine first.
    storage.refusedKeys = []
    XCTAssertTrue(store.save(title: "", body: "Edited", ownerID: owner))
    XCTAssertEqual(store.quarantinedDrafts(ownerID: owner), [StoredJSON(raw: original)])
    XCTAssertEqual(store.read(ownerID: owner).draft?.body, "Edited")
    XCTAssertNil(store.read(ownerID: owner).notice)

    // A draft that is not JSON at all says so, and clearing it keeps it too.
    try storage.set(Data("not json".utf8), forKey: key)
    XCTAssertNil(store.read(ownerID: owner).draft)
    XCTAssertEqual(store.read(ownerID: owner).notice, CaptureDraftReading.unreadableNotice)
    store.clear(ownerID: owner)
    XCTAssertNil(storage.data(forKey: key))
    XCTAssertEqual(
      store.quarantinedDrafts(ownerID: owner),
      [StoredJSON(raw: original), StoredJSON(raw: Data("not json".utf8))])
  }

  // MARK: Queue

  func testQueueStoreKeepsPendingEntriesIsolatedByOwner() {
    let store = CaptureQueueStore(defaults: makeDefaults())
    let firstOwner = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: firstOwner), [entry])
    XCTAssertEqual(store.load(ownerID: firstOwner), [entry])
    XCTAssertTrue(store.load(ownerID: UUID()).isEmpty)
  }

  func testQueueStoreDoesNotDuplicateAStableEntryID() {
    let store = CaptureQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
  }

  func testQueueStoreRemovesOnlyTheConfirmedEntry() {
    let store = CaptureQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let first = makeQueuedEntry()
    let second = makeQueuedEntry(id: UUID(), title: "Second thought")

    _ = store.enqueue(first, ownerID: ownerID)
    _ = store.enqueue(second, ownerID: ownerID)

    XCTAssertEqual(store.remove(entryID: first.id, ownerID: ownerID), [second])
  }

  func testQueueAcceptsPhotoOnlyEntryAndRejectsDuplicatePhotos() {
    let attachment = makeQueuedAttachment()

    XCTAssertTrue(makeQueuedEntry(body: "", attachments: [attachment]).isValid)
    XCTAssertFalse(makeQueuedEntry(body: "", attachments: [attachment, attachment]).isValid)
  }

  func testQueueStoreRejectsInvalidAndOverCapacityEntries() {
    let store = CaptureQueueStore(defaults: makeDefaults())
    let ownerID = UUID()

    XCTAssertNil(store.enqueue(makeQueuedEntry(body: "  not normalized  "), ownerID: ownerID))
    for index in 0..<CaptureQueueStore.maximumEntryCount {
      XCTAssertNotNil(
        store.enqueue(makeQueuedEntry(id: UUID(), title: "Entry \(index)"), ownerID: ownerID))
    }
    XCTAssertNil(store.enqueue(makeQueuedEntry(id: UUID()), ownerID: ownerID))
  }

  func testQueueStoreMarksARefusedCaptureInPlaceAcrossLaunches() {
    let defaults = makeDefaults()
    let store = CaptureQueueStore(defaults: defaults)
    let ownerID = UUID()
    let first = makeQueuedEntry(title: "Pasted log")
    let second = makeQueuedEntry(id: UUID(), title: "Second thought")
    let rejection = QueuedCaptureRejection(
      message: "MemoTrail cannot accept this Entry, so it will not sync.",
      rejectedAt: Date(timeIntervalSince1970: 1_790_000_000))
    _ = store.enqueue(first, ownerID: ownerID)
    _ = store.enqueue(second, ownerID: ownerID)

    var refused = first
    refused.rejection = rejection
    XCTAssertEqual(
      store.markRejected(entryID: first.id, rejection: rejection, ownerID: ownerID),
      [refused, second])

    // The marker survives a relaunch with the capture's content and order.
    let reloaded = CaptureQueueStore(defaults: defaults).load(ownerID: ownerID)
    XCTAssertEqual(reloaded, [refused, second])
    XCTAssertEqual(reloaded.map(\.rejection), [rejection, nil])
  }

  func testQueueStoreDoesNotBringBackARemovedCaptureWhenRefusingIt() {
    let defaults = makeDefaults()
    let store = CaptureQueueStore(defaults: defaults)
    let ownerID = UUID()
    let rejection = QueuedCaptureRejection(message: "Refused.", rejectedAt: Date())

    XCTAssertEqual(
      store.markRejected(entryID: UUID(), rejection: rejection, ownerID: ownerID), [])
    XCTAssertNil(defaults.data(forKey: CaptureQueueStore.storageKey(ownerID: ownerID)))
  }

  func testQueueKeepsACaptureWhoseRefusalMarkerIsMalformed() throws {
    let storage = MemoryCaptureStorage()
    let store = CaptureQueueStore(storage: storage)
    let ownerID = UUID()
    let entry = makeQueuedEntry()

    let malformedMarkers: [Any] = [
      NSNull(),
      "rejected",
      ["message": "", "rejectedAt": 1_000],
      ["message": String(repeating: "x", count: 501), "rejectedAt": 1_000],
      ["message": "Refused."],
      ["message": "Refused.", "rejectedAt": "yesterday"],
    ]
    for marker in malformedMarkers {
      var stored = try object(entry)
      stored["rejection"] = marker
      try storage.set(
        queueData(version: 3, entries: [stored]),
        forKey: CaptureQueueStore.storageKey(ownerID: ownerID))

      // The capture stays, sendable again, rather than costing the whole queue.
      let loaded = store.load(ownerID: ownerID)
      XCTAssertEqual(loaded.map(\.id), [entry.id], "\(marker)")
      XCTAssertNil(loaded.first?.rejection, "\(marker)")
    }
  }

  func testRefusedCaptureCopiesItsTitleAndNote() {
    XCTAssertEqual(
      makeQueuedEntry(title: "Pasted log", body: "Line one\nLine two").copyableText,
      "Pasted log\n\nLine one\nLine two")
    XCTAssertEqual(makeQueuedEntry(body: "Only a note").copyableText, "Only a note")
    XCTAssertEqual(
      makeQueuedEntry(body: "", attachments: [makeQueuedAttachment()]).copyableText, "")
  }

  // MARK: Draft

  func testCaptureDraftRetainsUnfinishedDateAndLegacyExactDate() throws {
    let store = CaptureDraftStore(defaults: makeDefaults())
    let owner = UUID()
    var draft = OccurrenceDraft(
      EntryOccurrence(
        precision: .year, start: nil, end: nil, label: nil, timezone: "Asia/Kathmandu"))
    draft.start = "20"
    XCTAssertTrue(store.save(title: "", body: "", occurrenceDraft: draft, ownerID: owner))
    XCTAssertEqual(store.load(ownerID: owner)?.captureOccurrence, draft)
    XCTAssertThrowsError(try draft.resolve())
    XCTAssertNil(store.load(ownerID: UUID()))
    let original = Date(timeIntervalSince1970: 1_500_000_000)
    XCTAssertTrue(store.save(title: "", body: "Legacy", occurredAt: original, ownerID: owner))
    XCTAssertEqual(try store.load(ownerID: owner)?.captureOccurrence?.resolve().start, original)
  }

  func testDraftStoreRestoresContentForOnlyItsOwner() {
    let store = CaptureDraftStore(defaults: makeDefaults())
    let firstOwner = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_783_088_200)

    XCTAssertTrue(
      store.save(
        title: " Draft title ", body: "  Keep my spacing.\n", occurredAt: occurredAt,
        ownerID: firstOwner))
    XCTAssertEqual(store.load(ownerID: firstOwner)?.title, " Draft title ")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.body, "  Keep my spacing.\n")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.occurredAt, occurredAt)
    XCTAssertNil(store.load(ownerID: UUID()))
  }

  func testDraftStoreLoadsLegacyTextDraftWithoutInventingADate() throws {
    let defaults = makeDefaults()
    let store = CaptureDraftStore(defaults: defaults)
    let ownerID = UUID()
    defaults.set(
      try JSONEncoder().encode(
        LegacyInboxDraft(
          title: "", body: "An earlier draft",
          updatedAt: Date(timeIntervalSince1970: 1_788_278_400))),
      forKey: CaptureDraftStore.storageKey(ownerID: ownerID))

    let reading = store.read(ownerID: ownerID)
    XCTAssertTrue(reading.isComplete)
    XCTAssertEqual(reading.draft?.body, "An earlier draft")
    XCTAssertNil(reading.draft?.occurredAt)
  }

  func testDraftStoreClearsEmptyAndAcceptedDrafts() {
    let store = CaptureDraftStore(defaults: makeDefaults())
    let ownerID = UUID()

    store.save(title: "", body: "Keep me", ownerID: ownerID)
    store.clear(ownerID: ownerID)
    XCTAssertNil(store.load(ownerID: ownerID))
    // A readable draft is cleared without a quarantined copy.
    XCTAssertEqual(store.quarantinedDrafts(ownerID: ownerID), [])

    XCTAssertFalse(store.save(title: "", body: "", ownerID: ownerID))
    XCTAssertNil(store.load(ownerID: ownerID))
  }

  @MainActor
  func testCapturedNoteTrimsWhitespaceAndKeepsWebFormatting() throws {
    let bold = UIFont.boldSystemFont(ofSize: 17)
    let note = NSMutableAttributedString(string: "\n  ")
    note.append(NSAttributedString(string: "Low tide", attributes: [.font: bold]))
    note.append(NSAttributedString(string: " and tea\nSecond line\n\n"))
    let captured = EntryEmphasisContent.capture(note)
    XCTAssertEqual(captured.body, "Low tide and tea\nSecond line")
    let rich = try XCTUnwrap(captured.rich)
    XCTAssertTrue(rich.isValid(expectedText: captured.body))
    let first = try XCTUnwrap(rich.document.content?.first?.content?.first)
    XCTAssertEqual(first.text, "Low tide")
    XCTAssertEqual(first.marks, [EntryEmphasisContent.Mark(type: "bold")])
    // Web's validator accepts the same document as Entry metadata.
    XCTAssertEqual(EntryRichText(rich)?.isValid(expectedText: captured.body), true)
    XCTAssertEqual(EntryEmphasisContent.capture(NSAttributedString(string: " \n ")).body, "")
    XCTAssertNil(EntryEmphasisContent.capture(NSAttributedString(string: " \n ")).rich)
  }

  @MainActor
  func testDraftAndQueueKeepFormattingOnlyForTheirExactNote() throws {
    let owner = UUID()
    let drafts = CaptureDraftStore(defaults: makeDefaults())
    let note = NSAttributedString(
      string: "Kept", attributes: [.font: UIFont.italicSystemFont(ofSize: 17)])
    let rich = EntryEmphasisContent(attributedText: note)
    XCTAssertTrue(drafts.save(title: "", body: "Kept", bodyRich: rich, ownerID: owner))
    let draft = try XCTUnwrap(drafts.load(ownerID: owner))
    XCTAssertEqual(draft.bodyRich, rich)
    XCTAssertTrue(
      EmphasisStyle.italic.isApplied(to: draft.note.attributes(at: 0, effectiveRange: nil)))
    XCTAssertTrue(drafts.save(title: "", body: "Changed", bodyRich: rich, ownerID: owner))
    XCTAssertNil(drafts.load(ownerID: owner)?.bodyRich)
    XCTAssertEqual(drafts.load(ownerID: owner)?.note.string, "Changed")

    let queue = CaptureQueueStore(defaults: makeDefaults())
    var entry = makeQueuedEntry(id: UUID(), body: "Kept")
    entry.bodyRich = rich
    XCTAssertTrue(entry.isValid)
    XCTAssertEqual(queue.enqueue(entry, ownerID: owner)?.first?.bodyRich, rich)
    var mismatched = entry
    mismatched.bodyRich = EntryEmphasisContent(attributedText: NSAttributedString(string: "Other"))
    XCTAssertFalse(mismatched.isValid)

    // Captures queued before formatting existed still load.
    let legacy = Data(
      #"{"id":"95000000-0000-4000-8000-000000000009","title":null,"body":"Old","occurredAt":null,"occurredTimezone":"UTC","queuedAt":0}"#
        .utf8)
    XCTAssertNil(try JSONDecoder().decode(QueuedCapture.self, from: legacy).bodyRich)
  }

  // MARK: Input

  func testCaptureInputTrimsAndAcceptsATitleANoteOrAPhoto() throws {
    let body = try CaptureInput.validate(title: "  ", body: "  A thought worth keeping.  ")
    XCTAssertNil(body.title)
    XCTAssertEqual(body.body, "A thought worth keeping.")
    let title = try CaptureInput.validate(title: " First time skiing ", body: "  ")
    XCTAssertEqual(title.title, "First time skiing")
    XCTAssertEqual(title.body, "")
    let photo = try CaptureInput.validate(title: "", body: "", hasAttachments: true)
    XCTAssertNil(photo.title)
    XCTAssertEqual(photo.body, "")
  }

  func testEmptyAndOversizedCapturesAreRejected() {
    XCTAssertThrowsError(try CaptureInput.validate(title: " \n ", body: "  ")) {
      XCTAssertEqual($0 as? CaptureError, .empty)
      XCTAssertEqual(
        $0.localizedDescription, "Write a title, a note, or add a photo before saving.")
    }
    XCTAssertThrowsError(
      try CaptureInput.validate(
        title: String(repeating: "a", count: CaptureInput.titleLimit + 1), body: "")
    ) { XCTAssertEqual($0 as? CaptureError, .titleTooLong) }
    XCTAssertThrowsError(
      try CaptureInput.validate(
        title: "", body: String(repeating: "a", count: CaptureInput.bodyLimit + 1))
    ) { XCTAssertEqual($0 as? CaptureError, .bodyTooLong) }
  }

  // MARK: The row a capture becomes

  func testCaptureInsertSendsAPlainEntryKeepingEveryPrecision() throws {
    let store = CaptureQueueStore(defaults: makeDefaults())
    let owner = UUID()
    for precision in DatePrecision.allCases {
      var draft = OccurrenceDraft(
        EntryOccurrence(
          precision: precision, start: nil, end: nil, label: nil, timezone: "Asia/Kathmandu"))
      switch precision {
      case .exact: draft.start = "2017-07-08T12:34:56"
      case .day, .range: draft.start = "2017-07-08"
      case .month: draft.start = "2017-07"
      case .year: draft.start = "2017"
      case .age, .approximate: draft.label = "At age 17"
      case .unknown: break
      }
      if precision == .range { draft.end = "2018-08-09" }
      let occurrence = try draft.resolve()
      var queued = makeQueuedEntry(id: UUID(), body: "Memory")
      queued.occurrence = occurrence
      XCTAssertNotNil(store.enqueue(queued, ownerID: owner))
      let restored = try XCTUnwrap(store.load(ownerID: owner).first { $0.id == queued.id })
      XCTAssertEqual(restored.effectiveOccurrence, occurrence)

      let json = try self.json(CaptureInsert(restored, ownerID: owner))
      XCTAssertEqual(json["id"] as? String, queued.id.uuidString.lowercased())
      XCTAssertEqual(json["owner_id"] as? String, owner.uuidString.lowercased())
      XCTAssertEqual(json["item_kind"] as? String, "entry")
      XCTAssertEqual(json["item_subtype"] as? String, "entry")
      XCTAssertEqual(json["client_id"] as? String, "ios:\(queued.id.uuidString.lowercased())")
      XCTAssertEqual(json["date_precision"] as? String, precision.rawValue)
      XCTAssertEqual(json["occurred_timezone"] as? String, "Asia/Kathmandu")
      XCTAssertEqual(
        json["occurred_start"] as? String, occurrence.start.map(EntryTimestamp.string(from:)))
      XCTAssertEqual(
        json["occurred_end"] as? String, occurrence.end.map(EntryTimestamp.string(from:)))
      XCTAssertEqual(json["occurred_label"] as? String, occurrence.label)
      if occurrence.start == nil { XCTAssertTrue(json["occurred_start"] is NSNull) }
      XCTAssertTrue(json["title"] is NSNull)
      XCTAssertEqual(Set(json.keys), CaptureInsertKeys.all)
    }
  }

  func testCaptureInsertCarriesBodyRichMetadataLikeWeb() throws {
    let rich = try JSONDecoder().decode(
      EntryEmphasisContent.self,
      from: Data(
        #"{"version":1,"text":"Hi","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hi","marks":[{"type":"bold"}]}]}]}}"#
          .utf8))
    let plain = makeQueuedEntry(id: UUID(), body: "Hi")
    let plainMetadata = try json(CaptureInsert(plain, ownerID: UUID()))["metadata"]
    XCTAssertEqual((plainMetadata as? [String: Any])?.isEmpty, true)
    var formatted = plain
    formatted.bodyRich = rich
    let metadata = try XCTUnwrap(
      try json(CaptureInsert(formatted, ownerID: UUID()))["metadata"] as? [String: Any])
    let bodyRich = try XCTUnwrap(metadata["body_rich"] as? [String: Any])
    XCTAssertEqual(bodyRich["text"] as? String, "Hi")
    XCTAssertEqual(bodyRich["version"] as? Int, 1)
  }

  // MARK: Failures

  func testCaptureSyncFailuresAreClassifiedByCodeLikeWeb() {
    func failure(_ code: String?) -> CaptureSyncFailure {
      CaptureSyncFailure(PostgrestError(code: code, message: "Any message"))
    }

    // Text Postgres cannot store, constraint and size violations, refused writes, and a
    // request PostgREST cannot read never succeed on a later attempt.
    for code in [
      "22P05", "22P02", "22001", "22023", "23502", "23505", "23514", "54000", "42501",
      "PGRST102",
    ] {
      XCTAssertEqual(failure(code), .rejected, code)
    }
    for code in ["PGRST301", "PGRST302", "PGRST303"] {
      XCTAssertEqual(failure(code), .session, code)
    }
    // Unavailable databases, stale schema caches, conflicts that succeed on retry, undeployed
    // functions, and errors without a code all stay retryable.
    for code in [
      nil, "", "PGRST000", "PGRST001", "PGRST002", "PGRST003", "PGRST204", "PGRST205",
      "PGRSTX00", "PGRST1XX", "40001", "40P01", "57014", "08006", "53300", "XX000", "42883",
      "42P01", "P0001", "22p05",
    ] {
      XCTAssertEqual(failure(code), .unavailable, code ?? "nil")
    }

    XCTAssertEqual(CaptureSyncFailure(URLError(.notConnectedToInternet)), .unavailable)
    XCTAssertEqual(CaptureSyncFailure(URLError(.timedOut)), .unavailable)
    let gateway = HTTPURLResponse(
      url: URL(string: "http://127.0.0.1:54321/rest/v1/entries")!, statusCode: 502,
      httpVersion: nil, headerFields: nil)!
    XCTAssertEqual(
      CaptureSyncFailure(HTTPError(data: Data("Bad gateway".utf8), response: gateway)),
      .unavailable)
    XCTAssertEqual(CaptureSyncFailure(CancellationError()), .unavailable)
  }

  func testCaptureUploadFailuresAreClassifiedByStatusLikeWeb() {
    // Storage answers with HTTP 400 and reports the real status in its error body.
    func failure(_ statusCode: String?) -> CaptureUploadFailure {
      CaptureUploadFailure(StorageError(statusCode: statusCode, message: "Any message"))
    }

    let expected: [(String, CaptureUploadFailure)] = [
      ("409", .exists), ("403", .denied), ("413", .tooLarge), ("415", .unsupportedType),
      ("400", .rejected), ("404", .rejected), ("422", .rejected), ("401", .session),
      ("408", .unavailable), ("423", .unavailable), ("429", .unavailable),
      ("500", .unavailable), ("503", .unavailable),
    ]
    for (statusCode, classification) in expected {
      XCTAssertEqual(failure(statusCode), classification, statusCode)
    }
    // Without a status Storage did not say why, so the photo keeps waiting.
    XCTAssertEqual(failure(nil), .unavailable)
    XCTAssertEqual(failure("EntityTooLarge"), .unavailable)

    // A body Storage did not write keeps only the HTTP status.
    func page(_ statusCode: Int) -> CaptureUploadFailure {
      let response = HTTPURLResponse(
        url: URL(string: "http://127.0.0.1:54321/storage/v1/object/entry-media/a.png")!,
        statusCode: statusCode, httpVersion: nil, headerFields: nil)!
      return CaptureUploadFailure(HTTPError(data: Data("Gateway page".utf8), response: response))
    }
    XCTAssertEqual(page(502), .unavailable)
    XCTAssertEqual(page(413), .tooLarge)
    XCTAssertEqual(page(400), .rejected)

    XCTAssertEqual(CaptureUploadFailure(URLError(.notConnectedToInternet)), .unavailable)
    XCTAssertEqual(CaptureUploadFailure(URLError(.networkConnectionLost)), .unavailable)
    XCTAssertEqual(CaptureUploadFailure(CancellationError()), .unavailable)
  }

  // MARK: Photo files

  func testPhotoStorePersistsPrivateDraftsByOwnerAndRemovesThem() throws {
    let store = CapturePhotoStore(rootURL: makePhotoRoot())
    let ownerID = UUID()
    let draft = try makePhotoDraft()

    try store.save(draft, ownerID: ownerID)

    XCTAssertEqual(try store.load(ownerID: ownerID), [draft])
    XCTAssertTrue(try store.load(ownerID: UUID()).isEmpty)

    try store.remove(photoID: draft.id, ownerID: ownerID)
    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testPhotoStoreIgnoresMalformedMetadata() throws {
    let rootURL = makePhotoRoot()
    let store = CapturePhotoStore(rootURL: rootURL)
    let ownerID = UUID()
    let ownerURL = rootURL.appending(path: ownerID.uuidString.lowercased())
    try FileManager.default.createDirectory(at: ownerURL, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: ownerURL.appending(path: "broken.json"))

    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testQueuedPhotoRegistrationSendsTheFactsSavedAtCapture() throws {
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let owner = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    let attachment = makeQueuedAttachment()
    let path = attachment.objectPath(ownerID: owner, entryID: entryID)
    XCTAssertEqual(
      path,
      "30000000-0000-4000-8000-000000000003/10000000-0000-4000-8000-000000000001/"
        + "20000000-0000-4000-8000-000000000001.png")
    let json = try self.json(
      RegisterEntryAttachmentParameters(entryID: entryID, attachment: attachment, objectPath: path))

    XCTAssertEqual(json["p_attachment_id"] as? String, attachment.id.uuidString)
    XCTAssertEqual(json["p_object_path"] as? String, path)
    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 8)
    XCTAssertEqual(json["p_pixel_width"] as? Int, 12)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
  }

  // MARK: Helpers

  private func makeQueuedEntry(
    id: UUID = UUID(uuidString: "F4D2DF16-A506-4BE6-A63E-B7B18AFE3468")!,
    title: String? = nil,
    body: String = "A thought worth keeping.",
    attachments: [QueuedCaptureAttachment] = []
  ) -> QueuedCapture {
    QueuedCapture(
      id: id, title: title, body: body, occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400), attachments: attachments)
  }

  private func makeQueuedAttachment(
    id: UUID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
  ) -> QueuedCaptureAttachment {
    QueuedCaptureAttachment(
      id: id, mimeType: .png, originalFilename: nil, byteSize: 8, pixelWidth: 12, pixelHeight: 8)
  }

  private func makePhotoDraft() throws -> PhotoDraft {
    try PhotoDraft.validate(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), mimeType: .png,
      originalFilename: nil, pixelWidth: 12, pixelHeight: 8)
  }

  private func makePhotoRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "CaptureQueueTests.\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "CaptureQueueTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
    return defaults
  }

  /// A queued capture as the JSON object the queue stores.
  private func object(_ capture: QueuedCapture) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as? [String: Any])
  }

  private func queueData(version: Int, entries: [Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["version": version, "entries": entries])
  }

  private func storedJSON(_ object: Any) throws -> StoredJSON {
    try XCTUnwrap(StoredJSON(object))
  }

  private func storedQueue(_ storage: MemoryCaptureStorage, owner: UUID) -> ParsedCaptureQueue {
    CaptureQueueStore.parse(storage.data(forKey: CaptureQueueStore.storageKey(ownerID: owner)))
  }

  private func quarantined(_ storage: MemoryCaptureStorage, owner: UUID) -> [StoredJSON] {
    CaptureQuarantine.read(storage.data(forKey: CaptureQueueStore.quarantineKey(ownerID: owner)))
      .map(\.value)
  }

  private func json(_ value: some Encodable) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}

/// The columns Web `syncInboxEntry` inserts.
private enum CaptureInsertKeys {
  static let all: Set<String> = [
    "id", "owner_id", "title", "body", "item_kind", "item_subtype", "occurred_start",
    "occurred_timezone", "date_precision", "occurred_end", "occurred_label", "client_id",
    "metadata",
  ]
}

/// Storage in memory that can refuse writes to chosen keys, like a full disk.
private final class MemoryCaptureStorage: CaptureStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]
  private var refused: Set<String> = []

  var refusedKeys: Set<String> {
    get { lock.withLock { refused } }
    set { lock.withLock { refused = newValue } }
  }

  func data(forKey key: String) -> Data? {
    lock.withLock { values[key] }
  }

  func set(_ data: Data, forKey key: String) throws {
    try lock.withLock {
      guard !refused.contains(key) else { throw CocoaError(.fileWriteOutOfSpace) }
      values[key] = data
    }
  }

  func remove(forKey key: String) throws {
    try lock.withLock {
      guard !refused.contains(key) else { throw CocoaError(.fileWriteOutOfSpace) }
      values.removeValue(forKey: key)
    }
  }
}

private struct LegacyQueuedInboxEntry: Encodable {
  let id: UUID
  let title: String?
  let body: String
  let occurredAt: Date
  let occurredTimezone: String
  let queuedAt: Date
}

private struct LegacyInboxDraft: Encodable {
  let title: String
  let body: String
  let updatedAt: Date
}
