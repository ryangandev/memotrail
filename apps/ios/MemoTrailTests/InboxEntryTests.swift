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
      entryType: .firstTime,
      occurredAt: occurredAt,
      occurredTimezone: "America/Los_Angeles"
    )

    XCTAssertEqual(input.title, "First time skiing")
    XCTAssertEqual(input.body, "A cold and brilliant day.")
    XCTAssertEqual(input.entryType, .firstTime)
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
        entryType: .firstTime,
        occurredAt: Date(),
        occurredTimezone: "UTC"
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
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: "UTC"
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
        entryType: .standard,
        occurredAt: Date(),
        occurredTimezone: ""
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidTimezone)
    }
  }

  func testDraftStoreRestoresContentForOnlyItsOwner() {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let firstOwner = UUID()
    let secondOwner = UUID()

    XCTAssertTrue(
      store.save(
        title: " Draft title ",
        body: "  Keep my spacing.\n",
        ownerID: firstOwner
      )
    )
    XCTAssertEqual(store.load(ownerID: firstOwner)?.title, " Draft title ")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.body, "  Keep my spacing.\n")
    XCTAssertNil(store.load(ownerID: secondOwner))
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

    let obsoleteQueue = TestStoredInboxQueue(version: 2, entries: [entry])
    defaults.set(try JSONEncoder().encode(obsoleteQueue), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)
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

  private func makeQueuedEntry(
    id: UUID = UUID(uuidString: "F4D2DF16-A506-4BE6-A63E-B7B18AFE3468")!,
    title: String? = nil,
    body: String = "A thought worth keeping."
  ) -> QueuedInboxEntry {
    QueuedInboxEntry(
      id: id,
      title: title,
      body: body,
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400)
    )
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
