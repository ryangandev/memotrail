import UIKit
import XCTest

// Carried over from the Inbox flows for P2 (Capture), which owns and verifies them. P1 moved
// them off the retired Inbox tab: captures now land in Library and wait in Pending sync.
extension LocalSessionUITests {
  func testCaptureSavesAFormattedNoteToLibrary() throws {
    let app = try launchLocalSession()
    let editor = app.textViews["capture-body"]
    XCTAssertTrue(editor.waitForExistence(timeout: 20))
    reveal(editor, in: app).tap()
    app.buttons["rich-format-toggle"].tap()
    app.buttons["rich-format-bold"].tap()
    editor.typeText("Harbor lights")
    app.buttons["rich-format-bold"].tap()
    editor.typeText(" after the storm")
    attach(app, "Formatted capture")
    app.buttons["rich-dismiss-keyboard"].tap()
    XCTAssertTrue(app.staticTexts["Draft saved on this iPhone."].waitForExistence(timeout: 5))
    app.buttons["save-entry"].tap()
    XCTAssertTrue(text("Saved to Library", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(text("Harbor lights after the storm", in: app).waitForExistence(timeout: 15))
    XCTAssertEqual(editor.value as? String ?? "", "")
    attach(app, "Saved formatted capture")

    // Quick Capture opens Web's full-screen composer, with the relevant date in place.
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(app.buttons["Close quick capture"].waitForExistence(timeout: 10))
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 5))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    quick.typeText("Lanterns on the pier")
    attach(app, "Quick Capture")
    composer.buttons["rich-dismiss-keyboard"].tap()
    composer.buttons["capture-date"].tap()
    let captureTime = composer.buttons["Use capture time"]
    XCTAssertTrue(captureTime.waitForExistence(timeout: 5))
    XCTAssertEqual(composer.buttons["capture-date"].label, "Custom date")
    attach(app, "Quick Capture relevant date")
    captureTime.tap()
    XCTAssertTrue(captureTime.waitForNonExistence(timeout: 5))

    // Saving closes it and announces the capture once, after it lands in Library.
    composer.buttons["save-entry"].tap()
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("Saved to Library", in: app).waitForExistence(timeout: 15))
    XCTAssertFalse(text("Saved on this iPhone", in: app).exists)
    attach(app, "Quick Capture saved")
  }

  func testOfflineQuickCaptureIsConfirmedOnceAndSyncsWhenOnline() throws {
    let app = try launchLocalSession(offline: true)
    XCTAssertTrue(app.buttons["workspace-new-entry"].waitForExistence(timeout: 20))
    app.buttons["workspace-new-entry"].tap()
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 10))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    quick.typeText("Ferry tickets for Saturday")
    composer.buttons["rich-dismiss-keyboard"].tap()
    composer.buttons["save-entry"].tap()

    // Without a connection, saving closes Quick Capture and confirms once that the capture is
    // safe on this iPhone, then Pending sync shows it waiting.
    let stored = text("Saved on this iPhone. MemoTrail will sync when you are online.", in: app)
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(stored.waitForExistence(timeout: 10))
    XCTAssertFalse(text("Saved to Library", in: app).exists)
    reveal(app.buttons["home-pending-entries"], in: app).tap()
    XCTAssertTrue(text("Ferry tickets for Saturday", in: app).waitForExistence(timeout: 5))
    attach(app, "Offline capture confirmed")

    // Retrying while still offline announces nothing again, as a toast or in the composer.
    XCTAssertTrue(stored.waitForNonExistence(timeout: 10))
    app.buttons["capture-pending-retry"].tap()
    Thread.sleep(forTimeInterval: 2)
    XCTAssertFalse(stored.exists)
    app.buttons["capture-pending-close"].tap()
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(text("1 Entry waiting to sync", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("capture-message", in: app).exists)
    attach(app, "Quick Capture while offline")
    app.buttons["Close quick capture"].tap()
    app.terminate()

    // Back online, the capture kept on this iPhone syncs and is announced once as saved.
    let online = try launchLocalSession()
    XCTAssertTrue(text("Saved to Library", in: online).waitForExistence(timeout: 20))
    XCTAssertFalse(text("Saved on this iPhone", in: online).exists)
    XCTAssertFalse(online.buttons["home-pending-entries"].exists)
    attach(online, "Offline capture synced")
  }

  func testRefusedQuickCaptureIsKeptWithCopyAndDiscard() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.buttons["workspace-new-entry"].waitForExistence(timeout: 20))
    app.buttons["workspace-new-entry"].tap()
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 10))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

    // Text pasted from a terminal can carry a NUL character, which Postgres text cannot store,
    // so MemoTrail refuses this capture on every attempt.
    let pasted = "Pasted from a terminal \u{0000} log"
    UIPasteboard.general.string = pasted
    quick.press(forDuration: 1.2)
    let pasteMenuItem = app.menuItems["Paste"]
    let pasteButton = app.buttons["Paste"]
    let deadline = Date().addingTimeInterval(5)
    while !pasteMenuItem.exists, !pasteButton.exists, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.25)
    }
    (pasteMenuItem.exists ? pasteMenuItem : pasteButton).tap()
    composer.buttons["rich-dismiss-keyboard"].tap()
    composer.buttons["save-entry"].tap()

    // It is announced as refused, never as offline, and waits in Pending sync with why.
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(
      text("MemoTrail did not accept 1 Entry. Review it in Pending sync.", in: app)
        .waitForExistence(timeout: 15))
    XCTAssertFalse(text("Saved on this iPhone", in: app).exists)
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(text("1 Entry not accepted", in: app).waitForExistence(timeout: 10))
    attach(app, "Quick Capture with a refused capture")
    app.buttons["Close quick capture"].tap()

    reveal(app.buttons["home-pending-entries"], in: app).tap()
    XCTAssertTrue(text("Not accepted", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(text("MemoTrail cannot accept this Entry, so it will not sync.", in: app).exists)
    XCTAssertFalse(app.buttons["capture-pending-retry"].exists)
    attach(app, "Refused capture in Pending sync")

    let copy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Copy the text of"))
      .firstMatch
    reveal(copy, in: app).tap()
    XCTAssertTrue(text("Text copied.", in: app).waitForExistence(timeout: 5))

    // Discard asks first, then removes the capture from this iPhone.
    let discard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard "))
      .firstMatch
    reveal(discard, in: app).tap()
    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Discard")).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertTrue(text("Discard this pending Entry?", in: app).exists)
    attach(app, "Discard refused capture")
    confirm.tap()
    XCTAssertTrue(text("Pending Entry discarded.", in: app).waitForExistence(timeout: 10))
    // Pending sync closes once nothing is left, like Web.
    XCTAssertTrue(element("capture-pending-list", in: app).waitForNonExistence(timeout: 5))
    XCTAssertFalse(app.buttons["home-pending-entries"].exists)
  }
}
