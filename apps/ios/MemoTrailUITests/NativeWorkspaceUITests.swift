import XCTest

@MainActor
final class NativeWorkspaceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  func testGalleryActionsAndNativeEditor() {
    let app = launch("--review-design-system")
    app.buttons["design-section-primitives"].tap()
    app.buttons["design-save"].tap()
    XCTAssertTrue(app.staticTexts["Preview saved to Library."].waitForExistence(timeout: 4))
    attach(app, "Actions")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.swipeUp()
    app.buttons["design-section-forms"].tap()
    app.buttons["design-open-editor"].tap()
    XCTAssertTrue(app.navigationBars["Sample editor"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["rich-format-toggle"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
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
    app.swipeUp()
    app.buttons["design-section-containers"].tap()
    XCTAssertTrue(app.navigationBars["Containers & data"].waitForExistence(timeout: 3))
    app.swipeUp()
    attach(app, "Dark records at accessibility text size")
    XCTAssertTrue(app.staticTexts["A quiet afternoon by the coast"].exists)
  }

  func testRichWritingTypingFormattingUndoAndSavedPreview() {
    let app = launch("--review-design-system")
    app.swipeUp()
    app.buttons["design-section-writing"].tap()
    let editor = app.textViews["rich-editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["rich-format-bold"].exists)
    app.buttons["rich-format-toggle"].tap()
    XCTAssertTrue(app.buttons["rich-format-bold"].exists)
    app.buttons["rich-format-bold"].tap()
    app.buttons["rich-format-italic"].tap()
    app.buttons["rich-format-underline"].tap()
    editor.typeText("A quiet day")
    XCTAssertEqual(editor.value as? String, "A quiet day")
    XCTAssertEqual(app.buttons["rich-format-bold"].value as? String, "On")
    XCTAssertEqual(app.buttons["rich-format-italic"].value as? String, "On")
    XCTAssertEqual(app.buttons["rich-format-underline"].value as? String, "On")
    attach(app, "Rich writing above the keyboard")
    app.buttons["rich-dismiss-keyboard"].tap()
    app.buttons["design-save-writing"].tap()
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["design-saved-writing"].waitForExistence(timeout: 3))
    attach(app, "Saved emphasis preview")
    app.buttons["design-reopen-writing"].tap()
    app.swipeDown()
    editor.tap()
    // Double-tap the first word in the native text view to select existing writing.
    editor.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.1)).doubleTap()
    attach(app, "Native selected word")
    app.buttons["rich-format-bold"].tap()
    XCTAssertEqual(editor.value as? String, "A quiet day")
    XCTAssertEqual(app.buttons["rich-format-bold"].value as? String, "Off")
    app.buttons["rich-undo"].tap()
    XCTAssertEqual(app.buttons["rich-format-bold"].value as? String, "On")
    app.buttons["rich-redo"].tap()
    XCTAssertEqual(app.buttons["rich-format-bold"].value as? String, "Off")
    attach(app, "Selection formatting after redo")
    app.buttons["rich-format-toggle"].tap()
    XCTAssertFalse(app.buttons["rich-format-bold"].exists)
  }

  func testRichWritingDarkLargeTextAndSheetCancel() {
    let app = launch("--review-design-system")
    app.buttons["design-preview-settings"].tap()
    app.buttons["Dark"].tap()
    app.buttons["design-preview-settings"].tap()
    app.buttons["Accessibility text"].tap()
    app.swipeUp()
    app.buttons["design-section-writing"].tap()
    app.swipeUp()
    app.buttons["rich-format-toggle"].tap()
    attach(app, "Dark rich text tools at accessibility size")
    app.swipeUp()
    app.buttons["design-open-writing-sheet"].tap()
    XCTAssertTrue(app.textViews["rich-sheet-editor"].waitForExistence(timeout: 3))
    app.textViews["rich-sheet-editor"].tap()
    app.textViews["rich-sheet-editor"].typeText("Cancelled draft")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Writing & formatting"].waitForExistence(timeout: 3))
    app.swipeDown()
    XCTAssertEqual(app.textViews["rich-editor"].value as? String, "")
  }

  // Opens every gallery section directly and keeps full-page screenshots for visual review.
  func testGallerySectionsScreenshotTour() {
    let sections = [
      "primitives", "foundations", "identity", "layout", "forms", "writing", "containers",
      "feedback",
    ]
    for section in sections {
      let app = XCUIApplication()
      app.launchArguments = ["--review-design-system", "--review-design-section", section]
      app.launch()
      XCTAssertTrue(app.staticTexts["design-preview-status"].waitForExistence(timeout: 5))
      var previous = app.screenshot().pngRepresentation
      attach(app, "\(section) 1")
      for page in 2...8 {
        app.swipeUp()
        let current = app.screenshot().pngRepresentation
        guard current != previous else { break }
        previous = current
        attach(app, "\(section) \(page)")
      }
    }
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
