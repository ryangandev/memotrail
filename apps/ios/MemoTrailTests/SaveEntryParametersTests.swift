@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

/// `save_entry` arguments: always the same 15 keys, so PostgREST resolves the one function, and
/// a null means what Web's null means.
final class SaveEntryParametersTests: XCTestCase {
  private let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
  private let locationID = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!

  func testUntouchedLocationIsResentAsTheExistingSnapshot() throws {
    let entry = try JSONDecoder().decode(EditableEntry.self, from: Data(editableJSON.utf8))
    let location = try XCTUnwrap(entry.primaryLocation)
    let parameters = try SaveEntryParameters(
      entryID: entry.id, expectedRevision: entry.revision, title: entry.title, body: entry.body,
      richText: entry.richText, occurrence: entry.occurrence(), tagNames: entry.tagNames,
      location: location, marks: entry.marks)

    let sent = try XCTUnwrap(try json(parameters)["p_primary_location"] as? [String: Any])
    XCTAssertEqual(
      sent as NSDictionary,
      [
        "kind": "existing", "id": "40000000-0000-4000-8000-000000000004", "revision": 3,
        "formattedAddress": "Rua Augusta 1, 1100-048 Lisboa, Portugal",
        "address": "Rua Augusta 1", "city": "Lisboa", "region": NSNull(),
        "postalCode": "1100-048", "country": "Portugal", "countryCode": "PT",
        "latitude": 38.7097, "longitude": -9.1365, "timezone": "Europe/Lisbon",
        "resultType": "address",
      ] as NSDictionary)
    XCTAssertEqual(sent.count, 14)

    // Removing the Location sends null, which clears it.
    let removed = try SaveEntryParameters(
      entryID: entry.id, expectedRevision: entry.revision, title: entry.title, body: entry.body,
      richText: nil, occurrence: entry.occurrence(), tagNames: [], location: nil,
      marks: entry.marks)
    XCTAssertTrue(try json(removed)["p_primary_location"] is NSNull)
  }

  func testMarksAreAlwaysSent() throws {
    for (marks, chapter, firstTime) in [
      (EntryMarks.none, false, false), (.firstTime, false, true), (.chapter, true, false),
      (EntryMarks(isChapter: true, isFirstTime: true), true, true),
    ] {
      let sent = try json(parameters(title: "Moving to Lisbon", marks: marks))
      XCTAssertEqual(sent["p_is_chapter"] as? Bool, chapter, marks.identityLabel)
      XCTAssertEqual(sent["p_is_first_time"] as? Bool, firstTime, marks.identityLabel)
    }
  }

  func testNullRichTextClearsFormatting() throws {
    XCTAssertTrue(try json(parameters(body: "Harbor lights"))["p_body_rich"] is NSNull)

    let rich = try JSONDecoder().decode(EntryRichText.self, from: Data(harborRichText.utf8))
    let sent = try XCTUnwrap(
      try json(parameters(body: "Harbor lights", richText: rich))["p_body_rich"]
        as? [String: Any])
    XCTAssertEqual(sent["text"] as? String, "Harbor lights")
    XCTAssertEqual(sent["version"] as? Int, 1)
  }

  func testEveryArgumentIsSentWithExplicitNulls() throws {
    let sent = try json(
      parameters(
        expectedRevision: nil, title: "  ", body: " A note ",
        occurrence: EntryOccurrence(precision: .unknown, timezone: "UTC")))
    XCTAssertEqual(
      Set(sent.keys),
      [
        "p_entry_id", "p_expected_revision", "p_title", "p_body", "p_body_rich",
        "p_occurred_start", "p_occurred_end", "p_occurred_timezone", "p_occurred_label",
        "p_date_precision", "p_tag_names", "p_primary_location", "p_photo_location",
        "p_is_chapter", "p_is_first_time",
      ])
    XCTAssertEqual(sent["p_entry_id"] as? String, "10000000-0000-4000-8000-000000000001")
    for key in [
      "p_expected_revision", "p_title", "p_body_rich", "p_occurred_start", "p_occurred_end",
      "p_occurred_label", "p_primary_location", "p_photo_location",
    ] {
      XCTAssertTrue(sent[key] is NSNull, key)
    }
    // A blank title is no title, and the note is trimmed, like Web.
    XCTAssertEqual(sent["p_body"] as? String, "A note")
    XCTAssertEqual(sent["p_occurred_timezone"] as? String, "UTC")
    XCTAssertEqual(sent["p_date_precision"] as? String, "unknown")
    XCTAssertEqual(sent["p_tag_names"] as? [String], [])
  }

  func testDatesAreSentAsWebWritesThem() throws {
    let start = try XCTUnwrap(EntryTimestamp.date(from: "2022-02-01T12:00:00Z"))
    let end = try XCTUnwrap(EntryTimestamp.date(from: "2022-11-01T12:00:00Z"))
    let sent = try json(
      parameters(
        title: "Lisbon", marks: .chapter,
        occurrence: EntryOccurrence(
          precision: .month, start: start, end: end, label: "  ", timezone: "Europe/Lisbon")))
    XCTAssertEqual(sent["p_occurred_start"] as? String, "2022-02-01T12:00:00.000Z")
    XCTAssertEqual(sent["p_occurred_end"] as? String, "2022-11-01T12:00:00.000Z")
    XCTAssertEqual(sent["p_date_precision"] as? String, "month")
    XCTAssertEqual(sent["p_occurred_timezone"] as? String, "Europe/Lisbon")
    // A blank description is no description.
    XCTAssertTrue(sent["p_occurred_label"] is NSNull)
  }

  func testChapterEndIsAllowedOnlyForAChapter() throws {
    let start = try XCTUnwrap(EntryTimestamp.date(from: "2022-02-01T12:00:00Z"))
    let end = try XCTUnwrap(EntryTimestamp.date(from: "2022-11-01T12:00:00Z"))
    let span = EntryOccurrence(
      precision: .month, start: start, end: end, label: nil, timezone: "Europe/Lisbon")
    XCTAssertNoThrow(try parameters(title: "Lisbon", marks: .chapter, occurrence: span))
    XCTAssertThrowsError(try parameters(title: "Lisbon", marks: .firstTime, occurrence: span)) {
      XCTAssertEqual(
        $0 as? SaveEntryError,
        .invalid(
          "The end date must follow the start and use Range, Approximate, or Age precision."))
    }
  }

  func testInvalidInputIsRefusedInWebsWords() throws {
    func refusal(_ make: () throws -> SaveEntryParameters) -> SaveEntryError? {
      do {
        _ = try make()
        return nil
      } catch {
        return error as? SaveEntryError
      }
    }
    XCTAssertEqual(
      refusal { try parameters(title: " ", body: "A note", marks: .chapter) },
      .invalid("Give this Chapter a title."))
    XCTAssertEqual(
      refusal { try parameters(title: " ", body: " \n ") },
      .invalid("Keep a title or note before saving."))
    XCTAssertEqual(
      refusal { try parameters(title: String(repeating: "t", count: EntryLimits.title + 1)) },
      .invalid("Keep the title under 200 characters."))
    XCTAssertEqual(
      refusal { try parameters(body: String(repeating: "b", count: EntryLimits.body + 1)) },
      .invalid("Keep the note under 50,000 characters."))
    XCTAssertEqual(
      refusal {
        try parameters(tagNames: (0...EntryLimits.tagCount).map { "tag \($0)" })
      },
      .invalid(EntryLimits.tagCountMessage))
    let rich = try JSONDecoder().decode(EntryRichText.self, from: Data(harborRichText.utf8))
    XCTAssertEqual(
      refusal { try parameters(body: "Harbor lights tonight", richText: rich) },
      .invalid(
        "MemoTrail could not keep this note's formatting. Edit the note, then save again."))
    XCTAssertEqual(
      refusal { try parameters(expectedRevision: 0) }, .invalid("This Entry review is invalid."))
    XCTAssertEqual(
      refusal {
        try parameters(occurrence: EntryOccurrence(precision: .day, timezone: "Not/AZone"))
      },
      .invalid("Choose a valid IANA time zone, for example America/Los_Angeles."))
    XCTAssertEqual(
      refusal {
        try parameters(location: EntryLocation(id: locationID, revision: 0))
      },
      .invalid("Choose a valid Location or remove it from this Entry."))
    XCTAssertEqual(
      refusal {
        try parameters(
          location: EntryLocation(id: locationID, revision: 1, latitude: 91, longitude: 0))
      },
      .invalid("Choose a valid Location or remove it from this Entry."))
  }

  func testPhotoLocationNeedsASavedEntryAndValidCoordinates() throws {
    let photo = PhotoLocationDraft(
      attachmentId: UUID(uuidString: "20000000-0000-4000-8000-00000000000A")!,
      latitude: -90, longitude: 180)
    XCTAssertThrowsError(try parameters(expectedRevision: nil, photoLocation: photo)) {
      XCTAssertEqual($0 as? SaveEntryError, .invalid("This Entry review is invalid."))
    }
    let sent = try XCTUnwrap(
      try json(parameters(expectedRevision: 2, photoLocation: photo))["p_photo_location"]
        as? [String: Any])
    XCTAssertEqual(
      sent as NSDictionary,
      ["attachmentId": "20000000-0000-4000-8000-00000000000a", "latitude": -90, "longitude": 180]
        as NSDictionary)

    for (latitude, longitude) in [(91.0, 0.0), (0, 181), (.infinity, 0), (0, .nan)] {
      XCTAssertFalse(
        PhotoLocationDraft(attachmentId: UUID(), latitude: latitude, longitude: longitude)
          .isValid)
      XCTAssertThrowsError(
        try parameters(
          expectedRevision: 2,
          photoLocation: PhotoLocationDraft(
            attachmentId: UUID(), latitude: latitude, longitude: longitude))
      ) {
        XCTAssertEqual(
          $0 as? SaveEntryError,
          .invalid("Choose the photo's GPS position again, or remove it from this draft."))
      }
    }
  }

  func testTagNamesAreTrimmedAndDeduplicatedKeepingTheFirstSpelling() throws {
    let sent = try json(parameters(tagNames: [" Lisbon ", "lisbon", "Moves", "LISBON"]))
    XCTAssertEqual(sent["p_tag_names"] as? [String], ["Lisbon", "Moves"])
    // A blank or overlong name is refused rather than dropped, like Web `parseTagNames`.
    for names in [["Lisbon", " "], [String(repeating: "t", count: EntryLimits.tagName + 1)]] {
      XCTAssertThrowsError(try parameters(tagNames: names)) {
        XCTAssertEqual($0 as? SaveEntryError, .invalid(EntryLimits.tagCountMessage))
      }
    }
  }

  func testRefusedSavesAreReportedInWebsWords() {
    XCTAssertEqual(
      SaveEntryError.classify(PostgrestError(code: "40001", message: "primary_location_changed")),
      .conflict(
        "The photo or Location changed. Close this editor, refresh, and confirm the latest version before saving."
      ))
    XCTAssertEqual(
      SaveEntryError.classify(PostgrestError(code: "22023", message: "chapter_requires_title")),
      .invalid("Give this Chapter a title."))
    XCTAssertEqual(
      SaveEntryError.classify(PostgrestError(code: "22023", message: "something_else")), .failed)
    XCTAssertEqual(SaveEntryError.classify(URLError(.notConnectedToInternet)), .failed)
    XCTAssertEqual(SaveEntryError.classify(SaveEntryError.sessionExpired), .sessionExpired)
    XCTAssertEqual(
      SaveEntryError.unconfirmed(isCreate: true).errorDescription,
      "MemoTrail could not confirm this Entry was added. Refresh to check before adding it again.")
    XCTAssertEqual(
      SaveEntryError.unconfirmed(isCreate: false).errorDescription,
      "This Entry changed on another device. Close it, refresh, and edit the latest version.")
    XCTAssertEqual(
      SaveEntryError.sessionExpired.errorDescription,
      "Your session expired. Sign in again before saving.")
    XCTAssertEqual(
      SaveEntryError.failed.errorDescription, "MemoTrail could not save these changes. Try again.")
  }

  // MARK: Helpers

  private func parameters(
    expectedRevision: Int? = 1, title: String? = "Title", body: String = "",
    richText: EntryRichText? = nil, tagNames: [String] = [], location: EntryLocation? = nil,
    photoLocation: PhotoLocationDraft? = nil, marks: EntryMarks = .none,
    occurrence: EntryOccurrence = EntryOccurrence(precision: .unknown, timezone: "UTC")
  ) throws -> SaveEntryParameters {
    try SaveEntryParameters(
      entryID: entryID, expectedRevision: expectedRevision, title: title, body: body,
      richText: richText, occurrence: occurrence, tagNames: tagNames, location: location,
      photoLocation: photoLocation, marks: marks)
  }

  private func json(_ parameters: SaveEntryParameters) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
  }

  private let harborRichText = """
    {"version":1,"text":"Harbor lights","document":{"type":"doc","content":[\
    {"type":"paragraph","content":[{"type":"text","text":"Harbor","marks":[{"type":"bold"}]},\
    {"type":"text","text":" lights"}]}]}}
    """

  /// An `editable_entry` answer: the `entries` row with keys the editor ignores, plus
  /// `tag_names` and the whole `locations` row.
  private let editableJSON = """
    {"id":"10000000-0000-4000-8000-000000000001","owner_id":"30000000-0000-4000-8000-000000000003",\
    "title":"Moving to Lisbon","body":"Boxes everywhere.","item_kind":"entry",\
    "item_subtype":"entry","is_first_time":true,"revision":4,\
    "occurred_start":"2022-02-01T12:00:00+00:00","occurred_end":null,"date_precision":"month",\
    "occurred_label":null,"occurred_timezone":"Europe/Lisbon","source_language":"en",\
    "client_id":"web:1","embedding_model":null,"embedding_updated_at":null,"metadata":{},\
    "created_at":"2022-02-02T09:00:00.123456+00:00","updated_at":"2026-10-18T19:00:00+00:00",\
    "deleted_at":null,"tag_names":["lisbon","moves"],\
    "primary_location":{"id":"40000000-0000-4000-8000-000000000004",\
    "owner_id":"30000000-0000-4000-8000-000000000003",\
    "formatted_address":"Rua Augusta 1, 1100-048 Lisboa, Portugal","address":"Rua Augusta 1",\
    "city":"Lisboa","region":null,"postal_code":"1100-048","country":"Portugal",\
    "country_code":"PT","latitude":38.7097,"longitude":-9.1365,"provider":"mapkit",\
    "provider_location_id":null,"metadata":{},"revision":3,\
    "created_at":"2022-02-02T09:00:00+00:00","updated_at":"2022-02-02T09:00:00+00:00",\
    "timezone_id":"Europe/Lisbon","result_type":"address","bound_entry_id":null,\
    "coordinate_source":"provider","source_attachment_id":null}}
    """
}
