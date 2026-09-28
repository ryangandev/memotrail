import XCTest

@MainActor
final class NativeWorkspaceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  func testGalleryActionsAndNativeEditor() {
    let app = launch("--review-design-system")
    app.buttons["design-section-actions"].tap()
    app.buttons["design-save"].tap()
    XCTAssertTrue(app.staticTexts["Preview saved to Library."].waitForExistence(timeout: 4))
    attach(app, "Actions")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["design-section-forms"].tap()
    app.buttons["design-open-editor"].tap()
    XCTAssertTrue(app.navigationBars["Sample editor"].waitForExistence(timeout: 3))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Forms & sheets"].waitForExistence(timeout: 3))
  }

  func testMapFiltersCitiesClusterAndRecordSelection() {
    let app = launch("--review-map")
    XCTAssertTrue(app.buttons["map-browse-records"].waitForExistence(timeout: 5))
    app.buttons["map-city-Austin"].tap()
    // MapKit exposes marker views as buttons on some OS versions.
    let marker = app.descendants(matching: .any)["map-location-cluster"].firstMatch
    XCTAssertTrue(
      marker.waitForExistence(timeout: 5),
      "MapKit should cluster the two overlapping Austin records.")
    marker.tap()
    XCTAssertTrue(app.navigationBars["Mapped records"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Our first home"].exists)
    XCTAssertTrue(app.staticTexts["A new beginning"].exists)
    attach(app, "Cluster records")
    app.buttons["Done"].tap()
    app.buttons["map-full-map"].tap()
    app.buttons["map-kind-goal"].tap()
    XCTAssertTrue(app.staticTexts["1 record · 1 Location"].exists)
    app.buttons["map-filters"].tap()
    app.textFields["map-from-year"].tap()
    app.textFields["map-from-year"].typeText("2027")
    app.buttons["Apply"].tap()
    XCTAssertTrue(app.staticTexts["No matching Locations"].waitForExistence(timeout: 3))
    attach(app, "Filtered empty map")
  }

  func testPrimaryTabsMoreRoutesAndBackNavigation() {
    let app = launch("--review-navigation")
    for title in ["Dashboard", "Inbox", "Timeline", "Library", "More"] {
      XCTAssertTrue(app.tabBars.buttons[title].exists)
    }
    app.tabBars.buttons["More"].tap()
    XCTAssertTrue(app.buttons["more-map"].waitForExistence(timeout: 3))
    app.swipeUp()
    app.buttons["more-design-system"].tap()
    app.buttons["design-preview-settings"].tap()
    app.buttons["Dark"].tap()
    XCTAssertTrue(app.staticTexts["Dark appearance"].waitForExistence(timeout: 3))
    app.navigationBars.buttons["More"].tap()
    attach(app, "More after leaving dark gallery preview")
    app.swipeDown()
    app.buttons["more-map"].tap()
    XCTAssertTrue(app.buttons["map-browse-records"].waitForExistence(timeout: 3))
    attach(app, "Map")
    app.navigationBars.buttons["More"].tap()
    app.swipeUp()
    app.buttons["more-tags"].tap()
    XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 3))
    app.navigationBars.buttons["More"].tap()
    app.swipeUp()
    app.buttons["more-settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Export archive"].exists)
    attach(app, "Settings")
  }

  func testGalleryDarkAppearanceAndLargeTextRecords() {
    let app = launch("--review-design-system")
    app.buttons["design-preview-settings"].tap()
    app.buttons["Dark"].tap()
    XCTAssertTrue(app.staticTexts["Dark appearance"].waitForExistence(timeout: 3))
    attach(app, "Dark gallery")
    app.buttons["design-preview-settings"].tap()
    app.buttons["Accessibility text"].tap()
    app.swipeUp()
    app.buttons["design-section-records"].tap()
    XCTAssertTrue(app.navigationBars["Records & media"].waitForExistence(timeout: 3))
    app.swipeUp()
    attach(app, "Dark records at accessibility text size")
    XCTAssertTrue(app.staticTexts["A quiet afternoon by the coast"].exists)
  }

  private func launch(_ mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [mode]
    app.launch()
    return app
  }

  private func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
