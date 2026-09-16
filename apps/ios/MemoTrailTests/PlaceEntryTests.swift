import XCTest

@testable import MemoTrail

final class PlaceEntryTests: XCTestCase {
  func testWorkspaceDecodesLocationRelationshipsAndPrivatePhoto() throws {
    let rows = try decoder.decode([PlaceWorkspaceRow].self, from: Data(workspaceJSON.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.name, "Golden Gate Park")
    XCTAssertEqual(
      entry.locationLabel, "501 Stanyan Street · San Francisco, California, United States")
    XCTAssertEqual(entry.coordinateLabel, "37.7694°N, 122.4862°W")
    XCTAssertEqual(entry.relatedEntries.first?.displayTitle, "Autumn walk")
    XCTAssertEqual(entry.protectedEntries.first?.relationshipLabel, "Home record")
    XCTAssertEqual(entry.coverAttachment?.mimeType, .jpeg)
    XCTAssertNil(entry.coverAttachment?.signedURL)
    XCTAssertFalse(entry.canMoveToTrash)
  }

  func testWorkspaceSortsByRecencyThenName() {
    let earlier = makeRow(name: "Zoo", updatedAt: Date(timeIntervalSince1970: 50))
    let sameTimeLaterName = makeRow(name: "Beach", updatedAt: Date(timeIntervalSince1970: 100))
    let sameTimeEarlierName = makeRow(
      name: "Arboretum", updatedAt: Date(timeIntervalSince1970: 100))

    XCTAssertEqual(
      PlaceWorkspace.entries(from: [earlier, sameTimeLaterName, sameTimeEarlierName]).map(\.name),
      ["Arboretum", "Beach", "Zoo"]
    )
  }

  func testLocationFallsBackWithoutAddressOrLocality() {
    XCTAssertEqual(makeRow(address: nil, city: "Philadelphia").entry.locationLabel, "Philadelphia")
    XCTAssertEqual(
      makeRow(address: nil, city: nil).entry.locationLabel, "Location details not added")
  }

  func testValidationNormalizesDetailsAndRelatedEntries() throws {
    let firstID = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
    let secondID = UUID(uuidString: "10000000-0000-4000-8000-000000000012")!
    let input = try makeInput(
      name: "  Golden Gate Park  ",
      address: "  501 Stanyan Street  ",
      city: " San Francisco ",
      notes: "  Autumn light.  ",
      relatedEntryIDs: [firstID, firstID, secondID]
    )

    XCTAssertEqual(input.name, "Golden Gate Park")
    XCTAssertEqual(input.address, "501 Stanyan Street")
    XCTAssertEqual(input.city, "San Francisco")
    XCTAssertEqual(input.notes, "Autumn light.")
    XCTAssertEqual(input.relatedEntryIDs, [firstID, secondID])
  }

  func testValidationRejectsMissingNameAndInvalidRevision() {
    XCTAssertThrowsError(try makeInput(name: " ")) { error in
      XCTAssertEqual(error as? PlaceEntryError, .nameRequired)
    }
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? PlaceEntryError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeInput(
        placeID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testValidationRequiresCoordinatePairAndBounds() {
    XCTAssertThrowsError(try makeInput(latitude: 37.7, longitude: nil)) { error in
      XCTAssertEqual(error as? PlaceEntryError, .invalidCoordinates)
    }
    XCTAssertThrowsError(try makeInput(latitude: 91, longitude: 0)) { error in
      XCTAssertEqual(error as? PlaceEntryError, .invalidCoordinates)
    }
    XCTAssertNoThrow(try makeInput(latitude: -90, longitude: 180))
  }

  func testValidationRejectsTooManyRelatedEntries() {
    let identifiers = (0...PlaceInput.relatedEntryLimit).map { offset in
      UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", offset))!
    }
    XCTAssertThrowsError(try makeInput(relatedEntryIDs: identifiers)) { error in
      XCTAssertEqual(error as? PlaceEntryError, .invalidRelatedEntries)
    }
  }

  func testSaveParametersUseRPCNamesAndExplicitNulls() throws {
    let input = try makeInput(latitude: nil, longitude: nil)
    let data = try JSONEncoder().encode(SavePlaceParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_name"] as? String, "Golden Gate Park")
    XCTAssertEqual(json["p_related_entry_ids"] as? [String], [])
    XCTAssertTrue(json["p_place_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_latitude"] is NSNull)
    XCTAssertTrue(json["p_longitude"] is NSNull)
  }

  func testTrashParametersUseOptimisticRevision() throws {
    let placeID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let data = try JSONEncoder().encode(
      TrashPlaceParameters(placeID: placeID, expectedRevision: 4)
    )
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_place_id"] as? String, placeID.uuidString.lowercased())
    XCTAssertEqual(json["p_expected_revision"] as? Int, 4)
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeInput(
    placeID: UUID? = nil,
    expectedRevision: Int? = nil,
    name: String = "Golden Gate Park",
    address: String = "501 Stanyan Street",
    city: String = "San Francisco",
    notes: String = "Autumn light.",
    latitude: Double? = 37.7694,
    longitude: Double? = -122.4862,
    relatedEntryIDs: [UUID] = []
  ) throws -> PlaceInput {
    try PlaceInput.validate(
      placeID: placeID,
      expectedRevision: expectedRevision,
      name: name,
      address: address,
      city: city,
      region: "California",
      country: "United States",
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      relatedEntryIDs: relatedEntryIDs
    )
  }

  private func makeRow(
    name: String = "Golden Gate Park",
    address: String? = "501 Stanyan Street",
    city: String? = "San Francisco",
    updatedAt: Date = Date(timeIntervalSince1970: 100)
  ) -> PlaceWorkspaceRow {
    PlaceWorkspaceRow(
      placeID: UUID(),
      name: name,
      address: address,
      city: city,
      region: nil,
      country: nil,
      latitude: nil,
      longitude: nil,
      notes: nil,
      revision: 1,
      createdAt: Date(timeIntervalSince1970: 50),
      updatedAt: updatedAt,
      linkedEntries: [],
      linkedEntryCount: 0,
      homeCount: 0,
      totalCount: 1
    )
  }

  private var workspaceJSON: String {
    #"""
    [{
      "place_id":"10000000-0000-4000-8000-000000000001",
      "name":"Golden Gate Park","address":"501 Stanyan Street",
      "city":"San Francisco","region":"California","country":"United States",
      "latitude":37.7694,"longitude":-122.4862,"notes":"Autumn light.","revision":3,
      "created_at":"2026-09-03T19:00:00Z","updated_at":"2026-09-03T20:00:00Z",
      "linked_entries":[{
        "id":"20000000-0000-4000-8000-000000000001","title":"Autumn walk",
        "body":"A quiet route.","entry_type":"standard","inbox_status":"reviewed",
        "occurred_start":"2026-09-01T19:00:00Z","occurred_end":null,
        "date_precision":"day","occurred_label":null,"occurred_timezone":"America/Los_Angeles",
        "revision":2,"updated_at":"2026-09-03T20:00:00Z","relationship":"related",
        "attachments":[{
          "id":"30000000-0000-4000-8000-000000000001","bucket_id":"entry-media",
          "object_path":"owner/entry/park.jpg","original_filename":"park.jpg",
          "mime_type":"image/jpeg","byte_size":2048,"pixel_width":1200,
          "pixel_height":800,"created_at":"2026-09-03T20:00:00Z"
        }]
      },{
        "id":"20000000-0000-4000-8000-000000000002","title":"San Francisco home",
        "body":"","entry_type":"home","inbox_status":"reviewed",
        "occurred_start":"2025-01-01T20:00:00Z","occurred_end":null,
        "date_precision":"year","occurred_label":null,"occurred_timezone":"America/Los_Angeles",
        "revision":1,"updated_at":"2026-09-02T20:00:00Z","relationship":"home",
        "attachments":[]
      }],"linked_entry_count":2,"home_count":1,"total_count":1
    }]
    """#
  }
}
