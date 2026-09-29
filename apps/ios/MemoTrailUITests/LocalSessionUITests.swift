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
    for (tab, expected) in [
      ("Inbox", "Notes from the farmers market"), ("Timeline", "Finished the first marathon"),
      ("Library", "Grandmother's recipe cards"),
    ] {
      app.tabBars.buttons[tab].tap()
      XCTAssertTrue(text(expected, in: app).waitForExistence(timeout: 15), tab)
      attach(app, tab)
    }
    app.tabBars.buttons["More"].tap()
    for route in ["Homes", "Vehicles", "First Times", "Goals", "Collections", "Tags", "Settings"] {
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
    XCTAssertTrue(app.navigationBars["Organize Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Peaches, basil", in: app).exists)
    attach(app, "Review opened from Dashboard")
    app.navigationBars["Organize Entry"].buttons["Cancel"].tap()
    app.tabBars.buttons["Dashboard"].tap()
    attach(app, "Dashboard Inbox and memory")

    // A current chapter opens its Timeline record.
    reveal(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HOMES")).firstMatch, in: app
    )
    .tap()
    XCTAssertTrue(app.navigationBars["Edit Home"].waitForExistence(timeout: 10))
    app.navigationBars["Edit Home"].buttons["Cancel"].tap()
    app.tabBars.buttons["Dashboard"].tap()

    // A recent Entry opens its canonical record.
    let goal = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Hike the coast trail")
    )
    .firstMatch
    reveal(goal, in: app)
    attach(app, "Dashboard recent Entries")
    goal.tap()
    XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 10))
    attach(app, "Recent Entry destination")
  }

  private func launchLocalSession() throws -> XCUIApplication {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard !path.isEmpty else {
      throw XCTSkip("Run apps/ios/scripts/review-local-session.py with the local Supabase stack.")
    }
    let app = XCUIApplication()
    app.launchArguments = ["--review-local-session"]
    app.launchEnvironment["MEMOTRAIL_REVIEW_SESSION"] = path
    app.launch()
    return app
  }

  private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }
}
