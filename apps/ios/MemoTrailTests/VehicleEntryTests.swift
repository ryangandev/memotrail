import XCTest

@testable import MemoTrail

final class VehicleEntryTests: XCTestCase {
  func testWorkspaceDecodesFactsOrganizationTimelineAndPrivatePhoto() throws {
    let rows = try decoder.decode([VehicleWorkspaceRow].self, from: Data(workspaceJSON.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.title, "Blue Civic")
    XCTAssertEqual(entry.factsLabel, "2018 Honda Civic · Midnight blue")
    XCTAssertEqual(entry.displayRange, "College years")
    XCTAssertEqual(entry.collectionNames, ["Life chapters"])
    XCTAssertEqual(entry.tagNames, ["road-trips"])
    XCTAssertEqual(entry.timelineTrackName, "Vehicles")
    XCTAssertEqual(entry.attachments.first?.mimeType, .jpeg)
    XCTAssertNil(entry.attachments.first?.signedURL)
  }

  func testWorkspaceSortsCurrentBeforeEarlierAndNewestFirst() {
    let current = makeRow(title: "Current", start: Date(timeIntervalSince1970: 100), end: nil)
    let recent = makeRow(title: "Recent", start: Date(timeIntervalSince1970: 300))
    let older = makeRow(title: "Older", start: Date(timeIntervalSince1970: 200))

    XCTAssertEqual(
      VehicleWorkspace.entries(from: [older, current, recent]).map(\.title),
      ["Current", "Recent", "Older"]
    )
  }

  func testFactsLabelHandlesCompleteAndIncompleteRecords() {
    XCTAssertEqual(makeRow().entry.factsLabel, "2018 Honda Civic · Blue")
    XCTAssertEqual(
      makeRow(make: nil, model: nil, modelYear: nil, color: nil).entry.factsLabel,
      "Details not recorded"
    )
  }

  func testRangeAndDurationMatchArchiveSemantics() {
    let entry = makeRow(
      start: isoDate("2020-03-12T20:00:00Z"),
      end: isoDate("2026-08-31T20:00:00Z")
    ).entry

    XCTAssertEqual(entry.displayRange, "Mar 12, 2020 - Aug 31, 2026")
    XCTAssertEqual(entry.durationLabel(), "6 years 5 months")
  }

  func testOpenVehicleRangeAndDurationUseProvidedNow() {
    let entry = makeRow(
      start: isoDate("2025-01-01T20:00:00Z"),
      end: nil
    ).entry

    XCTAssertEqual(entry.displayRange, "Since Jan 1, 2025")
    XCTAssertEqual(entry.durationLabel(now: isoDate("2026-03-01T20:00:00Z")), "1 year 2 months")
  }

  func testValidationNormalizesTextAndOrganization() throws {
    let input = try makeInput(
      title: "  Blue Civic  ",
      body: "  First long road trip  ",
      make: " Honda ",
      model: " Civic ",
      color: " Blue ",
      collectionNames: [" Vehicles ", "vehicles", "Life"],
      tagNames: [" Road ", "road", "Blue"]
    )

    XCTAssertEqual(input.title, "Blue Civic")
    XCTAssertEqual(input.body, "First long road trip")
    XCTAssertEqual(input.make, "Honda")
    XCTAssertEqual(input.model, "Civic")
    XCTAssertEqual(input.color, "Blue")
    XCTAssertEqual(input.collectionNames, ["Vehicles", "Life"])
    XCTAssertEqual(input.tagNames, ["Road", "Blue"])
  }

  func testValidationRejectsMissingTitleAndReversedRange() {
    XCTAssertThrowsError(try makeInput(title: " ")) { error in
      XCTAssertEqual(error as? VehicleEntryError, .titleRequired)
    }
    XCTAssertThrowsError(
      try makeInput(
        occurredStart: Date(timeIntervalSince1970: 200),
        occurredEnd: Date(timeIntervalSince1970: 100)
      )
    ) { error in
      XCTAssertEqual(error as? VehicleEntryError, .reversedRange)
    }
  }

  func testValidationRejectsModelYearOutsideVehicleHistory() {
    XCTAssertThrowsError(try makeInput(modelYear: 1885)) { error in
      XCTAssertEqual(error as? VehicleEntryError, .invalidModelYear)
    }
    XCTAssertNoThrow(try makeInput(modelYear: 2200))
  }

  func testValidationRequiresRevisionOnlyForExistingVehicle() {
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? VehicleEntryError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeInput(
        entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testSaveParametersUseRPCNamesAndExplicitNulls() throws {
    let input = try makeInput(
      entryID: nil,
      expectedRevision: nil,
      occurredEnd: nil,
      make: "",
      model: "",
      modelYear: nil,
      color: ""
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(SaveVehicleEntryParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_occurred_end"] is NSNull)
    XCTAssertTrue(json["p_make"] is NSNull)
    XCTAssertTrue(json["p_model_year"] is NSNull)
    XCTAssertTrue(json["p_color"] is NSNull)
    XCTAssertEqual(json["p_date_precision"] as? String, "range")
  }

  func testCaptureExtractionParametersUseSourceIdentityAndVehicleFacts() throws {
    let entryID = UUID(uuidString: "92000000-0000-4000-8000-000000000001")!
    let entry = InboxEntry(
      id: entryID, title: "Blue Civic", body: "First commute", createdAt: Date(),
      occurredStart: Date(timeIntervalSince1970: 100), occurredTimezone: "America/Los_Angeles",
      revision: 5, datePrecision: .range, occurredEnd: Date(timeIntervalSince1970: 200))
    let source = CaptureExtractionSource(
      entry: entry, title: "Blue Civic", body: "First commute", occurrence: entry.occurrence,
      collectionNames: ["Cars"], tagNames: ["commute"])
    let input = try makeInput(collectionNames: source.collectionNames, tagNames: source.tagNames)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: encoder.encode(SaveVehicleEntryParameters(input: input, source: source)))
        as? [String: Any])

    XCTAssertEqual(json["p_capture_id"] as? String, entryID.uuidString)
    XCTAssertEqual(json["p_capture_revision"] as? Int, 5)
    XCTAssertEqual(json["p_make"] as? String, "Honda")
    XCTAssertEqual(json["p_model_year"] as? Int, 2018)
    XCTAssertNil(json["p_entry_id"])
  }

  func testLocationRemovalSendsWebInputWithNullSourceAndLocation() throws {
    var input = try makeInput(
      entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"), expectedRevision: 4,
      color: "", collectionNames: ["Cars"], tagNames: ["commute"])
    input.occurredStartRaw = "2020-03-12T20:00:00.123456+00:00"
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: encoder.encode(RemoveVehicleLocationParameters(input: input))) as? [String: Any])
    let fields = try XCTUnwrap(json["p_input"] as? [String: Any])

    XCTAssertTrue(json["p_source"] is NSNull)
    XCTAssertTrue(json["p_location"] is NSNull)
    XCTAssertEqual(fields["id"] as? String, "10000000-0000-4000-8000-000000000001")
    XCTAssertEqual(fields["revision"] as? Int, 4)
    XCTAssertEqual(fields["title"] as? String, "Blue Civic")
    XCTAssertEqual(fields["occurredStart"] as? String, "2020-03-12T20:00:00.123456+00:00")
    XCTAssertEqual(fields["occurredEnd"] as? String, "1970-01-01T00:03:20Z")
    XCTAssertEqual(fields["datePrecision"] as? String, "range")
    XCTAssertEqual(fields["occurredTimezone"] as? String, "America/Los_Angeles")
    XCTAssertEqual(fields["modelYear"] as? Int, 2018)
    XCTAssertEqual(fields["collectionNames"] as? [String], ["Cars"])
    XCTAssertEqual(fields["tagNames"] as? [String], ["commute"])
    XCTAssertNil(fields["color"])
    XCTAssertNil(fields["occurredLabel"])
  }

  func testPrimaryLocationsDecodeEmbeddedRowsAndLabelLikeWeb() throws {
    let rows = try JSONDecoder().decode(
      [EntryPrimaryLocations.Row].self,
      from: Data(
        """
        [{"entry_id":"10000000-0000-4000-8000-000000000001","location":{
          "id":"50000000-0000-4000-8000-000000000001","revision":2,"name":"Pier 39",
          "formatted_address":"Pier 39, San Francisco, CA","address":"Beach Street",
          "city":"San Francisco","region":"CA","country":"United States",
          "latitude":37.8087,"longitude":-122.4098}},
         {"entry_id":"10000000-0000-4000-8000-000000000002","location":null}]
        """.utf8))
    let locations = EntryPrimaryLocations.assemble(rows)
    let location = try XCTUnwrap(
      locations[UUID(uuidString: "10000000-0000-4000-8000-000000000001")!])

    XCTAssertEqual(locations.count, 1)
    XCTAssertEqual(location.label, "Pier 39, San Francisco, CA")
    XCTAssertEqual(location.latitude, 37.8087)
    let manual = EntryLocation(
      id: UUID(), revision: 1, name: "Home", formattedAddress: " ", address: nil,
      city: "Oakland", region: "CA", country: nil, latitude: nil, longitude: nil)
    XCTAssertEqual(manual.label, "Oakland, CA")
    let empty = EntryLocation(
      id: UUID(), revision: 1, name: "Home", formattedAddress: nil, address: nil, city: nil,
      region: nil, country: nil, latitude: nil, longitude: nil)
    XCTAssertEqual(empty.label, "Location not set")
  }

  func testAllChapterPrecisionsValidateWithoutInventedDates() throws {
    for precision in TimelineDatePrecision.allCases {
      let unanchored = [.age, .approximate, .unknown].contains(precision)
      let input = try makeInput(
        occurredStart: unanchored ? nil : Date(timeIntervalSince1970: 100),
        datePrecision: precision,
        occurredLabel: [.age, .approximate].contains(precision) ? "During college" : "",
        occurredEnd: unanchored ? nil : Date(timeIntervalSince1970: 200))
      XCTAssertEqual(input.occurredStart == nil, unanchored)
      XCTAssertEqual(input.datePrecision, precision)
    }
    XCTAssertThrowsError(try makeInput(occurredStart: nil, occurredEnd: nil))
    XCTAssertThrowsError(try makeInput(occurredStart: nil, datePrecision: .age, occurredEnd: nil))
  }

  func testChapterDurationRespectsMonthYearAndUnknownPrecision() {
    var value = EntryOccurrence(
      precision: .month, start: isoDate("2020-03-12T12:00:00Z"),
      end: isoDate("2026-09-03T12:00:00Z"), label: nil, timezone: "UTC")
    XCTAssertEqual(value.spanLabel, "Mar 2020 - Sep 2026")
    XCTAssertEqual(value.durationLabel(), "About 6 years 6 months")
    value.precision = .year
    XCTAssertEqual(value.spanLabel, "2020 - 2026")
    XCTAssertEqual(value.durationLabel(), "About 6 years")
    value.precision = .unknown
    value.start = nil
    value.end = nil
    XCTAssertEqual(value.durationLabel(), "Duration unavailable")
  }

  func testWorkspaceDecodingAndSaveRetainRawExactBounds() throws {
    let base: [String: Any] = [
      "entry_id": UUID().uuidString, "title": "Chapter", "body": "Memory",
      "occurred_start": "2026-11-01T09:30:00.123456Z",
      "occurred_end": "2026-11-01T10:30:00.654321Z",
      "date_precision": "exact", "occurred_timezone": "America/Los_Angeles",
      "revision": 1, "updated_at": "2026-09-12T12:00:00Z",
      "place_id": UUID().uuidString, "place_name": "Home",
      "collection_names": [], "tag_names": [], "attachments": [], "total_count": 1,
    ]
    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: text) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      return try XCTUnwrap(formatter.date(from: text))
    }
    let row = try jsonDecoder.decode(
      VehicleWorkspaceRow.self, from: JSONSerialization.data(withJSONObject: base))
    let entry = row.entry
    let resolved = try OccurrenceDraft(entry.occurrence).resolve(
      original: entry.occurrence, span: true)
    var input = try makeInput(
      occurredStart: resolved.start, datePrecision: .exact, occurredEnd: resolved.end)
    input.preserveUnchangedBounds(from: entry)
    let encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(SaveVehicleEntryParameters(input: input))) as? [String: Any])
    XCTAssertEqual(encoded["p_occurred_start"] as? String, base["occurred_start"] as? String)
    XCTAssertEqual(encoded["p_occurred_end"] as? String, base["occurred_end"] as? String)
    for precision in ["age", "approximate", "unknown"] {
      var undated = base
      undated["occurred_start"] = NSNull()
      undated["occurred_end"] = NSNull()
      undated["occurred_timezone"] = NSNull()
      undated["date_precision"] = precision
      undated["occurred_label"] = "During college"
      let record = try jsonDecoder.decode(
        VehicleWorkspaceRow.self, from: JSONSerialization.data(withJSONObject: undated)
      ).entry
      XCTAssertNil(record.occurredStart)
      XCTAssertEqual(record.displayRange, "During college")
      XCTAssertEqual(record.durationLabel(), "Duration unavailable")
    }
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func isoDate(_ value: String) -> Date {
    try! decoder.decode(Date.self, from: Data("\"\(value)\"".utf8))
  }

  private func makeInput(
    entryID: UUID? = nil,
    expectedRevision: Int? = nil,
    title: String = "Blue Civic",
    body: String = "Memories",
    occurredStart: Date? = Date(timeIntervalSince1970: 100),
    datePrecision: TimelineDatePrecision = .range,
    occurredLabel: String = "",
    occurredEnd: Date? = Date(timeIntervalSince1970: 200),
    make: String = "Honda",
    model: String = "Civic",
    modelYear: Int? = 2018,
    color: String = "Blue",
    collectionNames: [String] = [],
    tagNames: [String] = []
  ) throws -> VehicleEntryInput {
    try VehicleEntryInput.validate(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: "America/Los_Angeles",
      make: make,
      model: model,
      modelYear: modelYear,
      color: color,
      collectionNames: collectionNames,
      tagNames: tagNames
    )
  }

  private func makeRow(
    id: UUID = UUID(),
    title: String = "Blue Civic",
    start: Date = Date(timeIntervalSince1970: 100),
    end: Date? = Date(timeIntervalSince1970: 200),
    make: String? = "Honda",
    model: String? = "Civic",
    modelYear: Int? = 2018,
    color: String? = "Blue"
  ) -> VehicleWorkspaceRow {
    VehicleWorkspaceRow(
      entryID: id,
      title: title,
      body: "Memories",
      occurredStart: start,
      occurredEnd: end,
      datePrecision: .range,
      occurredLabel: nil,
      occurredTimezone: "America/Los_Angeles",
      revision: 1,
      updatedAt: end ?? start,
      make: make,
      model: model,
      modelYear: modelYear,
      color: color,
      timelineTrackID: nil,
      timelineTrackName: "Vehicles",
      collectionNames: [],
      tagNames: [],
      attachments: [],
      totalCount: 1
    )
  }

  private var workspaceJSON: String {
    """
    [{
      "entry_id":"10000000-0000-4000-8000-000000000001",
      "title":"Blue Civic","body":"Road trips.",
      "occurred_start":"2020-03-12T20:00:00Z","occurred_end":null,
      "date_precision":"range","occurred_label":"College years",
      "occurred_timezone":"America/Los_Angeles","revision":3,
      "updated_at":"2026-09-03T19:00:00Z","make":"Honda","model":"Civic",
      "model_year":2018,"color":"Midnight blue",
      "timeline_track_id":"30000000-0000-4000-8000-000000000001",
      "timeline_track_name":"Vehicles","collection_names":["Life chapters"],
      "tag_names":["road-trips"],"attachments":[{
        "id":"40000000-0000-4000-8000-000000000001","bucket_id":"entry-media",
        "object_path":"owner/entry/vehicle.jpg","original_filename":"vehicle.jpg",
        "mime_type":"image/jpeg","byte_size":2048,"pixel_width":1200,
        "pixel_height":800,"created_at":"2026-09-03T19:00:00Z"
      }],"total_count":1
    }]
    """
  }
}
