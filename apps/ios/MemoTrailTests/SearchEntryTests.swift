import XCTest

@testable import MemoTrail

final class SearchEntryTests: XCTestCase {
  func testSearchResultPreservesPartialDatesAndPeriodEnds() throws {
    for (precision, kind, subtype, end, expected) in [
      ("year", "entry", "entry", "null", "2017"),
      ("month", "entry", "entry", "null", "Jan 2017"),
      ("range", "entry", "entry", "\"2019-02-03T12:00:00Z\"", "Jan 1, 2017 to Feb 3, 2019"),
      ("year", "entry", "period", "\"2020-01-01T12:00:00Z\"", "2017 - 2020"),
      ("day", "entity", "home", "null", "Since Jan 1, 2017"),
      ("unknown", "entry", "entry", "null", "Date unknown"),
    ] {
      let json = """
        {"entry_id":"4F8D0FE6-61D0-418A-8713-CF071AEEA450","title":"Memory","body":"Original","item_kind":"\(kind)","item_subtype":"\(subtype)","inbox_status":"organized","occurred_start":"2017-01-01T12:00:00Z","occurred_end":\(end),"date_precision":"\(precision)","occurred_timezone":"UTC","updated_at":"2026-09-02T12:00:00Z","total_count":1}
        """
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let entry = try decoder.decode(SearchEntry.self, from: Data(json.utf8))
      XCTAssertEqual(entry.displayDate, expected)
      XCTAssertEqual(entry.datePrecision, precision)
    }
  }
  func testExportSnapshotPreservesCountsAndPortableFilename() throws {
    let json = """
      {"id":"00000000-0000-0000-0000-000000000001","schema_version":1,"captured_at":"2026-09-12T19:00:00.123+00:00","expires_at":"2026-09-13T19:00:00.123+00:00","row_count":1005,"json_bytes":2200000,"datasets":{"entries":1005,"homes":0}}
      """
    let snapshot = try JSONDecoder().decode(ExportSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.rowCount, 1005)
    XCTAssertEqual(snapshot.datasets["homes"], 0)
    XCTAssertEqual(snapshot.filename, "MemoTrail-2026-09-12-00000000.zip")
    let request = try JSONEncoder().encode(ExportInput(action: "download", id: snapshot.id))
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["action", "id"]))
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

  func testExplorationRequestPreservesRetryIdentityWithoutProviderSecrets() throws {
    let id = UUID()
    let input = ExplorationInput(
      action: "send", entryID: id, requestID: id, question: "为什么学习？", sourceRevision: 2)
    let data = try JSONEncoder().encode(input)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["requestID"] as? String, id.uuidString)
    XCTAssertEqual(json["sourceRevision"] as? Int, 2)
    XCTAssertEqual(json["question"] as? String, "为什么学习？")
    XCTAssertEqual(
      Set(json.keys), Set(["action", "entryID", "requestID", "question", "sourceRevision"]))
  }

  func testExplorationWorkspaceDecodesPersistedHistoryAndDeletedSaveTombstones() throws {
    let id = UUID().uuidString
    let json = """
      {"source":{"id":"\(id)","title":null,"body":"Original","revision":2},
      "turns":[{"id":"\(id)","sequence":5,"question":"Why?","source_revision":1,
      "source_snapshot":{"body":"Original","body_truncated":false},"status":"completed","answer":"A perspective",
      "saved_entries":[{"request_id":"\(id)","entry_id":null,"title":null,"deleted":true}]}],
      "total_count":21,"links":[{"id":"\(id)","title":"Conclusion","relationship":"exploration_conclusion"}],"linksTruncated":false}
      """
    let workspace = try JSONDecoder().decode(ExplorationWorkspace.self, from: Data(json.utf8))
    XCTAssertEqual(workspace.totalCount, 21)
    XCTAssertEqual(workspace.turns.first?.sourceRevision, 1)
    XCTAssertEqual(workspace.turns.first?.sourceSnapshot["body"]?.text, "Original")
    XCTAssertNil(workspace.turns.first?.savedEntries.first?.entryID)
    XCTAssertEqual(workspace.turns.first?.savedEntries.first?.deleted, true)
    XCTAssertEqual(workspace.links.first?.relationship, "exploration_conclusion")
  }

  func testExplorationSaveEncodesHumanEditsAndAcceptsDeletedResult() throws {
    let id = UUID()
    let input = ExplorationInput(
      action: "save", requestID: id, turnID: id, title: "My words", body: "Edited conclusion")
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertEqual(json["body"] as? String, "Edited conclusion")
    XCTAssertNil(json["entryID"])
    let deleted = try JSONDecoder().decode(
      ExplorationSaveResult.self, from: Data("{\"entry_id\":null,\"created\":false}".utf8))
    XCTAssertNil(deleted.entryID)
  }

  func testSearchRequestNormalizesContentAndOrganization() throws {
    let request = try EntrySearchRequest.validate(
      query: "  teeth movement  ",
      classifications: [.goal, .goal, .entry],
      collectionNames: [" Learning ", "learning", "Health", " "],
      tagNames: [" Teeth ", "teeth", "science"],
      dateFrom: " ",
      dateTo: nil
    )

    XCTAssertEqual(request.query, "teeth movement")
    XCTAssertEqual(request.classifications, [.goal, .entry])
    XCTAssertEqual(request.collectionNames, ["Learning", "Health"])
    XCTAssertEqual(request.tagNames, ["Teeth", "science"])
    XCTAssertNil(request.dateFrom)
    XCTAssertTrue(request.hasCriteria)
  }

  func testFilterOnlySearchIsValidAndEmptySearchStaysIdle() throws {
    let filtered = try EntrySearchRequest.validate(
      query: " ", classifications: [.firstTime], collectionNames: [], tagNames: [], dateFrom: nil,
      dateTo: nil)
    let dated = try EntrySearchRequest.validate(
      query: "", classifications: [], collectionNames: [], tagNames: [], dateFrom: nil,
      dateTo: "2026-09-29")
    let empty = try EntrySearchRequest.validate(
      query: " ", classifications: [], collectionNames: [], tagNames: [], dateFrom: "",
      dateTo: "")

    XCTAssertTrue(filtered.hasCriteria)
    XCTAssertTrue(dated.hasCriteria)
    XCTAssertFalse(empty.hasCriteria)
  }

  func testSearchRejectsOversizedQueryAndOrganizationNames() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: String(repeating: "a", count: EntrySearchRequest.queryLimit + 1),
        classifications: [], collectionNames: [], tagNames: [], dateFrom: nil, dateTo: nil)
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .queryTooLong)
    }

    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "valid", classifications: [], collectionNames: [String(repeating: "c", count: 81)],
        tagNames: [], dateFrom: nil, dateTo: nil)
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .invalidCollections)
    }

    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "valid", classifications: [], collectionNames: [],
        tagNames: [String(repeating: "t", count: 61)], dateFrom: nil, dateTo: nil)
    ) { error in
      XCTAssertEqual(error as? EntrySearchError, .invalidTags)
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
        try EntrySearchRequest.validate(
          query: "", classifications: [], collectionNames: [], tagNames: [], dateFrom: from,
          dateTo: to)
      ) { error in
        XCTAssertEqual(error as? EntrySearchError, expected, "\(from ?? "-") \(to ?? "-")")
      }
    }
  }

  func testSearchEncodesTheWebRPCContract() throws {
    let request = try EntrySearchRequest.validate(
      query: "Japan", classifications: [.firstTime], collectionNames: ["Travel"],
      tagNames: ["Japan"], dateFrom: "2017-07-07", dateTo: "2017-07-08", limit: 25, offset: 50)
    let data = try JSONEncoder().encode(request.parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_query"] as? String, "Japan")
    XCTAssertEqual(json["p_item_classifications"] as? [String], ["first_time"])
    XCTAssertEqual(json["p_collection_names"] as? [String], ["Travel"])
    XCTAssertEqual(json["p_tag_names"] as? [String], ["Japan"])
    XCTAssertEqual(json["p_date_from"] as? String, "2017-07-07")
    XCTAssertEqual(json["p_date_to"] as? String, "2017-07-08")
    XCTAssertEqual(json["p_limit"] as? Int, 25)
    XCTAssertEqual(json["p_offset"] as? Int, 50)
    XCTAssertEqual(json["p_order"] as? String, "relevance")
    XCTAssertEqual(try request.page(offset: 75).offset, 75)
    XCTAssertEqual(try request.page(offset: 75).classifications, [.firstTime])
  }

  func testRecordFilterGroupsMatchTheWebClassifications() {
    XCTAssertEqual(WikiItemClassification.groups.map(\.title), ["Records", "Focused records"])
    XCTAssertEqual(
      WikiItemClassification.groups.flatMap(\.options).map(\.rawValue),
      ["entry", "entity", "goal", "first_time", "person", "home", "vehicle"])
    XCTAssertEqual(
      WikiItemClassification.groups.flatMap(\.options).map(\.title),
      ["Entries", "Entities", "Goals", "First Times", "People", "Homes", "Vehicles"])
  }

  func testSearchParametersEncodeAbsentDatesExplicitly() throws {
    let request = try EntrySearchRequest.validate(
      query: "learning", classifications: [], collectionNames: [], tagNames: [], dateFrom: nil,
      dateTo: nil)
    let data = try JSONEncoder().encode(request.parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_date_from"] is NSNull)
    XCTAssertTrue(json["p_date_to"] is NSNull)
  }

  func testSearchRejectsInvalidPagination() {
    XCTAssertThrowsError(
      try EntrySearchRequest.validate(
        query: "learning", classifications: [], collectionNames: [], tagNames: [], dateFrom: nil,
        dateTo: nil, limit: 101, offset: 0)
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
        "item_kind": "entry",
        "item_subtype": "first_time",
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
    XCTAssertEqual(entry.identityLabel, "First Time")
    XCTAssertEqual(entry.displayDate, "Jul 8, 2017")
    XCTAssertEqual(entry.collectionNames, ["Travel"])
    XCTAssertEqual(entry.tagNames, ["Japan"])
    XCTAssertEqual(entry.matchReasons, ["Title", "Collection"])
    XCTAssertEqual(entry.totalCount, 3)
    XCTAssertFalse(entry.isInInbox)
  }

  func testSearchEntryDecodesCanonicalPersonRoutingIdentity() throws {
    let json = """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": "Marina",
        "body": "Friend from the harbor.",
        "item_kind": "entity",
        "item_subtype": "person",
        "record_source": "person",
        "record_id": "F0A97797-CE56-4BD4-BA1E-BCE57304509E",
        "inbox_status": "organized",
        "updated_at": "2026-09-02T12:00:00Z",
        "total_count": 1
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entry = try decoder.decode(SearchEntry.self, from: Data(json.utf8))

    XCTAssertEqual(entry.itemKind, .entity)
    XCTAssertEqual(entry.itemSubtype, "person")
    XCTAssertEqual(entry.recordSource, .person)
    XCTAssertEqual(entry.recordID.uuidString, "F0A97797-CE56-4BD4-BA1E-BCE57304509E")
    XCTAssertEqual(entry.identityLabel, "Person")
  }

  func testSearchEntryFallsBackToUTCForAnInvalidLegacyTimezone() throws {
    let json = """
      {
        "entry_id": "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
        "title": null,
        "body": "\\n  \\nWhy keep learning?\\nBecause the world keeps changing.\\n",
        "item_kind": "entry",
        "item_subtype": "entry",
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
    XCTAssertEqual(entry.note, "Why keep learning?\nBecause the world keeps changing.")
    XCTAssertFalse(entry.hasLongNote)
    XCTAssertNil(entry.bodyRich)
    XCTAssertEqual(entry.displayDate, "Jul 3, 2026")
    XCTAssertTrue(entry.collectionNames.isEmpty)
    XCTAssertTrue(entry.tagNames.isEmpty)
    XCTAssertTrue(entry.isInInbox)
  }
}
