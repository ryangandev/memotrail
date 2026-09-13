import XCTest

@testable import MemoTrail

final class SearchEntryTests: XCTestCase {
  func testLibraryKeywordSearchDecodesKindsAndStableIdentities() throws {
    let id = UUID()
    let data = Data(
      """
      {"total_count":3,"items":[
        {"id":"\(id)","kind":"person","name":"学习","excerpt":"Friend","match_reasons":["Name"]},
        {"id":"\(id)","kind":"place","name":"Library","excerpt":"","match_reasons":[]},
        {"id":"\(id)","kind":"habit","name":"Read","excerpt":"Book","match_reasons":["Check-in note"]}
      ]}
      """.utf8)
    let page = try JSONDecoder().decode(LibrarySearchPage.self, from: data)
    XCTAssertTrue(page.isValid)
    XCTAssertEqual(page.totalCount, 3)
    XCTAssertEqual(Set(page.items.map(\.id)).count, 3)
    XCTAssertEqual(page.items[0].recordID, id)
    XCTAssertEqual(page.items[2].matchReasons, ["Check-in note"])
  }

  func testLibraryKeywordSearchUsesTheSharedBoundedContract() throws {
    let request = LibrarySearchParameters(p_query: "学习", p_offset: 20)
    let values = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    XCTAssertEqual(values["p_query"] as? String, "学习")
    XCTAssertEqual(values["p_limit"] as? Int, 20)
    XCTAssertEqual(values["p_offset"] as? Int, 20)
    let invalid = Data("{\"total_count\":-1,\"items\":[]}".utf8)
    XCTAssertFalse(try JSONDecoder().decode(LibrarySearchPage.self, from: invalid).isValid)
  }

  func testSearchResultPreservesPartialDatesAndPeriodEnds() throws {
    for (precision, type, end, expected) in [
      ("year", "standard", "null", "2017"),
      ("month", "standard", "null", "Jan 2017"),
      ("range", "standard", "\"2019-02-03T12:00:00Z\"", "Jan 1, 2017 to Feb 3, 2019"),
      ("year", "life_stage", "\"2020-01-01T12:00:00Z\"", "2017 - 2020"),
      ("day", "home", "null", "Since Jan 1, 2017"),
      ("unknown", "standard", "null", "Date unknown"),
    ] {
      let json = """
        {"entry_id":"4F8D0FE6-61D0-418A-8713-CF071AEEA450","title":"Memory","body":"Original","entry_type":"\(type)","inbox_status":"organized","occurred_start":"2017-01-01T12:00:00Z","occurred_end":\(end),"date_precision":"\(precision)","occurred_timezone":"UTC","updated_at":"2026-09-02T12:00:00Z","total_count":1}
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

  func testAISearchUsesSharedFiltersWithoutProviderSecrets() throws {
    let request = try EntrySearchRequest.validate(
      query: "第一次滑雪?", entryTypes: [.firstTime], collectionNames: ["Travel"], tagNames: ["winter"],
      dateFrom: nil, dateTo: nil)
    let input = AISearchRequest(request: request, timeZone: "America/Los_Angeles")
    XCTAssertEqual(input.parameters["q"], ["第一次滑雪?"])
    XCTAssertEqual(input.parameters["type"], ["first_time"])
    XCTAssertEqual(input.parameters["collection"], ["Travel"])
    XCTAssertEqual(input.parameters["tag"], ["winter"])
    XCTAssertEqual(input.parameters["from"], [])
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(input), encoding: .utf8))
    XCTAssertFalse(encoded.contains("AI_API_KEY"))
    XCTAssertTrue(encoded.contains("America"))
  }
  func testAISearchDecodesVerifiableCitationsAndUnknownDates() throws {
    let data = Data(
      #"{"question":"When did I ski?","findings":[{"text":"At age 17.","citations":[{"sourceID":"S1","quote":"第一次滑雪是在17岁。"}]}],"sources":[{"id":"S1","recordID":"11111111-1111-4111-8111-111111111111","kind":"entry","title":"Skiing","text":"第一次滑雪是在17岁。","href":"/history?entry=11111111-1111-4111-8111-111111111111","truncated":false}],"notices":[],"insufficientEvidence":false,"queries":["skiing","滑雪"]}"#
        .utf8)
    let answer = try JSONDecoder().decode(AISearchAnswer.self, from: data)
    XCTAssertEqual(answer.findings[0].citations[0].sourceID, answer.sources[0].id)
    XCTAssertEqual(
      answer.sources[0].recordID.uuidString.lowercased(), "11111111-1111-4111-8111-111111111111")
    XCTAssertFalse(answer.insufficientEvidence)
  }
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
