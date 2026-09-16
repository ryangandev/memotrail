import XCTest

@testable import MemoTrail

final class ResidenceEntryTests: XCTestCase {
  func testWorkspaceDecodesHomePlaceOrganizationAndPrivatePhoto() throws {
    let json = """
      [
        {
          "entry_id": "10000000-0000-4000-8000-000000000001",
          "title": "Philadelphia home",
          "body": "The rowhouse years.",
          "occurred_start": "2012-08-15T19:00:00Z",
          "occurred_end": "2025-06-01T19:00:00Z",
          "date_precision": "range",
          "occurred_label": "Ages 12 to 25",
          "occurred_timezone": "America/New_York",
          "revision": 3,
          "updated_at": "2026-09-03T19:00:00Z",
          "move_in_reason": "Family move",
          "move_out_reason": "California",
          "place_id": "20000000-0000-4000-8000-000000000001",
          "place_name": "Philadelphia rowhouse",
          "address": "123 Private St",
          "city": "Philadelphia",
          "region": "PA",
          "country": "USA",
          "latitude": 39.9526,
          "longitude": -75.1652,
          "place_notes": "Brick front",
          "timeline_track_id": "30000000-0000-4000-8000-000000000001",
          "timeline_track_name": "Homes",
          "collection_names": ["Life chapters"],
          "tag_names": ["east-coast"],
          "attachments": [
            {
              "id": "40000000-0000-4000-8000-000000000001",
              "bucket_id": "entry-media",
              "object_path": "owner/entry/home.jpg",
              "original_filename": "home.jpg",
              "mime_type": "image/jpeg",
              "byte_size": 2048,
              "pixel_width": 1200,
              "pixel_height": 800,
              "created_at": "2026-09-03T19:00:00Z"
            }
          ],
          "total_count": 1
        }
      ]
      """

    let rows = try decoder.decode([ResidenceWorkspaceRow].self, from: Data(json.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.title, "Philadelphia home")
    XCTAssertEqual(entry.displayLocation, "Philadelphia, PA, USA")
    XCTAssertEqual(entry.displayRange, "Ages 12 to 25")
    XCTAssertEqual(entry.collectionNames, ["Life chapters"])
    XCTAssertEqual(entry.tagNames, ["east-coast"])
    XCTAssertEqual(entry.attachments.first?.mimeType, .jpeg)
    XCTAssertNil(entry.attachments.first?.signedURL)
  }

  func testWorkspaceSortsCurrentBeforeEarlierAndNewestFirst() {
    let current = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      title: "Current",
      start: Date(timeIntervalSince1970: 100),
      end: nil
    )
    let recent = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
      title: "Recent",
      start: Date(timeIntervalSince1970: 300),
      end: Date(timeIntervalSince1970: 400)
    )
    let older = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
      title: "Older",
      start: Date(timeIntervalSince1970: 200),
      end: Date(timeIntervalSince1970: 250)
    )

    XCTAssertEqual(
      ResidenceWorkspace.entries(from: [older, current, recent]).map(\.title),
      ["Current", "Recent", "Older"]
    )
  }

  func testRangeLocationAndDurationMatchArchiveSemantics() {
    let entry = makeRow(
      title: "California",
      start: isoDate("2025-01-15T20:00:00Z"),
      end: isoDate("2026-03-14T20:00:00Z"),
      city: "San Diego",
      region: "San Diego"
    ).entry

    XCTAssertEqual(entry.displayRange, "Jan 15, 2025 - Mar 14, 2026")
    XCTAssertEqual(entry.displayLocation, "San Diego, USA")
    XCTAssertEqual(entry.durationLabel(), "1 year 1 month")
  }

  func testDurationHandlesShortAndOpenResidences() {
    let short = makeRow(
      start: isoDate("2026-01-31T20:00:00Z"),
      end: isoDate("2026-02-28T20:00:00Z")
    ).entry
    let current = makeRow(
      start: isoDate("2025-01-01T20:00:00Z"),
      end: nil
    ).entry

    XCTAssertEqual(short.durationLabel(), "Less than a month")
    XCTAssertEqual(current.durationLabel(now: isoDate("2026-03-01T20:00:00Z")), "1 year 2 months")
  }

  func testValidationNormalizesAllTextAndOrganization() throws {
    let input = try makeInput(
      title: "  California apartment  ",
      body: "  Sunny kitchen  ",
      placeName: "  Mission Valley  ",
      collectionNames: [" Homes ", "homes", "Life"],
      tagNames: [" West ", "west", "Sunny"]
    )

    XCTAssertEqual(input.title, "California apartment")
    XCTAssertEqual(input.body, "Sunny kitchen")
    XCTAssertEqual(input.placeName, "Mission Valley")
    XCTAssertEqual(input.collectionNames, ["Homes", "Life"])
    XCTAssertEqual(input.tagNames, ["West", "Sunny"])
  }

  func testValidationRejectsRequiredAndInvalidRangeFields() {
    XCTAssertThrowsError(try makeInput(title: " ")) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .titleRequired)
    }
    XCTAssertThrowsError(try makeInput(placeName: " ")) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .placeRequired)
    }
    XCTAssertThrowsError(
      try makeInput(
        occurredStart: Date(timeIntervalSince1970: 200),
        occurredEnd: Date(timeIntervalSince1970: 100)
      )
    ) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .reversedRange)
    }
    XCTAssertThrowsError(try makeInput(occurredEnd: nil, moveOutReason: "New city")) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .moveOutRequiresDate)
    }
  }

  func testValidationRejectsPartialOrOutOfRangeCoordinates() {
    XCTAssertThrowsError(try makeInput(latitude: 39, longitude: nil)) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .invalidCoordinates)
    }
    XCTAssertThrowsError(try makeInput(latitude: 91, longitude: 0)) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .invalidCoordinates)
    }
  }

  func testValidationRequiresRevisionOnlyForExistingHome() {
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? ResidenceEntryError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeInput(
        entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testSaveParametersEncodeExplicitNulls() throws {
    let input = try makeInput(
      occurredEnd: nil,
      placeID: nil,
      address: "",
      latitude: nil,
      longitude: nil
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(SaveResidenceEntryParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_occurred_end"] is NSNull)
    XCTAssertTrue(json["p_place_id"] is NSNull)
    XCTAssertTrue(json["p_address"] is NSNull)
    XCTAssertTrue(json["p_latitude"] is NSNull)
    XCTAssertEqual(json["p_date_precision"] as? String, "range")
  }

  func testCaptureExtractionParametersUseSourceIdentityAndSpecializedFields() throws {
    let entryID = UUID(uuidString: "91000000-0000-4000-8000-000000000001")!
    let entry = InboxEntry(
      id: entryID, title: "Our first apartment", body: "Moving day", createdAt: Date(),
      occurredStart: Date(timeIntervalSince1970: 100), occurredTimezone: "America/New_York",
      revision: 4, datePrecision: .range, occurredEnd: Date(timeIntervalSince1970: 200))
    let source = CaptureExtractionSource(
      entry: entry, title: "Our first apartment", body: "Moving day",
      occurrence: entry.occurrence, collectionNames: ["Philadelphia"], tagNames: ["home"])
    let input = try makeInput(collectionNames: source.collectionNames, tagNames: source.tagNames)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: encoder.encode(SaveResidenceEntryParameters(input: input, source: source)))
        as? [String: Any])

    XCTAssertEqual(json["p_capture_id"] as? String, entryID.uuidString)
    XCTAssertEqual(json["p_capture_revision"] as? Int, 4)
    XCTAssertEqual(json["p_place_name"] as? String, "Place")
    XCTAssertEqual(json["p_collection_names"] as? [String], ["Philadelphia"])
    XCTAssertNil(json["p_entry_id"])
  }

  func testUniversalAttachmentParametersPreservePrivateMetadata() throws {
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let draft = try FirstTimePhotoDraft.validate(
      id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
      data: Data([1, 2, 3]),
      mimeType: .png,
      originalFilename: nil,
      pixelWidth: 10,
      pixelHeight: 20
    )
    let data = try JSONEncoder().encode(
      RegisterResidenceAttachmentParameters(
        entryID: entryID,
        draft: draft,
        objectPath: "owner/entry/photo.png"
      ))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_entry_id"] as? String, entryID.uuidString)
    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 3)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
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
      "date_precision": "exact", "occurred_timezone": "America/New_York",
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
      ResidenceWorkspaceRow.self, from: JSONSerialization.data(withJSONObject: base))
    let entry = row.entry
    let resolved = try OccurrenceDraft(entry.occurrence).resolve(
      original: entry.occurrence, span: true)
    var input = try makeInput(
      occurredStart: resolved.start, datePrecision: .exact, occurredEnd: resolved.end)
    input.preserveUnchangedBounds(from: entry)
    let encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(SaveResidenceEntryParameters(input: input))) as? [String: Any])
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
        ResidenceWorkspaceRow.self, from: JSONSerialization.data(withJSONObject: undated)
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
    title: String = "Home",
    body: String = "Memories",
    occurredStart: Date? = Date(timeIntervalSince1970: 100),
    datePrecision: TimelineDatePrecision = .range,
    occurredLabel: String = "",
    occurredEnd: Date? = Date(timeIntervalSince1970: 200),
    placeID: UUID? = nil,
    placeName: String = "Place",
    address: String = "Address",
    latitude: Double? = 39,
    longitude: Double? = -75,
    moveOutReason: String = "",
    collectionNames: [String] = [],
    tagNames: [String] = []
  ) throws -> ResidenceEntryInput {
    try ResidenceEntryInput.validate(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: "America/New_York",
      placeID: placeID,
      placeName: placeName,
      address: address,
      city: "Philadelphia",
      region: "PA",
      country: "USA",
      latitude: latitude,
      longitude: longitude,
      placeNotes: "",
      moveInReason: "",
      moveOutReason: moveOutReason,
      collectionNames: collectionNames,
      tagNames: tagNames
    )
  }

  private func makeRow(
    id: UUID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
    title: String = "Home",
    start: Date = Date(timeIntervalSince1970: 100),
    end: Date? = Date(timeIntervalSince1970: 200),
    city: String? = "Philadelphia",
    region: String? = "PA"
  ) -> ResidenceWorkspaceRow {
    ResidenceWorkspaceRow(
      entryID: id,
      title: title,
      body: "Memories",
      occurredStart: start,
      occurredEnd: end,
      datePrecision: .range,
      occurredLabel: nil,
      occurredTimezone: "America/New_York",
      revision: 1,
      updatedAt: Date(timeIntervalSince1970: 300),
      moveInReason: nil,
      moveOutReason: nil,
      placeID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      placeName: "Place",
      address: nil,
      city: city,
      region: region,
      country: "USA",
      latitude: nil,
      longitude: nil,
      placeNotes: nil,
      timelineTrackID: nil,
      timelineTrackName: "Homes",
      collectionNames: [],
      tagNames: [],
      attachments: [],
      totalCount: 1
    )
  }
}
