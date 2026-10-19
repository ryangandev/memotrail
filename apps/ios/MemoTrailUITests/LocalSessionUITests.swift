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

  // MARK: Harness

  /// `offline` fails every request once the session is open, like an iPhone with no network.
  /// `contentSize` names a text size category, such as `UICTContentSizeCategoryAccessibilityL`.
  func launchLocalSession(offline: Bool = false, contentSize: String? = nil) throws
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
