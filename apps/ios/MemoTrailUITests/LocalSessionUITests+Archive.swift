import XCTest

// Carried over for P8 (Tags, Trash, Settings, Export), which owns and verifies them. P1 moved
// the counts to the new seed and replaced the retired Collections with seeded Trash items.
extension LocalSessionUITests {
  func testExportPreparesDownloadsAndDiscardsASnapshot() throws {
    try XCTSkipUnless(servesMediaAPI(), "Export needs the local Web API; run with --web.")
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["more-settings"], in: app).tap()
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
    reveal(app.buttons["more-tags"], in: app).tap()
    // The seed tags three Entries with coast and three with family; one has both.
    let coast = app.buttons["Manage tag coast, used by 3 Entries"]
    XCTAssertTrue(coast.waitForExistence(timeout: 15))
    let family = app.buttons["Manage tag family, used by 3 Entries"]
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

    // A tag's editor lists the Entries using it, and each opens its Item page.
    coast.tap()
    XCTAssertTrue(text("Used by 3 Entries", in: app).waitForExistence(timeout: 5))
    let quiet = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "A quiet afternoon by the coast")
    ).firstMatch
    XCTAssertTrue(quiet.waitForExistence(timeout: 10))
    attach(app, "Tag editor")
    quiet.tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // Merging keeps every assignment on the destination tag.
    XCTAssertTrue(family.waitForExistence(timeout: 10))
    family.tap()
    reveal(app.buttons["Destination tag"], in: app).tap()
    app.buttons["#coast (3)"].tap()
    reveal(app.buttons["merge-tag"], in: app).tap()
    let merge = app.buttons["Merge tags"]
    XCTAssertTrue(merge.waitForExistence(timeout: 5))
    attach(app, "Tag merge confirmation")
    merge.tap()
    XCTAssertTrue(text("Tags merged.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(family.waitForNonExistence(timeout: 10))
    let merged = app.buttons["Manage tag coast, used by 5 Entries"]
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
    XCTAssertTrue(app.staticTexts["5 items"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("Filters · 1 active", in: app).exists)
    attach(app, "Library filtered to a tag")
  }

  func testTrashRestoresDeletesForeverAndEmptiesTrash() throws {
    let app = try launchLocalSession()
    XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
    app.tabBars.buttons["More"].tap()

    // The seed leaves an Entry and a photo in Trash.
    reveal(app.buttons["more-trash"], in: app).tap()
    let restore = app.buttons["Restore ferry-blurry.png"]
    XCTAssertTrue(restore.waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 1)
    attach(app, "Trash")
    reveal(restore, in: app).tap()
    XCTAssertTrue(text("Item restored.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(restore.waitForNonExistence(timeout: 10))

    // Delete forever asks first, then removes only that item.
    let delete = app.buttons["Delete Duplicate grocery note forever"]
    reveal(delete, in: app).tap()
    XCTAssertTrue(
      app.staticTexts["Delete “Duplicate grocery note” forever?"].waitForExistence(timeout: 5))
    attach(app, "Delete forever confirmation")
    app.buttons["confirm-delete-forever"].tap()
    XCTAssertTrue(text("Item permanently deleted.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(delete.waitForNonExistence(timeout: 10))

    // An Entry moved to Trash from its Item page goes for good with Empty Trash.
    app.tabBars.buttons["Library"].tap()
    let pancakes = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Rainy Sunday pancakes")
    ).firstMatch
    reveal(pancakes, in: app).tap()
    reveal(app.buttons["item-trash"], in: app).tap()
    let moveToTrash = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "item-trash")
    ).firstMatch
    XCTAssertTrue(moveToTrash.waitForExistence(timeout: 5))
    moveToTrash.tap()
    app.tabBars.buttons["More"].tap()
    XCTAssertTrue(app.buttons["Restore Rainy Sunday pancakes"].waitForExistence(timeout: 15))
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
}
