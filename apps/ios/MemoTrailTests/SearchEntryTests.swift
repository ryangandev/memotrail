import XCTest

@testable import MemoTrail

/// Keyword search through `search_wiki_items`, shaped like
/// `supabase/migrations/202610190023_hybrid_search.sql`, and the Export download.
final class SearchEntryTests: XCTestCase {
  func testSearchResultShowsAChaptersSpanAndOtherwiseItsDate() throws {
    for (precision, subtype, end, expected) in [
      ("year", "entry", "null", "2017"),
      ("month", "entry", "null", "Jan 2017"),
      ("range", "entry", "\"2019-02-03T12:00:00+00:00\"", "Jan 1, 2017 to Feb 3, 2019"),
      ("year", "chapter", "\"2020-01-01T12:00:00+00:00\"", "2017 - 2020"),
      ("day", "chapter", "null", "Since Jan 1, 2017"),
      ("unknown", "entry", "null", "Date unknown"),
    ] {
      let entry = try decode(
        """
        {"entry_id":"4F8D0FE6-61D0-418A-8713-CF071AEEA450","title":"Memory","body":"Original","item_kind":"entry","item_subtype":"\(subtype)","is_first_time":false,"occurred_start":\(precision == "unknown" ? "null" : "\"2017-01-01T12:00:00+00:00\""),"occurred_end":\(end),"date_precision":"\(precision)","occurred_timezone":"UTC","updated_at":"2026-09-02T12:00:00+00:00","total_count":1}
        """)
      XCTAssertEqual(entry.displayDate, expected, "\(precision) \(subtype)")
      XCTAssertEqual(entry.datePrecision.rawValue, precision)
    }
  }

  func testSearchEntryDecodesTheRPCRowAndUsesItsRecordedZone() throws {
    let entry = try decode(
      """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": "First time in Japan",
        "body": "A summer trip.",
        "occurred_start": "2017-07-08T06:30:00+00:00",
        "occurred_end": null,
        "occurred_label": null,
        "occurred_timezone": "Asia/Tokyo",
        "revision": 4,
        "updated_at": "2026-09-02T12:00:00.123456+00:00",
        "tag_names": ["Japan"],
        "match_reasons": ["Title", "Tag"],
        "match_rank": 0.42,
        "total_count": 3,
        "date_precision": "day",
        "item_kind": "entry",
        "item_subtype": "entry",
        "is_first_time": true,
        "semantic_similarity": null,
        "semantic_char_start": null,
        "semantic_char_end": null,
        "semantic_chunk_count": null
      }
      """)

    XCTAssertEqual(entry.displayTitle, "First time in Japan")
    XCTAssertEqual(entry.identityLabel, "First Time")
    XCTAssertEqual(entry.marks, .firstTime)
    XCTAssertEqual(entry.displayDate, "Jul 8, 2017")
    XCTAssertEqual(entry.revision, 4)
    XCTAssertEqual(entry.tagNames, ["Japan"])
    XCTAssertEqual(entry.matchReasons, ["Title", "Tag"])
    XCTAssertEqual(entry.totalCount, 3)
    XCTAssertNotNil(entry.updatedAt)

    let chapter = try decode(
      """
      {"entry_id":"4F8D0FE6-61D0-418A-8713-CF071AEEA450","title":"  ","body":"","item_subtype":"chapter","is_first_time":true,"occurred_start":"2017-07-08T06:30:00+00:00","occurred_end":null,"date_precision":"month","occurred_timezone":"Asia/Tokyo","total_count":"7"}
      """)
    XCTAssertNil(chapter.title)
    XCTAssertEqual(chapter.identityLabel, "Chapter · First Time")
    XCTAssertEqual(chapter.displayTitle, "July 2017")
    XCTAssertEqual(chapter.totalCount, 7)
  }

  func testSearchEntryFallsBackToUTCForAnInvalidLegacyTimezone() throws {
    let entry = try decode(
      """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": null,
        "body": "\\n  \\nWhy keep learning?\\nBecause the world keeps changing.\\n",
        "item_kind": "entry",
        "item_subtype": "entry",
        "occurred_start": "2026-07-03T23:30:00+00:00",
        "occurred_label": null,
        "occurred_timezone": "Not/AZone",
        "date_precision": "day",
        "updated_at": "2026-09-02T12:00:00+00:00",
        "tag_names": null,
        "match_reasons": ["Body"],
        "total_count": 1
      }
      """)

    XCTAssertEqual(entry.occurrence.timezone, "UTC")
    XCTAssertEqual(entry.displayTitle, "Friday, July 3, 2026")
    XCTAssertEqual(entry.note, "Why keep learning?\nBecause the world keeps changing.")
    XCTAssertEqual(entry.excerpt, "Why keep learning? Because the world keeps changing.")
    XCTAssertFalse(entry.hasLongNote)
    XCTAssertNil(entry.bodyRich)
    XCTAssertEqual(entry.displayDate, "Jul 3, 2026")
    XCTAssertTrue(entry.tagNames.isEmpty)
    XCTAssertFalse(entry.isFirstTime)
  }

  func testLongNotesOfferTheFullNoteLikeWeb() {
    let long = SearchEntry(id: UUID(), title: nil, body: String(repeating: "a", count: 281))
    let short = SearchEntry(id: UUID(), title: nil, body: String(repeating: "a", count: 280))
    XCTAssertTrue(long.hasLongNote)
    XCTAssertFalse(short.hasLongNote)
  }

  func testSearchRequestNormalizesTheQueryRecordsAndTags() throws {
    let request = try EntrySearchRequest.validate(
      query: "  teeth movement  ",
      records: [.chapter, .chapter, .entry],
      tagNames: [" Teeth ", "teeth", "science", " "],
      dateFrom: " ",
      dateTo: nil
    )

    XCTAssertEqual(request.query, "teeth movement")
    XCTAssertEqual(request.records, [.chapter, .entry])
    XCTAssertEqual(request.tagNames, ["Teeth", "science"])
    XCTAssertNil(request.dateFrom)
    XCTAssertTrue(request.hasCriteria)
  }

  func testFilterOnlySearchIsValidAndEmptySearchStaysIdle() throws {
    let filtered = try EntrySearchRequest.validate(query: " ", records: [.firstTime])
    let tagged = try EntrySearchRequest.validate(query: "", tagNames: ["Lisbon"])
    let dated = try EntrySearchRequest.validate(query: "", dateTo: "2026-09-29")
    let empty = try EntrySearchRequest.validate(query: " ", dateFrom: "", dateTo: "")

    XCTAssertTrue(filtered.hasCriteria)
    XCTAssertTrue(tagged.hasCriteria)
    XCTAssertTrue(dated.hasCriteria)
    XCTAssertFalse(empty.hasCriteria)
  }

  func testSearchRejectsOversizedQueriesAndTags() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: String(repeating: "a", count: EntrySearchRequest.queryLimit + 1))
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .queryTooLong)
      XCTAssertEqual(
        error.localizedDescription, "Search phrases can be up to 200 characters.")
    }
    XCTAssertNoThrow(
      try EntrySearchRequest.validate(
        query: String(repeating: "a", count: EntrySearchRequest.queryLimit)))

    for tags in [
      [String(repeating: "t", count: EntryLimits.tagName + 1)],
      (0...EntryLimits.tagCount).map { "tag \($0)" },
    ] {
      XCTAssertThrowsError(try EntrySearchRequest.validate(query: "valid", tagNames: tags)) {
        error in
        XCTAssertEqual(error as? EntrySearchError, .invalidTags)
      }
    }
  }

  func testSearchRejectsInvalidAndReversedDates() {
    for (from, to, expected) in [
      ("2026-02-30", nil, EntrySearchError.invalidStartDate),
      ("2026-9-1", nil, .invalidStartDate),
      (nil, "September 1", .invalidEndDate),
      ("2026-09-03", "2026-09-02", .invalidDateRange),
    ] as [(String?, String?, EntrySearchError)] {
      XCTAssertThrowsError(
        try EntrySearchRequest.validate(query: "", dateFrom: from, dateTo: to)
      ) { error in
        XCTAssertEqual(error as? EntrySearchError, expected, "\(from ?? "-") \(to ?? "-")")
      }
    }
    XCTAssertNoThrow(
      try EntrySearchRequest.validate(query: "", dateFrom: "2026-09-03", dateTo: "2026-09-03"))
  }

  func testSearchEncodesTheKeywordRPCContractWithoutEmbeddingArguments() throws {
    let request = try EntrySearchRequest.validate(
      query: "Japan", records: [.firstTime, .chapter], tagNames: ["Japan"],
      dateFrom: "2017-07-07", dateTo: "2017-07-08", limit: 25, offset: 50)
    let json = try object(request.parameters)

    XCTAssertEqual(
      Set(json.keys),
      [
        "p_query", "p_item_classifications", "p_tag_names", "p_date_from", "p_date_to",
        "p_limit", "p_offset", "p_order",
      ])
    XCTAssertEqual(json["p_query"] as? String, "Japan")
    XCTAssertEqual(json["p_item_classifications"] as? [String], ["first_time", "chapter"])
    XCTAssertEqual(json["p_tag_names"] as? [String], ["Japan"])
    XCTAssertEqual(json["p_date_from"] as? String, "2017-07-07")
    XCTAssertEqual(json["p_date_to"] as? String, "2017-07-08")
    XCTAssertEqual(json["p_limit"] as? Int, 25)
    XCTAssertEqual(json["p_offset"] as? Int, 50)
    XCTAssertEqual(json["p_order"] as? String, "relevance")
    XCTAssertEqual(try request.page(offset: 75).offset, 75)
    XCTAssertEqual(try request.page(offset: 75).records, [.firstTime, .chapter])
    XCTAssertThrowsError(try request.page(offset: -1))
  }

  func testRecordFiltersMatchTheWebClassifications() {
    XCTAssertEqual(EntryRecordFilter.allCases.map(\.rawValue), ["entry", "chapter", "first_time"])
    XCTAssertEqual(
      EntryRecordFilter.allCases.map(\.title), ["Entries", "Chapters", "First Times"])
  }

  func testRecordFilterSendsEntryChapterAndFirstTimeClassifications() throws {
    for (record, classification) in [
      (EntryRecordFilter.entry, "entry"), (.chapter, "chapter"), (.firstTime, "first_time"),
    ] {
      // A filter alone is a search, so Library never needs a phrase to apply it.
      let request = try LibraryController.searchRequest(
        query: "", record: record, tagName: nil, dateFrom: "", dateTo: "")
      XCTAssertTrue(request.hasCriteria)
      let json = try object(request.parameters)
      XCTAssertEqual(json["p_item_classifications"] as? [String], [classification])
      XCTAssertEqual(json["p_query"] as? String, "")
      // iOS searches by keyword only, so no embedding argument is ever sent.
      XCTAssertFalse(json.keys.contains { $0.contains("embedding") || $0.contains("semantic") })
    }
    let all = try LibraryController.searchRequest(
      query: "", record: nil, tagName: nil, dateFrom: "", dateTo: "")
    XCTAssertFalse(all.hasCriteria)
    XCTAssertEqual(try object(all.parameters)["p_item_classifications"] as? [String], [])
  }

  func testSearchResultNamesAnUntitledEntryByItsDateOnly() throws {
    let untitled = SearchEntry(
      id: UUID(), title: nil, body: "Text", occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
      datePrecision: .day, occurredTimezone: "UTC")
    XCTAssertEqual(untitled.accessibilityLabel, "Entry, Tuesday, November 14, 2023")
    let titled = SearchEntry(
      id: UUID(), title: "Lisbon", body: "Text", isFirstTime: true,
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000), datePrecision: .day,
      occurredTimezone: "UTC")
    XCTAssertEqual(titled.accessibilityLabel, "First Time, Lisbon, Nov 14, 2023")
  }

  func testSearchParametersEncodeAbsentDatesExplicitly() throws {
    let json = try object(EntrySearchRequest.validate(query: "learning").parameters)

    XCTAssertTrue(json["p_date_from"] is NSNull)
    XCTAssertTrue(json["p_date_to"] is NSNull)
    XCTAssertEqual(json["p_item_classifications"] as? [String], [])
    XCTAssertEqual(json["p_tag_names"] as? [String], [])
  }

  func testSearchRejectsInvalidPagination() {
    for (limit, offset) in [(101, 0), (0, 0), (25, -1), (25, 10_001)] {
      XCTAssertThrowsError(
        try EntrySearchRequest.validate(query: "learning", limit: limit, offset: offset)
      ) { error in
        XCTAssertEqual(error as? EntrySearchError, .invalidPagination)
      }
    }
  }

  // MARK: Export

  func testExportSnapshotPreservesCountsAndPortableFilename() throws {
    let json = """
      {"id":"00000000-0000-0000-0000-000000000001","schema_version":1,"captured_at":"2026-09-12T19:00:00.123+00:00","expires_at":"2026-09-13T19:00:00.123+00:00","row_count":1005,"json_bytes":2200000,"datasets":{"entries":1005,"tags":0}}
      """
    let snapshot = try JSONDecoder().decode(ExportSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.rowCount, 1005)
    XCTAssertEqual(snapshot.datasets["tags"], 0)
    XCTAssertEqual(snapshot.filename, "MemoTrail-2026-09-12-00000000.zip")
    let request = try JSONEncoder().encode(ExportInput(action: "download", id: snapshot.id))
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["action", "id"]))
    let id = try XCTUnwrap(UUID(uuidString: "4F8D0FE6-61D0-418A-8713-CF071AEEA450"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let download = try encoder.encode(ExportInput(action: "download", id: id))
    XCTAssertEqual(
      String(decoding: download, as: UTF8.self),
      #"{"action":"download","id":"4f8d0fe6-61d0-418a-8713-cf071aeea450"}"#)
    let list = try encoder.encode(ExportInput(action: "list"))
    XCTAssertEqual(String(decoding: list, as: UTF8.self), #"{"action":"list"}"#)
  }

  func testExportFooterRejectsTruncatedDownloadsAndFalseCompletionText() {
    var tail = Data(repeating: 0, count: ExportAPI.tailSize)
    tail.replaceSubrange(0..<4, with: [0x50, 0x4b, 5, 6])
    tail[20] = UInt8(ExportAPI.completion.utf8.count)
    tail.replaceSubrange(22..<tail.count, with: ExportAPI.completion.utf8)
    XCTAssertTrue(ExportAPI.isComplete(tail))
    for count in 0..<tail.count { XCTAssertFalse(ExportAPI.isComplete(tail.prefix(count))) }
    XCTAssertFalse(ExportAPI.isComplete(tail + Data([0])))
    tail[0] = 0
    XCTAssertFalse(ExportAPI.isComplete(tail))
  }

  // MARK: Helpers

  private func decode(_ json: String) throws -> SearchEntry {
    try JSONDecoder().decode(SearchEntry.self, from: Data(json.utf8))
  }

  private func object(_ value: some Encodable) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
