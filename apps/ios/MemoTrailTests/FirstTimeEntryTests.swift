import XCTest

@testable import MemoTrail

final class FirstTimeEntryTests: XCTestCase {
  func testMediaDeliveryAcceptsOnlyRequestedImagesOnTheConfiguredServer() throws {
    let base = try XCTUnwrap(URL(string: "https://memotrail.example"))
    let path = "owner/entry/photo.jpg"
    let valid = "https://memotrail.example/api/media/image?token=scoped"
    XCTAssertEqual(
      MediaDelivery.validatedURLs([path: valid], paths: [path], base: base)[path]?.absoluteString,
      valid)
    for url in [
      "https://other.example/api/media/image?token=scoped",
      "http://memotrail.example/api/media/image?token=scoped",
      "https://memotrail.example/api/export?token=scoped",
      "https://memotrail.example/api/media/image",
    ] {
      XCTAssertTrue(MediaDelivery.validatedURLs([path: url], paths: [path], base: base).isEmpty)
    }
    XCTAssertTrue(
      MediaDelivery.validatedURLs(["not-requested": valid], paths: [path], base: base).isEmpty)
  }

  func testNativeSerializationRetainsUnchangedDatabaseMicroseconds() throws {
    let timestamp = "2026-11-01T09:30:00.123456+00:00"
    let date = Date(timeIntervalSince1970: 1793525400.123456)
    var original = makeRow(
      title: "First trip", occurredStart: date, datePrecision: .exact,
      occurredTimezone: "America/Los_Angeles"
    ).entry
    original.occurredStartRaw = timestamp
    var input = try FirstTimeEntryInput.validate(
      entryID: original.id, expectedRevision: original.revision, title: original.title,
      body: "Updated writing", occurredStart: date, datePrecision: .exact, occurredLabel: "",
      occurredTimezone: original.occurredTimezone, collectionNames: [], tagNames: [])
    input.preserveUnchangedBounds(from: original)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let fields = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoder.encode(SaveFirstTimeEntryParameters(input: input)))
        as? [String: Any])
    XCTAssertEqual(fields["p_occurred_start"] as? String, timestamp)
    XCTAssertTrue(fields["p_occurred_end"] is NSNull)
  }
  func testRangeAndExactDatesSurviveDedicatedEditorAndEncoding() throws {
    let start = Date(timeIntervalSince1970: 1793525400.123)
    let end = start.addingTimeInterval(86400)
    for precision in [TimelineDatePrecision.exact, .range] {
      let original = EntryOccurrence(
        precision: precision, start: start, end: precision == .range ? end : nil, label: nil,
        timezone: "America/Los_Angeles")
      let resolved = try OccurrenceDraft(original).resolve(original: original)
      XCTAssertEqual(resolved, original)
      let input = try FirstTimeEntryInput.validate(
        entryID: nil, expectedRevision: nil, title: "First experience", body: "Original",
        occurredStart: resolved.start,
        datePrecision: FirstTimeDatePrecision(rawValue: resolved.precision.rawValue)!,
        occurredLabel: "", occurredTimezone: resolved.timezone, collectionNames: [], tagNames: [],
        occurredEnd: resolved.end)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let fields = try XCTUnwrap(
        JSONSerialization.jsonObject(
          with: encoder.encode(SaveFirstTimeEntryParameters(input: input))) as? [String: Any])
      XCTAssertEqual(fields["p_date_precision"] as? String, precision.rawValue)
      XCTAssertNotNil(fields["p_occurred_end"])
      if precision == .range { XCTAssertEqual(input.occurredEnd, end) }
    }
  }

  func testAgeAndUnknownFirstTimesDoNotInventDates() throws {
    for precision in [FirstTimeDatePrecision.age, .approximate, .unknown] {
      let input = try FirstTimeEntryInput.validate(
        entryID: nil, expectedRevision: nil, title: "First experience", body: "",
        occurredStart: nil, datePrecision: precision,
        occurredLabel: precision == .unknown ? "" : "17岁", occurredTimezone: nil,
        collectionNames: [], tagNames: [])
      XCTAssertNil(input.occurredStart)
      XCTAssertNil(input.occurredEnd)
    }
  }
  func testWorkspaceDecodesEntryWithPrivateAttachmentMetadata() throws {
    let json = """
      [
        {
          "entry_id": "10000000-0000-4000-8000-000000000001",
          "title": "First ski trip",
          "body": "Fresh snow in Tahoe.",
          "inbox_status": "organized",
          "occurred_start": "2026-07-03T19:00:00Z",
          "date_precision": "day",
          "occurred_label": null,
          "occurred_timezone": "America/Los_Angeles",
          "revision": 2,
          "updated_at": "2026-09-02T19:00:00Z",
          "collection_names": ["Milestones"],
          "tag_names": ["outdoors"],
          "attachments": [
            {
              "id": "20000000-0000-4000-8000-000000000001",
              "parentAttachmentId": null,
              "variant": "original",
              "bucketId": "entry-media",
              "objectPath": "owner/entry/photo.jpg",
              "originalFilename": "snow.jpg",
              "mimeType": "image/jpeg",
              "byteSize": 2048,
              "pixelWidth": 1200,
              "pixelHeight": 800,
              "createdAt": "2026-09-02T19:00:00Z"
            }
          ]
        }
      ]
      """

    let rows = try decoder.decode([FirstTimeWorkspaceRow].self, from: Data(json.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.title, "First ski trip")
    XCTAssertEqual(entry.collectionNames, ["Milestones"])
    XCTAssertEqual(entry.tagNames, ["outdoors"])
    XCTAssertEqual(entry.attachments.first?.mimeType, .jpeg)
    XCTAssertEqual(entry.attachments.first?.byteSize, 2048)
    XCTAssertNil(entry.attachments.first?.signedURL)
    XCTAssertEqual(entry.occurredStartRaw, "2026-07-03T19:00:00Z")
  }

  func testWorkspaceSortsDatedEntriesBeforeUnknownDates() {
    let recent = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      title: "Recent",
      occurredStart: Date(timeIntervalSince1970: 300),
      updatedAt: Date(timeIntervalSince1970: 300)
    )
    let older = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
      title: "Older",
      occurredStart: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: 400)
    )
    let unknown = makeRow(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
      title: "Unknown",
      occurredStart: nil,
      updatedAt: Date(timeIntervalSince1970: 500)
    )

    XCTAssertEqual(
      FirstTimesWorkspace.entries(from: [unknown, older, recent]).map(\.title),
      ["Recent", "Older", "Unknown"]
    )
  }

  func testEntryUsesHumanDateLabelBeforeStoredDate() {
    let entry = makeRow(
      title: "First trip to Japan",
      occurredStart: Date(timeIntervalSince1970: 100),
      occurredLabel: "Age 17"
    ).entry

    XCTAssertEqual(entry.displayDate, "Age 17")
  }

  func testEntryFormatsStoredDateInOccurrenceTimezone() {
    let entry = makeRow(
      title: "New Year",
      occurredStart: Date(timeIntervalSince1970: 1_767_225_600),
      datePrecision: .day,
      occurredTimezone: "America/Los_Angeles"
    ).entry

    XCTAssertEqual(entry.displayDate, "Dec 31, 2025")
  }

  func testValidationAcceptsTitleOnlyUnknownDate() throws {
    let input = try makeInput(
      title: "  First time seeing the ocean  ",
      body: "  ",
      occurredStart: nil,
      datePrecision: .unknown,
      occurredTimezone: nil
    )

    XCTAssertEqual(input.title, "First time seeing the ocean")
    XCTAssertEqual(input.body, "")
    XCTAssertNil(input.occurredStart)
    XCTAssertNil(input.occurredTimezone)
  }

  func testValidationAcceptsAgeLabelWithoutExactDate() throws {
    let input = try makeInput(
      occurredStart: nil,
      datePrecision: .age,
      occurredLabel: "  Age 17  ",
      occurredTimezone: nil
    )

    XCTAssertEqual(input.occurredLabel, "Age 17")
  }

  func testValidationRejectsMissingTitleAndInvalidDateCombination() {
    XCTAssertThrowsError(try makeInput(title: " ")) { error in
      XCTAssertEqual(error as? FirstTimeEntryError, .titleRequired)
    }
    XCTAssertThrowsError(
      try makeInput(
        occurredStart: nil,
        datePrecision: .day,
        occurredTimezone: nil
      )
    ) { error in
      XCTAssertEqual(error as? FirstTimeEntryError, .invalidOccurrence)
    }
  }

  func testValidationNormalizesAndDeduplicatesOrganizationNames() throws {
    let input = try makeInput(
      collectionNames: [" Milestones ", "milestones", "Travel"],
      tagNames: [" Outdoors ", "outdoors", "Snow"]
    )

    XCTAssertEqual(input.collectionNames, ["Milestones", "Travel"])
    XCTAssertEqual(input.tagNames, ["Outdoors", "Snow"])
  }

  func testValidationRequiresRevisionOnlyForExistingEntries() {
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? FirstTimeEntryError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeInput(
        entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testSaveParametersEncodeExplicitNullsForTitleOnlyEntry() throws {
    let input = try makeInput(
      occurredStart: nil,
      datePrecision: .unknown,
      occurredTimezone: nil
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(SaveFirstTimeEntryParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_occurred_start"] is NSNull)
    XCTAssertTrue(json["p_occurred_timezone"] is NSNull)
    XCTAssertEqual(json["p_date_precision"] as? String, "unknown")
  }

  func testPhotoDraftValidatesSizeAndBuildsOwnerScopedPath() throws {
    let photoID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let ownerID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let draft = try FirstTimePhotoDraft.validate(
      id: photoID,
      data: Data([1, 2, 3]),
      mimeType: .heic,
      originalFilename: " photo.heic ",
      pixelWidth: 12,
      pixelHeight: 8
    )

    XCTAssertEqual(draft.originalFilename, "photo.heic")
    XCTAssertEqual(
      draft.objectPath(ownerID: ownerID, entryID: entryID),
      "30000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.heic"
    )
    XCTAssertThrowsError(
      try FirstTimePhotoDraft.validate(
        data: Data(),
        mimeType: .jpeg,
        originalFilename: nil,
        pixelWidth: nil,
        pixelHeight: nil
      )
    ) { error in
      XCTAssertEqual(error as? FirstTimeEntryError, .invalidPhotoSize)
    }
  }

  func testPhotoTypeDetectionPrefersFileSignatureAndSupportsPickerFallback() {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let webP = Data("RIFFsizeWEBP".utf8)
    let heic = Data([0, 0, 0, 0] + Array("ftypheic".utf8))

    XCTAssertEqual(
      FirstTimeImageType.detect(data: png, typeIdentifiers: ["public.jpeg"]),
      .png
    )
    XCTAssertEqual(FirstTimeImageType.detect(data: webP, typeIdentifiers: []), .webp)
    XCTAssertEqual(FirstTimeImageType.detect(data: heic, typeIdentifiers: []), .heic)
    XCTAssertEqual(
      FirstTimeImageType.detect(data: Data([1]), typeIdentifiers: ["public.jpeg"]),
      .jpeg
    )
    XCTAssertNil(FirstTimeImageType.detect(data: Data([1]), typeIdentifiers: ["public.image"]))
  }

  func testAttachmentParametersEncodeMetadataAndNullFilename() throws {
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let draft = try FirstTimePhotoDraft.validate(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      data: Data([1, 2, 3]),
      mimeType: .png,
      originalFilename: nil,
      pixelWidth: 10,
      pixelHeight: 20
    )
    let parameters = RegisterFirstTimeAttachmentParameters(
      entryID: entryID,
      draft: draft,
      objectPath: draft.objectPath(
        ownerID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
        entryID: entryID
      )
    )
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 3)
    XCTAssertEqual(json["p_pixel_width"] as? Int, 10)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeInput(
    entryID: UUID? = nil,
    expectedRevision: Int? = nil,
    title: String = "First ski trip",
    body: String = "Fresh snow.",
    occurredStart: Date? = Date(timeIntervalSince1970: 100),
    datePrecision: FirstTimeDatePrecision = .day,
    occurredLabel: String = "",
    occurredTimezone: String? = "America/Los_Angeles",
    collectionNames: [String] = [],
    tagNames: [String] = []
  ) throws -> FirstTimeEntryInput {
    try FirstTimeEntryInput.validate(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      collectionNames: collectionNames,
      tagNames: tagNames
    )
  }

  private func makeRow(
    id: UUID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
    title: String,
    occurredStart: Date?,
    datePrecision: FirstTimeDatePrecision = .unknown,
    occurredLabel: String? = nil,
    occurredTimezone: String? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 300)
  ) -> FirstTimeWorkspaceRow {
    FirstTimeWorkspaceRow(
      entryID: id,
      title: title,
      body: "Notes",
      inboxStatus: "organized",
      occurredStart: occurredStart,
      occurredEnd: nil,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      revision: 1,
      updatedAt: updatedAt,
      collectionNames: [],
      tagNames: [],
      attachments: []
    )
  }
}
