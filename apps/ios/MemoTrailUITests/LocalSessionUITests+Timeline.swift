import XCTest

// The Timeline, signed in as the seeded account (birth date 1990-05-14): Chapters as bars and
// First Times as points on a canvas of years, items without a calendar date listed apart, and
// a birth date that is only asked for on request.
extension LocalSessionUITests {
  func testTimelineDrawsChaptersAndFirstTimesAndAddsAChapter() throws {
    let app = try launchLocalSession()
    openTimeline(in: app)
    let canvas = element("timeline-canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 15))
    XCTAssertTrue(
      element("timeline-axis", in: app).label.hasPrefix("Years 1990 to"),
      element("timeline-axis", in: app).label)

    // The summary counts a Chapter that is also a First Time under both.
    XCTAssertGreaterThanOrEqual(try summaryCount("Chapter", in: app), 4)
    XCTAssertGreaterThanOrEqual(try summaryCount("First Time", in: app), 3)

    // Chapters are bars, and a First Time that is also a Chapter is one bar, not a point too.
    let chapters = element("timeline-band-chapters", in: app)
    let points = element("timeline-band-first-times", in: app)
    XCTAssertTrue(chapters.exists)
    XCTAssertTrue(points.exists)
    let open = item("Living on Maple Street", in: chapters)
    XCTAssertTrue(open.exists)
    XCTAssertTrue(open.label.contains("Since Jun 1, 2024"), open.label)
    XCTAssertTrue(item("Living in Lisbon", in: chapters).exists)
    XCTAssertTrue(item("First job at the bookshop", in: chapters).exists)
    XCTAssertFalse(item("First job at the bookshop", in: points).exists)
    XCTAssertTrue(item("First sourdough loaf", in: points).exists)
    let marathon = item("Finished the first marathon", in: points)
    XCTAssertTrue(marathon.exists)
    XCTAssertTrue(marathon.label.contains("Oct 8, 2023"), marathon.label)
    XCTAssertFalse(item("Finished the first marathon", in: chapters).exists)
    XCTAssertFalse(element("timeline-undated-section", in: app).exists)
    attach(app, "Timeline canvas")

    // The canvas scrolls back across the years to the older Chapters.
    let viewport = element("timeline-viewport", in: app)
    for _ in 0..<3 { viewport.swipeRight(velocity: .fast) }
    attach(app, "Timeline canvas scrolled back")

    // A point opens its Item page.
    for _ in 0..<12 where !marathon.isHittable { viewport.swipeLeft(velocity: .slow) }
    marathon.tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 15))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 10))

    // The same canvas in dark mode.
    XCUIDevice.shared.appearance = .dark
    addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = .light }
    // The appearance change settles asynchronously, so give it a moment before the capture.
    _ = XCTWaiter.wait(for: [expectation(description: "appearance settles")], timeout: 2)
    attach(app, "Timeline canvas in dark mode")
    XCUIDevice.shared.appearance = .light

    // Add to Timeline offers a Chapter or a First Time, then opens the editor with it checked.
    let title = "Timeline test chapter \(UUID().uuidString.prefix(6))"
    app.buttons["timeline-add"].tap()
    XCTAssertTrue(app.buttons["timeline-type-first-time"].waitForExistence(timeout: 10))
    attach(app, "Add to Timeline chooser")
    app.buttons["timeline-type-chapter"].tap()
    let titleField = element("editor-title", in: app)
    XCTAssertTrue(titleField.waitForExistence(timeout: 10))
    // Chapter is already checked for a Chapter, so the editor asks for its title.
    XCTAssertTrue(element("editor-chapter", in: app).exists)
    titleField.tap()
    titleField.typeText(title)
    app.buttons["editor-save"].tap()
    XCTAssertTrue(app.buttons["editor-save"].waitForNonExistence(timeout: 20))

    // The new Chapter is on the Timeline, placed or listed apart, whichever its date says.
    let added = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    XCTAssertTrue(added.waitForExistence(timeout: 20), title)
    attach(app, "Timeline after adding a Chapter")

    // Move it to Trash so the seeded Timeline stays as other tests read it.
    for _ in 0..<12 where !added.isHittable { viewport.swipeLeft(velocity: .slow) }
    added.tap()
    reveal(app.buttons["item-trash"], in: app).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "Move to Trash", "item-trash")
    ).firstMatch
    if confirm.waitForExistence(timeout: 5) { confirm.tap() }
    XCTAssertTrue(app.buttons["item-edit"].waitForNonExistence(timeout: 15))
  }

  func testTimelineSetsABirthDateOnlyWhenAsked() throws {
    // Start from a profile with no birth date, and put the seeded one back afterwards.
    _ = try requestTimelineStack(
      "/rest/v1/profiles?birth_date=not.is.null", method: "PATCH", body: ["birth_date": nil])
    addTeardownBlock { @MainActor [self] in
      _ = try? requestTimelineStack(
        "/rest/v1/profiles?user_id=not.is.null", method: "PATCH",
        body: ["birth_date": "1990-05-14"])
    }
    let app = try launchLocalSession()
    openTimeline(in: app)
    XCTAssertTrue(element("timeline-canvas", in: app).waitForExistence(timeout: 15))
    let setBirthDate = app.buttons["timeline-set-birth-date"]
    XCTAssertTrue(setBirthDate.waitForExistence(timeout: 15))

    // Nothing asks unprompted, even with the profile and the Timeline both loaded.
    Thread.sleep(forTimeInterval: 3)
    XCTAssertFalse(app.buttons["timeline-save-birth-date"].exists)
    XCTAssertFalse(text("When did your story begin?", in: app).exists)
    // Without a birth date the Timeline starts at its earliest item, not at a life's start.
    XCTAssertFalse(element("timeline-axis", in: app).label.hasPrefix("Years 1990"))
    attach(app, "Timeline without a birth date")

    // Asking opens the prompt, and Cancel closes it without saving.
    setBirthDate.tap()
    XCTAssertTrue(text("When did your story begin?", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["timeline-save-birth-date"].isEnabled)
    attach(app, "Birth date prompt")
    app.buttons["timeline-cancel-birth-date"].tap()
    XCTAssertTrue(app.buttons["timeline-save-birth-date"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(setBirthDate.exists)

    // Picking a date saves it, the button goes away, and the Timeline begins with that year.
    setBirthDate.tap()
    XCTAssertTrue(app.buttons["timeline-save-birth-date"].waitForExistence(timeout: 10))
    let field = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Birth date"))
      .firstMatch
    field.tap()
    let done = app.buttons["date-picker-done"]
    XCTAssertTrue(done.waitForExistence(timeout: 10))
    attach(app, "Birth date picker")
    // The picker opens on today; Done keeps it, and the year wheel is not needed to save.
    done.tap()
    XCTAssertTrue(app.buttons["timeline-save-birth-date"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["timeline-save-birth-date"].isEnabled)
    app.buttons["timeline-save-birth-date"].tap()
    XCTAssertTrue(app.buttons["timeline-save-birth-date"].waitForNonExistence(timeout: 15))
    XCTAssertTrue(text("Birth date saved.", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(setBirthDate.waitForNonExistence(timeout: 10))
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    XCTAssertTrue(
      element("timeline-axis", in: app).label.hasPrefix("Years \(year) to"),
      element("timeline-axis", in: app).label)
    attach(app, "Timeline after setting a birth date")
  }

  func testTimelineListsUnanchoredItemsApart() throws {
    let suffix = String(UUID().uuidString.prefix(6)).lowercased()
    let described = try saveUnanchored(
      title: "Learned to ride a bike \(suffix)", isChapter: false, label: "Age 7")
    let plain = try saveUnanchored(
      title: "Lost years \(suffix)", isChapter: true, label: nil)
    addTeardownBlock { @MainActor [self] in
      for id in [described, plain] { try? moveToTrashThroughTimelineAPI(id) }
    }

    let app = try launchLocalSession()
    openTimeline(in: app)
    XCTAssertTrue(element("timeline-canvas", in: app).waitForExistence(timeout: 15))
    let section = element("timeline-undated-section", in: app)
    XCTAssertTrue(reveal(section, in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(text("These have no calendar date", in: app).exists)

    // Each one says what it knows about when, and the canvas leaves it out.
    let first = element("timeline-undated-\(described.uuidString.lowercased())", in: app)
    XCTAssertTrue(reveal(first, in: app).exists)
    XCTAssertEqual(first.label, "Learned to ride a bike \(suffix), Roughly: Age 7")
    let second = element("timeline-undated-\(plain.uuidString.lowercased())", in: app)
    XCTAssertTrue(reveal(second, in: app).exists)
    XCTAssertEqual(second.label, "Lost years \(suffix), Undated")
    XCTAssertFalse(item("Learned to ride a bike", in: element("timeline-canvas", in: app)).exists)
    XCTAssertFalse(item("Lost years", in: element("timeline-canvas", in: app)).exists)
    attach(app, "Timeline items without a calendar date")

    // An item in the list opens its Item page.
    first.tap()
    XCTAssertTrue(app.buttons["item-edit"].waitForExistence(timeout: 15))
  }

  /// The summary wraps without a separator at either end of a line, and the canvas still opens
  /// items at accessibility text sizes.
  func testTimelineSummaryAndCanvasHoldAtAccessibilityTextSizes() throws {
    let app = try launchLocalSession(contentSize: "UICTContentSizeCategoryAccessibilityL")
    openTimeline(in: app)
    XCTAssertTrue(element("timeline-canvas", in: app).waitForExistence(timeout: 20))
    let summary = app.otherElements["Timeline summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    let lines = assertSeparatorsBetweenFacts(revealWhole(summary, in: app), in: app)
    XCTAssertGreaterThan(lines.count, 1, "\(lines)")
    attach(app, "Timeline summary at accessibility size")
    reveal(element("timeline-canvas", in: app), in: app)
    attach(app, "Timeline canvas at accessibility size")
    let open = item("Living on Maple Street", in: element("timeline-band-chapters", in: app))
    XCTAssertTrue(open.exists)
  }

  // MARK: Helpers

  private func openTimeline(in app: XCUIApplication) {
    XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Timeline"].tap()
  }

  /// A bar or point in a band, found by the start of its name.
  private func item(_ title: String, in container: XCUIElement) -> XCUIElement {
    container.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
  }

  /// The number in a summary count such as "4 Chapters".
  private func summaryCount(_ noun: String, in app: XCUIApplication) throws -> Int {
    let count = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", "[0-9]+ \(noun)s?")
    ).firstMatch
    XCTAssertTrue(count.waitForExistence(timeout: 10), noun)
    return try XCTUnwrap(Int(count.label.prefix(while: \.isNumber)), count.label)
  }

  /// Saves a First Time or a Chapter with no calendar date, the way the editor would.
  private func saveUnanchored(title: String, isChapter: Bool, label: String?) throws -> UUID {
    let id = UUID()
    _ = try requestTimelineStack(
      "/rest/v1/rpc/save_entry",
      body: [
        "p_entry_id": id.uuidString.lowercased(), "p_expected_revision": nil, "p_title": title,
        "p_body": "", "p_body_rich": nil, "p_tag_names": [String](),
        "p_primary_location": nil, "p_photo_location": nil, "p_is_chapter": isChapter,
        "p_is_first_time": !isChapter, "p_date_precision": label == nil ? "unknown" : "age",
        "p_occurred_start": nil, "p_occurred_end": nil, "p_occurred_label": label,
        "p_occurred_timezone": "UTC",
      ])
    return id
  }

  private func moveToTrashThroughTimelineAPI(_ id: UUID) throws {
    let rows = try requestTimelineStack(
      "/rest/v1/entries?id=eq.\(id.uuidString.lowercased())&select=revision", method: "GET")
    let revision = try XCTUnwrap(((rows as? [[String: Any]])?.first)?["revision"] as? Int)
    _ = try requestTimelineStack(
      "/rest/v1/entries?id=eq.\(id.uuidString.lowercased())&revision=eq.\(revision)",
      method: "PATCH", body: ["deleted_at": ISO8601DateFormatter().string(from: Date())])
  }

  /// The signed-in session the app was launched with, to call the local stack like a client.
  private func timelineSession() throws -> (url: URL, key: String, token: String) {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"] ?? ""
    let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
    let session = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return (
      try XCTUnwrap((session["supabaseURL"] as? String).flatMap(URL.init(string:))),
      try XCTUnwrap(session["publishableKey"] as? String),
      try XCTUnwrap(session["accessToken"] as? String)
    )
  }

  @discardableResult
  private func requestTimelineStack(
    _ path: String, method: String = "POST", body: [String: Any?]? = nil
  ) throws -> Any? {
    let session = try timelineSession()
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
}
