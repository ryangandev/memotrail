import XCTest

@testable import MemoTrail

/// Ported case by case from `apps/web/src/lib/data/timeline-layout.test.ts`, with the same
/// dates and pixel widths, so the native canvas places items where the Web one does.
final class TimelineLayoutTests: XCTestCase {
  /// 2026-09-02T12:00:00.000Z
  private let reference = Date(timeIntervalSince1970: 1_788_350_400)

  private func point(
    band: TimelineBand = .firstTimes, id: String = "point-1", labelWidthPixels: Double = 80,
    shape: TimelineShape = .point, windowEnd: String? = nil, windowStart: String = "2020-01-01"
  ) -> TimelineLayoutSource {
    TimelineLayoutSource(
      band: band, id: id, labelWidthPixels: labelWidthPixels, shape: shape, windowEnd: windowEnd,
      windowStart: windowStart)
  }

  private func bar(
    id: String = "bar-1", labelWidthPixels: Double = 80, windowEnd: String? = nil,
    windowStart: String = "2020-01-01"
  ) -> TimelineLayoutSource {
    point(
      band: .chapters, id: id, labelWidthPixels: labelWidthPixels, shape: .bar,
      windowEnd: windowEnd, windowStart: windowStart)
  }

  private func layout(
    _ items: [TimelineLayoutSource], birthDate: String? = nil, fillWidthPixels: Double = 0
  ) -> TimelineLayout {
    createTimelineLayout(
      items, referenceDate: reference, birthDate: birthDate, fillWidthPixels: fillWidthPixels)
  }

  func testReferenceDateIsTheOneWebUses() {
    XCTAssertEqual(TimelineCalendar.isoString(milliseconds: 1_788_350_400_000),
      "2026-09-02T12:00:00.000Z")
  }

  func testBuildsAStableCurrentYearRangeForAnEmptyTimeline() {
    let result = layout([])

    XCTAssertEqual(result.start, "2026-01-01T00:00:00.000Z")
    XCTAssertEqual(result.end, "2027-01-01T00:00:00.000Z")
    XCTAssertEqual(result.positions, [])
  }

  func testStartsAnEmptyTimelineAtTheOwnersBirthDateAndContinuesToToday() {
    let result = layout([], birthDate: "1994-04-18")

    XCTAssertEqual(result.start, "1994-04-18T00:00:00.000Z")
    XCTAssertEqual(
      result.yearMarkers.first, TimelineYearMarker(label: "1994", leftPercent: 0, year: 1994))
    XCTAssertGreaterThan(
      TimelineCalendar.time(of: result.end) ?? 0, reference.timeIntervalSince1970 * 1_000)
  }

  func testDoesNotMoveTheTimelineBeforeBirthForAnEarlierImportedFirstTime() {
    let result = layout([point(windowStart: "1990-01-01")], birthDate: "1994-04-18")

    XCTAssertEqual(result.start, "1994-04-18T00:00:00.000Z")
    XCTAssertEqual(result.positions.first?.leftPercent, 0)
  }

  func testPlacesAPointWithinPaddedBounds() throws {
    let result = layout([point()])
    let position = try XCTUnwrap(result.positions.first)

    XCTAssertGreaterThan(position.leftPercent, 0)
    XCTAssertLessThan(position.leftPercent, 100)
    XCTAssertEqual(position.barWidthPixels, 12)
    XCTAssertEqual(position.labelPlacement, .after)
  }

  func testDrawsABarFromItsWindowStartToItsWindowEnd() throws {
    let result = layout(
      [bar(windowEnd: "2022-01-01", windowStart: "2020-01-01")], birthDate: "2000-01-01")
    let position = try XCTUnwrap(result.positions.first)
    func marker(_ year: Int) throws -> Double {
      try XCTUnwrap(result.yearMarkers.first { $0.year == year }).leftPercent
    }

    XCTAssertEqual(position.leftPercent, try marker(2020), accuracy: 0.000005)
    XCTAssertEqual(
      position.leftPercent + position.barWidthPixels / result.canvasWidth * 100,
      try marker(2022), accuracy: 0.000005)
  }

  func testLetsAYearChapterReachTheNextJanuaryMarker() throws {
    // 2019 to 2021 is stored as the window 2019-01-01 up to, not including, 2022-01-01.
    let result = layout(
      [bar(windowEnd: "2022-01-01", windowStart: "2019-01-01")], birthDate: "2000-01-01")
    let position = try XCTUnwrap(result.positions.first)
    let end2022 = try XCTUnwrap(result.yearMarkers.first { $0.year == 2022 }).leftPercent

    XCTAssertEqual(position.labelPlacement, .inside)
    XCTAssertEqual(
      position.leftPercent + position.widthPixels / result.canvasWidth * 100, end2022,
      accuracy: 0.000005)
  }

  func testExtendsAnOpenBarToTheReferenceDate() throws {
    let result = layout([bar(windowStart: "2024-01-01")])
    let position = try XCTUnwrap(result.positions.first)

    XCTAssertGreaterThan(position.widthPixels, result.canvasWidth / 2)
    XCTAssertEqual(position.labelPlacement, .inside)
  }

  func testStacksOverlappingBarsOnDifferentRows() {
    let result = layout([
      bar(id: "bar-1", windowEnd: "2024-12-01", windowStart: "2020-01-01"),
      bar(id: "bar-2", windowEnd: "2025-01-01", windowStart: "2022-01-01"),
    ])

    XCTAssertEqual(result.positions.map(\.row), [0, 1])
    XCTAssertEqual(result.rowCountByBand[.chapters], 2)
  }

  func testReusesARowForBarsThatNoLongerOverlap() {
    let result = layout([
      bar(id: "bar-1", windowEnd: "2021-01-01"),
      bar(id: "bar-2", windowEnd: "2023-01-01", windowStart: "2022-01-01"),
    ])

    XCTAssertEqual(result.positions.map(\.row), [0, 0])
    XCTAssertEqual(result.rowCountByBand[.chapters], 1)
  }

  func testReusesARowForShortNonOverlappingBarsOnALifeLongTimeline() {
    let result = layout(
      [
        bar(id: "walmart", labelWidthPixels: 44, windowEnd: "2026-02-01", windowStart: "2025-05-19"),
        bar(id: "adobe", labelWidthPixels: 34, windowStart: "2026-04-13"),
      ], birthDate: "2000-05-16")

    XCTAssertEqual(result.positions.map(\.row), [0, 0])
    XCTAssertEqual(result.rowCountByBand[.chapters], 1)
  }

  func testSeparatesPointsWhoseRenderedLabelsOverlap() {
    let result = layout(
      [
        point(id: "point-1", windowStart: "2026-01-01"),
        point(id: "point-2", windowStart: "2026-06-01"),
      ], birthDate: "2000-05-16")

    XCTAssertEqual(result.positions.map(\.row), [0, 1])
    XCTAssertEqual(result.rowCountByBand[.firstTimes], 2)
  }

  func testAlignsShortOngoingBarsToTheirSharedPresentEndpoint() throws {
    let result = layout(
      [
        bar(id: "adobe", labelWidthPixels: 30, windowStart: "2026-04-13"),
        bar(id: "evergreen", labelWidthPixels: 30, windowStart: "2026-09-01"),
      ], birthDate: "2000-05-16")
    let rightEdges = result.positions.map {
      $0.leftPercent / 100 * result.canvasWidth + $0.offsetPixels + $0.barWidthPixels
    }
    let today = result.todayPercent / 100 * result.canvasWidth

    XCTAssertEqual(result.positions.map(\.labelPlacement), [.after, .after])
    XCTAssertEqual(rightEdges[0], rightEdges[1], accuracy: 0.000005)
    XCTAssertEqual(rightEdges[0], today, accuracy: 0.000005)
  }

  func testPutsATitleBesideABarTooShortToHoldItNeverCutOff() throws {
    let result = layout(
      [
        bar(id: "ended", labelWidthPixels: 64, windowEnd: "2010-06-02", windowStart: "2010-01-01"),
        bar(id: "ongoing", labelWidthPixels: 40, windowStart: "2026-04-13"),
        bar(id: "wide", labelWidthPixels: 64, windowEnd: "2020-01-01", windowStart: "2012-01-01"),
      ], birthDate: "2000-05-16")
    func position(_ id: String) throws -> TimelinePosition {
      try XCTUnwrap(result.positions.first { $0.id == id })
    }
    let ended = try position("ended")
    let ongoing = try position("ongoing")
    let wide = try position("wide")

    XCTAssertEqual(ended.labelPlacement, .after)
    XCTAssertEqual(ended.offsetPixels, 0)
    XCTAssertEqual(ended.labelWidthPixels, 64)
    XCTAssertEqual(ended.widthPixels, ended.barWidthPixels + 7 + 64, accuracy: 0.000005)
    // An ongoing bar still ends at today, with its title after the Today line.
    XCTAssertEqual(ongoing.labelPlacement, .after)
    XCTAssertLessThanOrEqual(ongoing.offsetPixels, 0)
    XCTAssertEqual(wide.labelPlacement, .inside)
    XCTAssertEqual(wide.offsetPixels, 0)
  }

  func testKeepsAShortBarVisibleAndCapsALongTitleBesideIt() throws {
    let result = layout(
      [bar(id: "week", labelWidthPixels: 400, windowEnd: "2010-01-09", windowStart: "2010-01-01")],
      birthDate: "2000-05-16")

    XCTAssertEqual(result.positions.first?.barWidthPixels, 10)
    XCTAssertEqual(result.positions.first?.labelWidthPixels, 180)
  }

  func testPutsAPointsTitleBeforeItsDotOnlyWhenItWouldPassTheEnd() throws {
    let result = layout(
      [
        point(id: "early", windowStart: "2010-01-01"),
        point(id: "late", windowStart: "2026-08-01"),
      ], birthDate: "2000-05-16")
    let early = try XCTUnwrap(result.positions.first)
    let late = try XCTUnwrap(result.positions.last)

    XCTAssertEqual(early.labelPlacement, .after)
    XCTAssertEqual(early.offsetPixels, -6)
    XCTAssertEqual(late.labelPlacement, .before)
    XCTAssertEqual(late.offsetPixels, -(7 + 80 + 6))
  }

  func testStacksRowsIndependentlyInEachBand() {
    let result = layout([point(), bar(id: "bar-2", windowStart: "2020-01-01")])

    XCTAssertEqual(result.positions.map(\.row), [0, 0])
  }

  func testIgnoresAWindowStartThatIsNotACalendarDate() {
    let result = layout([point(windowStart: "not a date")])

    XCTAssertEqual(result, layout([]))
  }

  func testFillsTheVisibleWidthAndStillWidensALongTimelinePastIt() {
    XCTAssertEqual(layout([]).canvasWidth, 840)
    XCTAssertEqual(layout([], fillWidthPixels: 1100.6).canvasWidth, 1100)
    let long = layout([], birthDate: "1990-01-01", fillWidthPixels: 1100)
    XCTAssertEqual(long.canvasWidth, Double(long.yearMarkers.count) * 112)
    XCTAssertGreaterThan(long.canvasWidth, 1100)
  }

  // MARK: Beyond the Web cases

  func testYearMarkersSitOnJanuaryFirstAndStartWithBirthYear() throws {
    let result = layout([], birthDate: "2024-07-01")

    XCTAssertEqual(result.yearMarkers.map(\.year), [2024, 2025, 2026])
    XCTAssertEqual(result.yearMarkers.first?.leftPercent, 0)
    XCTAssertEqual(result.startYear, 2024)
    XCTAssertEqual(result.endYear, 2026)
    XCTAssertGreaterThan(try XCTUnwrap(result.yearMarkers.dropFirst().first).leftPercent, 0)
  }

  func testTodayLineSitsBetweenTheEdgesOfTheRange() {
    let result = layout([point()])

    XCTAssertGreaterThan(result.todayPercent, 0)
    XCTAssertLessThan(result.todayPercent, 100)
  }

  func testDatesRollOverLikeJavaScriptAndLeapDaysCount() {
    XCTAssertEqual(
      TimelineCalendar.isoString(milliseconds: TimelineCalendar.time(ofDate: "2024-02-29") ?? 0),
      "2024-02-29T00:00:00.000Z")
    // Date.UTC(2021, 1, 31) is March 3 in a non-leap year.
    XCTAssertEqual(
      TimelineCalendar.isoString(milliseconds: TimelineCalendar.time(ofDate: "2021-02-31") ?? 0),
      "2021-03-03T00:00:00.000Z")
    XCTAssertNil(TimelineCalendar.time(ofDate: "2021-2-3"))
    XCTAssertNil(TimelineCalendar.time(ofDate: nil))
  }

  func testEstimatedLabelWidthRoundsUp() {
    XCTAssertEqual(estimateLabelWidth(""), 0)
    XCTAssertEqual(estimateLabelWidth("abcde"), 31)
  }
}
