import XCTest

// The Dashboard, signed in as the seeded account: a Chapter in progress (Living on Maple
// Street), First Times, tags, and recent captures.
extension LocalSessionUITests {
  func testDashboardShowsGreetingCountsNowAndRecentEntries() throws {
    let app = try launchLocalSession()

    // The greeting uses the preferred name from the profile, not the sign-in name.
    XCTAssertTrue(text(", Review.", in: app).waitForExistence(timeout: 20))
    XCTAssertTrue(
      text("A calm view of what is going on and what you have kept.", in: app).exists)
    XCTAssertTrue(element("dashboard-counts", in: app).waitForExistence(timeout: 15))
    // At least what the seed holds: 21 Entries, 3 First Times, and 8 tags.
    XCTAssertGreaterThanOrEqual(try dashboardCount("Entries kept", in: app), 21)
    XCTAssertGreaterThanOrEqual(try dashboardCount("First Times", in: app), 3)
    XCTAssertGreaterThanOrEqual(try dashboardCount("Tags", in: app), 8)
    XCTAssertGreaterThanOrEqual(try dashboardCount("Going on now", in: app), 1)
    attach(app, "Dashboard top")

    // Now lists the open Chapter with its span and an honest length.
    let now = reveal(element("dashboard-now", in: app), in: app)
    XCTAssertTrue(now.waitForExistence(timeout: 10))
    let chapter = now.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Living on Maple Street")
    ).firstMatch
    XCTAssertTrue(chapter.waitForExistence(timeout: 5))
    XCTAssertTrue(chapter.label.contains("Since Jun 1, 2024"), chapter.label)
    XCTAssertTrue(chapter.label.contains("year"), chapter.label)

    // A memory for today is either an older Entry or an invitation to keep writing.
    XCTAssertTrue(reveal(element("dashboard-memory", in: app), in: app).exists)
    attach(app, "Dashboard memory and Now")

    // Recent Entries name an untitled Entry by its date, without repeating the date beside it.
    let recent = reveal(element("dashboard-recent", in: app), in: app)
    XCTAssertTrue(recent.waitForExistence(timeout: 10))
    let rows = recent.buttons
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertLessThanOrEqual(rows.count, 5)
    // Other tests in a run can save newer Entries, so this row is checked when it is listed.
    let untitled = rows.matching(
      NSPredicate(format: "label CONTAINS %@", "Waiting for a little context")
    ).firstMatch
    if untitled.exists {
      XCTAssertTrue(untitled.label.contains("Undated entry"), untitled.label)
    }
    attach(app, "Dashboard recent entries")

    // A row opens the Entry's page.
    rows.firstMatch.tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
  }

  func testDashboardCountsOpenTheirDestinations() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(element("dashboard-counts", in: app).waitForExistence(timeout: 20))

    // Entries kept opens Library.
    try dashboardCountButton("Entries kept", in: app).tap()
    XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)

    // Going on now opens Timeline.
    app.tabBars.buttons["Dashboard"].tap()
    try dashboardCountButton("Going on now", in: app).tap()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].isSelected)

    // First Times and Tags open from More, like Web's routes.
    app.tabBars.buttons["Dashboard"].tap()
    try dashboardCountButton("First Times", in: app).tap()
    XCTAssertTrue(app.navigationBars["First Times"].waitForExistence(timeout: 10))
    app.tabBars.buttons["Dashboard"].tap()
    try dashboardCountButton("Tags", in: app).tap()
    XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 10))
  }

  /// The number in a count button such as "21 Entries kept".
  private func dashboardCount(_ name: String, in app: XCUIApplication) throws -> Int {
    let label = try dashboardCountButton(name, in: app).label
    return try XCTUnwrap(Int(label.prefix(while: \.isNumber)), label)
  }

  private func dashboardCountButton(_ name: String, in app: XCUIApplication) throws
    -> XCUIElement
  {
    let button = app.buttons.matching(
      NSPredicate(format: "label MATCHES %@", "[0-9]+ \(name)")
    ).firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 15), name)
    return button
  }
}
