import XCTest

@testable import MemoTrail

/// Photos on an Entry: the upload and registration, the gallery Web's media routes return,
/// camera dates and GPS positions, and the files and parameters each step sends.
final class EntryPhotoTests: XCTestCase {
  private let ownerID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
  private let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
  private let photoID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

  // MARK: Upload and registration

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
      XCTFail("A cancelled upload must not start.")
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
      XCTFail("A lost registration answer must stay unconfirmed.")
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

  // MARK: Gallery and delivery

  func testGalleryDecodesUnavailablePhotosAndValidatesDeliveryOrigin() throws {
    let data = Data(
      """
      {"photos":[{"id":"\(photoID)","name":"Original.jpg","imageUrl":null}],"hasMore":true}
      """.utf8)
    let response = try JSONDecoder().decode(EntryPhotosResponse.self, from: data)
    XCTAssertEqual(response.photos.first?.id, photoID)
    XCTAssertEqual(response.photos.first?.name, "Original.jpg")
    XCTAssertTrue(response.hasMore)
    let base = URL(string: "https://memotrail.example")!
    XCTAssertNil(response.photos.first?.displayURL(base: base))
    let valid = EntryPhotoInfo(
      id: photoID, name: "Photo",
      imageUrl: "https://memotrail.example/api/media/image?token=scoped")
    XCTAssertEqual(valid.displayURL(base: base)?.absoluteString, valid.imageUrl)
    XCTAssertNil(valid.displayURL(base: nil))
    XCTAssertNil(valid.displayURL(base: URL(string: "https://other.example")))
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
      "https://memotrail.example/api/media/image?token=",
      "https://someone@memotrail.example/api/media/image?token=scoped",
    ] {
      XCTAssertTrue(
        MediaDelivery.validatedURLs([path: url], paths: [path], base: base).isEmpty, url)
    }
    XCTAssertTrue(
      MediaDelivery.validatedURLs(["not-requested": valid], paths: [path], base: base).isEmpty)
  }

  // MARK: Camera date and GPS position

  func testCameraDateAdoptionIsAnExplicitDayDraftWithNoTimezoneInference() throws {
    let data = Data(
      """
      {"attachmentId":"10000000-0000-4000-8000-000000000001","sourceVersion":"v1",
      "capturedLocal":"2017-07-08T12:34:56.123","calendarDate":"2017-07-08",
      "offset":null,"latitude":39.95,"longitude":-75.166667}
      """.utf8)
    let metadata = try JSONDecoder().decode(PhotoCameraMetadata.self, from: data)
    var previous = OccurrenceDraft(EntryOccurrence(precision: .unknown, timezone: "UTC"))
    previous.precision = .range
    previous.start = "2020-01-01"
    previous.end = "2020-01-02"
    previous.label = "Original range"
    previous.timezone = "Pacific/Kiritimati"
    let draft = try metadata.calendarDraft(previous: previous)
    XCTAssertEqual(draft.precision, .day)
    XCTAssertEqual(draft.start, "2017-07-08")
    XCTAssertEqual(draft.end, "")
    XCTAssertEqual(draft.endMode, .date)
    XCTAssertEqual(draft.label, "")
    XCTAssertEqual(draft.timezone, "Pacific/Kiritimati")
    // The draft it came from is untouched.
    XCTAssertEqual(previous.precision, .range)
    XCTAssertEqual(previous.label, "Original range")
    XCTAssertEqual(metadata.capturedLocal, "2017-07-08T12:34:56.123")
    XCTAssertNil(metadata.offset)
    XCTAssertEqual(try draft.resolve().timezone, "Pacific/Kiritimati")
  }

  func testCameraDateAdoptionRejectsMissingOrImpossibleDates() {
    for date in [nil, "2017-02-30", "2017-7-8", "not a date"] as [String?] {
      let metadata = PhotoCameraMetadata(
        attachmentId: UUID(), sourceVersion: "v1", capturedLocal: nil, calendarDate: date,
        offset: nil, latitude: nil, longitude: nil)
      XCTAssertThrowsError(
        try metadata.calendarDraft(
          previous: OccurrenceDraft(EntryOccurrence(precision: .unknown, timezone: "UTC"))),
        date ?? "nil")
    }
  }

  func testPhotoLocationIsSentAsItsCoordinatesOnly() throws {
    let draft = PhotoLocationDraft(attachmentId: photoID, latitude: 39.95, longitude: -75.166667)
    XCTAssertTrue(draft.isValid)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
    XCTAssertEqual(json.count, 3)
    XCTAssertEqual(json["attachmentId"] as? String, "20000000-0000-4000-8000-000000000001")
    XCTAssertEqual(json["latitude"] as? Double, 39.95)
    XCTAssertEqual(json["longitude"] as? Double, -75.166667)
    XCTAssertEqual(
      try JSONDecoder().decode(PhotoLocationDraft.self, from: JSONEncoder().encode(draft)), draft)
  }

  // MARK: Files and parameters

  func testPhotoDraftValidatesSizeAndBuildsOwnerScopedPath() throws {
    let draft = try PhotoDraft.validate(
      id: photoID, data: Data([1, 2, 3]), mimeType: .heic, originalFilename: " photo.heic ",
      pixelWidth: 12, pixelHeight: 8)

    XCTAssertEqual(draft.originalFilename, "photo.heic")
    XCTAssertEqual(
      draft.objectPath(ownerID: ownerID, entryID: entryID),
      "30000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/"
        + "20000000-0000-4000-8000-000000000001.heic")
    XCTAssertEqual(
      try PhotoDraft.validate(
        data: Data([1]), mimeType: .jpeg, originalFilename: "  ", pixelWidth: nil,
        pixelHeight: nil
      ).originalFilename, nil)

    for (data, filename, width, error) in [
      (Data(), nil, 12, PhotoDraftError.invalidSize),
      (Data(count: PhotoDraft.maximumByteSize + 1), nil, 12, .invalidSize),
      (Data([1]), String(repeating: "f", count: 256), 12, .filenameTooLong),
      (Data([1]), nil, 0, .invalidDimensions),
    ] as [(Data, String?, Int, PhotoDraftError)] {
      XCTAssertThrowsError(
        try PhotoDraft.validate(
          data: data, mimeType: .jpeg, originalFilename: filename, pixelWidth: width,
          pixelHeight: 8)
      ) {
        XCTAssertEqual($0 as? PhotoDraftError, error)
      }
    }
    XCTAssertEqual(
      PhotoDraftError.invalidSize.errorDescription, "Each photo must be no larger than 50 MB.")
    XCTAssertEqual(
      PhotoDraftError.unsupportedType.errorDescription,
      "Use a JPEG, PNG, WebP, HEIC, or HEIF image.")
  }

  func testPhotoTypeDetectionPrefersFileSignatureAndSupportsPickerFallback() {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let webP = Data("RIFFsizeWEBP".utf8)
    let heic = Data([0, 0, 0, 0] + Array("ftypheic".utf8))
    let heif = Data([0, 0, 0, 0] + Array("ftypmif1".utf8))

    XCTAssertEqual(PhotoImageType.detect(data: png, typeIdentifiers: ["public.jpeg"]), .png)
    XCTAssertEqual(PhotoImageType.detect(data: jpeg, typeIdentifiers: []), .jpeg)
    XCTAssertEqual(PhotoImageType.detect(data: webP, typeIdentifiers: []), .webp)
    XCTAssertEqual(PhotoImageType.detect(data: heic, typeIdentifiers: []), .heic)
    XCTAssertEqual(PhotoImageType.detect(data: heif, typeIdentifiers: []), .heif)
    XCTAssertEqual(PhotoImageType.detect(data: Data([1]), typeIdentifiers: ["public.jpeg"]), .jpeg)
    XCTAssertNil(PhotoImageType.detect(data: Data([1]), typeIdentifiers: ["public.image"]))
    XCTAssertEqual(PhotoImageType.jpeg.fileExtension, "jpg")
  }

  func testRegistrationParametersEncodeMetadataAndNullFilename() throws {
    let draft = try PhotoDraft.validate(
      id: photoID, data: Data([1, 2, 3]), mimeType: .png, originalFilename: nil,
      pixelWidth: 10, pixelHeight: 20)
    let path = draft.objectPath(ownerID: ownerID, entryID: entryID)
    let json = try self.json(
      RegisterEntryAttachmentParameters(entryID: entryID, draft: draft, objectPath: path))

    XCTAssertEqual(
      Set(json.keys),
      [
        "p_entry_id", "p_attachment_id", "p_object_path", "p_original_filename", "p_mime_type",
        "p_byte_size", "p_pixel_width", "p_pixel_height",
      ])
    XCTAssertEqual(json["p_object_path"] as? String, path)
    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 3)
    XCTAssertEqual(json["p_pixel_width"] as? Int, 10)
    XCTAssertEqual(json["p_pixel_height"] as? Int, 20)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
  }

  func testTrashingAPhotoSendsOnlyItsID() throws {
    XCTAssertEqual(
      try json(TrashEntryAttachmentParameters(attachmentID: photoID)) as NSDictionary,
      ["p_attachment_id": photoID.uuidString] as NSDictionary)
    let rows = try JSONDecoder().decode(
      [TrashedEntryAttachment].self,
      from: Data(
        #"[{"attachment_id":"20000000-0000-4000-8000-000000000001","entry_id":"10000000-0000-4000-8000-000000000001","deleted_at":"2026-10-18T19:00:00+00:00"}]"#
          .utf8))
    XCTAssertEqual(rows, [TrashedEntryAttachment(attachmentID: photoID, entryID: entryID)])
  }

  private func json(_ value: some Encodable) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
