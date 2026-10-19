import XCTest

// The Entry editor (P3) from an Item page. Only the first test changes seeded data: it turns
// "Notes from the farmers market", which no other test reads, into a closed Chapter, so the
// Dashboard's open Chapters stay as seeded.
extension LocalSessionUITests {
  func testEditEntryTurnsItIntoAChapterAndChecksFirstTime() throws {
    let app = try launchLocalSession()
    openEditor(for: "Notes from the farmers market", in: app)
    attach(app, "Editor opened")

    reveal(checkbox("Chapter", in: app), in: app, above: footer(app)).tap()
    reveal(checkbox("First Time", in: app), in: app, above: footer(app)).tap()
    XCTAssertEqual(checkbox("Chapter", in: app).value as? String, "On")
    XCTAssertEqual(checkbox("First Time", in: app).value as? String, "On")
    // A Chapter whose date has no end opens as still going on; ending it today closes it.
    let present = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Present"))
      .firstMatch
    reveal(present, in: app, above: footer(app))
    XCTAssertEqual(present.value as? String, "On")
    attach(app, "Editor as a Chapter")
    present.tap()
    let end = reveal(app.buttons["End date"], in: app, above: footer(app))
    XCTAssertEqual(end.value as? String, "Not set")
    end.tap()
    let done = app.buttons["date-picker-done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5))
    attach(app, "End date picker")
    done.tap()
    XCTAssertNotEqual(end.value as? String, "Not set")
    attach(app, "Editor with an end date")

    app.buttons["editor-save"].tap()
    XCTAssertTrue(text("Entry saved.", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.navigationBars["Chapter · First Time"].waitForExistence(timeout: 15))
    attach(app, "Item page as a Chapter")
  }

  func testChapterRequiresATitle() throws {
    let app = try launchLocalSession()
    openEditor(for: "Undated entry", in: app)
    XCTAssertEqual(app.textFields["editor-title"].value as? String, "Add a title")

    reveal(checkbox("Chapter", in: app), in: app, above: footer(app)).tap()
    app.buttons["editor-save"].tap()
    XCTAssertTrue(text("Give this Chapter a title.", in: app).waitForExistence(timeout: 5))
    // Nothing was saved, so the editor stays open on the same draft.
    XCTAssertTrue(app.buttons["editor-save"].exists)
    XCTAssertEqual(checkbox("Chapter", in: app).value as? String, "On")
    attach(app, "Chapter without a title")

    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
  }

  func testWebFormattedNoteStaysReadOnlyUntilChosen() throws {
    XCUIDevice.shared.appearance = .dark
    addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = .light }
    let app = try launchLocalSession()
    openEditor(for: "Weekend packing list", in: app)
    XCTAssertTrue(app.buttons["editor-edit-web-note"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.textViews["editor-body"].exists)
    attach(app, "Editor with a Web note, dark")

    app.buttons["editor-edit-web-note"].tap()
    let confirm = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Edit note here", "editor-edit-web-note")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Edit Web note confirmation, dark")
    confirm.tap()
    XCTAssertTrue(app.textViews["editor-body"].waitForExistence(timeout: 5))
    attach(app, "Editing a Web note, dark")
    reveal(checkbox("Chapter", in: app), in: app)
    attach(app, "Editor tags, photos, and marks, dark")
    reveal(element("occurrence-precision", in: app), in: app)
    app.swipeUp()
    attach(app, "Editor date, dark")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
  }

  /// Opens the Item page of a seeded Entry from Library, then its editor.
  private func openEditor(for title: String, in app: XCUIApplication) {
    XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Library"].tap()
    // Scoped to the list, since the Dashboard behind the tab keeps its recent captures.
    let list = element("library-items", in: app)
    XCTAssertTrue(list.waitForExistence(timeout: 15))
    let row = list.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15), title)
    reveal(row, in: app, above: app.tabBars.firstMatch).tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 15))
    app.buttons["item-edit"].tap()
    XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 10))
  }

  /// The editor footer, which the form scrolls under.
  private func footer(_ app: XCUIApplication) -> XCUIElement { app.buttons["editor-save"] }

  /// A checkbox, which reads as one button named by its title and detail.
  private func checkbox(_ title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title), ")).firstMatch
  }
}
