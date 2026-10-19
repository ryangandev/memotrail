import XCTest

// Carried over for P7 (Library and First Times), which owns and verifies it. P1 replaced the
// retired Goal record and Version history with the seeded Entries and the Item page.
extension LocalSessionUITests {
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

    // A keyword search shows why each record matched, with its formatted note: two seeded
    // titles name the coast and a third Entry is tagged with it.
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
    app.buttons["Entries"].tap()
    XCTAssertTrue(app.staticTexts["Filters · 1 active"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["3 items"].exists)
    attach(app, "Library filtered results")

    // A result opens its Item page, and Clear all returns to browsing.
    app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "A quiet afternoon by the coast")
    ).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
    app.navigationBars["Entry"].buttons.element(boundBy: 0).tap()
    reveal(app.buttons["library-clear-search"], in: app).tap()
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 10))
  }
}
