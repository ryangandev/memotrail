import XCTest

// The Item page, signed in as the seeded account: a closed Chapter (Living in Lisbon) with six
// Entries inside it and a Chapter nested in it (Portuguese lessons), and moving an Entry to Trash.
extension LocalSessionUITests {
  func testItemPageShowsAChapterWithItsEntriesAndOverlaps() throws {
    let app = try launchLocalSession()
    try openFromLibrarySearch("Living in Lisbon", in: app)

    // A Chapter names its kind, its dates and length, and lists the Entries dated inside it.
    XCTAssertTrue(app.navigationBars["Chapter"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["item-edit"].label, "Edit Chapter")
    XCTAssertTrue(text("Feb 1, 2022", in: app).exists)
    attach(app, "Chapter Item page")

    let entries = reveal(element("item-chapter-entries", in: app), in: app)
    XCTAssertTrue(entries.waitForExistence(timeout: 15))
    XCTAssertTrue(text("6 Entries", in: app).waitForExistence(timeout: 10))
    for title in [
      "First morning in Alfama", "Tram 28 to the castle", "Ranking the custard tarts",
      "A night of fado", "Beach day in Cascais", "Packing the last boxes",
    ] {
      XCTAssertTrue(entryButton(title, in: app).waitForExistence(timeout: 5), title)
    }
    // Oldest first, like Web, and not the Chapter nested inside.
    let first = entryButton("First morning in Alfama", in: app).frame.minY
    let last = entryButton("Packing the last boxes", in: app).frame.minY
    XCTAssertLessThan(first, last)
    attach(app, "Chapter Entries")

    // The Chapter that overlaps it is listed below, with its dates.
    let overlap = entryButton("Portuguese lessons", in: app)
    reveal(overlap, in: app)
    XCTAssertTrue(element("item-chapter-overlaps", in: app).exists)
    XCTAssertTrue(overlap.label.contains("Mar 1, 2022"), overlap.label)
    attach(app, "Chapters during this time")

    // The same page in dark mode.
    XCUIDevice.shared.appearance = .dark
    defer { XCUIDevice.shared.appearance = .light }
    attach(app, "Chapters during this time in dark mode")
    reveal(entryButton("First morning in Alfama", in: app), in: app)
    attach(app, "Chapter Entries in dark mode")

    // The overlapping Chapter lists the three Entries inside it and the one around it.
    reveal(overlap, in: app).tap()
    XCTAssertTrue(app.navigationBars["Chapter"].waitForExistence(timeout: 10))
    XCTAssertTrue(text("3 Entries", in: app).waitForExistence(timeout: 15))
    XCTAssertTrue(entryButton("Tram 28 to the castle", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(entryButton("First morning in Alfama", in: app).exists)
    XCTAssertTrue(reveal(entryButton("Living in Lisbon", in: app), in: app).exists)
    attach(app, "Nested Chapter in dark mode")

    // An Entry opens its own page, which has no Chapter parts.
    reveal(entryButton("A night of fado", in: app), in: app).tap()
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["item-edit"].label, "Edit Entry")
    XCTAssertFalse(element("item-chapter-entries", in: app).exists)
    attach(app, "Entry Item page in dark mode")
  }

  func testItemPageMovesAnEntryToTrash() throws {
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let title = "Letting go \(marker)"
    let entryID = try saveEntryThroughAPI(title: title, body: "Made to leave.")
    let app = try launchLocalSession()
    try openFromLibrarySearch(marker, in: app)
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 10))
    XCTAssertTrue(text(title, in: app).exists)
    attach(app, "Entry before Trash")

    // Move to Trash asks first and names the Entry, and Cancel leaves it alone.
    reveal(app.buttons["item-trash"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "item-trash")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertTrue(text("Move “\(title)” to Trash?", in: app).exists)
    XCTAssertTrue(text("You can restore it later from Trash.", in: app).exists)
    attach(app, "Move to Trash confirmation")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.buttons["item-edit"].exists)

    // Confirming leaves the page, and the Entry waits in Trash to be restored.
    reveal(app.buttons["item-trash"], in: app).tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForNonExistence(timeout: 15))
    XCTAssertTrue(try entryIsInTrash(entryID))
    app.tabBars.buttons["More"].tap()
    reveal(app.buttons["more-trash"], in: app).tap()
    XCTAssertTrue(app.buttons["Restore \(title)"].waitForExistence(timeout: 15))
    attach(app, "Trash after moving an Entry from its page")
  }

  // MARK: Helpers

  /// Opens Library ready to type, searches, and opens the first result named like `query`.
  private func openFromLibrarySearch(_ query: String, in app: XCUIApplication) throws {
    XCTAssertTrue(app.buttons["workspace-search"].waitForExistence(timeout: 20))
    app.buttons["workspace-search"].tap()
    let field = app.textFields["Search your Life Wiki"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.typeText("\(query)\n")
    XCTAssertTrue(element("library-results", in: app).waitForExistence(timeout: 15))
    let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", query))
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    reveal(result, in: app).tap()
  }

  /// A row of an Item page's lists, found by the title it shows.
  private func entryButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
  }

  /// The signed-in session the app was launched with, to call the local stack like a client.
  private func localSession() throws -> (url: URL, key: String, token: String) {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
    let session = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return (
      try XCTUnwrap((session["supabaseURL"] as? String).flatMap(URL.init(string:))),
      try XCTUnwrap(session["publishableKey"] as? String),
      try XCTUnwrap(session["accessToken"] as? String)
    )
  }

  private func requestLocalStack(
    _ path: String, method: String = "POST", body: [String: Any?]? = nil
  ) throws -> Any? {
    let session = try localSession()
    var request = URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: session.url)))
    request.httpMethod = method
    request.setValue(session.key, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(
        withJSONObject: body.mapValues { $0 ?? NSNull() })
    }
    var result: (Data?, URLResponse?, Error?)?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
      result = (data, response, error)
      done.signal()
    }.resume()
    XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
    let (data, response, error) = try XCTUnwrap(result)
    XCTAssertNil(error)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    XCTAssertTrue((200..<300).contains(status), "\(path): \(status) \(text)")
    return data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
  }

  /// Saves a new dated Entry like the editor does, so a test can move one to Trash without
  /// touching the seeded records other tests read.
  private func saveEntryThroughAPI(title: String, body: String) throws -> UUID {
    let id = UUID()
    _ = try requestLocalStack(
      "/rest/v1/rpc/save_entry",
      body: [
        "p_entry_id": id.uuidString.lowercased(), "p_expected_revision": nil, "p_title": title,
        "p_body": body, "p_body_rich": nil, "p_tag_names": [String](),
        "p_primary_location": nil, "p_photo_location": nil, "p_is_chapter": false,
        "p_is_first_time": false, "p_date_precision": "day",
        "p_occurred_start": "2026-10-17T12:00:00-07:00", "p_occurred_end": nil,
        "p_occurred_label": nil, "p_occurred_timezone": "America/Los_Angeles",
      ])
    return id
  }

  private func entryIsInTrash(_ id: UUID) throws -> Bool {
    let rows = try requestLocalStack(
      "/rest/v1/entries?id=eq.\(id.uuidString.lowercased())&select=deleted_at", method: "GET")
    let row = try XCTUnwrap((rows as? [[String: Any]])?.first)
    return !(row["deleted_at"] is NSNull) && row["deleted_at"] != nil
  }
}
