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

    // Quick Capture opens Web's full-screen composer, where Date picks a day and an optional
    // time in place.
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(app.buttons["Close quick capture"].waitForExistence(timeout: 10))
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 5))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    quick.typeText("Lanterns on the pier")
    attach(app, "Quick Capture")
    composer.buttons["rich-dismiss-keyboard"].tap()
    let dateToggle = composer.buttons["capture-date"]
    XCTAssertEqual(dateToggle.value as? String, "Off")
    dateToggle.tap()
    let day = composer.buttons["capture-date-day"]
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    XCTAssertEqual(dateToggle.value as? String, "On")
    // It starts on today, with no time until one is added.
    XCTAssertEqual(
      day.value as? String, Date().formatted(.dateTime.month(.abbreviated).day().year()))
    let time = composer.buttons["capture-date-time"]
    XCTAssertEqual(time.value as? String, "Not set")
    time.tap()
    let timeDone = app.buttons["capture-date-time-done"]
    XCTAssertTrue(timeDone.waitForExistence(timeout: 5))
    attach(app, "Quick Capture time picker")
    timeDone.tap()
    XCTAssertTrue(timeDone.waitForNonExistence(timeout: 5))
    XCTAssertNotEqual(time.value as? String, "Not set")
    attach(app, "Quick Capture day and time")
    // Clear leaves the capture time, and turning Date off closes the field.
    composer.buttons["capture-date-clear"].tap()
    XCTAssertEqual(day.value as? String, "Not set")
    dateToggle.tap()
    XCTAssertTrue(day.waitForNonExistence(timeout: 5))

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

    // The workspace header counts it, like Web's sync indicator, and opens the same list.
    let indicator = app.buttons["workspace-pending-sync"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 5))
    XCTAssertEqual(indicator.label, "Pending sync, 1 pending")
    indicator.tap()
    XCTAssertTrue(element("capture-pending-list", in: app).waitForExistence(timeout: 5))
    app.buttons["capture-pending-close"].tap()

    // Quick Capture lists it under the composer, with Retry now, and no problem in the
    // composer itself.
    app.buttons["workspace-new-entry"].tap()
    let section = element("capture-pending-section", in: app)
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    XCTAssertTrue(contains("Ferry tickets for Saturday", in: section))
    XCTAssertTrue(section.buttons["capture-pending-retry"].exists)
    XCTAssertFalse(element("capture-message", in: app).exists)
    attach(app, "Quick Capture while offline")
    app.buttons["Close quick capture"].tap()
    app.terminate()

    // Back online, the capture kept on this iPhone syncs and is announced once as saved.
    let online = try launchLocalSession()
    XCTAssertTrue(text("Saved to Library", in: online).waitForExistence(timeout: 20))
    XCTAssertFalse(text("Saved on this iPhone", in: online).exists)
    XCTAssertFalse(online.buttons["home-pending-entries"].exists)
    XCTAssertTrue(online.buttons["workspace-pending-sync"].waitForNonExistence(timeout: 5))
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
    let indicator = app.buttons["workspace-pending-sync"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 5))
    XCTAssertEqual(indicator.label, "Pending sync, 1 not accepted")
    app.buttons["workspace-new-entry"].tap()
    let section = element("capture-pending-section", in: app)
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    XCTAssertTrue(contains("Not accepted", in: section))
    // A capture MemoTrail refused is never retried, so there is nothing to retry.
    XCTAssertFalse(section.buttons["capture-pending-retry"].exists)
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
    XCTAssertFalse(app.buttons["workspace-pending-sync"].exists)
  }

  func testUnreadableCaptureIsListedWithCopyAndDiscard() throws {
    let kept = "Notes from the old phone about the lake house"
    // Dark mode here, so the Pending sync sheet is reviewed in both appearances.
    let app = try launchCaptureSession(unreadableCapture: kept, appearance: "dark")

    // A stored capture this version cannot read is counted apart and never sent.
    let indicator = app.buttons["workspace-pending-sync"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 20))
    XCTAssertEqual(indicator.label, "Pending sync, 1 unreadable")
    // The Dashboard lists it too, though nothing waits to sync, like Web's pending notice.
    let notice = app.buttons["home-pending-entries"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    XCTAssertTrue(notice.label.contains("1 saved Entry could not be read"))
    indicator.tap()
    let list = element("capture-pending-list", in: app)
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    XCTAssertTrue(text("Could not be read", in: app).exists)
    XCTAssertTrue(
      text("1 saved Entry on this iPhone could not be read; copy what you want to keep", in: app)
        .exists)
    XCTAssertTrue(
      text("this version of MemoTrail cannot read it. It is kept until you discard it.", in: app)
        .exists)
    XCTAssertTrue(text(kept, in: app).exists)
    XCTAssertFalse(app.buttons["capture-pending-retry"].exists)
    attach(app, "Unreadable capture in Pending sync in dark mode")

    // Copy text keeps what it holds. The runner does not read the pasteboard back, since iOS
    // asks the person before another app pastes.
    reveal(app.buttons["Copy the text of this saved Entry"], in: app).tap()
    XCTAssertTrue(text("Text copied.", in: app).waitForExistence(timeout: 5))

    // Discard asks first, then removes it for good.
    let discard = app.buttons["Discard this saved Entry"]
    reveal(discard, in: app).tap()
    XCTAssertTrue(text("Discard this saved Entry?", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(
      text("It will be removed from this iPhone, along with any photos it holds.", in: app).exists)
    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Discard")).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Discard unreadable capture")
    confirm.tap()
    XCTAssertTrue(text("Saved Entry discarded.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(list.waitForNonExistence(timeout: 5))
    XCTAssertTrue(indicator.waitForNonExistence(timeout: 5))
    XCTAssertFalse(notice.exists)

    // It stays gone after a relaunch.
    app.terminate()
    let relaunched = try launchCaptureSession()
    XCTAssertTrue(relaunched.buttons["workspace-new-entry"].waitForExistence(timeout: 20))
    XCTAssertFalse(relaunched.buttons["workspace-pending-sync"].waitForExistence(timeout: 3))
  }

  func testQuickCaptureOpensFocusedAndReadyToType() throws {
    let app = try launchCaptureSession(appearance: "dark")
    XCTAssertTrue(app.buttons["workspace-new-entry"].waitForExistence(timeout: 20))
    app.buttons["workspace-new-entry"].tap()

    // Typing goes straight into the note without a tap first.
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 5))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    let note = "Straight into the note \(Int(Date().timeIntervalSince1970))"
    app.typeText(note)
    XCTAssertEqual(quick.value as? String, note)
    XCTAssertEqual(composer.buttons["save-entry"].label, "Save")
    attach(app, "Quick Capture focused in dark mode")

    // Keys from a hardware keyboard reach the note too. XCUITest drops a Return typed with
    // Command before it reaches the app, so CaptureComposerKeyboardTests covers that shortcut.
    quick.typeKey("!", modifierFlags: [])
    XCTAssertEqual(quick.value as? String, note + "!")
    composer.buttons["save-entry"].tap()
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("Saved to Library", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(text(note + "!", in: app).waitForExistence(timeout: 15))
    attach(app, "Saved from Quick Capture in dark mode")
  }

  /// Whether any element inside `container` has a label containing `label`.
  func contains(_ label: String, in container: XCUIElement) -> Bool {
    container.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.exists
  }

  /// Like `launchLocalSession`, and can start with a stored capture this version cannot read,
  /// or in a chosen appearance.
  func launchCaptureSession(unreadableCapture: String? = nil, appearance: String? = nil) throws
    -> XCUIApplication
  {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard !path.isEmpty else {
      throw XCTSkip("Run apps/ios/scripts/review-local-session.py with the local Supabase stack.")
    }
    let app = XCUIApplication()
    app.launchArguments = ["--review-local-session"]
    if let appearance { app.launchArguments += ["-native-appearance", appearance] }
    app.launchEnvironment["MEMOTRAIL_REVIEW_SESSION"] = path
    if let unreadableCapture {
      app.launchEnvironment["MEMOTRAIL_REVIEW_UNREADABLE_CAPTURE"] = unreadableCapture
    }
    app.launch()
    return app
  }
}

