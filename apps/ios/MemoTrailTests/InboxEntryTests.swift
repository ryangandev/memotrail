import XCTest

@testable import MemoTrail

final class InboxEntryTests: XCTestCase {
  func testBodyOnlyCaptureIsTrimmedAndAccepted() throws {
    let capture = try InboxCapture.validate(
      title: "  ",
      body: "  A thought worth keeping.  "
    )

    XCTAssertNil(capture.title)
    XCTAssertEqual(capture.body, "A thought worth keeping.")
  }

  func testTitleOnlyCaptureIsAccepted() throws {
    let capture = try InboxCapture.validate(
      title: " First time skiing ",
      body: "  "
    )

    XCTAssertEqual(capture.title, "First time skiing")
    XCTAssertEqual(capture.body, "")
  }

  func testEmptyCaptureIsRejected() {
    XCTAssertThrowsError(
      try InboxCapture.validate(title: " \n ", body: "  ")
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .empty)
    }
  }

  func testPhotoOnlyCaptureIsAccepted() throws {
    let capture = try InboxCapture.validate(
      title: "",
      body: "",
      hasAttachments: true
    )

    XCTAssertNil(capture.title)
    XCTAssertEqual(capture.body, "")
  }

  func testOversizedTitleAndBodyAreRejected() {
    XCTAssertThrowsError(
      try InboxCapture.validate(
        title: String(repeating: "a", count: InboxCapture.titleLimit + 1),
        body: ""
      )
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .titleTooLong)
    }

    XCTAssertThrowsError(
      try InboxCapture.validate(
        title: "",
        body: String(repeating: "a", count: InboxCapture.bodyLimit + 1)
      )
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .bodyTooLong)
    }
  }

  func testBodyOnlyEntryUsesFirstLineAsItsDisplayTitle() {
    let entry = InboxEntry(
      id: UUID(),
      title: nil,
      body: "Why do people keep learning?\nBecause our model of the world keeps changing.",
      createdAt: Date(timeIntervalSince1970: 0),
      occurredStart: nil
    )

    XCTAssertEqual(entry.displayTitle, "Why do people keep learning?")
    XCTAssertEqual(
      entry.displayExcerpt,
      "Because our model of the world keeps changing."
    )
  }

  func testTitledEntryKeepsItsBodyAsTheExcerpt() {
    let entry = InboxEntry(
      id: UUID(),
      title: "How aligners move teeth",
      body: "Small forces trigger bone remodeling.",
      createdAt: Date(timeIntervalSince1970: 0),
      occurredStart: nil
    )

    XCTAssertEqual(entry.displayTitle, "How aligners move teeth")
    XCTAssertEqual(entry.displayExcerpt, "Small forces trigger bone remodeling.")
  }

  func testReviewAcceptsEditableContentTypeAndOccurrence() throws {
    let occurredAt = Date(timeIntervalSince1970: 1_788_278_400)
    let input = try InboxReviewInput.validate(
      entryID: UUID(),
      revision: 2,
      title: "  First time skiing  ",
      body: "  A cold and brilliant day.  ",
      collectionNames: [" Travel ", "travel", "First Times"],
      entryType: .firstTime,
      occurredAt: occurredAt,
      occurredTimezone: "America/Los_Angeles",
      tagNames: [" Skiing ", "skiing", "snow"]
    )

    XCTAssertEqual(input.title, "First time skiing")
    XCTAssertEqual(input.body, "A cold and brilliant day.")
    XCTAssertEqual(input.entryType, .firstTime)
    XCTAssertEqual(input.collectionNames, ["Travel", "First Times"])
    XCTAssertEqual(input.tagNames, ["Skiing", "snow"])
    XCTAssertEqual(input.occurredAt, occurredAt)
    XCTAssertEqual(input.revision, 2)
  }

  func testReviewRequiresATitleForAFirstTime() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: " ",
        body: "I tried something new.",
        collectionNames: [],
        entryType: .firstTime,
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .firstTimeRequiresTitle)
    }
  }

  func testReviewRejectsInvalidRevisionAndTimezone() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 0,
        title: "A thought",
        body: "",
        collectionNames: [],
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidRevision)
    }

    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [],
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: "",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidTimezone)
    }
  }

  func testReviewRejectsInvalidOrganizationNames() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [""],
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidCollections)
    }

    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [],
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: [String(repeating: "t", count: 61)]
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidTags)
    }
  }

  func testReviewRPCParametersEncodeANilTitleExplicitly() throws {
    let parameters = ReviewEntryParameters(
      entryID: UUID(),
      expectedRevision: 1,
      title: nil,
      body: "A body-only Entry",
      entryType: .standard,
      occurredStart: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "UTC",
      collectionNames: [],
      tagNames: [],
      markDone: false
    )
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json.keys.contains("p_title"))
    XCTAssertTrue(json["p_title"] is NSNull)
  }

  func testDraftStoreRestoresContentForOnlyItsOwner() {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let firstOwner = UUID()
    let secondOwner = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_783_088_200)

    XCTAssertTrue(
      store.save(
        title: " Draft title ",
        body: "  Keep my spacing.\n",
        occurredAt: occurredAt,
        ownerID: firstOwner
      )
    )
    XCTAssertEqual(store.load(ownerID: firstOwner)?.title, " Draft title ")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.body, "  Keep my spacing.\n")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.occurredAt, occurredAt)
    XCTAssertNil(store.load(ownerID: secondOwner))
  }

  func testDraftStoreLoadsLegacyTextDraftWithoutInventingADate() throws {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()
    let legacyDraft = LegacyInboxDraft(
      title: "",
      body: "An earlier draft",
      updatedAt: Date(timeIntervalSince1970: 1_788_278_400)
    )
    defaults.set(
      try JSONEncoder().encode(legacyDraft),
      forKey: InboxDraftStore.storageKey(ownerID: ownerID)
    )

    let loadedDraft = try XCTUnwrap(store.load(ownerID: ownerID))
    XCTAssertEqual(loadedDraft.body, "An earlier draft")
    XCTAssertNil(loadedDraft.occurredAt)
  }

  func testDraftStoreClearsEmptyAndAcceptedDrafts() {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()

    store.save(title: "", body: "Keep me", ownerID: ownerID)
    store.clear(ownerID: ownerID)
    XCTAssertNil(store.load(ownerID: ownerID))

    XCTAssertFalse(store.save(title: "", body: "", ownerID: ownerID))
    XCTAssertNil(store.load(ownerID: ownerID))
  }

  func testDraftStoreDiscardsCorruptedOrOversizedData() throws {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()
    let key = InboxDraftStore.storageKey(ownerID: ownerID)

    defaults.set(Data("not json".utf8), forKey: key)
    XCTAssertNil(store.load(ownerID: ownerID))

    let oversizedDraft = InboxDraft(
      title: String(repeating: "t", count: InboxCapture.titleLimit + 1),
      body: "",
      updatedAt: Date()
    )
    defaults.set(try JSONEncoder().encode(oversizedDraft), forKey: key)
    XCTAssertNil(store.load(ownerID: ownerID))
  }

  func testQueueStoreKeepsPendingEntriesIsolatedByOwner() {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let firstOwner = UUID()
    let secondOwner = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: firstOwner), [entry])
    XCTAssertEqual(store.load(ownerID: firstOwner), [entry])
    XCTAssertTrue(store.load(ownerID: secondOwner).isEmpty)
  }

  func testQueueStoreDoesNotDuplicateAStableEntryID() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
  }

  func testQueueStoreRemovesOnlyTheConfirmedEntry() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let first = makeQueuedEntry()
    let second = makeQueuedEntry(
      id: UUID(),
      title: "Second thought"
    )

    _ = store.enqueue(first, ownerID: ownerID)
    _ = store.enqueue(second, ownerID: ownerID)

    XCTAssertEqual(store.remove(entryID: first.id, ownerID: ownerID), [second])
  }

  func testQueueStoreDiscardsCorruptedObsoleteAndDuplicateData() throws {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let ownerID = UUID()
    let key = InboxQueueStore.storageKey(ownerID: ownerID)

    defaults.set(Data("not json".utf8), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)

    let entry = makeQueuedEntry()
    let duplicateQueue = TestStoredInboxQueue(version: 1, entries: [entry, entry])
    defaults.set(try JSONEncoder().encode(duplicateQueue), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)

    let obsoleteQueue = TestStoredInboxQueue(version: 3, entries: [entry])
    defaults.set(try JSONEncoder().encode(obsoleteQueue), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)
  }

  func testQueueStoreLoadsVersionOneEntriesWithoutInventingAttachments() throws {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let ownerID = UUID()
    let legacyEntry = LegacyQueuedInboxEntry(
      id: UUID(),
      title: nil,
      body: "An earlier queued thought",
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400)
    )
    let queue = LegacyStoredInboxQueue(version: 1, entries: [legacyEntry])
    defaults.set(
      try JSONEncoder().encode(queue),
      forKey: InboxQueueStore.storageKey(ownerID: ownerID)
    )

    let loaded = try XCTUnwrap(store.load(ownerID: ownerID).first)
    XCTAssertEqual(loaded.id, legacyEntry.id)
    XCTAssertTrue(loaded.attachments.isEmpty)
  }

  func testQueueAcceptsPhotoOnlyEntryAndRejectsDuplicatePhotos() throws {
    let attachment = makeQueuedAttachment()
    let photoOnly = makeQueuedEntry(
      body: "",
      attachments: [attachment]
    )

    XCTAssertTrue(photoOnly.isValid)
    XCTAssertFalse(
      makeQueuedEntry(body: "", attachments: [attachment, attachment]).isValid
    )
  }

  func testQueueStoreRejectsInvalidAndOverCapacityEntries() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let invalidEntry = makeQueuedEntry(body: "  not normalized  ")

    XCTAssertNil(store.enqueue(invalidEntry, ownerID: ownerID))

    for index in 0..<InboxQueueStore.maximumEntryCount {
      XCTAssertNotNil(
        store.enqueue(
          makeQueuedEntry(id: UUID(), title: "Entry \(index)"),
          ownerID: ownerID
        )
      )
    }

    XCTAssertNil(
      store.enqueue(makeQueuedEntry(id: UUID()), ownerID: ownerID)
    )
  }

  func testPhotoStorePersistsPrivateDraftsByOwnerAndRemovesThem() throws {
    let rootURL = makePhotoRoot()
    let store = InboxPhotoStore(rootURL: rootURL)
    let ownerID = UUID()
    let otherOwnerID = UUID()
    let draft = try makePhotoDraft()

    try store.save(draft, ownerID: ownerID)

    XCTAssertEqual(try store.load(ownerID: ownerID), [draft])
    XCTAssertTrue(try store.load(ownerID: otherOwnerID).isEmpty)

    try store.remove(photoID: draft.id, ownerID: ownerID)
    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testPhotoStoreIgnoresMalformedMetadata() throws {
    let rootURL = makePhotoRoot()
    let store = InboxPhotoStore(rootURL: rootURL)
    let ownerID = UUID()
    let ownerURL = rootURL.appending(path: ownerID.uuidString.lowercased())
    try FileManager.default.createDirectory(
      at: ownerURL,
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(
      to: ownerURL.appending(path: "broken.json")
    )

    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testUniversalAttachmentParametersEncodeQueuedMetadata() throws {
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let attachment = makeQueuedAttachment()
    let parameters = RegisterEntryAttachmentParameters(
      entryID: entryID,
      attachment: attachment,
      objectPath: attachment.objectPath(ownerID: UUID(), entryID: entryID)
    )
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_attachment_id"] as? String, attachment.id.uuidString)
    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 8)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
  }

  private func makeQueuedEntry(
    id: UUID = UUID(uuidString: "F4D2DF16-A506-4BE6-A63E-B7B18AFE3468")!,
    title: String? = nil,
    body: String = "A thought worth keeping.",
    attachments: [QueuedInboxAttachment] = []
  ) -> QueuedInboxEntry {
    QueuedInboxEntry(
      id: id,
      title: title,
      body: body,
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400),
      attachments: attachments
    )
  }

  private func makeQueuedAttachment() -> QueuedInboxAttachment {
    QueuedInboxAttachment(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      mimeType: .png,
      originalFilename: nil,
      byteSize: 8,
      pixelWidth: 12,
      pixelHeight: 8
    )
  }

  private func makePhotoDraft() throws -> FirstTimePhotoDraft {
    try FirstTimePhotoDraft.validate(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      mimeType: .png,
      originalFilename: nil,
      pixelWidth: 12,
      pixelHeight: 8
    )
  }

  private func makePhotoRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "InboxEntryTests.\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "InboxEntryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
    return defaults
  }
}

private struct TestStoredInboxQueue: Encodable {
  let version: Int
  let entries: [QueuedInboxEntry]
}

private struct LegacyStoredInboxQueue: Encodable {
  let version: Int
  let entries: [LegacyQueuedInboxEntry]
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
