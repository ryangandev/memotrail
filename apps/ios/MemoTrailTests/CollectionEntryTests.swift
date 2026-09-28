import XCTest

@testable import MemoTrail

final class CollectionEntryTests: XCTestCase {
  func testWorkspaceDecodesCollectionCountsAndEmptyRecency() throws {
    let json = """
      [
        {
          "collection_id": "10000000-0000-4000-8000-000000000001",
          "name": "Reflection",
          "system_key": "reflection",
          "color": null,
          "sort_order": 10,
          "entry_count": 2,
          "unreviewed_count": 1,
          "latest_entry_at": null,
          "created_at": "2026-09-02T19:00:00Z",
          "updated_at": "2026-09-02T20:00:00Z"
        }
      ]
      """

    let collection = try XCTUnwrap(
      decoder.decode([MemoCollection].self, from: Data(json.utf8)).first
    )

    XCTAssertEqual(collection.name, "Reflection")
    XCTAssertEqual(collection.entryCount, 2)
    XCTAssertEqual(collection.unreviewedCount, 1)
    XCTAssertEqual(collection.latestEntryLabel, "Empty Collection")
  }

  func testWorkspaceSortsByConfiguredOrderThenNameAndIdentifier() throws {
    let later = try makeCollection(
      id: "10000000-0000-4000-8000-000000000003",
      name: "Travel",
      sortOrder: 20
    )
    let beta = try makeCollection(
      id: "10000000-0000-4000-8000-000000000002",
      name: "Beta",
      sortOrder: 10
    )
    let alpha = try makeCollection(
      id: "10000000-0000-4000-8000-000000000001",
      name: "alpha",
      sortOrder: 10
    )

    XCTAssertEqual(
      CollectionsWorkspace.collections(from: [later, beta, alpha]).map(\.name),
      ["alpha", "Beta", "Travel"]
    )
  }

  func testEntryDecodesOrganizationAndPrivateAttachmentMetadata() throws {
    let entry = try decodeEntry()

    XCTAssertEqual(entry.displayTitle, "First sunrise trail")
    XCTAssertEqual(entry.displayType, "First Time")
    XCTAssertEqual(entry.collectionNames, ["Milestones", "Travel"])
    XCTAssertEqual(entry.tagNames, ["outdoors"])
    XCTAssertEqual(entry.coverAttachment?.mimeType, .png)
    XCTAssertNil(entry.coverAttachment?.signedURL)
    XCTAssertEqual(entry.totalCount, 26)
  }

  func testEntryUsesHumanDateLabelAndInboxState() throws {
    let entry = try decodeEntry()

    XCTAssertEqual(entry.displayDate, "Labor Day week, 2026")
    XCTAssertTrue(entry.isInInbox)
  }

  func testEntryFormatsRangeInOccurrenceTimezone() throws {
    let entry = try decodeEntry(
      occurredStart: "2026-01-01T07:00:00Z",
      occurredEnd: "2026-02-01T07:00:00Z",
      occurredLabel: nil,
      datePrecision: "month",
      timezone: "America/Los_Angeles"
    )

    XCTAssertEqual(entry.displayDate, "Dec 2025 - Jan 2026")
  }

  func testEntryFallsBackToUTCForInvalidLegacyTimezone() throws {
    let entry = try decodeEntry(
      occurredStart: "2026-01-01T07:00:00Z",
      occurredEnd: nil,
      occurredLabel: nil,
      datePrecision: "day",
      timezone: "Not/A-Timezone"
    )

    XCTAssertEqual(entry.displayDate, "Jan 1, 2026")
  }

  func testBodyOnlyEntryBuildsTitleAndExcerpt() throws {
    let entry = try decodeEntry(
      title: nil,
      body: "A useful first line\nThe rest of the note remains readable."
    )

    XCTAssertEqual(entry.displayTitle, "A useful first line")
    XCTAssertEqual(entry.displayExcerpt, "The rest of the note remains readable.")
  }

  func testEntryPreservesCanonicalAndSpecializedRoutingIdentity() throws {
    let entry = try decodeEntry(
      itemKind: "entity",
      itemSubtype: "person",
      recordSource: "person",
      recordID: "30000000-0000-4000-8000-000000000099"
    )

    XCTAssertEqual(entry.itemKind, .entity)
    XCTAssertEqual(entry.itemSubtype, "person")
    XCTAssertEqual(entry.recordSource, .person)
    XCTAssertEqual(entry.recordID.uuidString, "30000000-0000-4000-8000-000000000099")
    XCTAssertEqual(entry.displayType, "Person")
  }

  func testPaginationValidationAcceptsSharedContractBounds() throws {
    let collectionID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let request = try CollectionPageRequest.validate(
      collectionID: collectionID,
      limit: 100,
      offset: 10_000
    )

    XCTAssertEqual(request.limit, 100)
    XCTAssertEqual(request.offset, 10_000)
  }

  func testPaginationValidationRejectsOutOfContractValues() {
    let collectionID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!

    XCTAssertThrowsError(
      try CollectionPageRequest.validate(collectionID: collectionID, limit: 0)
    ) { error in
      XCTAssertEqual(error as? CollectionEntryError, .invalidPagination)
    }
    XCTAssertThrowsError(
      try CollectionPageRequest.validate(collectionID: collectionID, offset: 10_001)
    ) { error in
      XCTAssertEqual(error as? CollectionEntryError, .invalidPagination)
    }
  }

  func testPaginationParametersUseRpcNames() throws {
    let collectionID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let parameters = try CollectionPageRequest.validate(
      collectionID: collectionID,
      offset: 25
    ).parameters
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_collection_id"] as? String, collectionID.uuidString.lowercased())
    XCTAssertEqual(json["p_limit"] as? Int, 25)
    XCTAssertEqual(json["p_offset"] as? Int, 25)
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeCollection(id: String, name: String, sortOrder: Int) throws
    -> MemoCollection
  {
    let json = """
      {
        "collection_id": "\(id)",
        "name": "\(name)",
        "system_key": null,
        "color": null,
        "sort_order": \(sortOrder),
        "entry_count": 0,
        "unreviewed_count": 0,
        "latest_entry_at": null,
        "created_at": "2026-09-02T19:00:00Z",
        "updated_at": "2026-09-02T19:00:00Z"
      }
      """
    return try decoder.decode(MemoCollection.self, from: Data(json.utf8))
  }

  private func decodeEntry(
    title: String? = "First sunrise trail",
    body: String = "A complete note.",
    occurredStart: String? = "2026-09-07T19:00:00Z",
    occurredEnd: String? = nil,
    occurredLabel: String? = "Labor Day week, 2026",
    datePrecision: String = "approximate",
    timezone: String? = "America/Los_Angeles",
    itemKind: String = "entry",
    itemSubtype: String = "first_time",
    recordSource: String = "entry",
    recordID: String = "20000000-0000-4000-8000-000000000001"
  ) throws -> CollectionEntry {
    let object: [String: Any] = [
      "collection_id": "10000000-0000-4000-8000-000000000001",
      "collection_name": "Milestones",
      "total_count": 26,
      "entry_id": "20000000-0000-4000-8000-000000000001",
      "title": title ?? NSNull(),
      "body": body,
      "inbox_status": "unreviewed",
      "item_kind": itemKind,
      "item_subtype": itemSubtype,
      "record_source": recordSource,
      "record_id": recordID,
      "occurred_start": occurredStart ?? NSNull(),
      "occurred_end": occurredEnd ?? NSNull(),
      "date_precision": datePrecision,
      "occurred_label": occurredLabel ?? NSNull(),
      "occurred_timezone": timezone ?? NSNull(),
      "revision": 2,
      "created_at": "2026-09-02T19:00:00Z",
      "updated_at": "2026-09-02T20:00:00Z",
      "collection_names": ["Milestones", "Travel"],
      "tag_names": ["outdoors"],
      "attachments": [
        [
          "id": "30000000-0000-4000-8000-000000000001",
          "parentAttachmentId": NSNull(),
          "variant": "original",
          "bucketId": "entry-media",
          "objectPath": "owner/entry/photo.png",
          "originalFilename": "trail.png",
          "mimeType": "image/png",
          "byteSize": 2048,
          "pixelWidth": 1200,
          "pixelHeight": 800,
          "createdAt": "2026-09-02T19:00:00Z",
        ]
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try decoder.decode(CollectionEntry.self, from: data)
  }
}
