import XCTest

@testable import MemoTrail

@MainActor
final class LocationMapTests: XCTestCase {
  private func item(
    _ year: Int?, kind: WikiItemKind = .entry, city: String? = "Austin", region: String? = "Texas",
    entryID: UUID = UUID()
  ) -> LocationMapItem {
    LocationMapItem(
      entryID: entryID, locationID: UUID(), title: "Record", kind: kind, subtype: kind.rawValue,
      inboxStatus: "organized",
      occurredAt: year.flatMap { ISO8601DateFormatter().date(from: "\($0)-01-01T00:00:00Z") },
      latitude: 30.267, longitude: -97.743, address: "Austin", city: city, region: region,
      country: "US")
  }

  func testYearRangeIsInclusiveAndExcludesUnknownDatesOnlyWhenFiltering() {
    let items = [item(2021), item(2022), item(2023), item(nil), item(2022, kind: .goal)]
    XCTAssertEqual(LocationMapFilter().apply(to: items).count, 5)
    XCTAssertEqual(
      LocationMapFilter(kind: .entry, fromYear: 2021, toYear: 2022).apply(to: items).count, 2)
    XCTAssertEqual(LocationMapFilter(toYear: 2022).apply(to: items).count, 3)
    XCTAssertEqual(LocationMapFilter(fromYear: 2022).apply(to: items).count, 3)
    XCTAssertFalse(LocationMapFilter(fromYear: 0).isValid)
    XCTAssertFalse(LocationMapFilter(toYear: 10000).isValid)
    XCTAssertFalse(LocationMapFilter(fromYear: 2025, toYear: 2021).isValid)
  }

  func testYearsUseUTCAsTheWebMapDoes() {
    let date = ISO8601DateFormatter().date(from: "2021-12-31T23:30:00-02:00")!
    let value = LocationMapItem(
      entryID: UUID(), locationID: UUID(), title: "Boundary", kind: .entry, subtype: "entry",
      inboxStatus: "organized", occurredAt: date, latitude: 0, longitude: 0, address: "", city: nil,
      region: nil, country: nil)
    XCTAssertEqual(value.year, 2022)
  }

  func testCityShortcutsNormalizeNamesSeparateRegionsAndCountEntriesOnce() {
    let id = UUID()
    let values = [
      item(2021, entryID: id), item(2022, city: " austin ", region: "TEXAS", entryID: id),
      item(2023), item(2024, city: "Austin", region: "Minnesota"), item(nil, city: nil),
    ]
    let areas = LocationMapArea.shortcuts(for: values)
    XCTAssertEqual(areas.count, 2)
    XCTAssertEqual(areas.first?.entryCount, 2)
    XCTAssertEqual(areas.first?.items.count, 3)
    XCTAssertEqual(LocationMapArea.uniqueEntries(in: values).count, 4)
  }

  func testAssemblyOmitsMissingDeletedAndInvalidCoordinatesAndDeduplicatesPairs() {
    let entryID = UUID()
    let locationID = UUID()
    let missing = UUID()
    let entry = MapEntryRow(
      id: entryID, title: "Home", body: nil, itemKind: .entity, itemSubtype: "home",
      inboxStatus: "organized", occurredStart: nil)
    func location(_ latitude: Double?, _ longitude: Double?) -> MapLocationRow {
      MapLocationRow(
        id: locationID, latitude: latitude, longitude: longitude,
        formattedAddress: "  Austin, Texas  ", name: "", city: "Austin", region: "Texas",
        country: "US")
    }
    let links = [
      MapLocationLink(entryID: entryID, placeID: locationID),
      MapLocationLink(entryID: entryID, placeID: locationID),
      MapLocationLink(entryID: missing, placeID: locationID),
      MapLocationLink(entryID: entryID, placeID: missing),
    ]
    let results = LocationMapAssembly.items(
      links: links, entries: [entry], locations: [location(0, 0)])
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].address, "Austin, Texas")
    XCTAssertEqual(results[0].kind, .entity)
    for coordinates: (Double?, Double?) in [(nil, 0), (0, nil), (91, 0), (0, 181), (.nan, 0)] {
      XCTAssertTrue(
        LocationMapAssembly.items(
          links: links, entries: [entry], locations: [location(coordinates.0, coordinates.1)]
        ).isEmpty)
    }
    XCTAssertTrue(
      LocationMapAssembly.items(links: links, entries: [], locations: [location(0, 0)]).isEmpty)
  }

  func testControllerRetriesWithoutPublishingStaleOrPartialMap() async {
    var attempt = 0
    let rows = [item(2021)]
    let controller = LocationMapController {
      attempt += 1
      if attempt == 2 { throw URLError(.networkConnectionLost) }
      return LocationMapSnapshot(items: rows, truncated: attempt == 1)
    }
    await controller.load()
    XCTAssertEqual(controller.items.count, 1)
    XCTAssertTrue(controller.truncated)
    await controller.load()
    XCTAssertTrue(controller.items.isEmpty)
    XCTAssertFalse(controller.truncated)
    XCTAssertNotNil(controller.errorMessage)
    await controller.load()
    XCTAssertNil(controller.errorMessage)
    XCTAssertEqual(controller.items.count, 1)
  }

  func testCancellationCanBeRetried() async {
    var attempt = 0
    let controller = LocationMapController {
      attempt += 1
      if attempt == 1 { throw CancellationError() }
      return LocationMapSnapshot(items: [], truncated: false)
    }
    await controller.load()
    XCTAssertFalse(controller.hasLoaded)
    XCTAssertFalse(controller.isLoading)
    await controller.load()
    XCTAssertTrue(controller.hasLoaded)
  }

  func testMoreMatchesTheActiveWebDestinationsWithoutRetiredSurfaces() {
    let routes = WorkspaceRoute.groups.flatMap(\.routes)
    XCTAssertEqual(Set(routes), Set(WorkspaceRoute.allCases))
    XCTAssertEqual(routes.count, Set(routes).count)
    XCTAssertEqual(
      RootTabDestination.allCases.map(\.title),
      ["Dashboard", "Inbox", "Timeline", "Library", "More"])
  }
}
