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
    reveal(app.buttons["design-section-forms"], in: app).tap()
    app.buttons["design-open-editor"].tap()
    XCTAssertTrue(app.navigationBars["Sample editor"].waitForExistence(timeout: 3))
    attach(app, "Sample editor")
    XCTAssertTrue(app.buttons["rich-format-toggle"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
  }

  func testSignInFollowsTheWebWelcome() {
    let app = launch("--review-sign-in")
    XCTAssertTrue(
      app.staticTexts["A quiet place for everything worth keeping."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Welcome to MemoTrail"].exists)
    XCTAssertTrue(app.staticTexts["Sign in to continue to your private space."].exists)
    XCTAssertTrue(app.buttons["google-sign-in"].exists)
    attach(app, "Sign in")
    app.swipeUp()
    attach(app, "Sign in card")
  }

  func testMapFiltersAreasClustersAndRecords() {
    let app = launch("--review-map")
    XCTAssertTrue(app.staticTexts["5 Entry Locations"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Choose a map point"].exists)
    attach(app, "Map")

    // Category and years filter as they change, like Web.
    app.buttons["Category"].tap()
    app.buttons["Goals"].tap()
    XCTAssertTrue(app.staticTexts["1 Entry Location"].waitForExistence(timeout: 3))
    let fromYear = app.textFields["map-from-year"]
    fromYear.tap()
    fromYear.typeText("2027")
    XCTAssertTrue(app.staticTexts["0 Entry Locations"].waitForExistence(timeout: 3))
    XCTAssertTrue(
      app.staticTexts[
        "No current Entries match these filters. Add a Location in an Entry to place it on this map."
      ].exists)
    attach(app, "Filtered empty map")
    fromYear.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "\n")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    app.buttons["Category"].tap()
    app.buttons["All records"].tap()
    XCTAssertTrue(app.staticTexts["5 Entry Locations"].waitForExistence(timeout: 3))

    // An area zooms the map, and a cluster lists its Entries below it, newest first.
    app.buttons["map-city-Austin"].tap()
    // MapKit exposes marker views as buttons on some OS versions.
    let marker = app.descendants(matching: .any)["map-location-cluster"].firstMatch
    XCTAssertTrue(
      marker.waitForExistence(timeout: 5),
      "MapKit should cluster the two overlapping Austin records.")
    marker.tap()
    XCTAssertTrue(app.staticTexts["2 Entries here"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["A new beginning"].exists)
    for fact in ["First Time", "Austin, Texas", "Jun 1, 2022"] {
      XCTAssertTrue(app.staticTexts[fact].exists, fact)
    }
    attach(app, "Cluster records")
    app.buttons["map-record-99000000-0000-4000-8000-000000000001"].tap()
    XCTAssertTrue(
      app.staticTexts["This is a synthetic preview record."].waitForExistence(timeout: 3))
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
    XCTAssertTrue(app.staticTexts["map-count"].waitForExistence(timeout: 3))
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
    reveal(app.buttons["design-section-containers"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Containers & data"].waitForExistence(timeout: 3))
    reveal(app.buttons["Open sample memory"], in: app).tap()
    XCTAssertTrue(app.staticTexts["RecordCard action fired."].waitForExistence(timeout: 3))
    let summary = reveal(app.staticTexts["A quiet afternoon by the coast"], in: app)
    attach(app, "Dark records at accessibility text size")
    XCTAssertTrue(summary.isHittable)
  }

  // Like Web SeparatedList, a separator shows only between two facts on a line as frames narrow.
  func testFlowSeparatorsStayBetweenFactsAsTheirFramesNarrow() {
    let app = launch("--review-design-system")
    for size in ["Standard text", "Large text", "Accessibility text"] {
      app.buttons["design-preview-settings"].tap()
      app.buttons[size].tap()
      reveal(app.buttons["design-section-containers"], in: app).tap()
      XCTAssertTrue(app.navigationBars["Containers & data"].waitForExistence(timeout: 3))
      for frame in ["Wide", "Medium", "Narrow"] {
        for kind in ["separated facts", "word-spaced facts"] {
          let row = revealWhole(app.otherElements["\(frame) \(kind)"], in: app)
          let lines = assertSeparatorsBetweenFacts(row, in: app)
          // At standard text a phone's widest frame still fits the shorter row on one line.
          if frame == "Wide", kind == "word-spaced facts", size == "Standard text" {
            XCTAssertEqual(lines.count, 1, "\(lines)")
          }
          if frame == "Narrow" { XCTAssertGreaterThan(lines.count, 1, "\(lines)") }
        }
        attach(app, "\(frame) flow separators at \(size)")
      }
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
  }

  func testRichWritingTypingFormattingUndoAndSavedPreview() {
    let app = launch("--review-design-system")
    reveal(app.buttons["design-section-writing"], in: app).tap()
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

  func testGallerySheetsShowMessagesAndFitShortChoices() {
    let app = launchSection("primitives")
    reveal(app.buttons["Open form sheet"], in: app).tap()
    XCTAssertTrue(app.staticTexts["Edit a memory"].waitForExistence(timeout: 3))
    app.buttons["Save memory"].tap()
    XCTAssertTrue(app.staticTexts["Add a title before saving."].waitForExistence(timeout: 3))
    attach(app, "Form sheet with message")
    let title = app.textFields["Title, required"]
    title.tap()
    title.typeText("First ski day")
    app.buttons["Save memory"].tap()
    XCTAssertTrue(
      app.staticTexts["Demo saved for an undated memory. No data was uploaded."]
        .waitForExistence(timeout: 5))

    reveal(app.buttons["Open fitted sheet"], in: app).tap()
    XCTAssertTrue(app.staticTexts["What are you adding?"].waitForExistence(timeout: 3))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Fitted sheet")
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Moment")).firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Moment chosen."].waitForExistence(timeout: 3))
  }

  func testRichWritingDarkLargeTextAndSheetCancel() {
    let app = launch("--review-design-system")
    app.buttons["design-preview-settings"].tap()
    app.buttons["Dark"].tap()
    app.buttons["design-preview-settings"].tap()
    app.buttons["Accessibility text"].tap()
    reveal(app.buttons["design-section-writing"], in: app).tap()
    reveal(app.buttons["rich-format-toggle"], in: app).tap()
    attach(app, "Dark rich text tools at accessibility size")
    reveal(app.buttons["design-open-writing-sheet"], in: app).tap()
    XCTAssertTrue(app.textViews["rich-sheet-editor"].waitForExistence(timeout: 3))
    app.textViews["rich-sheet-editor"].tap()
    app.textViews["rich-sheet-editor"].typeText("Cancelled draft")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Writing & formatting"].waitForExistence(timeout: 3))
    app.swipeDown()
    XCTAssertEqual(app.textViews["rich-editor"].value as? String, "")
  }

  func testFormFieldsPickersAndOrganizationEditing() {
    let app = launchSection("forms")
    let record = reveal(app.buttons["Record"], in: app)
    record.tap()
    XCTAssertTrue(app.buttons["People"].waitForExistence(timeout: 3))
    attach(app, "Grouped select menu")
    app.buttons["People"].tap()
    XCTAssertEqual(record.value as? String, "People")

    let emptyDate = reveal(app.buttons["Empty date"], in: app)
    XCTAssertEqual(emptyDate.value as? String, "Not set")
    emptyDate.tap()
    XCTAssertTrue(app.buttons["date-picker-done"].waitForExistence(timeout: 3))
    attach(app, "Date picker popover")
    app.buttons["date-picker-done"].tap()
    XCTAssertNotEqual(emptyDate.value as? String, "Not set")
    app.buttons["Clear empty date"].tap()
    XCTAssertEqual(emptyDate.value as? String, "Not set")

    reveal(app.buttons["Default time zone"], in: app).tap()
    let search = app.searchFields["Search city or region"]
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.tap()
    search.typeText("Kathmandu")
    attach(app, "Time zone search")
    app.buttons["(UTC+05:45) Kathmandu - Asia"].tap()
    XCTAssertEqual(
      app.buttons["Default time zone"].value as? String, "(UTC+05:45) Kathmandu - Asia")

    reveal(app.buttons["organization-add-tag"], in: app).tap()
    let tagSearch = app.textFields["organization-search-tag"]
    XCTAssertTrue(tagSearch.waitForExistence(timeout: 3))
    tagSearch.typeText("mile")
    attach(app, "Tag picker")
    app.buttons["milestone"].tap()
    XCTAssertTrue(app.buttons["milestone"].isSelected)
    tagSearch.typeText("road trip,")
    XCTAssertTrue(app.buttons["road trip"].waitForExistence(timeout: 3))
    tagSearch.typeText("sunrise")
    app.buttons["organization-done"].tap()
    XCTAssertTrue(app.buttons["Remove milestone from Tags"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Remove road trip from Tags"].exists)
    XCTAssertTrue(app.buttons["Remove sunrise from Tags"].exists)
    XCTAssertTrue(app.staticTexts["5 of 50 Tags"].exists)
    attach(app, "Added tags")

    reveal(app.buttons["Date type, required"], in: app).tap()
    app.buttons["Date range"].tap()
    let present = reveal(
      app.descendants(matching: .toggle)["Present, This period is still ongoing"], in: app)
    XCTAssertTrue(app.buttons["End date"].exists)
    present.tap()
    XCTAssertEqual(present.value as? String, "On")
    XCTAssertFalse(app.buttons["End date"].exists)
    attach(app, "Ongoing date range")
  }

  func testToastsStackPassTouchesThroughAndDismiss() {
    let app = launchSection("feedback")
    app.buttons["Show success"].tap()
    XCTAssertTrue(app.staticTexts["Changes saved."].waitForExistence(timeout: 3))
    // Touches outside the toast reach the page beneath its overlay window.
    app.buttons["Show error"].tap()
    XCTAssertTrue(app.staticTexts["Could not save. Try again."].waitForExistence(timeout: 3))
    attach(app, "Stacked toasts")
    app.buttons["Dismiss notification"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Changes saved."].waitForNonExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Could not save. Try again."].exists)
    reveal(app.staticTexts["Failure"], in: app)
    attach(app, "Media states")
    XCTAssertTrue(app.staticTexts["Photo unavailable"].exists)
    XCTAssertTrue(app.images["Coast"].exists)
  }

  func testToastsRiseFromTheBottomClearOfTheKeyboard() {
    let app = launchSection("feedback")
    let window = app.windows.firstMatch.frame
    app.buttons["Show success"].tap()
    let saved = app.staticTexts["Changes saved."]
    XCTAssertTrue(saved.waitForExistence(timeout: 3))
    // Like Web, a toast sits low, leaving the top free for back and close buttons.
    XCTAssertGreaterThan(saved.frame.minY, window.midY)
    XCTAssertLessThan(saved.frame.maxY, window.maxY - 100)
    attach(app, "Toast at the bottom")
    app.buttons["Dismiss notification"].firstMatch.tap()
    XCTAssertTrue(saved.waitForNonExistence(timeout: 3))

    let field = app.textFields["toast-message"]
    field.tap()
    field.typeText("Saved while typing")
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
    app.buttons["Show info"].tap()
    let typed = app.staticTexts["Saved while typing"]
    XCTAssertTrue(typed.waitForExistence(timeout: 3))
    Thread.sleep(forTimeInterval: 0.5)
    XCTAssertLessThan(typed.frame.maxY, keyboard.frame.minY)
    attach(app, "Toast above the keyboard")
  }

  func testPhotoFieldSamplesUploadProgressAndRemoval() {
    let app = launchSection("forms")
    reveal(app.buttons["Add sample"], in: app).tap()
    app.buttons["Add sample"].tap()
    XCTAssertTrue(app.buttons["Remove selected sample-2.png"].exists)
    app.buttons["Simulate upload"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["Photo upload progress"].waitForExistence(timeout: 3))
    attach(app, "Photo upload progress")
    XCTAssertTrue(
      app.descendants(matching: .any)["Photo upload progress"].waitForNonExistence(timeout: 6))
    let status = app.staticTexts["design-photo-status"]
    XCTAssertEqual(status.label, "2 saved · 2 new")
    // The preview pages between saved photos, like Web's photo viewer.
    app.buttons["Preview coast-memory.jpg"].tap()
    XCTAssertTrue(app.navigationBars["coast-memory.jpg"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.images["coast-memory.jpg"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["1 of 2"].exists)
    XCTAssertFalse(app.buttons["Previous photo"].isEnabled)
    attach(app, "Photo preview")
    app.buttons["Next photo"].tap()
    XCTAssertTrue(app.navigationBars["harbor-walk.jpg"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["2 of 2"].exists)
    XCTAssertFalse(app.buttons["Next photo"].isEnabled)
    app.navigationBars["harbor-walk.jpg"].buttons["Done"].tap()
    XCTAssertTrue(app.navigationBars["harbor-walk.jpg"].waitForNonExistence(timeout: 3))
    app.buttons["Remove selected sample-1.png"].tap()
    XCTAssertEqual(status.label, "2 saved · 1 new")
    app.buttons["Remove coast-memory.jpg"].tap()
    XCTAssertEqual(status.label, "1 saved · 1 new")
    XCTAssertFalse(app.buttons["Preview coast-memory.jpg"].exists)
    XCTAssertTrue(app.buttons["Remove selected sample-2.png"].exists)
  }

  // Opens every gallery section directly and keeps full-page screenshots for visual review.
  func testGallerySectionsScreenshotTour() {
    let allSections = [
      "primitives", "foundations", "identity", "layout", "forms", "writing", "containers",
      "feedback",
    ]
    // Set TEST_RUNNER_GALLERY_SECTIONS=forms,feedback to review only some sections.
    let requested = (ProcessInfo.processInfo.environment["GALLERY_SECTIONS"] ?? "")
      .split(separator: ",").map(String.init)
    for section in requested.isEmpty ? allSections : requested {
      let app = XCUIApplication()
      app.launchArguments = ["--review-design-system", "--review-design-section", section]
      app.launch()
      XCTAssertTrue(app.staticTexts["design-preview-status"].waitForExistence(timeout: 5))
      var previous = app.screenshot().pngRepresentation
      attach(app, "\(section) 1")
      // Foundations is the longest section; the tour stops once a swipe no longer scrolls.
      for page in 2...20 {
        app.swipeUp()
        let current = app.screenshot().pngRepresentation
        guard current != previous else { break }
        previous = current
        attach(app, "\(section) \(page)")
      }
    }
  }

  /// Every specimen the component specs list appears, by its identifier, in the gallery section
  /// that shows its component. The list is generated from packages/design-system/components, so
  /// a specimen added to a spec fails here until the native gallery shows it.
  func testGalleryShowsEveryComponentSpecimen() {
    let sections = ["Badge": "forms", "Button": "primitives"]
    let specimens = Dictionary(grouping: MTComponentSpecimen.allCases, by: \.component)
    for component in specimens.keys.sorted() where sections[component] == nil {
      XCTFail("Name the gallery section that shows \(component) specimens.")
    }
    let known = Set(MTComponentSpecimen.allCases.map(\.accessibilityIdentifier))
    for (component, section) in sections.sorted(by: { $0.key < $1.key }) {
      let expected = specimens[component] ?? []
      XCTAssertFalse(expected.isEmpty, "\(component) lists no specimens.")
      let app = launchSection(section)
      // The gallery shows specimens in spec order, so revealing each one only scrolls down.
      for specimen in expected {
        let element = app.descendants(matching: .any)[specimen.accessibilityIdentifier]
        XCTAssertTrue(
          reveal(element, in: app).exists, "\(section) does not show \(specimen.rawValue).")
        XCTAssertTrue(element.staticTexts[specimen.rawValue].exists)
        XCTAssertTrue(element.staticTexts[specimen.summary].exists)
      }
      let shown = app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'specimen-'"))
        .allElementsBoundByIndex.map(\.identifier)
      XCTAssertEqual(Set(shown).subtracting(known), [], "\(section) shows unlisted specimens.")
      attach(app, "\(component) specimens")
    }
  }

  private func launchSection(_ section: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--review-design-system", "--review-design-section", section]
    app.launch()
    XCTAssertTrue(app.staticTexts["design-preview-status"].waitForExistence(timeout: 5))
    return app
  }

  private func launch(_ mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [mode]
    app.launch()
    return app
  }
}
