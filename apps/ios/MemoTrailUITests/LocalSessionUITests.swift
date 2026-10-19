import UIKit
import XCTest

/// Runs signed in as the seeded, disposable local account that
/// `apps/ios/scripts/review-local-session.py` creates and removes.
///
/// This file is the shared harness. Each area adds its tests in
/// `LocalSessionUITests+<Area>.swift`, using the helpers below.
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
    // No test removes these seeded records.
    for (tab, expected) in [
      ("Timeline", "Finished the first marathon"), ("Library", "Grandmother's recipe cards"),
    ] {
      app.tabBars.buttons[tab].tap()
      XCTAssertTrue(text(expected, in: app).waitForExistence(timeout: 15), tab)
      // Each tab's header keeps New entry beside the mark, like Web's phone header.
      XCTAssertTrue(app.buttons["workspace-new-entry"].isHittable, tab)
      attach(app, tab)
    }
    app.tabBars.buttons["More"].tap()
    // More groups its destinations like Web's mobile More menu. The group labels are drawn in
    // uppercase, so match them ignoring case.
    for group in ["Focused views", "Organize", "Trash and settings"] {
      let label = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", group)).firstMatch
      XCTAssertTrue(label.waitForExistence(timeout: 5), group)
    }
    attach(app, "More")
    // The header mark opens the Dashboard, like Web's brand link.
    app.buttons["workspace-brand"].tap()
    XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
    app.tabBars.buttons["More"].tap()
    for (identifier, route) in [
      ("more-firstTimes", "First Times"), ("more-tags", "Tags"), ("more-trash", "Trash"),
      ("more-settings", "Settings"),
    ] {
      reveal(app.buttons[identifier], in: app).tap()
      XCTAssertTrue(app.navigationBars[route].waitForExistence(timeout: 10), route)
      Thread.sleep(forTimeInterval: 1.5)
      attach(app, route)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
  }

  /// Summary rows wrap at large text sizes without a separator at either end of a line, like Web.
  func testSummaryRowsKeepSeparatorsBetweenFactsAtLargeTextSizes() throws {
    for size in ["UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityL"] {
      let app = try launchLocalSession(contentSize: size)
      XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))
      app.tabBars.buttons["Timeline"].tap()
      let timeline = app.otherElements["Timeline summary"]
      XCTAssertTrue(timeline.waitForExistence(timeout: 15))
      let lines = assertSeparatorsBetweenFacts(revealWhole(timeline, in: app), in: app)
      // Like Web, the Timeline summary is one short line that wraps only at accessibility sizes.
      if size.contains("Accessibility") {
        XCTAssertGreaterThan(lines.count, 1, "\(lines)")
      } else {
        XCTAssertEqual(lines.count, 1, "\(lines)")
      }
      attach(app, "Timeline summary at \(size)")
      app.tabBars.buttons["More"].tap()
      reveal(app.buttons["more-firstTimes"], in: app).tap()
      let summary = app.otherElements["First Times summary"]
      XCTAssertTrue(summary.waitForExistence(timeout: 10))
      assertSeparatorsBetweenFacts(revealWhole(summary, in: app), in: app)
      attach(app, "First Times summary at \(size)")
      app.navigationBars.buttons.element(boundBy: 0).tap()
      app.terminate()
    }
  }

  /// Visits every screen in light, dark, and the largest accessibility text size, and keeps a
  /// screenshot of the top of each screen and of the screen scrolled once, for a pixel review.
  /// It reads seeded data and saves nothing.
  func testScreenTourInEachAppearanceAndTheLargestTextSize() throws {
    for (appearance, contentSize) in [
      ("light", nil), ("dark", nil), ("light", "UICTContentSizeCategoryAccessibilityXXXL"),
    ] as [(String, String?)] {
      let pass = contentSize == nil ? appearance : "largest text"
      let app = try launchLocalSession(contentSize: contentSize, appearance: appearance)
      XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 20))
      tourScreen(app, "Dashboard, \(pass)")

      app.buttons["workspace-new-entry"].tap()
      XCTAssertTrue(app.buttons["Close quick capture"].waitForExistence(timeout: 10))
      tourScreen(app, "Quick Capture, \(pass)", scroll: false)
      app.buttons["Close quick capture"].tap()

      for (tab, expected) in [
        ("Timeline", "Finished the first marathon"), ("Library", "Grandmother's recipe cards"),
      ] {
        app.tabBars.buttons[tab].tap()
        XCTAssertTrue(text(expected, in: app).waitForExistence(timeout: 15), tab)
        tourScreen(app, "\(tab), \(pass)")
      }

      app.buttons["workspace-search"].tap()
      let field = app.textFields["Search Library"]
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      field.typeText("Living in Lisbon\n")
      XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
      tourScreen(app, "Library results, \(pass)", scroll: false)
      let result = app.buttons
        .matching(NSPredicate(format: "label CONTAINS %@", "Living in Lisbon")).firstMatch
      XCTAssertTrue(result.waitForExistence(timeout: 10))
      reveal(result, in: app).tap()
      XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 15))
      tourScreen(app, "Chapter Item page, \(pass)")
      reveal(app.buttons["item-edit"], in: app).tap()
      XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 10))
      tourScreen(app, "Entry editor, \(pass)")
      app.buttons["Cancel"].tap()
      XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))

      app.tabBars.buttons["More"].tap()
      XCTAssertTrue(reveal(app.buttons["more-settings"], in: app).waitForExistence(timeout: 10))
      tourScreen(app, "More, \(pass)")
      for (identifier, route) in [
        ("more-firstTimes", "First Times"), ("more-tags", "Tags"), ("more-trash", "Trash"),
      ] {
        reveal(app.buttons[identifier], in: app).tap()
        XCTAssertTrue(app.navigationBars[route].waitForExistence(timeout: 10), route)
        tourScreen(app, "\(route), \(pass)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
      }
      reveal(app.buttons["more-settings"], in: app).tap()
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
      tourScreen(app, "Settings, \(pass)")
      reveal(app.buttons["Export"], in: app).tap()
      XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
      tourScreen(app, "Export, \(pass)")
      app.terminate()
    }
  }

  /// Keeps the screen once it settles and, unless `scroll` is false, again after one swipe up.
  private func tourScreen(_ app: XCUIApplication, _ name: String, scroll: Bool = true) {
    Thread.sleep(forTimeInterval: 1.5)
    attach(app, name)
    guard scroll else { return }
    app.swipeUp()
    Thread.sleep(forTimeInterval: 1)
    attach(app, "\(name), scrolled")
    app.swipeDown()
  }

  // MARK: Harness

  /// `offline` fails every request once the session is open, like an iPhone with no network.
  /// `contentSize` names a text size category, such as `UICTContentSizeCategoryAccessibilityL`.
  /// `appearance` is `light` or `dark`, the values Settings stores; it follows the system if nil.
  func launchLocalSession(
    offline: Bool = false, contentSize: String? = nil, appearance: String? = nil
  ) throws -> XCUIApplication {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard !path.isEmpty else {
      throw XCTSkip("Run apps/ios/scripts/review-local-session.py with the local Supabase stack.")
    }
    let app = XCUIApplication()
    app.launchArguments = ["--review-local-session"] + (offline ? ["--review-offline"] : [])
    if let contentSize {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
    }
    if let appearance { app.launchArguments += ["-native-appearance", appearance] }
    app.launchEnvironment["MEMOTRAIL_REVIEW_SESSION"] = path
    app.launch()
    return app
  }

  /// Whether `review-local-session.py --web` serves the Web media API for this run.
  func servesMediaAPI() -> Bool {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard let data = FileManager.default.contents(atPath: path),
      let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return session["apiURL"] is String
  }

  // A retained Dashboard composer can remain in the accessibility tree under the cover.
  // Select the smallest container with both the modal close action and its note editor.
  func quickCapture(in app: XCUIApplication) throws -> XCUIElement {
    let containers = app.otherElements
      .containing(.button, identifier: "close-quick-capture")
      .containing(.textView, identifier: "capture-body")
      .allElementsBoundByIndex
    let composer = try XCTUnwrap(containers.last)
    XCTAssertEqual(composer.textViews.matching(identifier: "capture-body").count, 1)
    return composer
  }

  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }
}
