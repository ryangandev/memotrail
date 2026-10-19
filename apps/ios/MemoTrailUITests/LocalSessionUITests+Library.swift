import XCTest

// Library browse and search, and First Times, signed in as the seeded account. The seed has four
// Chapters (one also a First Time), three First Times, and 21 Entries in all. Tests that run
// earlier in the same session add Entries, Chapters, and First Times, so those counts are minimums.
extension LocalSessionUITests {
  func testLibrarySearchFiltersChaptersAndFirstTimes() throws {
    let app = try launchLocalSession()
    // The Dashboard search action opens Library ready to type, over the browse list.
    XCTAssertTrue(app.buttons["workspace-search"].waitForExistence(timeout: 20))
    app.buttons["workspace-search"].tap()
    let field = app.textFields["Search Library"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(count("Entries", in: app), 21)
    attach(app, "Library browse")

    // Browse labels Chapters and First Times and leaves a plain Entry unlabeled.
    let bookshop = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Chapter · First Time, First job at the bookshop")
    ).firstMatch
    XCTAssertTrue(reveal(bookshop, in: app).exists)
    attach(app, "Library browse labels")
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Chapter, Living in Lisbon")
      ).firstMatch.exists)
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", "First Time, First sourdough loaf")
      ).firstMatch.exists)
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Sunset from the ferry, ")
      ).firstMatch.exists)
    for _ in 0..<12 where !field.isHittable { app.swipeDown(velocity: .fast) }

    // A keyword search shows why each record matched, with its formatted note: two seeded
    // titles name the coast and a third Entry is tagged with it.
    field.tap()
    field.typeText("coast\n")
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["3 Entries"].exists)
    XCTAssertTrue(text("Matched in Title", in: app).exists)
    attach(app, "Library results")
    reveal(app.buttons["Read full note"], in: app).tap()
    XCTAssertEqual(app.buttons["Read full note"].value as? String, "Expanded")
    attach(app, "Library full note")

    // Filters apply as they change and count as active.
    reveal(app.buttons["library-filters"], in: app).tap()
    reveal(app.buttons["Record"], in: app).tap()
    app.buttons["Entries"].tap()
    XCTAssertTrue(app.staticTexts["Filters · 1 active"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["3 Entries"].exists)
    attach(app, "Library filtered results")

    // A result opens its Item page, and Clear all returns to browsing.
    app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "A quiet afternoon by the coast")
    ).firstMatch.tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
    app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["library-clear-search"], in: app).tap()
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 10))

    // A Record filter alone is a search: Chapters, then First Times, with no phrase.
    reveal(app.buttons["library-filters"], in: app).tap()
    reveal(recordMenu(in: app), in: app).tap()
    app.buttons["Chapters"].tap()
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 10))
    XCTAssertGreaterThanOrEqual(count("Entries", in: app), 4)
    XCTAssertTrue(
      reveal(
        app.buttons.matching(
          NSPredicate(
            format: "label BEGINSWITH %@",
            "Chapter · First Time, First job at the bookshop")
        ).firstMatch, in: app
      ).exists)
    attach(app, "Library chapters only")
    reveal(recordMenu(in: app), in: app).tap()
    app.buttons["First Times"].tap()
    // The marathon is not a Chapter, so it shows once the First Times results replace them.
    let marathon = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "First Time, Finished the first marathon")
    ).firstMatch
    XCTAssertTrue(marathon.waitForExistence(timeout: 10))
    XCTAssertGreaterThanOrEqual(count("Entries", in: app), 3)
    XCTAssertTrue(reveal(marathon, in: app).exists)
    attach(app, "Library first times only")
  }

  func testFirstTimesListsMarkedEntriesAndAddOpensTheEditorChecked() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["more-firstTimes"], in: app).tap()
    XCTAssertTrue(app.navigationBars["First Times"].waitForExistence(timeout: 10))

    // The three marked Entries, one of them also a Chapter, and no photos on any.
    let summary = app.otherElements["First Times summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 15))
    XCTAssertGreaterThanOrEqual(count("First Times", in: summary), 3)
    XCTAssertTrue(text("0 photos", in: app).exists)
    for title in [
      "First sourdough loaf", "Finished the first marathon", "First job at the bookshop",
    ] {
      let card = app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", title + ", ")
      ).firstMatch
      XCTAssertTrue(reveal(card, in: app).exists, title)
    }
    attach(app, "First Times")

    // A card opens its Item page.
    let marathon = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Finished the first marathon, ")
    ).firstMatch
    reveal(marathon, in: app).tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
    app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()

    // Add opens the Entry editor with First Time already checked and Chapter not.
    // Add is in the page header, above the cards revealed earlier; more cards from earlier tests
    // in the run can scroll it out of the lazy list, so scroll back up to it first.
    let add = app.buttons["firsttimes-add"]
    for _ in 0..<12 where !add.exists || !add.isHittable { app.swipeDown() }
    add.tap()
    let firstTime = element("editor-first-time", in: app)
    XCTAssertTrue(firstTime.waitForExistence(timeout: 10))
    XCTAssertEqual(firstTime.value as? String, "On")
    XCTAssertEqual(element("editor-chapter", in: app).value as? String, "Off")
    attach(app, "First Times add")
    app.buttons["editor-close"].tap()
    XCTAssertTrue(app.navigationBars["First Times"].waitForExistence(timeout: 10))
    XCTAssertFalse(firstTime.exists)
  }

  /// The Record filter's menu, whose label also names the current choice once one is made.
  private func recordMenu(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Record")).firstMatch
  }
}
