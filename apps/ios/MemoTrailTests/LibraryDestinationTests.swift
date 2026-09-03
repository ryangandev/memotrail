import XCTest

@testable import MemoTrail

final class LibraryDestinationTests: XCTestCase {
  func testAvailableDestinationsContainOnlyImplementedArchives() {
    XCTAssertEqual(
      LibraryDestination.available,
      [.collections, .firstTimes, .homes, .vehicles, .goals, .trash]
    )
    XCTAssertTrue(LibraryDestination.available.allSatisfy(\.isAvailable))
  }

  func testPlannedDestinationsRemainVisibleButUnavailable() {
    XCTAssertEqual(
      LibraryDestination.planned,
      [.places, .people]
    )
    XCTAssertTrue(LibraryDestination.planned.allSatisfy { !$0.isAvailable })
  }

  func testEveryDestinationHasDistinctStableIdentity() {
    XCTAssertEqual(Set(LibraryDestination.allCases.map(\.id)).count, 8)
    XCTAssertEqual(LibraryDestination.allCases.count, 8)
  }

  func testEveryDestinationHasUserFacingMetadata() {
    for destination in LibraryDestination.allCases {
      XCTAssertFalse(destination.title.isEmpty)
      XCTAssertFalse(destination.summary.isEmpty)
      XCTAssertFalse(destination.systemImage.isEmpty)
    }
  }
}
