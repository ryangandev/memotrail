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
