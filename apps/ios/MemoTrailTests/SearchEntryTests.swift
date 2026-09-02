import XCTest

@testable import MemoTrail

final class SearchEntryTests: XCTestCase {
  func testSearchRequestNormalizesContentAndOrganization() throws {
    let request = try EntrySearchRequest.validate(
      query: "  teeth movement  ",
      entryTypes: [.firstTime, .firstTime, .standard],
      collectionNames: [" Learning ", "learning", "Health"],
      tagNames: [" Teeth ", "teeth", "science"],
      dateFrom: nil,
      dateTo: nil
    )

    XCTAssertEqual(request.query, "teeth movement")
    XCTAssertEqual(request.entryTypes, [.firstTime, .standard])
    XCTAssertEqual(request.collectionNames, ["Learning", "Health"])
    XCTAssertEqual(request.tagNames, ["Teeth", "science"])
    XCTAssertTrue(request.hasCriteria)
  }

  func testFilterOnlySearchIsValidAndEmptySearchStaysIdle() throws {
    let filtered = try EntrySearchRequest.validate(
      query: " ",
      entryTypes: [.lifeStage],
      collectionNames: [],
      tagNames: [],
      dateFrom: nil,
      dateTo: nil
    )
    let empty = try EntrySearchRequest.validate(
      query: " ",
      entryTypes: [],
      collectionNames: [],
      tagNames: [],
      dateFrom: nil,
      dateTo: nil
    )

    XCTAssertTrue(filtered.hasCriteria)
    XCTAssertFalse(empty.hasCriteria)
  }

  func testSearchRejectsOversizedQueryAndOrganizationNames() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: String(repeating: "a", count: EntrySearchRequest.queryLimit + 1),
        entryTypes: [],
        collectionNames: [],
        tagNames: [],
        dateFrom: nil,
        dateTo: nil
      )
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .queryTooLong)
    }

    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "valid",
        entryTypes: [],
        collectionNames: [String(repeating: "c", count: 81)],
        tagNames: [],
        dateFrom: nil,
        dateTo: nil
      )
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .invalidCollections)
    }
  }

  func testSearchRejectsReversedDateRange() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "",
        entryTypes: [],
        collectionNames: [],
        tagNames: [],
        dateFrom: Date(timeIntervalSince1970: 1_788_364_800),
        dateTo: Date(timeIntervalSince1970: 1_788_278_400)
      )
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .invalidDateRange)
    }
  }

  func testSearchEncodesDateOnlyFiltersAndPagination() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let request = try EntrySearchRequest.validate(
      query: "Japan",
      entryTypes: [.firstTime],
      collectionNames: ["Travel"],
      tagNames: ["Japan"],
      dateFrom: Date(timeIntervalSince1970: 1_499_491_800),
      dateTo: Date(timeIntervalSince1970: 1_499_578_200),
      limit: 25,
      offset: 50,
      calendar: calendar
    )
    let data = try JSONEncoder().encode(request.parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_query"] as? String, "Japan")
    XCTAssertEqual(json["p_entry_types"] as? [String], ["first_time"])
    XCTAssertEqual(json["p_collection_names"] as? [String], ["Travel"])
    XCTAssertEqual(json["p_tag_names"] as? [String], ["Japan"])
    XCTAssertEqual(json["p_date_from"] as? String, "2017-07-07")
    XCTAssertEqual(json["p_date_to"] as? String, "2017-07-08")
    XCTAssertEqual(json["p_limit"] as? Int, 25)
    XCTAssertEqual(json["p_offset"] as? Int, 50)
  }

  func testSearchParametersEncodeAbsentDatesExplicitly() throws {
    let request = try EntrySearchRequest.validate(
      query: "learning",
      entryTypes: [],
      collectionNames: [],
      tagNames: [],
      dateFrom: nil,
      dateTo: nil
    )
    let data = try JSONEncoder().encode(request.parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_date_from"] is NSNull)
    XCTAssertTrue(json["p_date_to"] is NSNull)
  }

  func testSearchRejectsInvalidPagination() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "learning",
        entryTypes: [],
        collectionNames: [],
        tagNames: [],
        dateFrom: nil,
        dateTo: nil,
        limit: 101,
        offset: 0
      )
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .invalidPagination)
    }
  }

  func testSearchEntryDecodesRPCResultAndUsesPreservedTimezone() throws {
    let json = """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": "First time in Japan",
        "body": "A summer trip.",
        "entry_type": "first_time",
        "inbox_status": "organized",
        "occurred_start": "2017-07-08T06:30:00Z",
        "occurred_label": null,
        "occurred_timezone": "Asia/Tokyo",
        "updated_at": "2026-09-02T12:00:00Z",
        "collection_names": ["Travel"],
        "tag_names": ["Japan"],
        "match_reasons": ["Title", "Collection"],
        "total_count": 3
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entry = try decoder.decode(SearchEntry.self, from: Data(json.utf8))

    XCTAssertEqual(entry.displayTitle, "First time in Japan")
    XCTAssertEqual(entry.displayType, "First Time")
    XCTAssertEqual(entry.displayDate, "Jul 8, 2017")
    XCTAssertEqual(entry.collectionNames, ["Travel"])
    XCTAssertEqual(entry.tagNames, ["Japan"])
    XCTAssertEqual(entry.matchReasons, ["Title", "Collection"])
    XCTAssertEqual(entry.totalCount, 3)
    XCTAssertFalse(entry.isInInbox)
  }

  func testSearchEntryFallsBackToUTCForAnInvalidLegacyTimezone() throws {
    let json = """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": null,
        "body": "Why keep learning?\\nBecause the world keeps changing.",
        "entry_type": "standard",
        "inbox_status": "unreviewed",
        "occurred_start": "2026-07-03T23:30:00Z",
        "occurred_label": null,
        "occurred_timezone": "Not/AZone",
        "updated_at": "2026-09-02T12:00:00Z",
        "collection_names": null,
        "tag_names": null,
        "match_reasons": ["Body"],
        "total_count": 1
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entry = try decoder.decode(SearchEntry.self, from: Data(json.utf8))

    XCTAssertEqual(entry.displayTitle, "Why keep learning?")
    XCTAssertEqual(entry.displayExcerpt, "Because the world keeps changing.")
    XCTAssertEqual(entry.displayDate, "Jul 3, 2026")
    XCTAssertTrue(entry.collectionNames.isEmpty)
    XCTAssertTrue(entry.tagNames.isEmpty)
    XCTAssertTrue(entry.isInInbox)
  }
}
