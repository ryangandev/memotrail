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
    // More groups its destinations like Web's mobile More menu.
    for group in ["Explore", "Focused views", "Organize", "Archive and account"] {
      XCTAssertTrue(app.staticTexts[group].waitForExistence(timeout: 5), group)
    }
    attach(app, "More")
    // The header mark opens the Dashboard, like Web's brand link.
    app.buttons["workspace-brand"].tap()
    XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
    app.tabBars.buttons["More"].tap()
    for route in [
      "Map", "People", "Homes", "Vehicles", "First Times", "Goals", "Collections", "Tags",
      "Version history", "Trash", "Settings",
    ] {
      reveal(app.buttons[route], in: app).tap()
      Thread.sleep(forTimeInterval: 1.5)
      attach(app, route)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
  }

  func testCollectionsOpenEntriesFilterLibraryAndAddEditAndTrashCollections() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Collections"], in: app).tap()
    let summer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Summer 2025"))
      .firstMatch
    XCTAssertTrue(summer.waitForExistence(timeout: 15))
    XCTAssertTrue(text("2 Collections · 4 Entry placements", in: app).exists)
    XCTAssertTrue(app.buttons["Edit Summer 2025"].exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Collections")

    // New Collection creates one, and a lower display order places it first.
    app.buttons["new-collection"].tap()
    let name = app.textFields["organization-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Road trips")
    let order = app.textFields["organization-order"]
    order.tap()
    order.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "-5")
    XCTAssertEqual(order.value as? String, "-5")
    attach(app, "New Collection")
    app.buttons["save-organization"].tap()
    XCTAssertTrue(text("Collection created.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(text("3 Collections · 4 Entry placements", in: app).waitForExistence(timeout: 10))
    let road = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Road trips"))
      .firstMatch
    XCTAssertTrue(road.exists)
    XCTAssertLessThan(road.frame.minY, summer.frame.minY)

    // A Collection lists its Entries with Web's rich notes and organization links.
    summer.tap()
    XCTAssertTrue(app.navigationBars["Summer 2025"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("3 Entries", in: app).exists)
    let letters = app.buttons["Letters from the coast house"]
    XCTAssertTrue(letters.waitForExistence(timeout: 15))
    let fullNote = reveal(app.buttons["Read full note"], in: app)
    fullNote.tap()
    XCTAssertEqual(fullNote.value as? String, "Expanded")
    attach(app, "Collection Entries")

    // An Entry's tag opens Library filtered to it, like Web `/library?tag=`.
    reveal(app.buttons["Tag walks"], in: app).tap()
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    // The seeded Goal shares the tag with this Entry.
    XCTAssertTrue(app.staticTexts["2 items"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Filters · 1 active", in: app).exists)
    app.tabBars.buttons["More"].tap()

    // Its title opens the Entry, and New entry opens Quick Capture over the page.
    let quiet = app.buttons["A quiet afternoon by the coast"]
    reveal(quiet, in: app).tap()
    XCTAssertTrue(app.buttons["edit-item"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(letters.waitForExistence(timeout: 10))
    while !app.buttons["New entry"].isHittable { app.swipeDown() }
    app.buttons["New entry"].tap()
    XCTAssertTrue(app.navigationBars["New Entry"].waitForExistence(timeout: 10))
    app.navigationBars["New Entry"].buttons["Close"].tap()
    XCTAssertTrue(app.navigationBars["Summer 2025"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // An empty Collection moves to Trash from its own page, which then closes.
    XCTAssertTrue(road.waitForExistence(timeout: 10))
    road.tap()
    XCTAssertTrue(text("This Collection is empty", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Open Inbox"].exists)
    attach(app, "Empty Collection")
    app.buttons["Edit Road trips"].tap()
    XCTAssertTrue(app.staticTexts["Edit Collection"].waitForExistence(timeout: 5))
    app.buttons["remove-organization"].tap()
    // The confirmation repeats the footer's label, so skip the footer button itself.
    let trash = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Move to Trash", "remove-organization")
    ).firstMatch
    XCTAssertTrue(trash.waitForExistence(timeout: 5))
    attach(app, "Collection trash confirmation")
    trash.tap()
    XCTAssertTrue(text("Collection moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(text("2 Collections · 4 Entry placements", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(road.waitForNonExistence(timeout: 10))

    // Settings' Archive organization leaves the sheet for Collections, like Web's link.
    app.tabBars.buttons["Dashboard"].tap()
    app.buttons["workspace-settings"].tap()
    reveal(app.buttons["Archive organization"], in: app).tap()
    XCTAssertTrue(app.buttons["new-collection"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.navigationBars["Settings"].exists)
    XCTAssertTrue(app.tabBars.buttons["More"].isSelected)
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
    XCTAssertTrue(app.navigationBars["Goal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-goal"].exists)
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

  func testExportPreparesDownloadsAndDiscardsASnapshot() throws {
    try XCTSkipUnless(servesMediaAPI(), "Export needs the local Web API; run with --web.")
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Settings"], in: app).tap()
    reveal(app.buttons["Export archive"], in: app).tap()
    XCTAssertTrue(
      text("No snapshots yet. Your archive is unchanged.", in: app).waitForExistence(timeout: 15))
    attach(app, "Export")

    // Prepare snapshot captures one consistent copy, which downloads as a complete ZIP.
    app.buttons["Prepare snapshot"].tap()
    XCTAssertTrue(text("Snapshot prepared.", in: app).waitForExistence(timeout: 30))
    let download = app.buttons["Download ZIP"]
    XCTAssertTrue(download.waitForExistence(timeout: 15))
    reveal(download, in: app).tap()
    let share = app.buttons["Save or share ZIP"]
    XCTAssertTrue(share.waitForExistence(timeout: 60))
    attach(app, "Export ZIP ready")
    app.buttons["Remove local copy"].tap()
    XCTAssertTrue(share.waitForNonExistence(timeout: 5))

    // Discard asks beside the snapshot, then removes the temporary copy.
    reveal(app.buttons["Discard snapshot"], in: app).tap()
    let confirm = app.buttons["Confirm discard"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    attach(app, "Export discard confirmation")
    confirm.tap()
    XCTAssertTrue(text("Temporary copy discarded.", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(
      text("No snapshots yet. Your archive is unchanged.", in: app).waitForExistence(timeout: 15))
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
    XCTAssertTrue(app.navigationBars["Goal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-goal"].waitForExistence(timeout: 10))
    app.navigationBars["Goal"].buttons.element(boundBy: 0).tap()
    reveal(app.buttons["library-clear-search"], in: app).tap()
    XCTAssertTrue(element("library-items", in: app).waitForExistence(timeout: 10))
    XCTAssertEqual(field.value as? String, "A phrase, date, or question about your life...")

    reveal(app.buttons["library-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
  }

  func testItemPageLinksItemsRestoresVersionsAndCreatesLinkedGoals() throws {
    let app = try launchLocalSession()

    // Library opens a plain Entry on its Item page, like Web `/items/<id>`.
    XCTAssertTrue(app.buttons["workspace-search"].waitForExistence(timeout: 20))
    app.buttons["workspace-search"].tap()
    let field = app.textFields["Search your Life Wiki"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.typeText("Evening walks\n")
    let result = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Evening walks along the river")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    result.tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-item"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      text("Most evenings that spring ended with the same loop", in: app).exists)
    XCTAssertTrue(text("Summer 2025", in: app).exists)
    attach(app, "Item page")

    // Find Items links another Entry at once.
    reveal(app.buttons["Find Items"], in: app).tap()
    let search = app.textFields["Search related Items"]
    reveal(search, in: app).tap()
    search.typeText("recipe\n")
    let link = app.buttons["Link Grandmother's recipe cards"]
    XCTAssertTrue(link.waitForExistence(timeout: 10))
    reveal(link, in: app).tap()
    XCTAssertTrue(text("Item linked.", in: app).waitForExistence(timeout: 10))
    let unlink = app.buttons["Unlink Grandmother's recipe cards"]
    XCTAssertTrue(unlink.waitForExistence(timeout: 10))
    reveal(unlink, in: app)
    attach(app, "Item page Related Items")

    // The linked Entry opens on its own Item page, which lists this one under Linked from.
    app.buttons["Grandmother's recipe cards"].tap()
    XCTAssertTrue(
      app.staticTexts["A shoebox of index cards, most of them stained with butter."]
        .waitForExistence(timeout: 10))
    reveal(app.buttons["Linked from"], in: app).tap()
    XCTAssertTrue(
      reveal(app.buttons["Evening walks along the river"], in: app).waitForExistence(timeout: 10))
    attach(app, "Linked Item page")
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Version history compares the version before the link, and restoring it removes the link.
    reveal(app.buttons["item-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      text("Differences from current version: Entry links.", in: app).waitForExistence(timeout: 10))
    attach(app, "Item version history")
    reveal(app.buttons["restore-version"], in: app).tap()
    let restore = app.buttons["Restore version"]
    XCTAssertTrue(restore.waitForExistence(timeout: 5))
    restore.tap()
    XCTAssertTrue(text("Version restored.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      reveal(text("No matching linked Items.", in: app), in: app).waitForExistence(timeout: 10))
    attach(app, "Item version history after restoring")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["edit-item"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      reveal(text("No matching linked Items.", in: app), in: app).waitForExistence(timeout: 10))

    // Current photos load on request through the Web media API, when the review serves it.
    reveal(app.buttons["entry-photos-load"], in: app).tap()
    let photos = servesMediaAPI() ? "No saved photos on this Entry." : "Could not load photos."
    XCTAssertTrue(reveal(text(photos, in: app), in: app).waitForExistence(timeout: 10))
    attach(app, "Item page current photos")

    // Create linked Goal starts from this Entry's title and opens the new Goal.
    reveal(app.buttons["create-linked-goal"], in: app).tap()
    let goalTitle = app.textFields["linked-goal-title"]
    XCTAssertTrue(goalTitle.waitForExistence(timeout: 5))
    XCTAssertEqual(goalTitle.value as? String, "Evening walks along the river")
    attach(app, "Create linked Goal")
    app.buttons["save-linked-goal"].tap()
    XCTAssertTrue(text("Goal created.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-goal"].waitForExistence(timeout: 10))
    attach(app, "Linked Goal")
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Move to Trash confirms, then returns to Library.
    reveal(app.buttons["trash-item"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "trash-item")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(text("Entry moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(field.waitForExistence(timeout: 10))
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

  func testTagsFindPreviewMergeAddAndDeleteTags() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Tags"], in: app).tap()
    let coast = app.buttons["Manage tag coast, used by 2 Entries"]
    XCTAssertTrue(coast.waitForExistence(timeout: 15))
    let family = app.buttons["Manage tag family, used by 2 Entries"]
    XCTAssertTrue(family.exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Tags")

    // Search narrows the badges by name.
    let search = app.textFields["Find a tag"]
    search.tap()
    search.typeText("coa\n")
    XCTAssertTrue(family.waitForNonExistence(timeout: 10))
    XCTAssertTrue(coast.exists)
    attach(app, "Tags search")
    app.buttons["Clear find a tag"].tap()
    app.buttons["Search"].tap()
    XCTAssertTrue(family.waitForExistence(timeout: 10))

    // A tag's editor lists the Entries using it, and each opens its Item.
    coast.tap()
    XCTAssertTrue(app.staticTexts["Edit Tag"].waitForExistence(timeout: 5))
    XCTAssertTrue(text("Used by 2 Entries", in: app).exists)
    let quiet = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "A quiet afternoon by the coast")
    ).firstMatch
    XCTAssertTrue(quiet.waitForExistence(timeout: 10))
    attach(app, "Tag editor")
    quiet.tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-item"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Merging keeps every assignment on the destination tag.
    XCTAssertTrue(family.waitForExistence(timeout: 10))
    family.tap()
    reveal(app.buttons["Destination tag"], in: app).tap()
    app.buttons["#coast (2)"].tap()
    reveal(app.buttons["merge-tag"], in: app).tap()
    let merge = app.buttons["Merge tags"]
    XCTAssertTrue(merge.waitForExistence(timeout: 5))
    attach(app, "Tag merge confirmation")
    merge.tap()
    XCTAssertTrue(text("Tags merged.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(family.waitForNonExistence(timeout: 10))
    let merged = app.buttons["Manage tag coast, used by 3 Entries"]
    XCTAssertTrue(merged.waitForExistence(timeout: 10))

    // New Tag creates an unused tag, which can then be deleted.
    app.buttons["new-tag"].tap()
    let name = app.textFields["organization-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Create a Tag"].exists)
    name.tap()
    name.typeText("sunsets")
    attach(app, "New Tag")
    app.buttons["save-organization"].tap()
    XCTAssertTrue(text("Tag created.", in: app).waitForExistence(timeout: 10))
    let sunsets = app.buttons["Manage tag sunsets, used by 0 Entries"]
    XCTAssertTrue(sunsets.waitForExistence(timeout: 10))
    sunsets.tap()
    XCTAssertTrue(text("No Entries use this tag yet.", in: app).waitForExistence(timeout: 5))
    app.buttons["remove-organization"].tap()
    let delete = app.buttons["Delete tag"]
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertTrue(text("Tag deleted.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(sunsets.waitForNonExistence(timeout: 10))

    // View all Entries opens Library filtered to the tag, like Web `/library?tag=`.
    merged.tap()
    reveal(app.buttons["view-tag-entries"], in: app, above: app.buttons["save-organization"]).tap()
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["3 items"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Filters · 1 active", in: app).exists)
    attach(app, "Library filtered to a tag")
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

    // Version history restores the Home from before the edit, and its page shows it on return.
    reveal(app.buttons["home-version-history"], in: app).tap()
    XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      text("Differences from current version:", in: app).waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Home version history")
    reveal(app.buttons["restore-version"], in: app).tap()
    let restore = app.buttons["Restore version"]
    XCTAssertTrue(restore.waitForExistence(timeout: 5))
    restore.tap()
    XCTAssertTrue(text("Version restored.", in: app).waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.staticTexts["Closer to work"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts["Closer to work and the park"].waitForNonExistence(timeout: 5))
    attach(app, "Home page after restoring")
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

  func testTrashRestoresDeletesForeverAndEmptiesTrash() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()

    // Two new Collections move to Trash, so Trash has its own items to restore and delete.
    reveal(app.buttons["Collections"], in: app).tap()
    for name in ["Old drafts", "Spare room"] { createAndTrashCollection(name, in: app) }
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Trash"], in: app).tap()
    let restore = app.buttons["Restore Old drafts"]
    XCTAssertTrue(restore.waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Trash")
    reveal(restore, in: app).tap()
    XCTAssertTrue(text("Item restored.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(restore.waitForNonExistence(timeout: 10))

    // Delete forever asks first, then removes only that item.
    let delete = app.buttons["Delete Spare room forever"]
    reveal(delete, in: app).tap()
    XCTAssertTrue(app.staticTexts["Delete “Spare room” forever?"].waitForExistence(timeout: 5))
    attach(app, "Delete forever confirmation")
    app.buttons["confirm-delete-forever"].tap()
    XCTAssertTrue(text("Item permanently deleted.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(delete.waitForNonExistence(timeout: 10))

    // The restored Collection is back, and Empty Trash removes it for good with the rest.
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Collections"], in: app).tap()
    XCTAssertTrue(app.buttons["Edit Old drafts"].waitForExistence(timeout: 15))
    trashCollection("Old drafts", in: app)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Trash"], in: app).tap()
    XCTAssertTrue(app.buttons["Restore Old drafts"].waitForExistence(timeout: 15))
    while !app.buttons["empty-trash"].isHittable { app.swipeDown() }
    app.buttons["empty-trash"].tap()
    let confirm = app.buttons["confirm-empty-trash"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    attach(app, "Empty Trash confirmation")
    confirm.tap()
    let emptied = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", "^[0-9]+ confirmed items? permanently deleted\\..*")
    ).firstMatch
    XCTAssertTrue(emptied.waitForExistence(timeout: 30))
    XCTAssertTrue(text("Nothing in Trash", in: app).waitForExistence(timeout: 10))
    attach(app, "Empty Trash")
  }

  private func createAndTrashCollection(_ name: String, in app: XCUIApplication) {
    XCTAssertTrue(app.buttons["new-collection"].waitForExistence(timeout: 15))
    app.buttons["new-collection"].tap()
    let field = app.textFields["organization-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(name)
    app.buttons["save-organization"].tap()
    XCTAssertTrue(text("Collection created.", in: app).waitForExistence(timeout: 10))
    trashCollection(name, in: app)
  }

  private func trashCollection(_ name: String, in app: XCUIApplication) {
    reveal(app.buttons["Edit \(name)"], in: app).tap()
    app.buttons["remove-organization"].tap()
    // The confirmation repeats the footer's label, so skip the footer button itself.
    let trash = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@", "Move to Trash", "remove-organization")
    ).firstMatch
    XCTAssertTrue(trash.waitForExistence(timeout: 5))
    trash.tap()
    XCTAssertTrue(text("Collection moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Edit \(name)"].waitForNonExistence(timeout: 10))
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

  func testGoalsOpenTheirPageAndLinksAndRecordABucketListAchievement() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["Goals"], in: app).tap()
    let seeded = app.buttons["Hike the coast trail, Active"]
    XCTAssertTrue(seeded.waitForExistence(timeout: 15))
    XCTAssertTrue(text("1 goal", in: app).exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Goals")

    // A card opens the Goal's page with its state, horizon, target, and connected Items.
    seeded.tap()
    XCTAssertTrue(app.staticTexts["Target Oct 31, 2026"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Short-term"].exists)
    let home = reveal(app.buttons["Maple Street flat"], in: app)
    XCTAssertTrue(app.buttons["Finished the first marathon"].exists)
    attach(app, "Goal page")

    // Like Web, a connected Home opens its own page and a Moment opens on the Timeline.
    home.tap()
    XCTAssertTrue(app.buttons["edit-home"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["Finished the first marathon"], in: app).tap()
    XCTAssertTrue(app.staticTexts["Edit moment"].waitForExistence(timeout: 10))
    attach(app, "Connected Moment on the Timeline")
    app.buttons["close-timeline-editor"].tap()
    app.tabBars.buttons["More"].tap()
    XCTAssertTrue(app.buttons["edit-goal"].waitForExistence(timeout: 10))

    // Edit replaces a related Item and saves, like Web.
    app.buttons["edit-goal"].tap()
    XCTAssertTrue(app.staticTexts["Edit Goal"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Goal editor")
    reveal(app.buttons["Remove related Item Finished the first marathon"], in: app).tap()
    reveal(app.buttons["Choose a related Item"], in: app).tap()
    let hatchback = app.buttons["Blue hatchback · Vehicle"]
    XCTAssertTrue(hatchback.waitForExistence(timeout: 5))
    hatchback.tap()
    app.buttons["add-goal-related-item"].tap()
    XCTAssertTrue(app.buttons["Remove related Item Blue hatchback"].waitForExistence(timeout: 5))
    attach(app, "Goal editor related Items")
    app.buttons["save-goal"].tap()
    XCTAssertTrue(text("Goal saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(reveal(app.buttons["Blue hatchback"], in: app).exists)
    XCTAssertFalse(app.buttons["Finished the first marathon"].exists)
    attach(app, "Goal page after saving")
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // A new Goal in Bucket List can be marked achieved from its editor.
    XCTAssertTrue(app.buttons["add-goal"].waitForExistence(timeout: 5))
    app.buttons["add-goal"].tap()
    let title = app.textFields["goal-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Learn to sail\n")
    // Scroll Organization clear of the sheet footer before adding a Collection.
    app.swipeUp()
    reveal(app.buttons["organization-add-collection"], in: app).tap()
    let collections = app.textFields["organization-search-collection"]
    XCTAssertTrue(collections.waitForExistence(timeout: 3))
    collections.typeText("Bucket List")
    app.buttons["organization-done"].tap()
    XCTAssertTrue(
      app.buttons["Remove Bucket List from Collections"].waitForExistence(timeout: 3))
    attach(app, "New Goal")
    app.buttons["save-goal"].tap()
    XCTAssertTrue(text("Goal created.", in: app).waitForExistence(timeout: 10))
    let created = app.buttons["Learn to sail, Considering"]
    XCTAssertTrue(created.waitForExistence(timeout: 10))
    XCTAssertTrue(text("1 in Bucket List", in: app).exists)
    attach(app, "Goals with the new Goal")

    reveal(created, in: app).tap()
    XCTAssertTrue(app.buttons["edit-goal"].waitForExistence(timeout: 10))
    app.buttons["edit-goal"].tap()
    let achieve = reveal(app.buttons["achieve-bucket-list-goal"], in: app)
    XCTAssertTrue(app.staticTexts["Turn this achievement into a First Time"].exists)
    attach(app, "Bucket List milestone")
    achieve.tap()
    let achieved = text("Achievement saved, with a linked First Time.", in: app)
    XCTAssertTrue(achieved.waitForExistence(timeout: 10))
    // The editor stays open on the achieved Goal, like Web.
    XCTAssertTrue(app.buttons["achieve-bucket-list-goal"].waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.buttons["Reflective state"].value as? String, "Achieved")
    attach(app, "Goal editor after the achievement")
    XCTAssertTrue(achieved.waitForNonExistence(timeout: 10))
    app.buttons["close-goal-editor"].tap()
    XCTAssertTrue(app.buttons["save-goal"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Achieved"].waitForExistence(timeout: 10))
    XCTAssertTrue(reveal(app.buttons["Learn to sail"], in: app).exists)
    attach(app, "Achieved Goal page")

    // Moving it to Trash from its page returns to the list without it.
    app.buttons["edit-goal"].tap()
    reveal(app.buttons["trash-goal"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "trash-goal")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(text("Goal moved to Trash.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["add-goal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Learn to sail, Achieved"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(text("1 goal", in: app).exists)
    attach(app, "Goals after Trash")
  }

  func testPeopleOpenTheirPageAndLinksAndEditTheirItems() throws {
    let app = try launchLocalSession()

    // Library finds a Person from People and opens their page, like Web `/people/<id>`.
    XCTAssertTrue(app.buttons["workspace-search"].waitForExistence(timeout: 20))
    app.buttons["workspace-search"].tap()
    let field = app.textFields["Search your Life Wiki"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.typeText("Avery\n")
    let result = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Person, Avery Lane")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    result.tap()
    XCTAssertTrue(app.navigationBars["Person"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["edit-person"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Running partner"].exists)

    // People lists each Person as a card that opens their page.
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["People"], in: app).tap()
    let card = app.buttons["Avery Lane, Running partner"]
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    XCTAssertTrue(text("1 person", in: app).exists)
    XCTAssertTrue(text("1 connected Item", in: app).exists)
    Thread.sleep(forTimeInterval: 1)
    attach(app, "People")
    card.tap()
    XCTAssertTrue(app.staticTexts["Running partner"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Notes"].exists)
    let marathon = reveal(app.buttons["Finished the first marathon"], in: app)
    attach(app, "Person page")

    // Like Web, a connected Moment opens on the Timeline.
    marathon.tap()
    XCTAssertTrue(app.staticTexts["Edit moment"].waitForExistence(timeout: 10))
    app.buttons["close-timeline-editor"].tap()
    app.tabBars.buttons["More"].tap()
    XCTAssertTrue(app.buttons["edit-person"].waitForExistence(timeout: 10))

    // Edit swaps the linked Item. A Person with links cannot move to Trash yet.
    app.buttons["edit-person"].tap()
    XCTAssertTrue(app.staticTexts["Edit Person"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["trash-person"].isEnabled)
    // A linked Item opens to show its text, like Web `details`.
    app.buttons.matching(
      NSPredicate(format: "label == %@ AND value == %@", "Finished the first marathon", "Collapsed")
    ).firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Slow, happy, and soaked by the last mile."].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.6)
    attach(app, "Person editor")
    reveal(app.buttons["Unlink Finished the first marathon"], in: app).tap()
    reveal(app.buttons["Link an Item"], in: app).tap()
    let flat = app.buttons["Maple Street flat"]
    XCTAssertTrue(flat.waitForExistence(timeout: 5))
    flat.tap()
    app.buttons["person-link-item-add"].tap()
    XCTAssertTrue(app.buttons["Unlink Maple Street flat"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      text("Unlink every Item and save before removing this Person.", in: app).exists)
    attach(app, "Person editor connected Items")
    app.buttons["save-person"].tap()
    XCTAssertTrue(text("Person saved.", in: app).waitForExistence(timeout: 10))
    let home = reveal(app.buttons["Maple Street flat"], in: app)
    XCTAssertFalse(app.buttons["Finished the first marathon"].exists)
    attach(app, "Person page after saving")

    // A connected Home opens its own page.
    home.tap()
    XCTAssertTrue(app.buttons["edit-home"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Once every link is removed and saved, the Person moves to Trash from their page.
    XCTAssertTrue(app.buttons["edit-person"].waitForExistence(timeout: 10))
    app.buttons["edit-person"].tap()
    reveal(app.buttons["Unlink Maple Street flat"], in: app).tap()
    app.buttons["save-person"].tap()
    XCTAssertTrue(app.buttons["save-person"].waitForNonExistence(timeout: 10))
    app.buttons["edit-person"].tap()
    let trash = app.buttons["trash-person"]
    XCTAssertTrue(trash.waitForExistence(timeout: 5))
    XCTAssertTrue(trash.isEnabled)
    trash.tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "trash-person")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(text("Person moved to Trash.", in: app).waitForExistence(timeout: 10))
    let empty = text("Remember the first person in your story", in: app)
    XCTAssertTrue(empty.waitForExistence(timeout: 10))
    attach(app, "People after Trash")

    // Add Person starts from a name alone.
    app.buttons["add-person"].tap()
    let name = app.textFields["person-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Keep someone in your story"].exists)
    name.tap()
    name.typeText("Jordan Reyes")
    attach(app, "New Person")
    app.buttons["save-person"].tap()
    XCTAssertTrue(text("Person created.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.buttons["Jordan Reyes, A person in your story"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("0 connected Items", in: app).exists)
    attach(app, "People with the new Person")
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

  /// Whether `review-local-session.py --web` serves the Web media API for this run.
  private func servesMediaAPI() -> Bool {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    guard let data = FileManager.default.contents(atPath: path),
      let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return session["apiURL"] is String
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }
}
