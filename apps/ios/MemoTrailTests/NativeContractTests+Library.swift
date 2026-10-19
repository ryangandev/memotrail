import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// Library browse, keyword search, and First Times against the local stack.
extension NativeContractTests {
  @MainActor
  func testSearchFindsChaptersAndFirstTimesByKeywordWithoutSemanticArguments() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = "libmark" + String(UUID().uuidString.prefix(8)).lowercased()
    let day = EntryOccurrence(
      precision: .day, start: try XCTUnwrap(EntryTimestamp.date(from: "2024-05-04T12:00:00Z")),
      end: nil, label: nil, timezone: "UTC")

    func save(_ title: String, _ marks: EntryMarks) async throws -> UUID {
      try await api.save(
        SaveEntryParameters(
          entryID: UUID(), expectedRevision: nil, title: title, body: "Notes about \(marker).",
          richText: nil, occurrence: day, tagNames: [], location: nil, marks: marks)
      ).entryID
    }
    let plain = try await save("Plain \(marker)", .none)
    let chapter = try await save("Chapter \(marker)", .chapter)
    let firstTime = try await save("First \(marker)", .firstTime)

    let library = LibraryController(client: client, ownerID: ownerID)
    library.query = marker
    await library.search()
    XCTAssertNil(library.searchErrorMessage)
    XCTAssertEqual(Set(library.results.map(\.id)), [plain, chapter, firstTime])
    XCTAssertEqual(library.resultCount, 3)
    let labels = Dictionary(uniqueKeysWithValues: library.results.map { ($0.id, $0.identityLabel) })
    XCTAssertEqual(labels[plain], "Entry")
    XCTAssertEqual(labels[chapter], "Chapter")
    XCTAssertEqual(labels[firstTime], "First Time")
    XCTAssertTrue(library.results.allSatisfy { $0.matchReasons.contains("Title") })

    // Each Record filter narrows the same phrase. A First Time is an Entry, so Entries keep it.
    for (record, expected) in [
      (EntryRecordFilter.chapter, Set([chapter])),
      (.firstTime, Set([firstTime])),
      (.entry, Set([plain, firstTime])),
    ] {
      library.record = record
      await library.search()
      XCTAssertEqual(Set(library.results.map(\.id)), expected, record.rawValue)
    }

    // Browsing lists the same Entries with their marks.
    await library.loadItems()
    XCTAssertNil(library.errorMessage)
    let rows = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
    XCTAssertEqual(rows[plain]?.marks, EntryMarks.none)
    XCTAssertEqual(rows[chapter]?.marks, .chapter)
    XCTAssertEqual(rows[firstTime]?.marks, .firstTime)
    XCTAssertEqual(rows[firstTime]?.displayTitle, "First \(marker)")

    // The First Times view lists the marked Entry, and only it.
    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    await firstTimes.load()
    XCTAssertNil(firstTimes.loadErrorMessage)
    XCTAssertTrue(firstTimes.showsSummary)
    XCTAssertTrue(firstTimes.entries.contains { $0.id == firstTime })
    XCTAssertFalse(firstTimes.entries.contains { $0.id == plain || $0.id == chapter })
  }
}
