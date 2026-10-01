import XCTest

@testable import MemoTrail

final class ProfileSettingsTests: XCTestCase {
  func testPreferredNameNormalizesLikeWebAndAllowsTheSignInName() throws {
    XCTAssertEqual(try ProfileSettings.parsePreferredName("  River  Gan  "), "River Gan")
    XCTAssertNil(try ProfileSettings.parsePreferredName("   "))
    XCTAssertEqual(try ProfileSettings.parsePreferredName("👨‍👩‍👧 Gan"), "👨‍👩‍👧 Gan")
    let long = String(repeating: "x", count: 81)
    XCTAssertThrowsError(try ProfileSettings.parsePreferredName(long)) {
      XCTAssertEqual($0 as? ProfileSettingsError, .longName)
    }
    XCTAssertThrowsError(try ProfileSettings.parsePreferredName("River\nGan")) {
      XCTAssertEqual($0 as? ProfileSettingsError, .multilineName)
    }
  }

  func testBirthDateAcceptsARealPastDateOrRemoval() throws {
    XCTAssertEqual(
      try ProfileSettings.parseBirthDate("1994-04-18", today: "2026-09-13"), "1994-04-18")
    XCTAssertNil(try ProfileSettings.parseBirthDate("  ", today: "2026-09-13"))
    for (value, expected) in [
      ("1994-02-30", ProfileSettingsError.incompleteBirthDate),
      ("04/18/1994", .incompleteBirthDate),
      ("2026-09-14", .birthDateOutOfRange),
      ("1799-12-31", .birthDateOutOfRange),
    ] {
      XCTAssertThrowsError(try ProfileSettings.parseBirthDate(value, today: "2026-09-13")) {
        XCTAssertEqual($0 as? ProfileSettingsError, expected, value)
      }
    }
    XCTAssertEqual(
      ProfileSettings.todayText(Date(timeIntervalSince1970: 1_790_726_400)), "2026-09-30")
  }

  func testTimezoneAcceptsIANANamesOnly() throws {
    XCTAssertEqual(
      try ProfileSettings.parseTimezone(" America/Los_Angeles "), "America/Los_Angeles")
    XCTAssertThrowsError(try ProfileSettings.parseTimezone("Los Angeles")) {
      XCTAssertEqual($0 as? ProfileSettingsError, .invalidTimezone)
    }
  }

  func testStoredProfileReadsInvalidValuesAsUnset() throws {
    let stored = try JSONDecoder().decode(
      ProfileSettings.self,
      from: Data(
        #"{"display_name":"  ","birth_date":"2001-02-29","timezone":"Mars/Base"}"#.utf8))
    XCTAssertEqual(stored, ProfileSettings(preferredName: nil, birthDate: nil, timezone: "UTC"))

    let saved = try JSONDecoder().decode(
      ProfileSettings.self,
      from: Data(
        #"{"display_name":"River","birth_date":"2000-02-29","timezone":"Asia/Tokyo"}"#.utf8))
    XCTAssertEqual(
      saved,
      ProfileSettings(preferredName: "River", birthDate: "2000-02-29", timezone: "Asia/Tokyo"))
  }
}
