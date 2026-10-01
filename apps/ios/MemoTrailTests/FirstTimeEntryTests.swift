import XCTest

@testable import MemoTrail

final class FirstTimeEntryTests: XCTestCase {
  @MainActor
  func testWritingRevisionUsesTheOriginalGuardAndServerProof() async throws {
    let id = UUID()
    let request = EntryPhotoUpload.WritingRevision(entryID: id, expectedRevision: 2)
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(body["p_entry_id"] as? String, id.uuidString)
    XCTAssertEqual(body["p_expected_revision"] as? Int, 2)
    let photosOnly = try await EntryPhotoUpload.confirmedWritingRevision(revision: 2) { 4 }
    XCTAssertEqual(photosOnly, 4)
    let writingGap = try await EntryPhotoUpload.confirmedWritingRevision(revision: 2) { 2 }
    XCTAssertEqual(writingGap, 2)
  }

  @MainActor
  func testWritingRevisionNeverAcceptsRegressionOrNetworkFailure() async {
    do {
      _ = try await EntryPhotoUpload.confirmedWritingRevision(revision: 2) { 1 }
      XCTFail("A regressed revision must not be used for a write")
    } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    do {
      _ = try await EntryPhotoUpload.confirmedWritingRevision(revision: 2) {
        throw URLError(.notConnectedToInternet)
      }
      XCTFail("An unconfirmed revision must not be used for a write")
    } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
  }

  @MainActor
  func testCancelledPhotoAttemptDoesNotStartNetworkWrites() async {
    var uploads = 0
    var registrations = 0
    let task = Task { @MainActor in
      try await EntryPhotoUpload.confirm {
        uploads += 1
      } register: {
        registrations += 1
        return true
      }
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled upload should not start")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(uploads, 0)
    XCTAssertEqual(registrations, 0)
  }

  @MainActor
  func testPhotoRegistrationReconcilesAnUncertainUpload() async throws {
    var registered = false
    let confirmed = try await EntryPhotoUpload.confirm {
      throw URLError(.networkConnectionLost)
    } register: {
      registered = true
      return true
    }
    XCTAssertTrue(confirmed)
    XCTAssertTrue(registered)
  }

  @MainActor
  func testPhotoRegistrationFailureStaysRetryableWithoutRemovingOriginal() async throws {
    var objectExists = false
    var registrationCount = 0
    do {
      _ = try await EntryPhotoUpload.confirm {
        objectExists = true
      } register: {
        registrationCount += 1
        throw URLError(.networkConnectionLost)
      }
      XCTFail("A lost registration response must remain unconfirmed")
    } catch { XCTAssertTrue(objectExists) }
    let retried = try await EntryPhotoUpload.confirm {
      throw URLError(.cannotWriteToFile)
    } register: {
      registrationCount += 1
      return objectExists
    }
    XCTAssertTrue(retried)
    XCTAssertEqual(registrationCount, 2)
    let missing = try await EntryPhotoUpload.confirm {
    } register: {
      false
    }
    XCTAssertFalse(missing)
  }

  func testCurrentGalleryDecodesUnavailablePhotosAndValidatesDeliveryOrigin() throws {
    let id = UUID()
    let data = Data(
      """
      {"photos":[{"id":"\(id)","name":"Original.jpg","imageUrl":null}],"hasMore":true}
      """.utf8)
    let response = try JSONDecoder().decode(EntryPhotosResponse.self, from: data)
    XCTAssertEqual(response.photos.first?.id, id)
    XCTAssertEqual(response.photos.first?.name, "Original.jpg")
    XCTAssertTrue(response.hasMore)
    let base = URL(string: "https://memotrail.example")!
    XCTAssertNil(response.photos.first?.displayURL(base: base))
    let valid = EntryPhotoInfo(
      id: id, name: "Photo", imageUrl: "https://memotrail.example/api/media/image?token=scoped")
    XCTAssertEqual(valid.displayURL(base: base)?.absoluteString, valid.imageUrl)
    XCTAssertNil(valid.displayURL(base: nil))
    XCTAssertNil(valid.displayURL(base: URL(string: "https://other.example")))
  }
  func testPhotoPlaceDraftCreatesAnEntryOwnedSnapshotAndRejectsCatalogSelection() throws {
    let photo = UUID()
    var draft = PhotoPlaceDraft(
      attachmentId: photo, name: "Ski slope", latitude: 39.95, longitude: -75.166667)
    XCTAssertNoThrow(try draft.validate())
    draft.latitude = .nan
    XCTAssertThrowsError(try draft.validate())
    draft.latitude = 39.95
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
    XCTAssertEqual(json["kind"] as? String, "new")
    XCTAssertEqual(json["latitude"] as? Double, 39.95)
    XCTAssertEqual(json["longitude"] as? Double, -75.166667)
    XCTAssertEqual(json["attachmentId"] as? String, photo.uuidString)
    XCTAssertNil(json["placeId"])
    draft.name = " "
    XCTAssertThrowsError(try draft.validate())
    let existing = PhotoPlaceDraft(
      kind: "existing", attachmentId: photo, placeId: UUID(), revision: 2, name: "Existing place")
    XCTAssertThrowsError(try existing.validate())
  }
  func testCameraDateAdoptionIsAnExplicitDayDraftWithNoTimezoneInference() throws {
    let data = Data(
      """
      {"attachmentId":"10000000-0000-4000-8000-000000000001","sourceVersion":"v1",
      "capturedLocal":"2017-07-08T12:34:56.123","calendarDate":"2017-07-08",
      "offset":null,"latitude":39.95,"longitude":-75.166667}
      """.utf8)
    let metadata = try JSONDecoder().decode(PhotoCameraMetadata.self, from: data)
    var previous = OccurrenceDraft(
      EntryOccurrence(
        precision: .unknown, timezone: "Pacific/Kiritimati"))
    previous.precision = .range
    previous.start = "2020-01-01T12:00"
    previous.end = "2020-01-02T12:00"
    previous.label = "Original range"
    previous.timezone = "Pacific/Kiritimati"
    let draft = try metadata.calendarDraft(previous: previous)
    XCTAssertEqual(draft.precision, .day)
    XCTAssertEqual(draft.start, "2017-07-08")
    XCTAssertEqual(draft.end, "")
    XCTAssertEqual(draft.label, "")
    XCTAssertEqual(draft.timezone, previous.timezone)
    XCTAssertEqual(previous.precision, .range)
    XCTAssertEqual(previous.label, "Original range")
    XCTAssertEqual(metadata.capturedLocal, "2017-07-08T12:34:56.123")
    XCTAssertNil(metadata.offset)
    XCTAssertEqual(try draft.resolve().timezone, "Pacific/Kiritimati")
  }

  func testCameraDateAdoptionRejectsMissingOrImpossibleDates() throws {
    for date in [nil, "2017-02-30", "2017-7-8", "not a date"] as [String?] {
      let metadata = PhotoCameraMetadata(
        attachmentId: UUID(), sourceVersion: "v1", capturedLocal: nil,
        calendarDate: date, offset: nil, latitude: nil, longitude: nil)
      XCTAssertThrowsError(
        try metadata.calendarDraft(
          previous: OccurrenceDraft(
            EntryOccurrence(precision: .unknown, timezone: "UTC"))))
    }
  }

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
    XCTAssertEqual(entry.originalAttachments.map(\.objectPath), ["owner/entry/photo.jpg"])
  }

  func testOriginalPhotosLeaveOutGeneratedVariants() throws {
    let original = """
      {"id":"20000000-0000-4000-8000-000000000001","parentAttachmentId":null,
       "variant":"original","bucketId":"entry-media","objectPath":"owner/entry/photo.jpg",
       "originalFilename":"snow.jpg","mimeType":"image/jpeg","byteSize":2048,
       "pixelWidth":1200,"pixelHeight":800,"createdAt":"2026-09-02T19:00:00Z"}
      """
    let thumbnail = """
      {"id":"20000000-0000-4000-8000-000000000002",
       "parentAttachmentId":"20000000-0000-4000-8000-000000000001",
       "variant":"thumbnail","bucketId":"entry-media","objectPath":"owner/entry/photo-thumb.webp",
       "originalFilename":null,"mimeType":"image/webp","byteSize":512,
       "pixelWidth":320,"pixelHeight":213,"createdAt":"2026-09-02T19:00:01Z"}
      """
    let attachments = try decoder.decode(
      [FirstTimeAttachment].self, from: Data("[\(original),\(thumbnail)]".utf8))
    var entry = makeRow(title: "First ski trip", occurredStart: nil).entry
    entry.attachments = attachments

    XCTAssertEqual(entry.originalAttachments.map(\.variant), [.original])
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

  func testLocationRemovalSendsWebInputWithANullLocation() throws {
    let input = try makeInput(
      entryID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"), expectedRevision: 3,
      occurredStart: nil, datePrecision: .unknown, occurredTimezone: nil,
      collectionNames: ["Milestones"])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: encoder.encode(RemoveFirstTimeLocationParameters(input: input))) as? [String: Any])
    let fields = try XCTUnwrap(json["p_input"] as? [String: Any])

    XCTAssertTrue(json["p_location"] is NSNull)
    XCTAssertNil(json["p_source"])
    XCTAssertEqual(fields["id"] as? String, "10000000-0000-4000-8000-000000000001")
    XCTAssertEqual(fields["revision"] as? Int, 3)
    XCTAssertEqual(fields["title"] as? String, "First ski trip")
    XCTAssertEqual(fields["datePrecision"] as? String, "unknown")
    XCTAssertEqual(fields["collectionNames"] as? [String], ["Milestones"])
    XCTAssertNil(fields["occurredStart"])
    XCTAssertNil(fields["occurredTimezone"])
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
