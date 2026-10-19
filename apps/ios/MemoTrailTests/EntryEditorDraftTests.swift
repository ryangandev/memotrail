import XCTest

@testable import MemoTrail

/// The Entry editor's draft rules, mirroring Web `occurrence.test.ts`, the editor cases of
/// `inbox-review.test.ts`, and the date controls of `occurrence-editor.tsx`.
@MainActor
final class EntryEditorDraftTests: XCTestCase {
  private let original = EntryOccurrence(
    precision: .exact, start: Date(timeIntervalSince1970: 1_793_525_427.123), end: nil,
    label: nil, timezone: "America/Los_Angeles")

  private func draft(
    _ precision: DatePrecision, start: String = "", end: String = "",
    endMode: OccurrenceDraft.EndMode = .date, label: String = "", timezone: String = "UTC"
  ) -> OccurrenceDraft {
    var draft = OccurrenceDraft(
      EntryOccurrence(precision: precision, start: nil, end: nil, label: nil, timezone: timezone))
    draft.start = start
    draft.end = end
    draft.endMode = endMode
    draft.label = label
    return draft
  }

  private func message(_ work: () throws -> Void) -> String? {
    do {
      try work()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private func entry(
    title: String? = "Morning", body: String = "Plain note", richText: EntryRichText? = nil,
    marks: EntryMarks = .none, start: Date? = nil, end: Date? = nil,
    precision: DatePrecision = .unknown, timezone: String? = nil, tags: [String] = [],
    location: EntryLocation? = nil
  ) -> EditableEntry {
    EditableEntry(
      id: UUID(), title: title, body: body, richText: richText, subtype: marks.subtype,
      isFirstTime: marks.isFirstTime, revision: 3, occurredStart: start, occurredEnd: end,
      occurredTimezone: timezone, datePrecision: precision, tagNames: tags,
      primaryLocation: location)
  }

  // MARK: Web `resolveOccurrenceDraft`

  func testUnchangedInstantKeepsItsSecondsMillisecondsAndRepeatedHour() throws {
    let opened = OccurrenceDraft(original)
    XCTAssertEqual(opened.start, "2026-11-01T01:30:27")
    XCTAssertEqual(try opened.resolvedForSave(original: original), original)
    XCTAssertEqual(
      OccurrenceDraft.wallTimeToDate("2026-11-01T01:30:27", timezone: original.timezone),
      Date(timeIntervalSince1970: 1_793_521_827))
  }

  func testCalendarPrecisionsKeepTheirTextInTheRecordedZone() throws {
    for (precision, start) in [(DatePrecision.year, "2017"), (.month, "2017-07"), (.day, "2017-07-08")] {
      let value = try draft(precision, start: start, timezone: "Pacific/Auckland")
        .resolvedForSave()
      XCTAssertEqual(value.precision, precision)
      XCTAssertEqual(OccurrenceDraft(value).start, start)
      XCTAssertEqual(value.timezone, "Pacific/Auckland")
    }
  }

  func testAgesAndApproximateDatesStoreOnlyTheirDescription() throws {
    for precision in [DatePrecision.age, .approximate] {
      let value = try draft(precision, label: "17岁，第一次去日本").resolvedForSave()
      XCTAssertEqual(
        value,
        EntryOccurrence(
          precision: precision, start: nil, end: nil, label: "17岁，第一次去日本", timezone: "UTC"))
    }
  }

  func testOpenRangesSaveAndReversedOrUndescribedDatesDoNot() throws {
    let range = draft(.range, start: "2020-01-01")
    XCTAssertNil(try range.resolvedForSave().end)
    var reversed = range
    reversed.end = "2019-01-01"
    XCTAssertEqual(
      message { _ = try reversed.resolvedForSave() },
      "The end date must be on or after the start date.")
    var age = range
    age.precision = .age
    age.start = ""
    XCTAssertEqual(
      message { _ = try age.resolvedForSave() },
      "Describe the age or approximate period you remember.")
    var long = range
    long.label = String(repeating: "x", count: 201)
    XCTAssertEqual(
      message { _ = try long.resolvedForSave() },
      "Keep the date description under 200 characters.")
  }

  func testAnEndDateIsOptionalAndPresentKeepsItOpen() throws {
    XCTAssertNil(try draft(.range, start: "2020-01-01", endMode: .present).resolvedForSave().end)
    XCTAssertNil(try draft(.range, start: "2020-01-01").resolvedForSave().end)
    XCTAssertEqual(
      try draft(.range, start: "2020-01-01", end: "2023-01-01").resolvedForSave().end,
      ISO8601DateFormatter().date(from: "2023-01-01T12:00:00Z"))
    XCTAssertNil(
      try draft(.range, start: "2020-01-01", end: "2023-01-01", endMode: .present)
        .resolvedForSave().end)
  }

  func testChaptersEndAtEachPrecisionButOrdinaryEntriesDoNot() throws {
    for (precision, start, end) in [
      (DatePrecision.year, "2017", "2023"), (.month, "2017-07", "2023-06"),
      (.exact, "2017-07-08T01:30:01", "2023-06-01T02:00:01"),
      (.day, "2017-07-08", "2023-06-01"),
    ] {
      let value = try draft(precision, start: start, end: end, timezone: "Asia/Kathmandu")
        .resolvedForSave(span: true)
      XCTAssertNotNil(value.end)
      XCTAssertNil(OccurrenceRules.problem(value, span: true))
      XCTAssertEqual(
        OccurrenceRules.problem(value),
        "Only ranges, ages, or approximate periods can have an end date.")
      XCTAssertNotNil(
        message { _ = try self.draft(precision, start: end, end: start).resolvedForSave(span: true) })
    }
  }

  func testAnEmptyCalendarDateIsStoredAsUnknownAndKeepsItsDescription() throws {
    for precision in [DatePrecision.exact, .day, .month, .year, .range] {
      XCTAssertEqual(
        try draft(precision, label: "Sometime in childhood").resolvedForSave(),
        EntryOccurrence(
          precision: .unknown, start: nil, end: nil, label: "Sometime in childhood",
          timezone: "UTC"),
        "\(precision)")
    }
    // A Chapter still going on has no end either.
    XCTAssertEqual(
      try draft(.day, endMode: .present).resolvedForSave(span: true).precision, .unknown)
  }

  func testAnEndDateNeedsAStartDate() {
    for (precision, span) in [(DatePrecision.day, true), (.approximate, false)] {
      XCTAssertEqual(
        message {
          _ = try draft(precision, end: "2023-01-01", label: "Around college")
            .resolvedForSave(span: span)
        },
        "Add a start date before the end date.")
    }
  }

  func testInvalidPartialDatesAreRefusedRatherThanConverted() {
    for (precision, start) in [(DatePrecision.year, "20"), (.month, "2017-13"), (.day, "2017-02-30")] {
      XCTAssertEqual(
        message { _ = try draft(precision, start: start).resolvedForSave() },
        "Choose a valid calendar date and time. This time may not exist during a daylight-saving change."
      )
    }
    XCTAssertEqual(
      message { _ = try draft(.day, start: "2026-01-01", timezone: "Not/AZone").resolvedForSave() },
      OccurrenceRules.timezoneMessage)
  }

  // MARK: Web `OccurrenceEditor`

  func testASavedDateWithoutAnEndOpensAsStillGoingOn() {
    let open = OccurrenceDraft.editing(
      EntryOccurrence(
        precision: .unknown, start: nil, end: nil, label: nil, timezone: "UTC"),
      undatedTimezone: "Europe/Paris")
    XCTAssertEqual(open.endMode, .present)
    XCTAssertEqual(open.timezone, "Europe/Paris")
    XCTAssertEqual(open.segment, .day)
    XCTAssertFalse(open.presentShown(span: false))
    XCTAssertEqual(open.shownEndMode(span: false), .date)
    XCTAssertTrue(open.presentShown(span: true))
  }

  func testACoarserDateKeepsWhatItCanHoldAndAFinerOneStartsEmpty() {
    var value = draft(.day, start: "2017-07-08", label: "Moving day")
    value.changeSegment(to: .month, span: false, unsurePrecision: .approximate)
    XCTAssertEqual([value.start, value.end], ["2017-07", ""])
    XCTAssertEqual(value.precision, .month)
    value.changeSegment(to: .year, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(value.start, "2017")
    value.changeSegment(to: .month, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(value.start, "")
    value.start = "2017-07"
    value.changeSegment(to: .day, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(value.start, "")
    XCTAssertEqual(value.precision, .day)
    XCTAssertEqual(value.label, "Moving day")
  }

  func testAnEmptyDayIsUnknownUntilItIsEdited() throws {
    var value = draft(.unknown)
    XCTAssertEqual(value.segment, .day)
    XCTAssertEqual(try value.resolvedForSave().precision, .unknown)
    value.edit { $0.start = "2024-02-03" }
    XCTAssertEqual(value.precision, .day)
    XCTAssertEqual(try value.resolvedForSave().precision, .day)
  }

  func testNotSureKeepsAnAgeAndADayEndBecomesARange() {
    var age = draft(.age, label: "Age 17")
    age.changeSegment(to: .year, span: false, unsurePrecision: .age)
    age.changeSegment(to: .unsure, span: false, unsurePrecision: .age)
    XCTAssertEqual(age.precision, .age)
    XCTAssertEqual(age.label, "Age 17")
    XCTAssertEqual(age.endMode, .present)
    XCTAssertFalse(age.endAdded(span: false))

    var range = draft(.range, start: "2020-01-02", end: "2021-03-04")
    range.changeSegment(to: .unsure, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(range.precision, .approximate)
    XCTAssertEqual(range.end, "2021-03-04")
    XCTAssertEqual(range.endMode, .date)
    XCTAssertTrue(range.endAdded(span: false))
    range.changeSegment(to: .day, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(range.precision, .range)
    // An ordinary Entry's Month has no end; a Chapter's keeps it.
    var month = range
    month.changeSegment(to: .month, span: false, unsurePrecision: .approximate)
    XCTAssertEqual(month.end, "")
    range.changeSegment(to: .month, span: true, unsurePrecision: .approximate)
    XCTAssertEqual(range.end, "2021-03")
  }

  func testAddTimeKeepsTheDateAndStartsTheTimeEmpty() {
    var value = draft(.day, start: "2017-07-08", end: "2017-08-01")
    XCTAssertTrue(value.timeToggleShown(span: true))
    value.toggleTime(true, span: true)
    XCTAssertEqual(value.precision, .exact)
    XCTAssertEqual([value.start, value.end], ["2017-07-08", "2017-08-01"])
    XCTAssertFalse(value.endToggleShown(span: false))
    value.start = "2017-07-08T09:15:00"
    value.toggleTime(false, span: false)
    XCTAssertEqual([value.start, value.end], ["2017-07-08", ""])
    XCTAssertEqual(value.precision, .day)
    XCTAssertFalse(draft(.range, start: "2017-07-08").timeToggleShown(span: false))
  }

  func testAddEndDateMakesADayRangeAndNotSureEndOnADate() {
    var day = draft(.day, start: "2017-07-08")
    day.toggleEnd(true)
    XCTAssertEqual(day.precision, .range)
    XCTAssertTrue(day.endAdded(span: false))
    day.end = "2017-07-09"
    day.toggleEnd(false)
    XCTAssertEqual(day.precision, .day)
    XCTAssertEqual(day.end, "")

    var unsure = draft(.approximate, endMode: .present, label: "College")
    unsure.toggleEnd(true)
    XCTAssertEqual(unsure.endMode, .date)
    XCTAssertEqual(unsure.precision, .approximate)
    unsure.toggleEnd(false)
    XCTAssertEqual(unsure.endMode, .present)
  }

  func testPresentClearsTheEndDate() {
    var value = draft(.range, start: "2020-01-01", end: "2021-01-01")
    value.setPresent(true)
    XCTAssertEqual(value.end, "")
    XCTAssertEqual(value.endMode, .present)
    value.setPresent(false)
    XCTAssertEqual(value.endMode, .date)
  }

  func testACameraDateBecomesADayOnlyWhenItIsReal() throws {
    var value = draft(.range, start: "2020-01-01", end: "2021-01-01", label: "Trip")
    try value.useCalendarDate("2024-05-06")
    XCTAssertEqual(value.precision, .day)
    XCTAssertEqual([value.start, value.end, value.label], ["2024-05-06", "", ""])
    XCTAssertThrowsError(try value.useCalendarDate("2024-02-30"))
    XCTAssertThrowsError(try value.useCalendarDate("2024-5-6"))
    XCTAssertEqual(value.start, "2024-05-06")
  }

  // MARK: Web `EntryEditorDialog`

  func testCheckingChapterKeepsADayEndAndUncheckingKeepsItAsARange() {
    var value = EntryEditorDraft(mode: .new(.none), timezone: "UTC")
    value.occurrence = draft(.range, start: "2020-01-01", end: "2021-01-01")
    value.changeMarks(.chapter)
    XCTAssertEqual(value.occurrence.precision, .day)
    XCTAssertEqual(value.occurrence.end, "2021-01-01")
    value.changeMarks(.none)
    XCTAssertEqual(value.occurrence.precision, .range)
    XCTAssertEqual(value.occurrence.end, "2021-01-01")

    value.changeMarks(.chapter)
    value.occurrence = draft(.month, start: "2020-01", end: "2021-01")
    value.changeMarks(EntryMarks(isChapter: false, isFirstTime: true))
    XCTAssertEqual(value.occurrence.end, "")
    XCTAssertEqual(value.marks, .firstTime)

    value.changeMarks(.chapter)
    value.occurrence = draft(.approximate, end: "2021-01-01", label: "College")
    value.changeMarks(.none)
    XCTAssertEqual(value.occurrence.end, "2021-01-01")
  }

  func testAChapterNeedsATitleBeforeItsDateIsChecked() {
    var value = EntryEditorDraft(mode: .new(.chapter), timezone: "UTC")
    value.occurrence = draft(.day, start: "2017-02-30")
    XCTAssertEqual(
      message { _ = try value.parameters(body: "Note", richText: nil, tagOptions: []) },
      "Give this Chapter a title.")
    value.title = "  Grad school  "
    XCTAssertNotNil(message { _ = try value.parameters(body: "", richText: nil, tagOptions: []) })
    value.occurrence = draft(.day, start: "2017-02-01", end: "2018-05-01")
    let parameters = try? value.parameters(body: "", richText: nil, tagOptions: [])
    XCTAssertEqual(parameters?.title, "Grad school")
    XCTAssertEqual(parameters?.marks, .chapter)
    XCTAssertEqual(parameters?.occurrence.precision, .day)
    XCTAssertNotNil(parameters?.occurrence.end)
  }

  func testANewDraftSavesOnceWithItsIDAndWithoutAPhotoLocation() throws {
    let id = UUID()
    var value = EntryEditorDraft(mode: .new(.firstTime), timezone: "Asia/Tokyo", entryID: id)
    value.title = "First swim"
    value.photoLocation = PhotoLocationDraft(attachmentId: UUID(), latitude: 1, longitude: 2)
    value.tagNames = ["summer", " Lake "]
    let parameters = try value.parameters(
      body: "", richText: nil, tagOptions: ["Summer", "lake"])
    XCTAssertEqual(parameters.entryID, id)
    XCTAssertNil(parameters.expectedRevision)
    XCTAssertNil(parameters.photoLocation)
    XCTAssertEqual(parameters.tagNames, ["Summer", "lake"])
    XCTAssertEqual(parameters.marks, .firstTime)
    XCTAssertEqual(parameters.occurrence.precision, .unknown)
    XCTAssertEqual(parameters.occurrence.timezone, "Asia/Tokyo")
  }

  func testAnEditedDraftKeepsItsRevisionAndCanRemoveItsLocation() throws {
    let location = EntryLocation(
      id: UUID(), revision: 1, formattedAddress: "Pier 1", latitude: 37.8, longitude: -122.4)
    var value = EntryEditorDraft(
      mode: .edit(entry(location: location)), timezone: "UTC")
    XCTAssertEqual(value.revision, 3)
    XCTAssertEqual(try value.parameters(body: "Note", richText: nil, tagOptions: []).location, location)
    value.location = nil
    let photo = PhotoLocationDraft(attachmentId: UUID(), latitude: 1, longitude: 2)
    value.photoLocation = photo
    let parameters = try value.parameters(body: "Note", richText: nil, tagOptions: [])
    XCTAssertNil(parameters.location)
    XCTAssertEqual(parameters.photoLocation, photo)
    XCTAssertEqual(parameters.expectedRevision, 3)
  }

  func testTheSettingsTimeZoneOnlyReplacesAnUnenteredDate() {
    var undated = EntryEditorDraft(mode: .new(.none), timezone: "UTC")
    undated.useDefaultTimezone("Europe/Paris")
    XCTAssertEqual(undated.occurrence.timezone, "Europe/Paris")
    undated.occurrence.start = "2024-01-01"
    undated.useDefaultTimezone("Asia/Tokyo")
    XCTAssertEqual(undated.occurrence.timezone, "Europe/Paris")

    var dated = EntryEditorDraft(
      mode: .edit(
        entry(
          start: Date(timeIntervalSince1970: 0), precision: .day, timezone: "America/Chicago")),
      timezone: "UTC")
    dated.useDefaultTimezone("Europe/Paris")
    XCTAssertEqual(dated.occurrence.timezone, "America/Chicago")
  }

  // MARK: Tags

  func testMostUsedTagsSkipAddedNamesAndTheCountShowsNearTheLimit() {
    let options = ["Family", "Travel", "Food", "Work", "Books", "Music", "Garden", "Film"]
    XCTAssertEqual(
      EntryTagField.suggestions(["travel"], options: options),
      ["Family", "Food", "Work", "Books", "Music", "Garden"])
    let full = (0..<EntryLimits.tagCount).map { "tag\($0)" }
    XCTAssertEqual(EntryTagField.suggestions(full, options: options), [])
    XCTAssertFalse(EntryTagField.showsLimit(Array(full.prefix(59))))
    XCTAssertTrue(EntryTagField.showsLimit(Array(full.prefix(60))))
    XCTAssertEqual(
      EntryTagField.namesToSave(["family"], draft: " TRAVEL ", options: options),
      ["Family", "Travel"])
    XCTAssertEqual(
      EntryTagField.namesToSave(["Family"], draft: "family", options: options), ["Family"])
  }

  // MARK: Note

  func testAnUntouchedNoteResendsItsWebFormattingUnchanged() throws {
    let node = try JSONDecoder().decode(
      EntryRichText.Node.self,
      from: Data(
        #"{"type":"doc","content":[{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Tent"}]}]}]}]}"#
          .utf8))
    let rich = EntryRichText(version: 1, text: EntryRichText.plainText(node), document: node)
    let saved = entry(body: rich.text, richText: rich)
    let opening = EntryEditorNote.opening(saved)
    XCTAssertTrue(opening.hasWebOnlyFormatting)
    let untouched = EntryEditorNote.toSave(
      current: opening.note, opening: opening.note, original: saved)
    XCTAssertEqual(untouched.body, saved.body)
    XCTAssertEqual(untouched.richText, rich)

    let edited = EntryEditorNote.toSave(
      current: NSAttributedString(string: "Tent and stove"), opening: opening.note,
      original: saved)
    XCTAssertEqual(edited.body, "Tent and stove")
    XCTAssertNotEqual(edited.richText, rich)

    XCTAssertFalse(EntryEditorNote.opening(entry()).hasWebOnlyFormatting)
    let fresh = EntryEditorNote.toSave(
      current: NSAttributedString(string: "  Hello  "), opening: NSAttributedString(),
      original: nil)
    XCTAssertEqual(fresh.body.trimmed, "Hello")
  }
}
