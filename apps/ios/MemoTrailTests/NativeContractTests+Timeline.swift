import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// The Timeline against the local stack: `timeline_workspace` windows, and the layout over them.
extension NativeContractTests {
  @MainActor
  func testTimelineReturnsChaptersAndFirstTimesWithTheirWindows() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()

    func occurrence(
      _ precision: DatePrecision, _ start: String?, end: String? = nil, label: String? = nil,
      timezone: String = "UTC"
    ) throws -> EntryOccurrence {
      EntryOccurrence(
        precision: precision, start: try start.map { try XCTUnwrap(EntryTimestamp.date(from: $0)) },
        end: try end.map { try XCTUnwrap(EntryTimestamp.date(from: $0)) }, label: label,
        timezone: timezone)
    }
    func save(_ title: String, _ marks: EntryMarks, _ when: EntryOccurrence) async throws -> UUID {
      try await api.save(
        SaveEntryParameters(
          entryID: UUID(), expectedRevision: nil, title: "\(title) \(marker)", body: "",
          richText: nil, occurrence: when, tagNames: [], location: nil, marks: marks)
      ).entryID
    }

    let closed = try await save(
      "Living in Lisbon", .chapter,
      occurrence(.month, "2021-03-01T12:00:00Z", end: "2021-08-31T12:00:00Z"))
    let open = try await save(
      "Learning Portuguese", EntryMarks(isChapter: true, isFirstTime: true),
      occurrence(.year, "2022-06-15T12:00:00Z"))
    let swim = try await save("First swim", .firstTime, occurrence(.day, "2021-05-10T12:00:00Z"))
    // 23:30 UTC is already the next day in Tokyo, and the window follows the recorded zone.
    let tokyo = try await save(
      "First ramen", .firstTime,
      occurrence(.day, "2021-05-10T23:30:00Z", timezone: "Asia/Tokyo"))
    let remembered = try await save(
      "First bicycle", .firstTime, occurrence(.age, nil, label: "Age 7"))
    let plain = try await save("Plain entry", .none, occurrence(.day, "2021-05-10T12:00:00Z"))

    let controller = TimelineController(client: client, ownerID: ownerID)
    await controller.load()
    XCTAssertNil(controller.loadErrorMessage)
    let rows = Dictionary(uniqueKeysWithValues: controller.items.map { ($0.id, $0) })

    // An ordinary Entry is neither a Chapter nor a First Time, so it is not on the Timeline. The
    // contract run shares one account, so other tests' Chapters and First Times may be there too.
    XCTAssertNil(rows[plain])
    XCTAssertTrue(Set(rows.keys).isSuperset(of: [closed, open, swim, tokyo, remembered]))

    // A Chapter covers whole months from the first day to the day after the last.
    XCTAssertEqual(rows[closed]?.windowStart, "2021-03-01")
    XCTAssertEqual(rows[closed]?.windowEnd, "2021-09-01")
    XCTAssertEqual(rows[closed]?.marks, .chapter)
    // An open Chapter keeps its year and has no end.
    XCTAssertEqual(rows[open]?.windowStart, "2022-01-01")
    XCTAssertNil(rows[open]?.windowEnd)
    XCTAssertEqual(rows[open]?.marks, EntryMarks(isChapter: true, isFirstTime: true))
    // A First Time covers its one day, read in its own time zone.
    XCTAssertEqual(rows[swim]?.windowStart, "2021-05-10")
    XCTAssertEqual(rows[swim]?.windowEnd, "2021-05-11")
    XCTAssertEqual(rows[tokyo]?.windowStart, "2021-05-11")
    XCTAssertEqual(rows[tokyo]?.windowEnd, "2021-05-12")
    // A First Time with no calendar date has no window and goes in the unanchored list.
    XCTAssertNil(rows[remembered]?.windowStart)
    XCTAssertNil(rows[remembered]?.windowEnd)
    XCTAssertTrue(controller.undated.contains { $0.id == remembered })
    XCTAssertEqual(rows[remembered]?.undatedLabel, "Roughly: Age 7")

    // A First Time Chapter is one bar, so it is a Chapter only; the other First Times are points.
    XCTAssertTrue(controller.chapters.contains { $0.id == open })
    XCTAssertFalse(controller.firstTimes.contains { $0.id == open })
    XCTAssertTrue(controller.firstTimes.contains { $0.id == swim })
    XCTAssertEqual(
      controller.firstTimeCount,
      controller.firstTimes.count + controller.chapters.filter(\.isFirstTime).count)

    // The layout takes the rows as they come: every dated item is placed, the undated one is not,
    // and the open Chapter's bar ends on the Today line.
    let layout = createTimelineLayout(
      controller.items.compactMap {
        $0.layoutSource(titleWidth: estimateLabelWidth($0.displayTitle))
      }, referenceDate: controller.referenceDate)
    let placed = Set(layout.positions.map(\.id))
    XCTAssertTrue(
      placed.isSuperset(of: [closed, open, swim, tokyo].map { $0.uuidString.lowercased() }))
    XCTAssertFalse(placed.contains(remembered.uuidString.lowercased()))
    let openPosition = try XCTUnwrap(
      layout.positions.first { $0.id == open.uuidString.lowercased() })
    let today = layout.todayPercent / 100 * layout.canvasWidth
    let barEnd =
      openPosition.leftPercent / 100 * layout.canvasWidth + openPosition.offsetPixels
      + openPosition.barWidthPixels
    XCTAssertEqual(barEnd, today, accuracy: 0.001)
  }
}
