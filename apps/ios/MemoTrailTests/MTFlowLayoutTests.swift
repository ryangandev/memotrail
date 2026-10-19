import XCTest

@testable import MemoTrail

final class MTFlowLayoutTests: XCTestCase {
  private let fact = MTFlowLayout.Item(size: CGSize(width: 60, height: 16))
  private let separator = MTFlowLayout.Item(size: CGSize(width: 4, height: 16), isSeparator: true)

  private func lines(_ items: [MTFlowLayout.Item], width: CGFloat) -> [MTFlowLayout.Line] {
    MTFlowLayout.lines(for: items, width: width, spacing: 8)
  }

  func testSeparatorsShowBetweenFactsOnOneLine() {
    // Each separator sits one gap from the facts on either side.
    XCTAssertEqual(
      lines([fact, separator, fact, separator, fact], width: 400),
      [MTFlowLayout.Line(indices: [0, 1, 2, 3, 4], width: 220, height: 16)])
  }

  func testAWrappedFactLeavesItsSeparatorOffBothLines() {
    // The last separator still fits on the first line, but the fact after it does not.
    XCTAssertEqual(
      lines([fact, separator, fact, separator, fact], width: 160),
      [
        MTFlowLayout.Line(indices: [0, 1, 2], width: 140, height: 16),
        MTFlowLayout.Line(indices: [4], width: 60, height: 16),
      ])
    // On the narrowest rows every fact starts a line, so no separator shows.
    XCTAssertEqual(
      lines([fact, separator, fact, separator, fact], width: 100).map(\.indices), [[0], [2], [4]])
  }

  func testSeparatorsWithoutAFactOnBothSidesNeverShow() {
    // Leading and trailing separators, and all but the first of a run, are left out.
    XCTAssertEqual(
      lines([separator, fact, separator, separator, fact, separator], width: 400).map(\.indices),
      [[1, 2, 4]])
    XCTAssertEqual(lines([separator, separator], width: 400), [])
  }

  func testItemsWithoutSeparatorsWrapLikeFlexWrap() {
    let button = MTFlowLayout.Item(size: CGSize(width: 90, height: 32))
    let wide = MTFlowLayout.Item(size: CGSize(width: 300, height: 40))
    // A taller item sets its line's height, and one wider than the row is fitted to it.
    XCTAssertEqual(
      lines([fact, separator, fact, button, wide], width: 230),
      [
        MTFlowLayout.Line(indices: [0, 1, 2], width: 140, height: 16),
        MTFlowLayout.Line(indices: [3], width: 90, height: 32),
        MTFlowLayout.Line(indices: [4], width: 230, height: 40),
      ])
  }

  func testRowsCenterTheirChildrenByDefault() {
    let line = MTFlowLayout.Line(indices: [0, 1], width: 160, height: 44)
    let items = [
      MTFlowLayout.Item(size: CGSize(width: 60, height: 44), baseline: 27),
      MTFlowLayout.Item(size: CGSize(width: 90, height: 20), baseline: 16),
    ]
    let row = MTFlowLayout.rowOffsets(of: line, items: items, alignment: .center)
    XCTAssertEqual(row.offsets, [0, 12])
    XCTAssertEqual(row.height, 44)
  }

  func testFirstBaselineRowsLineUpLabelsAndGrowToFitTheLowestChild() {
    // A one-line checkbox centers its label in the 44 pt hit target, so its baseline sits lower
    // than that of a checkbox whose detail line makes it taller.
    let line = MTFlowLayout.Line(indices: [0, 2], width: 200, height: 52)
    let items = [
      MTFlowLayout.Item(size: CGSize(width: 80, height: 44), baseline: 27),
      separator,
      MTFlowLayout.Item(size: CGSize(width: 100, height: 52), baseline: 18),
    ]
    let row = MTFlowLayout.rowOffsets(of: line, items: items, alignment: .firstTextBaseline)
    XCTAssertEqual(row.offsets, [0, 9])
    XCTAssertEqual(row.height, 61)
  }
}
