import UIKit
import XCTest

@testable import MemoTrail

/// Checks the generated design tokens against what iOS can actually draw.
final class DesignTokenTests: XCTestCase {
  func testEveryIconNamesAnSFSymbol() {
    for icon in MTIcon.allCases {
      XCTAssertNotNil(
        UIImage(systemName: icon.systemName),
        "\(icon) maps to \(icon.systemName), which is not an SF Symbol on this iOS version.")
    }
  }

  func testCatalogsNameEachTokenOnce() {
    let catalogs: [String: [String]] = [
      "MTColor": MTColor.catalog.map(\.name),
      "MTTextRole": MTTextRole.catalog.map(\.name),
      "MTShadow": MTShadow.catalog.map(\.name),
      "MTEasing": MTEasing.catalog.map(\.name),
      "MTMaterial": MTMaterial.catalog.map(\.name),
      "MTElevation": MTElevation.catalog.map(\.name),
    ]
    for (catalog, names) in catalogs {
      XCTAssertFalse(names.isEmpty, "\(catalog) is empty.")
      XCTAssertEqual(Set(names).count, names.count, "\(catalog) repeats a name.")
    }
  }
}
