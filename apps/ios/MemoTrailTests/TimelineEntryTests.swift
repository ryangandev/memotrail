import XCTest

@testable import MemoTrail

final class TimelineEntryTests: XCTestCase {
  func testUnanchoredMomentsRemainVisibleAndSpanPrecisionsKeepTheirEnd() throws {
    let id = UUID()
    let row = makeRow(
      entryID: id, title: "Childhood", occurredStart: nil, occurredLabel: "Ages 1 to 12")
    XCTAssertEqual(TimelineWorkspace.tracks(from: [row]).first?.entries.first?.id, id)
    XCTAssertNil(row.entry?.occurredStart)
    XCTAssertEqual(row.entry?.displayDate, "Ages 1 to 12")
    for precision in [TimelineDatePrecision.age, .approximate, .unknown] {
      let input = try TimelineEntryInput.validate(
        entryID: nil, expectedRevision: nil, trackID: UUID(), kind: .stage, title: "Childhood",
        body: "", occurredStart: nil, occurredEnd: nil, datePrecision: precision,
        occurredLabel: precision == .unknown ? "" : "Ages 1 to 12", occurredTimezone: "UTC")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(
          with: JSONEncoder().encode(SaveTimelineEntryParameters(input: input))) as? [String: Any])
      XCTAssertTrue(json["p_occurred_start"] is NSNull)
      XCTAssertTrue(json["p_occurred_end"] is NSNull)
    }
    var draft = OccurrenceDraft(
      EntryOccurrence(
        precision: .year, start: nil, end: nil, label: nil, timezone: "Asia/Kathmandu"))
    draft.start = "2017"
    draft.end = "2023"
    let span = try draft.resolve(span: true)
    XCTAssertNotNil(span.end)
    XCTAssertNoThrow(try span.validate(span: true))
    XCTAssertThrowsError(try span.validate())
    draft.end = "2016"
    XCTAssertThrowsError(try draft.resolve(span: true))
  }

  func testExactTimelineSerializationPreservesDatabaseMicroseconds() throws {
    let json = """
      {"track_id":"10000000-0000-4000-8000-000000000001","track_name":"Life","track_sort_order":1,"track_is_hidden":false,"entry_id":"20000000-0000-4000-8000-000000000001","title":"A moment","body":"Original","entry_type":"standard","timeline_kind":"event","occurred_start":"2026-11-01T09:30:00.123456Z","date_precision":"exact","occurred_timezone":"America/Los_Angeles","revision":1,"updated_at":"2026-09-12T12:00:00Z"}
      """
    // Match the Supabase SDK's fractional-second decoding behavior.
    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: text) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      return try XCTUnwrap(formatter.date(from: text))
    }
    let row = try jsonDecoder.decode(TimelineWorkspaceRow.self, from: Data(json.utf8))
    let entry = try XCTUnwrap(row.entry)
    let resolved = try OccurrenceDraft(entry.occurrence).resolve(original: entry.occurrence)
    var input = try TimelineEntryInput.validate(
      entryID: entry.id, expectedRevision: entry.revision, trackID: entry.trackID, kind: .event,
      title: entry.title, body: entry.body, occurredStart: resolved.start, occurredEnd: nil,
      datePrecision: .exact, occurredLabel: "", occurredTimezone: entry.occurredTimezone)
    input.preserveUnchangedBounds(from: entry)
    let encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(SaveTimelineEntryParameters(input: input))) as? [String: Any])
    XCTAssertEqual(encoded["p_occurred_start"] as? String, "2026-11-01T09:30:00.123456Z")
  }

  func testWorkspaceDecodesEmptyAndPopulatedTracks() throws {
    let json = """
      [
        {
          "track_id": "10000000-0000-4000-8000-000000000001",
          "track_name": "Places",
          "track_system_key": "places",
          "track_sort_order": 10,
          "track_is_hidden": false,
          "entry_id": "20000000-0000-4000-8000-000000000001",
          "title": "Living in Philadelphia",
          "body": "A long chapter.",
          "entry_type": "home",
          "timeline_kind": "stage",
          "occurred_start": "2012-08-15T19:00:00Z",
          "occurred_end": null,
          "date_precision": "range",
          "occurred_label": "Ages 12 to 25",
          "occurred_timezone": "America/Los_Angeles",
          "revision": 3,
          "updated_at": "2026-09-02T19:00:00Z"
        },
        {
          "track_id": "10000000-0000-4000-8000-000000000002",
          "track_name": "Education",
          "track_system_key": "education",
          "track_sort_order": 20,
          "track_is_hidden": false,
          "entry_id": null,
          "title": null,
          "body": null,
          "entry_type": null,
          "timeline_kind": null,
          "occurred_start": null,
          "occurred_end": null,
          "date_precision": null,
          "occurred_label": null,
          "occurred_timezone": null,
          "revision": null,
          "updated_at": null
        }
      ]
      """
    let rows = try decoder.decode([TimelineWorkspaceRow].self, from: Data(json.utf8))
    let tracks = TimelineWorkspace.tracks(from: rows)

    XCTAssertEqual(tracks.map(\.name), ["Places", "Education"])
    XCTAssertEqual(tracks[0].entries.first?.title, "Living in Philadelphia")
    XCTAssertEqual(tracks[0].entries.first?.entryType, "home")
    XCTAssertEqual(tracks[0].entries.first?.revision, 3)
    XCTAssertTrue(tracks[1].entries.isEmpty)
  }

  func testWorkspaceSortsTracksAndEntriesChronologically() throws {
    let later = makeRow(
      trackID: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
      trackName: "First Times",
      trackSortOrder: 80,
      entryID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
      title: "Later",
      occurredStart: Date(timeIntervalSince1970: 200)
    )
    let earlier = makeRow(
      trackID: later.trackID,
      trackName: later.trackName,
      trackSortOrder: later.trackSortOrder,
      entryID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      title: "Earlier",
      occurredStart: Date(timeIntervalSince1970: 100)
    )
    let places = makeRow(
      trackID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      trackName: "Places",
      trackSortOrder: 10,
      entryID: nil,
      title: nil,
      occurredStart: nil
    )

    let tracks = TimelineWorkspace.tracks(from: [later, earlier, places])

    XCTAssertEqual(tracks.map(\.name), ["Places", "First Times"])
    XCTAssertEqual(tracks[1].entries.map(\.title), ["Earlier", "Later"])
  }

  func testEntryUsesHumanLabelAndOpenStage() throws {
    let row = makeRow(
      entryID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      title: "Philadelphia years",
      occurredStart: Date(timeIntervalSince1970: 100),
      occurredLabel: "Ages 12 to 25"
    )

    XCTAssertEqual(row.entry?.displayDate, "Ages 12 to 25")

    let withoutLabel = makeRow(
      entryID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
      title: "California",
      occurredStart: Date(timeIntervalSince1970: 100)
    )
    XCTAssertTrue(withoutLabel.entry?.displayDate.hasSuffix(" onward") == true)
  }

  func testSpecializedEntryTypesRouteToTheirOwnedEditors() throws {
    let entryID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let home = try XCTUnwrap(
      makeRow(entryID: entryID, title: "Home", occurredStart: Date(), entryType: "home").entry
    )
    let vehicle = try XCTUnwrap(
      makeRow(
        entryID: entryID,
        title: "Vehicle",
        occurredStart: Date(),
        entryType: "vehicle"
      ).entry
    )
    let lifeStage = try XCTUnwrap(
      makeRow(entryID: entryID, title: "Stage", occurredStart: Date()).entry
    )

    XCTAssertEqual(home.specializedEditor, .home)
    XCTAssertEqual(vehicle.specializedEditor, .vehicle)
    XCTAssertNil(lifeStage.specializedEditor)
  }

  func testValidationNormalizesAStage() throws {
    let input = try makeInput(
      title: "  College years  ",
      body: "  A formative chapter.  ",
      occurredLabel: "  Ages 18 to 22  "
    )

    XCTAssertEqual(input.title, "College years")
    XCTAssertEqual(input.body, "A formative chapter.")
    XCTAssertEqual(input.occurredLabel, "Ages 18 to 22")
  }

  func testValidationAcceptsAnEventWithoutAnEndDate() throws {
    let input = try makeInput(kind: .event, occurredEnd: nil, datePrecision: .day)

    XCTAssertEqual(input.kind, .event)
    XCTAssertNil(input.occurredEnd)
  }

  func testValidationRejectsMissingOrOversizedContent() {
    XCTAssertThrowsError(try makeInput(title: " ")) { error in
      XCTAssertEqual(error as? TimelineEntryError, .titleRequired)
    }
    XCTAssertThrowsError(
      try makeInput(body: String(repeating: "a", count: TimelineEntryInput.bodyLimit + 1))
    ) { error in
      XCTAssertEqual(error as? TimelineEntryError, .bodyTooLong)
    }
  }

  func testValidationRejectsInvalidRangesAndEventEnds() {
    XCTAssertThrowsError(
      try makeInput(
        occurredStart: Date(timeIntervalSince1970: 200),
        occurredEnd: Date(timeIntervalSince1970: 100)
      )
    ) { error in
      XCTAssertEqual(error as? TimelineEntryError, .reversedRange)
    }
    XCTAssertThrowsError(try makeInput(kind: .event)) { error in
      XCTAssertEqual(error as? TimelineEntryError, .eventHasEnd)
    }
  }

  func testValidationRequiresRevisionOnlyForExistingEntries() {
    XCTAssertThrowsError(try makeInput(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? TimelineEntryError, .invalidRevision)
    }

    XCTAssertNoThrow(
      try makeInput(
        entryID: UUID(uuidString: "20000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testValidationRejectsInvalidTimezoneAndHumanLabel() {
    XCTAssertThrowsError(try makeInput(occurredTimezone: "")) { error in
      XCTAssertEqual(error as? TimelineEntryError, .invalidTimezone)
    }
    XCTAssertThrowsError(
      try makeInput(
        occurredLabel: String(repeating: "a", count: TimelineEntryInput.labelLimit + 1)
      )
    ) { error in
      XCTAssertEqual(error as? TimelineEntryError, .labelTooLong)
    }
  }

  func testSaveParametersEncodeExplicitNullsForNewOpenStage() throws {
    let input = try makeInput(occurredEnd: nil, occurredLabel: "")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(SaveTimelineEntryParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_occurred_end"] is NSNull)
    XCTAssertTrue(json["p_occurred_label"] is NSNull)
    XCTAssertEqual(json["p_timeline_kind"] as? String, "stage")
    XCTAssertEqual(json["p_date_precision"] as? String, "range")
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeInput(
    entryID: UUID? = nil,
    expectedRevision: Int? = nil,
    kind: TimelineKind = .stage,
    title: String = "Life stage",
    body: String = "Notes",
    occurredStart: Date = Date(timeIntervalSince1970: 100),
    occurredEnd: Date? = Date(timeIntervalSince1970: 200),
    datePrecision: TimelineDatePrecision = .range,
    occurredLabel: String = "",
    occurredTimezone: String = "America/Los_Angeles"
  ) throws -> TimelineEntryInput {
    try TimelineEntryInput.validate(
      entryID: entryID,
      expectedRevision: expectedRevision,
      trackID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      kind: kind,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone
    )
  }

  private func makeRow(
    trackID: UUID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
    trackName: String = "Places",
    trackSortOrder: Int = 10,
    entryID: UUID?,
    title: String?,
    occurredStart: Date?,
    occurredLabel: String? = nil,
    entryType: String = "life_stage"
  ) -> TimelineWorkspaceRow {
    TimelineWorkspaceRow(
      trackID: trackID,
      trackName: trackName,
      trackSystemKey: trackName.lowercased(),
      trackSortOrder: trackSortOrder,
      trackIsHidden: false,
      entryID: entryID,
      title: title,
      body: entryID == nil ? nil : "Notes",
      entryType: entryID == nil ? nil : entryType,
      timelineKind: entryID == nil ? nil : "stage",
      occurredStart: occurredStart,
      occurredEnd: nil,
      datePrecision: entryID == nil ? nil : "range",
      occurredLabel: occurredLabel,
      occurredTimezone: entryID == nil ? nil : "America/Los_Angeles",
      revision: entryID == nil ? nil : 1,
      updatedAt: entryID == nil ? nil : Date(timeIntervalSince1970: 300)
    )
  }
}
