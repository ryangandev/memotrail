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
    // The avatar in the shared header opens Settings, like the Web header.
    app.buttons["workspace-settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    attach(app, "Settings from the header")
    app.navigationBars["Settings"].buttons["Done"].tap()
    // Other tests organize or trash the remaining seeded captures, but none removes this one.
    for (tab, expected) in [
      ("Inbox", "Weekend packing list"), ("Timeline", "Finished the first marathon"),
      ("Library", "Grandmother's recipe cards"),
    ] {
      app.tabBars.buttons[tab].tap()
      if tab == "Timeline" {
        dismissBirthDatePrompt(
          once: app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", expected)
          ).firstMatch, in: app)
      }
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
    XCTAssertTrue(app.staticTexts["Review Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Peaches, basil", in: app).exists)
    attach(app, "Review opened from Dashboard")
    app.buttons["close-entry-review"].tap()
    app.tabBars.buttons["Dashboard"].tap()
    attach(app, "Dashboard Inbox and memory")

    // A current chapter opens its Timeline record.
    reveal(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HOMES")).firstMatch, in: app
    )
    .tap()
    XCTAssertTrue(app.staticTexts["Edit Home"].waitForExistence(timeout: 10))
    app.buttons["close-home-editor"].tap()
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

  func testCaptureSavesAFormattedNoteToTheInbox() throws {
    let app = try launchLocalSession()
    let editor = app.textViews["capture-body"]
    XCTAssertTrue(editor.waitForExistence(timeout: 20))
    reveal(editor, in: app).tap()
    app.buttons["rich-format-toggle"].tap()
    app.buttons["rich-format-bold"].tap()
    editor.typeText("Harbor lights")
    app.buttons["rich-format-bold"].tap()
    editor.typeText(" after the storm")
    attach(app, "Formatted capture")
    app.buttons["rich-dismiss-keyboard"].tap()
    XCTAssertTrue(app.staticTexts["Draft saved on this iPhone."].waitForExistence(timeout: 5))
    app.buttons["save-entry"].tap()
    XCTAssertTrue(text("Saved to Inbox", in: app).waitForExistence(timeout: 15))
    let row = app.buttons["Organize Harbor lights after the storm"]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    XCTAssertEqual(editor.value as? String ?? "", "")
    attach(app, "Saved formatted capture")
  }

  func testInboxReviewSavesOrganizesAndMovesCapturesToTrash() throws {
    let app = try launchLocalSession()
    app.tabBars.buttons["Inbox"].tap()
    let capture = app.buttons["Organize Notes from the farmers market"]
    XCTAssertTrue(capture.waitForExistence(timeout: 20))
    attach(app, "Inbox")

    // Move to Trash asks first, then leaves a toast like Web.
    app.buttons["Move Waiting for a little context to Trash"].tap()
    XCTAssertTrue(app.buttons["Move to Trash"].waitForExistence(timeout: 5))
    attach(app, "Trash confirmation")
    app.buttons["Move to Trash"].tap()
    XCTAssertTrue(text("Capture moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.buttons["Organize Waiting for a little context"].waitForNonExistence(timeout: 5))

    // Saving without editing a note keeps Web-only formatting, such as this list.
    reveal(app.buttons["Organize Weekend packing list"], in: app).tap()
    XCTAssertTrue(text("Lists, quotes, links, and code", in: app).waitForExistence(timeout: 10))
    attach(app, "Review with Web formatting")
    app.buttons["save-entry-review"].tap()
    XCTAssertTrue(text("Entry saved.", in: app).waitForExistence(timeout: 10))

    // Save changes keeps the capture in the Inbox with its formatted note.
    capture.tap()
    XCTAssertTrue(app.staticTexts["Review Entry"].waitForExistence(timeout: 10))
    attach(app, "Review Entry")
    let editor = app.textViews["review-body"]
    editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
    app.buttons["rich-format-toggle"].tap()
    app.buttons["rich-format-bold"].tap()
    editor.typeText(" Sweet corn.")
    app.buttons["rich-dismiss-keyboard"].tap()
    app.swipeUp()
    attach(app, "Review Entry fields")
    app.buttons["save-entry-review"].tap()
    XCTAssertTrue(text("Entry saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(text("Sweet corn.", in: app).waitForExistence(timeout: 5))

    // Version history opens inside the review, and Save to Library organizes the capture.
    capture.tap()
    XCTAssertTrue(app.buttons["review-version-history"].waitForExistence(timeout: 10))
    XCTAssertTrue((editor.value as? String ?? "").hasSuffix("Sweet corn."))
    app.buttons["review-version-history"].tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
    app.navigationBars["Version history"].buttons.element(boundBy: 0).tap()
    app.buttons["organize-entry"].tap()
    XCTAssertTrue(text("Entry organized.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(capture.waitForNonExistence(timeout: 10))
    attach(app, "Inbox organized")
  }

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

    // A keyword search shows why each record matched, with its formatted note.
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
    app.buttons["Goals"].tap()
    XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Filters · 1 active"].exists)
    attach(app, "Library filtered results")

    // A result opens its record, and Clear all returns to browsing.
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Goal, Hike the coast trail"))
      .firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 10))
    app.navigationBars["Goals"].buttons.element(boundBy: 0).tap()
    reveal(app.buttons["library-clear-search"], in: app).tap()
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 10))
    XCTAssertEqual(field.value as? String, "A phrase, date, or question about your life...")

    reveal(app.buttons["library-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
  }

  func testSettingsSavesThePreferredNameForTheGreeting() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(text("Review.", in: app).waitForExistence(timeout: 20))
    app.buttons["workspace-settings"].tap()
    let field = app.textFields["settings-preferred-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertEqual(field.value as? String, "Review Tester")
    XCTAssertFalse(app.buttons["Save name"].isEnabled)
    attach(app, "Settings")

    // Each setting saves on its own once it changes, like Web.
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 13) + "  River  ")
    app.buttons["Save name"].tap()
    XCTAssertTrue(text("Preferred name saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertEqual(field.value as? String, "River")
    XCTAssertFalse(app.buttons["Save name"].isEnabled)
    attach(app, "Preferred name saved")

    reveal(app.buttons["Save time zone"], in: app)
    attach(app, "Settings preferences")
    reveal(text("Private by default", in: app), in: app)
    attach(app, "Settings end")

    // The Dashboard greeting follows the saved name.
    app.navigationBars["Settings"].buttons["Done"].tap()
    XCTAssertTrue(text("River.", in: app).waitForExistence(timeout: 10))
  }

  func testTimelineStartsFromTheBirthDateAndAddsEditsAndTrashesMoments() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Timeline"].tap()
    XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Birth date prompt")
    app.buttons["Not now"].tap()
    XCTAssertTrue(app.buttons["timeline-set-birth-date"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["2019 to 2026"].exists)
    attach(app, "Timeline")

    // Set birth date saves the profile and starts the range there.
    app.buttons["timeline-set-birth-date"].tap()
    app.buttons["Birth date, required"].tap()
    // The calendar's month and year header opens the month and year wheels.
    let header = app.datePickers.buttons["DatePicker.Show"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    header.tap()
    let year = app.pickerWheels.element(boundBy: 1)
    XCTAssertTrue(year.waitForExistence(timeout: 5))
    year.adjust(toPickerWheelValue: "1994")
    app.datePickers.buttons["DatePicker.Hide"].tap()
    app.datePickers.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "September 18"))
      .firstMatch.tap()
    app.buttons["date-picker-done"].tap()
    attach(app, "Birth date chosen")
    app.buttons["timeline-save-birth-date"].tap()
    XCTAssertTrue(text("Birth date saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["timeline-set-birth-date"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(text("1994 to", in: app).exists)

    // Add moment asks what to add, then saves a Moment to the first track.
    app.buttons["add-timeline-moment"].tap()
    XCTAssertTrue(app.staticTexts["What are you adding?"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Type chooser")
    app.buttons["timeline-type-moment"].tap()
    let title = app.textFields["timeline-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("First ski day")
    attach(app, "New moment")
    app.swipeUp()
    attach(app, "New moment notes and organization")
    app.buttons["save-timeline-moment"].tap()
    XCTAssertTrue(text("Moment created.", in: app).waitForExistence(timeout: 10))
    let moment = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "First ski day")
    ).firstMatch
    XCTAssertTrue(moment.waitForExistence(timeout: 10))
    attach(app, "Moment on its track")

    // The moment reopens for editing and moves to Trash.
    moment.tap()
    XCTAssertTrue(app.staticTexts["Edit moment"].waitForExistence(timeout: 5))
    reveal(app.buttons["trash-timeline-moment"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Move to Trash", "trash-timeline-moment")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Moment trash confirmation")
    confirm.tap()
    XCTAssertTrue(text("Moment moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(moment.waitForNonExistence(timeout: 10))

    // Manage tracks creates a track that the Timeline shows on return.
    app.buttons["manage-timeline-tracks"].tap()
    XCTAssertTrue(app.staticTexts["Timeline tracks"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.otherElements["Edit Education"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Default · 2 moments", in: app).exists)
    attach(app, "Timeline tracks")
    app.buttons["add-timeline-track"].tap()
    let name = app.textFields["Name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Travel")
    attach(app, "New track")
    app.buttons["create-timeline-track"].tap()
    XCTAssertTrue(text("Track created.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.otherElements["Edit Travel"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(reveal(app.staticTexts["Travel"], in: app).waitForExistence(timeout: 10))
    attach(app, "Timeline with the new track")
  }

  func testHomesOpenTheirPageAndAddEditAndTrashHomes() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))

    // Like Web, a Home on the Timeline opens its own page.
    app.tabBars.buttons["Timeline"].tap()
    let onTimeline = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Maple Street flat")
    ).firstMatch
    dismissBirthDatePrompt(once: onTimeline, in: app)
    reveal(onTimeline, in: app).tap()
    XCTAssertTrue(app.staticTexts["Closer to work"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-home"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Homes"], in: app).tap()
    let seeded = app.buttons["Maple Street flat, Since Jun 1, 2021"]
    XCTAssertTrue(seeded.waitForExistence(timeout: 15))
    XCTAssertTrue(text("1 current residence", in: app).exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Homes")

    // A card opens the Home's own page with its facts, Story, and organization.
    seeded.tap()
    XCTAssertTrue(app.staticTexts["Closer to work"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["120 Maple Street"].exists)
    attach(app, "Home page")
    reveal(app.buttons["home-version-history"], in: app)
    attach(app, "Home page Story and organization")

    // Edit saves through the Web editor sections and the page shows the change.
    app.buttons["edit-home"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Edit Home"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Home editor")
    let movedIn = reveal(app.textFields["Why you moved in"], in: app)
    movedIn.tap()
    movedIn.typeText(" and the park\n")
    // The saved Location shows its map, address, and coordinates above the address fields.
    app.swipeUp()
    XCTAssertTrue(reveal(app.buttons["Remove Location"], in: app).exists)
    XCTAssertTrue(app.staticTexts["45.52310, -122.67650"].exists)
    attach(app, "Home editor Location")
    app.buttons["save-home"].tap()
    XCTAssertTrue(text("Home saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Closer to work and the park"].waitForExistence(timeout: 10))
    attach(app, "Home page after saving")

    // Version history opens this Home's history.
    reveal(app.buttons["home-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Home version history")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Add Home creates one without a date or Location, like Web.
    XCTAssertTrue(app.buttons["add-home"].waitForExistence(timeout: 5))
    app.buttons["add-home"].tap()
    let name = app.textFields["home-title"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Harbor Road cottage")
    attach(app, "New Home")
    app.buttons["save-home"].tap()
    XCTAssertTrue(text("Home created.", in: app).waitForExistence(timeout: 10))
    let created = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Harbor Road cottage")
    ).firstMatch
    XCTAssertTrue(created.waitForExistence(timeout: 10))
    XCTAssertTrue(text("2 homes", in: app).exists)
    attach(app, "Homes with the new Home")

    // Moving it to Trash from its page returns to the list without it.
    reveal(created, in: app).tap()
    XCTAssertTrue(app.buttons["edit-home"].firstMatch.waitForExistence(timeout: 10))
    app.buttons["edit-home"].firstMatch.tap()
    reveal(app.buttons["trash-home"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "trash-home")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Home trash confirmation")
    confirm.tap()
    XCTAssertTrue(text("Home moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["add-home"].waitForExistence(timeout: 10))
    XCTAssertTrue(created.waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("1 home", in: app).exists)
    attach(app, "Homes after Trash")
  }

  func testVehiclesOpenTheirPageAndAddEditAndTrashVehicles() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))

    // Like Web, a Vehicle on the Timeline opens its own page.
    app.tabBars.buttons["Timeline"].tap()
    let onTimeline = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Blue hatchback")
    ).firstMatch
    dismissBirthDatePrompt(once: onTimeline, in: app)
    reveal(onTimeline, in: app).tap()
    XCTAssertTrue(app.staticTexts["2015 Honda Fit · Blue"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-vehicle"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Vehicles"], in: app).tap()
    let seeded = app.buttons["Blue hatchback, Since Sep 15, 2019"]
    XCTAssertTrue(seeded.waitForExistence(timeout: 15))
    XCTAssertTrue(text("1 current vehicle", in: app).exists)
    Thread.sleep(forTimeInterval: 1.5)
    attach(app, "Vehicles")

    // A card opens the Vehicle's page with its facts, Location, Story, and organization.
    seeded.tap()
    let location = "Hawthorne Boulevard, Portland, OR, United States"
    XCTAssertTrue(app.staticTexts[location].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["2015 Honda Fit · Blue"].exists)
    attach(app, "Vehicle page")
    reveal(app.buttons["vehicle-version-history"], in: app)
    attach(app, "Vehicle page Story and organization")

    // Edit shows the saved Location, and removing it saves with the other changes.
    app.buttons["edit-vehicle"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Edit Vehicle"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Vehicle editor")
    // Scroll the saved Location clear of the sheet footer before removing it.
    app.swipeUp()
    XCTAssertTrue(reveal(app.buttons["Remove Location"], in: app).exists)
    XCTAssertTrue(app.staticTexts["45.51200, -122.62500"].exists)
    attach(app, "Vehicle editor Location")
    app.buttons["Remove Location"].tap()
    XCTAssertTrue(app.buttons["Remove Location"].waitForNonExistence(timeout: 5))
    let color = reveal(app.textFields["Color"], in: app)
    color.tap()
    color.typeText(" and silver\n")
    attach(app, "Vehicle editor facts")
    app.buttons["save-vehicle"].tap()
    XCTAssertTrue(text("Vehicle saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts["2015 Honda Fit · Blue and silver"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts[location].exists)
    attach(app, "Vehicle page after saving")

    // Version history opens this Vehicle's history.
    reveal(app.buttons["vehicle-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Vehicle version history")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Add Vehicle creates one with only a name, like Web.
    XCTAssertTrue(app.buttons["add-vehicle"].waitForExistence(timeout: 5))
    app.buttons["add-vehicle"].tap()
    let name = app.textFields["vehicle-title"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Harbor ferry bike")
    attach(app, "New Vehicle")
    app.buttons["save-vehicle"].tap()
    XCTAssertTrue(text("Vehicle created.", in: app).waitForExistence(timeout: 10))
    let created = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Harbor ferry bike")
    ).firstMatch
    XCTAssertTrue(created.waitForExistence(timeout: 10))
    XCTAssertTrue(text("2 vehicles", in: app).exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Vehicles with the new Vehicle")

    // Moving it to Trash from its page returns to the list without it.
    reveal(created, in: app).tap()
    XCTAssertTrue(app.buttons["edit-vehicle"].firstMatch.waitForExistence(timeout: 10))
    app.buttons["edit-vehicle"].firstMatch.tap()
    reveal(app.buttons["trash-vehicle"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "trash-vehicle")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(text("Vehicle moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["add-vehicle"].waitForExistence(timeout: 10))
    XCTAssertTrue(created.waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("1 vehicle", in: app).exists)
    attach(app, "Vehicles after Trash")
  }

  func testFirstTimesOpenTheirPageAndAddEditAndTrashFirstTimes() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))

    // Like Web, a First Time on the Timeline opens its own page.
    app.tabBars.buttons["Timeline"].tap()
    let onTimeline = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "First sourdough loaf")
    ).firstMatch
    dismissBirthDatePrompt(once: onTimeline, in: app)
    reveal(onTimeline, in: app).tap()
    let location = "Alberta Street, Portland, OR, United States"
    XCTAssertTrue(app.staticTexts[location].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-first-time"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["First Times"], in: app).tap()
    let seeded = app.buttons["First sourdough loaf, Mar 2, 2024"]
    XCTAssertTrue(seeded.waitForExistence(timeout: 15))
    XCTAssertTrue(text("1 First Time", in: app).exists)
    Thread.sleep(forTimeInterval: 1.5)
    attach(app, "First Times")

    // A card opens the First Time's page with its date, Location, Story, and organization.
    seeded.tap()
    XCTAssertTrue(app.staticTexts[location].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Mar 2, 2024"].exists)
    attach(app, "First Time page")

    // Edit shows the saved Location, and removing it saves with the other changes.
    app.buttons["edit-first-time"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Edit First Time"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "First Time editor")
    let title = app.textFields["first-time-title"]
    title.tap()
    title.typeText(" at home\n")
    // Scroll the saved Location clear of the sheet footer before removing it.
    app.swipeUp()
    XCTAssertTrue(reveal(app.buttons["Remove Location"], in: app).exists)
    XCTAssertTrue(app.staticTexts["45.55900, -122.64500"].exists)
    attach(app, "First Time editor Location")
    app.buttons["Remove Location"].tap()
    XCTAssertTrue(app.buttons["Remove Location"].waitForNonExistence(timeout: 5))
    app.swipeUp()
    attach(app, "First Time editor reflection and organization")
    app.buttons["save-first-time"].tap()
    XCTAssertTrue(text("First Time saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["First sourdough loaf at home"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts[location].exists)
    attach(app, "First Time page after saving")

    // Version history opens this First Time's history.
    reveal(app.buttons["first-time-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Add First Time creates one with only a title, like Web.
    XCTAssertTrue(app.buttons["add-first-time"].waitForExistence(timeout: 5))
    app.buttons["add-first-time"].tap()
    let name = app.textFields["first-time-title"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("First ferry ride")
    attach(app, "New First Time")
    app.buttons["save-first-time"].tap()
    XCTAssertTrue(text("First Time created.", in: app).waitForExistence(timeout: 10))
    let created = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "First ferry ride")
    ).firstMatch
    XCTAssertTrue(created.waitForExistence(timeout: 10))
    XCTAssertTrue(text("2 First Times", in: app).exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "First Times with the new First Time")

    // Moving it to Trash from its page returns to the list without it.
    reveal(created, in: app).tap()
    XCTAssertTrue(app.buttons["edit-first-time"].firstMatch.waitForExistence(timeout: 10))
    app.buttons["edit-first-time"].firstMatch.tap()
    reveal(app.buttons["trash-first-time"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Move to Trash", "trash-first-time")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(text("First Time moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["add-first-time"].waitForExistence(timeout: 10))
    XCTAssertTrue(created.waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("1 First Time", in: app).exists)
    attach(app, "First Times after Trash")
  }

  /// Timeline asks for the birth date on the first visit until one is saved, like Web. The
  /// Timeline test saves one for the shared seeded account, so later tests find no prompt.
  private func dismissBirthDatePrompt(once loaded: XCUIElement, in app: XCUIApplication) {
    let notNow = app.buttons["Not now"]
    let deadline = Date().addingTimeInterval(15)
    while !notNow.exists, !loaded.exists, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.25)
    }
    // The prompt opens once the profile and the Timeline have both loaded.
    if notNow.exists || notNow.waitForExistence(timeout: 3) { notNow.tap() }
    XCTAssertTrue(loaded.waitForExistence(timeout: 5))
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

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }
}
