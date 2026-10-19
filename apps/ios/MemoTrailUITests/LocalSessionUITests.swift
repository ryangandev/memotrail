import UIKit
import XCTest

/// Runs signed in as the seeded, disposable local account that
/// `apps/ios/scripts/review-local-session.py` creates and removes.
@MainActor
final class LocalSessionUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  func testSeededArchiveAcrossPrimaryTabs() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(text("Review", in: app).waitForExistence(timeout: 20))
    attach(app, "Dashboard")
    // The avatar in the shared header opens Settings, like the Web header.
    app.buttons["workspace-settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    attach(app, "Settings from the header")
    app.navigationBars["Settings"].buttons["Done"].tap()
    // Other tests organize or trash the remaining seeded captures, but none removes this one.
    for (tab, expected) in [
      ("Inbox", "Weekend packing list"), ("Timeline", "Finished the first marathon"),
      ("Library", "Grandmother's recipe cards"),
    ] {
      app.tabBars.buttons[tab].tap()
      if tab == "Timeline" {
        dismissBirthDatePrompt(
          once: app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", expected)
          ).firstMatch, in: app)
      }
      XCTAssertTrue(text(expected, in: app).waitForExistence(timeout: 15), tab)
      // Each tab's header keeps New entry beside the mark, like Web's phone header.
      XCTAssertTrue(app.buttons["workspace-new-entry"].isHittable, tab)
      attach(app, tab)
    }
    app.tabBars.buttons["More"].tap()
    // More groups its destinations like Web's mobile More menu.
    for group in ["Explore", "Focused views", "Organize", "Archive and account"] {
      XCTAssertTrue(app.staticTexts[group].waitForExistence(timeout: 5), group)
    }
    attach(app, "More")
    // The header mark opens the Dashboard, like Web's brand link.
    app.buttons["workspace-brand"].tap()
    XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
    app.tabBars.buttons["More"].tap()
    for route in [
      "Map", "People", "Homes", "Vehicles", "First Times", "Goals", "Collections", "Tags",
      "Version history", "Trash", "Settings",
    ] {
      reveal(app.buttons[route], in: app).tap()
      Thread.sleep(forTimeInterval: 1.5)
      attach(app, route)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
  }

  func testDashboardRibbonSectionsAndLinksOpenTheirRecords() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.otherElements["home-data-ribbon"].waitForExistence(timeout: 20))
    attach(app, "Dashboard top")

    // The ribbon opens its area, including More destinations.
    app.buttons["2 Collections"].tap()
    XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Dashboard"].tap()

    // Ready to organize opens that capture's review in Inbox.
    reveal(app.buttons["Organize Notes from the farmers market"], in: app).tap()
    XCTAssertTrue(app.staticTexts["Review Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Peaches, basil", in: app).exists)
    attach(app, "Review opened from Dashboard")
    app.buttons["close-entry-review"].tap()
    app.tabBars.buttons["Dashboard"].tap()
    attach(app, "Dashboard Inbox and memory")

    // A current chapter opens its Timeline record.
    reveal(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HOMES")).firstMatch, in: app
    )
    .tap()
    XCTAssertTrue(app.staticTexts["Edit Home"].waitForExistence(timeout: 10))
    app.buttons["close-home-editor"].tap()
    app.tabBars.buttons["Dashboard"].tap()

    // A recent Entry opens its canonical record.
    let goal = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Hike the coast trail")
    )
    .firstMatch
    reveal(goal, in: app)
    attach(app, "Dashboard recent Entries")
    goal.tap()
    XCTAssertTrue(app.navigationBars["Goal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-goal"].exists)
    attach(app, "Recent Entry destination")
  }

  func testCaptureSavesAFormattedNoteToTheInbox() throws {
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
    XCTAssertTrue(text("Saved to Inbox", in: app).waitForExistence(timeout: 15))
    let row = app.buttons["Organize Harbor lights after the storm"]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    XCTAssertEqual(editor.value as? String ?? "", "")
    attach(app, "Saved formatted capture")

    // Quick Capture opens Web's full-screen composer, with the relevant date in place.
    app.tabBars.buttons["Inbox"].tap()
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

    // Saving closes it and announces the capture once, after it lands in the Inbox.
    composer.buttons["save-entry"].tap()
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("Saved to Inbox", in: app).waitForExistence(timeout: 15))
    XCTAssertFalse(text("Saved on this iPhone", in: app).exists)
    XCTAssertTrue(app.buttons["Organize Lanterns on the pier"].waitForExistence(timeout: 15))
    attach(app, "Quick Capture saved")

    // Keep the seeded captures as the Dashboard's newest three for the other tests.
    app.buttons["Move Lanterns on the pier to Trash"].tap()
    app.buttons["Move to Trash"].tap()
    XCTAssertTrue(text("Capture moved to Trash.", in: app).waitForExistence(timeout: 10))
  }

  func testOfflineQuickCaptureIsConfirmedOnceAndSyncsWhenOnline() throws {
    let app = try launchLocalSession(offline: true)
    XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Inbox"].tap()
    app.buttons["workspace-new-entry"].tap()
    let composer = try quickCapture(in: app)
    let quick = composer.textViews["capture-body"]
    XCTAssertTrue(quick.waitForExistence(timeout: 10))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    quick.typeText("Ferry tickets for Saturday")
    composer.buttons["rich-dismiss-keyboard"].tap()
    composer.buttons["save-entry"].tap()

    // Without a connection, saving closes Quick Capture and confirms once that the capture is
    // safe on this iPhone, then the Inbox shows it waiting to sync.
    let stored = text("Saved on this iPhone. MemoTrail will sync when you are online.", in: app)
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(stored.waitForExistence(timeout: 10))
    XCTAssertFalse(text("Saved to Inbox", in: app).exists)
    XCTAssertTrue(text("Ferry tickets for Saturday", in: app).waitForExistence(timeout: 5))
    attach(app, "Offline capture confirmed")

    // Retrying while still offline announces nothing again, as a toast or in the composer.
    XCTAssertTrue(stored.waitForNonExistence(timeout: 10))
    // SwiftUI propagates the pending section's identifier to its children; use the visible
    // action label to find the retry button and to confirm it disappears after sync.
    reveal(app.buttons["Retry now"], in: app).tap()
    Thread.sleep(forTimeInterval: 2)
    XCTAssertFalse(stored.exists)
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(text("1 Entry waiting to sync", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("capture-message", in: app).exists)
    attach(app, "Quick Capture while offline")
    app.buttons["Close quick capture"].tap()
    app.terminate()

    // Back online, the capture kept on this iPhone syncs and is announced once as saved.
    let online = try launchLocalSession()
    XCTAssertTrue(text("Saved to Inbox", in: online).waitForExistence(timeout: 20))
    XCTAssertFalse(text("Saved on this iPhone", in: online).exists)
    online.tabBars.buttons["Inbox"].tap()
    let row = online.buttons["Organize Ferry tickets for Saturday"]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    XCTAssertFalse(online.buttons["Retry now"].exists)
    attach(online, "Offline capture synced")

    // Keep the seeded captures as the Dashboard's newest three for the other tests.
    online.buttons["Move Ferry tickets for Saturday to Trash"].tap()
    online.buttons["Move to Trash"].tap()
    XCTAssertTrue(text("Capture moved to Trash.", in: online).waitForExistence(timeout: 10))
  }

  func testRefusedQuickCaptureIsKeptWithCopyAndDiscard() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Inbox"].tap()
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

    // It is announced as refused, never as offline, and waits in the Inbox with why.
    XCTAssertTrue(app.buttons["Close quick capture"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(
      text("MemoTrail did not accept 1 Entry. Review it in your Inbox.", in: app)
        .waitForExistence(timeout: 15))
    XCTAssertFalse(text("Saved on this iPhone", in: app).exists)
    XCTAssertTrue(text("Not accepted", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(text("MemoTrail cannot accept this Entry, so it will not sync.", in: app).exists)
    XCTAssertFalse(app.buttons["Retry now"].exists)
    attach(app, "Refused capture in Pending sync")
    app.buttons["workspace-new-entry"].tap()
    XCTAssertTrue(text("1 Entry not accepted", in: app).waitForExistence(timeout: 10))
    attach(app, "Quick Capture with a refused capture")
    app.buttons["Close quick capture"].tap()

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
    XCTAssertTrue(text("Not accepted", in: app).waitForNonExistence(timeout: 5))
    XCTAssertFalse(app.otherElements["inbox-pending-entries"].exists)
  }

  func testExportPreparesDownloadsAndDiscardsASnapshot() throws {
    try XCTSkipUnless(servesMediaAPI(), "Export needs the local Web API; run with --web.")
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Settings"], in: app).tap()
    reveal(app.buttons["Export archive"], in: app).tap()
    XCTAssertTrue(
      text("No snapshots yet. Your archive is unchanged.", in: app).waitForExistence(timeout: 15))
    attach(app, "Export")

    // Prepare snapshot captures one consistent copy, which downloads as a complete ZIP.
    app.buttons["Prepare snapshot"].tap()
    XCTAssertTrue(text("Snapshot prepared.", in: app).waitForExistence(timeout: 30))
    let download = app.buttons["Download ZIP"]
    XCTAssertTrue(download.waitForExistence(timeout: 15))
    reveal(download, in: app).tap()
    let share = app.buttons["Save or share ZIP"]
    XCTAssertTrue(share.waitForExistence(timeout: 60))
    attach(app, "Export ZIP ready")
    app.buttons["Remove local copy"].tap()
    XCTAssertTrue(share.waitForNonExistence(timeout: 5))

    // Discard asks beside the snapshot, then removes the temporary copy.
    reveal(app.buttons["Discard snapshot"], in: app).tap()
    let confirm = app.buttons["Confirm discard"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Export discard confirmation")
    confirm.tap()
    XCTAssertTrue(text("Temporary copy discarded.", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(
      text("No snapshots yet. Your archive is unchanged.", in: app).waitForExistence(timeout: 15))
  }

  func testLibrarySearchFiltersAndOpensRecords() throws {
    let app = try launchLocalSession()
    // The Dashboard search action opens Library ready to type, over the browse list.
    XCTAssertTrue(app.buttons["workspace-search"].waitForExistence(timeout: 20))
    app.buttons["workspace-search"].tap()
    let field = app.textFields["Search your Life Wiki"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    attach(app, "Library browse")

    // A keyword search shows why each record matched, with its formatted note.
    field.typeText("coast\n")
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["3 items"].exists)
    XCTAssertTrue(text("Matched in Title", in: app).exists)
    attach(app, "Library results")
    reveal(app.buttons["Read full note"], in: app).tap()
    XCTAssertEqual(app.buttons["Read full note"].value as? String, "Expanded")
    attach(app, "Library full note")

    // Filters apply as they change and count as active.
    reveal(app.buttons["library-filters"], in: app).tap()
    reveal(app.buttons["Record"], in: app).tap()
    app.buttons["Goals"].tap()
    XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Filters · 1 active"].exists)
    attach(app, "Library filtered results")

    // A result opens its record, and Clear all returns to browsing.
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Goal, Hike the coast trail"))
      .firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Goal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-goal"].waitForExistence(timeout: 10))
    app.navigationBars["Goal"].buttons.element(boundBy: 0).tap()
    reveal(app.buttons["library-clear-search"], in: app).tap()
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 10))
    XCTAssertEqual(field.value as? String, "A phrase, date, or question about your life...")

    reveal(app.buttons["library-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
  }

  func testSettingsSavesThePreferredNameForTheGreeting() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(text("Review.", in: app).waitForExistence(timeout: 20))
    app.buttons["workspace-settings"].tap()
    let field = app.textFields["settings-preferred-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertEqual(field.value as? String, "Review Tester")
    XCTAssertFalse(app.buttons["Save name"].isEnabled)
    attach(app, "Settings")

    // Each setting saves on its own once it changes, like Web.
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 13) + "  River  ")
    app.buttons["Save name"].tap()
    XCTAssertTrue(text("Preferred name saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertEqual(field.value as? String, "River")
    XCTAssertFalse(app.buttons["Save name"].isEnabled)
    attach(app, "Preferred name saved")

    reveal(app.buttons["Save time zone"], in: app)
    attach(app, "Settings preferences")
    reveal(text("Private by default", in: app), in: app)
    attach(app, "Settings end")

    // The Dashboard greeting follows the saved name.
    app.navigationBars["Settings"].buttons["Done"].tap()
    XCTAssertTrue(text("River.", in: app).waitForExistence(timeout: 10))
  }

  /// Summary rows wrap at large text sizes without a separator at either end of a line, like Web.
  func testSummaryRowsKeepSeparatorsBetweenFactsAtLargeTextSizes() throws {
    for size in ["UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityL"] {
      let app = try launchLocalSession(contentSize: size)
      XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))
      app.tabBars.buttons["Timeline"].tap()
      dismissBirthDatePrompt(
        once: app.buttons.matching(
          NSPredicate(format: "label BEGINSWITH %@", "Finished the first marathon")
        ).firstMatch, in: app)
      let timeline = app.otherElements["Timeline summary"]
      XCTAssertTrue(timeline.waitForExistence(timeout: 5))
      let lines = assertSeparatorsBetweenFacts(revealWhole(timeline, in: app), in: app)
      XCTAssertGreaterThan(lines.count, 1, "\(lines)")
      attach(app, "Timeline summary at \(size)")
      app.tabBars.buttons["More"].tap()
      for route in ["People", "Homes", "Vehicles", "First Times", "Goals"] {
        reveal(app.buttons[route], in: app).tap()
        let summary = app.otherElements["\(route) summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), route)
        assertSeparatorsBetweenFacts(revealWhole(summary, in: app), in: app)
        attach(app, "\(route) summary at \(size)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
      }
      app.terminate()
    }
  }

  func testTagsFindPreviewMergeAddAndDeleteTags() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Tags"], in: app).tap()
    let coast = app.buttons["Manage tag coast, used by 2 Entries"]
    XCTAssertTrue(coast.waitForExistence(timeout: 15))
    let family = app.buttons["Manage tag family, used by 2 Entries"]
    XCTAssertTrue(family.exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Tags")

    // Search narrows the badges by name.
    let search = app.textFields["Find a tag"]
    search.tap()
    search.typeText("coa\n")
    XCTAssertTrue(family.waitForNonExistence(timeout: 10))
    XCTAssertTrue(coast.exists)
    attach(app, "Tags search")
    app.buttons["Clear find a tag"].tap()
    app.buttons["Search"].tap()
    XCTAssertTrue(family.waitForExistence(timeout: 10))

    // A tag's editor lists the Entries using it, and each opens its Item.
    coast.tap()
    XCTAssertTrue(app.staticTexts["Edit Tag"].waitForExistence(timeout: 5))
    XCTAssertTrue(text("Used by 2 Entries", in: app).exists)
    let quiet = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "A quiet afternoon by the coast")
    ).firstMatch
    XCTAssertTrue(quiet.waitForExistence(timeout: 10))
    attach(app, "Tag editor")
    quiet.tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-item"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Merging keeps every assignment on the destination tag.
    XCTAssertTrue(family.waitForExistence(timeout: 10))
    family.tap()
    reveal(app.buttons["Destination tag"], in: app).tap()
    app.buttons["#coast (2)"].tap()
    reveal(app.buttons["merge-tag"], in: app).tap()
    let merge = app.buttons["Merge tags"]
    XCTAssertTrue(merge.waitForExistence(timeout: 5))
    attach(app, "Tag merge confirmation")
    merge.tap()
    XCTAssertTrue(text("Tags merged.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(family.waitForNonExistence(timeout: 10))
    let merged = app.buttons["Manage tag coast, used by 3 Entries"]
    XCTAssertTrue(merged.waitForExistence(timeout: 10))

    // New Tag creates an unused tag, which can then be deleted.
    app.buttons["new-tag"].tap()
    let name = app.textFields["organization-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Create a Tag"].exists)
    name.tap()
    name.typeText("sunsets")
    attach(app, "New Tag")
    app.buttons["save-organization"].tap()
    XCTAssertTrue(text("Tag created.", in: app).waitForExistence(timeout: 10))
    let sunsets = app.buttons["Manage tag sunsets, used by 0 Entries"]
    XCTAssertTrue(sunsets.waitForExistence(timeout: 10))
    sunsets.tap()
    XCTAssertTrue(text("No Entries use this tag yet.", in: app).waitForExistence(timeout: 5))
    app.buttons["remove-organization"].tap()
    let delete = app.buttons["Delete tag"]
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertTrue(text("Tag deleted.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(sunsets.waitForNonExistence(timeout: 10))

    // View all Entries opens Library filtered to the tag, like Web `/library?tag=`.
    merged.tap()
    reveal(app.buttons["view-tag-entries"], in: app, above: app.buttons["save-organization"]).tap()
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["3 items"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Filters · 1 active", in: app).exists)
    attach(app, "Library filtered to a tag")
  }

  func testTimelineStartsFromTheBirthDateAndAddsEditsAndTrashesMoments() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Timeline"].tap()
    XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Birth date prompt")
    app.buttons["Not now"].tap()
    XCTAssertTrue(app.buttons["timeline-set-birth-date"].waitForExistence(timeout: 5))
    // The range ends a padded stretch after today, so only its start is fixed.
    XCTAssertTrue(text("2019 to", in: app).exists)
    attach(app, "Timeline")

    // Set birth date saves the profile and starts the range there.
    app.buttons["timeline-set-birth-date"].tap()
    app.buttons["Birth date, required"].tap()
    // The calendar's month and year header opens the month and year wheels.
    let header = app.datePickers.buttons["DatePicker.Show"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    header.tap()
    // The calendar opens on today's month, so both wheels move.
    let year = app.pickerWheels.element(boundBy: 1)
    XCTAssertTrue(year.waitForExistence(timeout: 5))
    app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "September")
    year.adjust(toPickerWheelValue: "1994")
    app.datePickers.buttons["DatePicker.Hide"].tap()
    app.datePickers.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "September 18"))
      .firstMatch.tap()
    app.buttons["date-picker-done"].tap()
    attach(app, "Birth date chosen")
    app.buttons["timeline-save-birth-date"].tap()
    XCTAssertTrue(text("Birth date saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["timeline-set-birth-date"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(text("1994 to", in: app).exists)

    // Add moment asks what to add, then saves a Moment to the first track.
    app.buttons["add-timeline-moment"].tap()
    XCTAssertTrue(app.staticTexts["What are you adding?"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Type chooser")
    app.buttons["timeline-type-moment"].tap()
    let title = app.textFields["timeline-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("First ski day")
    attach(app, "New moment")
    app.swipeUp()
    attach(app, "New moment notes and organization")
    app.buttons["save-timeline-moment"].tap()
    XCTAssertTrue(text("Moment created.", in: app).waitForExistence(timeout: 10))
    let moment = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "First ski day")
    ).firstMatch
    XCTAssertTrue(moment.waitForExistence(timeout: 10))
    attach(app, "Moment on its track")

    // The moment reopens for editing and moves to Trash.
    moment.tap()
    XCTAssertTrue(app.staticTexts["Edit moment"].waitForExistence(timeout: 5))
    reveal(app.buttons["trash-timeline-moment"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Move to Trash", "trash-timeline-moment")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Moment trash confirmation")
    confirm.tap()
    XCTAssertTrue(text("Moment moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(moment.waitForNonExistence(timeout: 10))

    // Manage tracks creates a track that the Timeline shows on return.
    app.buttons["manage-timeline-tracks"].tap()
    XCTAssertTrue(app.staticTexts["Timeline tracks"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.otherElements["Edit Education"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Default · 2 moments", in: app).exists)
    attach(app, "Timeline tracks")
    app.buttons["add-timeline-track"].tap()
    let name = app.textFields["Name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Travel")
    attach(app, "New track")
    app.buttons["create-timeline-track"].tap()
    XCTAssertTrue(text("Track created.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.otherElements["Edit Travel"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(reveal(app.staticTexts["Travel"], in: app).waitForExistence(timeout: 10))
    attach(app, "Timeline with the new track")
  }

  func testTrashRestoresDeletesForeverAndEmptiesTrash() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()

    // Two new Collections move to Trash, so Trash has its own items to restore and delete.
    reveal(app.buttons["Collections"], in: app).tap()
    for name in ["Old drafts", "Spare room"] { createAndTrashCollection(name, in: app) }
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Trash"], in: app).tap()
    let restore = app.buttons["Restore Old drafts"]
    XCTAssertTrue(restore.waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Trash")
    reveal(restore, in: app).tap()
    XCTAssertTrue(text("Item restored.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(restore.waitForNonExistence(timeout: 10))

    // Delete forever asks first, then removes only that item.
    let delete = app.buttons["Delete Spare room forever"]
    reveal(delete, in: app).tap()
    XCTAssertTrue(app.staticTexts["Delete “Spare room” forever?"].waitForExistence(timeout: 5))
    attach(app, "Delete forever confirmation")
    app.buttons["confirm-delete-forever"].tap()
    XCTAssertTrue(text("Item permanently deleted.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(delete.waitForNonExistence(timeout: 10))

    // The restored Collection is back, and Empty Trash removes it for good with the rest.
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Collections"], in: app).tap()
    XCTAssertTrue(app.buttons["Edit Old drafts"].waitForExistence(timeout: 15))
    trashCollection("Old drafts", in: app)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Trash"], in: app).tap()
    XCTAssertTrue(app.buttons["Restore Old drafts"].waitForExistence(timeout: 15))
    while !app.buttons["empty-trash"].isHittable { app.swipeDown() }
    app.buttons["empty-trash"].tap()
    let confirm = app.buttons["confirm-empty-trash"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    attach(app, "Empty Trash confirmation")
    confirm.tap()
    let emptied = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", "^[0-9]+ confirmed items? permanently deleted\\..*")
    ).firstMatch
    XCTAssertTrue(emptied.waitForExistence(timeout: 30))
    XCTAssertTrue(text("Nothing in Trash", in: app).waitForExistence(timeout: 10))
    attach(app, "Empty Trash")
  }

  /// Timeline asks for the birth date on the first visit until one is saved, like Web. The
  /// Timeline test saves one for the shared seeded account, so later tests find no prompt.
  private func dismissBirthDatePrompt(once loaded: XCUIElement, in app: XCUIApplication) {
    let notNow = app.buttons["Not now"]
    let deadline = Date().addingTimeInterval(15)
    while !notNow.exists, !loaded.exists, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.25)
    }
    // The prompt opens once the profile and the Timeline have both loaded.
    if notNow.exists || notNow.waitForExistence(timeout: 3) { notNow.tap() }
    XCTAssertTrue(loaded.waitForExistence(timeout: 5))
  }

  /// `offline` fails every request once the session is open, like an iPhone with no network.
  /// `contentSize` names a text size category, such as `UICTContentSizeCategoryAccessibilityL`.
  private func launchLocalSession(offline: Bool = false, contentSize: String? = nil) throws
    -> XCUIApplication
  {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard !path.isEmpty else {
      throw XCTSkip("Run apps/ios/scripts/review-local-session.py with the local Supabase stack.")
    }
    let app = XCUIApplication()
    app.launchArguments = ["--review-local-session"] + (offline ? ["--review-offline"] : [])
    if let contentSize {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
    }
    app.launchEnvironment["MEMOTRAIL_REVIEW_SESSION"] = path
    app.launch()
    return app
  }

  /// Whether `review-local-session.py --web` serves the Web media API for this run.
  private func servesMediaAPI() -> Bool {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard let data = FileManager.default.contents(atPath: path),
      let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return session["apiURL"] is String
  }

  // A retained Dashboard composer can remain in the accessibility tree under the cover.
  // Select the smallest container with both the modal close action and its note editor.
  private func quickCapture(in app: XCUIApplication) throws -> XCUIElement {
    let containers = app.otherElements
      .containing(.button, identifier: "close-quick-capture")
      .containing(.textView, identifier: "capture-body")
      .allElementsBoundByIndex
    let composer = try XCTUnwrap(containers.last)
    XCTAssertEqual(composer.textViews.matching(identifier: "capture-body").count, 1)
    return composer
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }
}
