import XCTest

@testable import MemoTrail

final class PlaceEntryTests: XCTestCase {
  func testWorkspaceDecodesStandalonePersonalPlace() throws {
    let rows = try decoder.decode([PlaceWorkspaceRow].self, from: Data(workspaceJSON.utf8))
    let entry = try XCTUnwrap(rows.first?.entry)

    XCTAssertEqual(entry.name, "Golden Gate Park")
    XCTAssertEqual(
      entry.locationLabel, "501 Stanyan Street · San Francisco, California, United States")
    XCTAssertTrue(entry.canMoveToTrash)
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

  func testValidationNormalizesDetails() throws {
    let input = try makeInput(
      name: "  Golden Gate Park  ",
      address: "  501 Stanyan Street  ",
      city: " San Francisco ",
      notes: "  Autumn light.  "
    )

    XCTAssertEqual(input.name, "Golden Gate Park")
    XCTAssertEqual(input.address, "501 Stanyan Street")
    XCTAssertEqual(input.city, "San Francisco")
    XCTAssertEqual(input.notes, "Autumn light.")
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
    longitude: Double? = -122.4862
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
      notes: notes
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
      "linked_entries":[],"linked_entry_count":0,"home_count":0,"total_count":1
    }]
    """#
  }
}
