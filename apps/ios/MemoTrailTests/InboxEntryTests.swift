import UIKit
import XCTest

@testable import MemoTrail

final class InboxEntryTests: XCTestCase {
  func testCaptureDraftRetainsUnfinishedDateAndLegacyExactDate() throws {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let owner = UUID()
    var draft = OccurrenceDraft(
      EntryOccurrence(
        precision: .year, start: nil, end: nil, label: nil, timezone: "Asia/Kathmandu"))
    draft.start = "20"
    XCTAssertTrue(store.save(title: "", body: "", occurrenceDraft: draft, ownerID: owner))
    XCTAssertEqual(store.load(ownerID: owner)?.captureOccurrence, draft)
    XCTAssertThrowsError(try draft.resolve())
    XCTAssertNil(store.load(ownerID: UUID()))
    let original = Date(timeIntervalSince1970: 1_500_000_000)
    XCTAssertTrue(store.save(title: "", body: "Legacy", occurredAt: original, ownerID: owner))
    XCTAssertEqual(try store.load(ownerID: owner)?.captureOccurrence?.resolve().start, original)
  }

  func testCaptureQueueAndServerPayloadRetainEveryPrecision() throws {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let owner = UUID()
    for precision in TimelineDatePrecision.allCases {
      var draft = OccurrenceDraft(
        EntryOccurrence(
          precision: precision, start: nil, end: nil, label: nil, timezone: "Asia/Kathmandu"))
      switch precision {
      case .exact: draft.start = "2017-07-08T12:34:56"
      case .day, .range: draft.start = "2017-07-08"
      case .month: draft.start = "2017-07"
      case .year: draft.start = "2017"
      case .age, .approximate: draft.label = "At age 17"
      case .unknown: break
      }
      if precision == .range { draft.end = "2018-08-09" }
      let occurrence = try draft.resolve()
      var queued = QueuedInboxEntry(
        id: UUID(), title: nil, body: "Memory", occurredAt: Date(), occurredTimezone: "UTC",
        queuedAt: Date())
      queued.occurrence = occurrence
      XCTAssertNotNil(store.enqueue(queued, ownerID: owner))
      let restored = try XCTUnwrap(store.load(ownerID: owner).first { $0.id == queued.id })
      XCTAssertEqual(restored.effectiveOccurrence, occurrence)
      XCTAssertEqual(restored.presentedEntry.datePrecision, precision)
      XCTAssertEqual(restored.presentedEntry.occurredStart, occurrence.start)
      let payload = InboxEntryInsert(
        id: queued.id, ownerID: owner, title: nil, body: "Memory", occurredStart: occurrence.start,
        occurredTimezone: occurrence.timezone, datePrecision: precision.rawValue,
        occurredEnd: occurrence.end, occurredLabel: occurrence.label, clientID: "ios:\(queued.id)")
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String: Any])
      XCTAssertEqual(json["date_precision"] as? String, precision.rawValue)
      XCTAssertEqual(json["occurred_timezone"] as? String, "Asia/Kathmandu")
      XCTAssertEqual(json["item_kind"] as? String, "entry")
      XCTAssertEqual(json["item_subtype"] as? String, "entry")
      if occurrence.start == nil { XCTAssertNil(json["occurred_start"]) }
      XCTAssertEqual(json["occurred_label"] as? String, occurrence.label)
    }
  }

  @MainActor
  func testCapturedNoteTrimsWhitespaceAndKeepsWebFormatting() throws {
    let bold = UIFont.boldSystemFont(ofSize: 17)
    let note = NSMutableAttributedString(string: "\n  ")
    note.append(NSAttributedString(string: "Low tide", attributes: [.font: bold]))
    note.append(NSAttributedString(string: " and tea\nSecond line\n\n"))
    let captured = EntryEmphasisContent.capture(note)
    XCTAssertEqual(captured.body, "Low tide and tea\nSecond line")
    let rich = try XCTUnwrap(captured.rich)
    XCTAssertTrue(rich.isValid(expectedText: captured.body))
    let first = try XCTUnwrap(rich.document.content?.first?.content?.first)
    XCTAssertEqual(first.text, "Low tide")
    XCTAssertEqual(first.marks, [EntryEmphasisContent.Mark(type: "bold")])
    // Web's validator accepts the same document as Entry metadata.
    XCTAssertEqual(EntryRichText(rich)?.isValid(expectedText: captured.body), true)
    XCTAssertEqual(EntryEmphasisContent.capture(NSAttributedString(string: " \n ")).body, "")
    XCTAssertNil(EntryEmphasisContent.capture(NSAttributedString(string: " \n ")).rich)
  }

  @MainActor
  func testDraftAndQueueKeepFormattingOnlyForTheirExactNote() throws {
    let owner = UUID()
    let drafts = InboxDraftStore(defaults: makeDefaults())
    let note = NSAttributedString(
      string: "Kept", attributes: [.font: UIFont.italicSystemFont(ofSize: 17)])
    let rich = EntryEmphasisContent(attributedText: note)
    XCTAssertTrue(drafts.save(title: "", body: "Kept", bodyRich: rich, ownerID: owner))
    let draft = try XCTUnwrap(drafts.load(ownerID: owner))
    XCTAssertEqual(draft.bodyRich, rich)
    XCTAssertTrue(
      EmphasisStyle.italic.isApplied(to: draft.note.attributes(at: 0, effectiveRange: nil)))
    XCTAssertTrue(drafts.save(title: "", body: "Changed", bodyRich: rich, ownerID: owner))
    XCTAssertNil(drafts.load(ownerID: owner)?.bodyRich)
    XCTAssertEqual(drafts.load(ownerID: owner)?.note.string, "Changed")

    let queue = InboxQueueStore(defaults: makeDefaults())
    var entry = QueuedInboxEntry(
      id: UUID(), title: nil, body: "Kept", occurredAt: Date(), occurredTimezone: "UTC",
      queuedAt: Date())
    entry.bodyRich = rich
    XCTAssertTrue(entry.isValid)
    XCTAssertEqual(queue.enqueue(entry, ownerID: owner)?.first?.bodyRich, rich)
    var mismatched = entry
    mismatched.bodyRich = EntryEmphasisContent(attributedText: NSAttributedString(string: "Other"))
    XCTAssertFalse(mismatched.isValid)

    // Drafts and queued Entries saved before formatting existed still load.
    let legacy = Data(
      #"{"id":"95000000-0000-4000-8000-000000000009","title":null,"body":"Old","occurredAt":null,"occurredTimezone":"UTC","queuedAt":0}"#
        .utf8)
    XCTAssertNil(try JSONDecoder().decode(QueuedInboxEntry.self, from: legacy).bodyRich)
  }

  func testCaptureInsertCarriesBodyRichMetadataLikeWeb() throws {
    func json(_ payload: InboxEntryInsert) throws -> [String: Any] {
      try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    }
    let rich = try JSONDecoder().decode(
      EntryEmphasisContent.self,
      from: Data(
        #"{"version":1,"text":"Hi","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hi","marks":[{"type":"bold"}]}]}]}}"#
          .utf8))
    let plain = InboxEntryInsert(
      id: UUID(), ownerID: UUID(), title: nil, body: "Hi", occurredStart: nil,
      occurredTimezone: "UTC", clientID: "ios:test")
    XCTAssertEqual((try json(plain)["metadata"] as? [String: Any])?.isEmpty, true)
    var formatted = plain
    formatted.metadata = [EntryRichText.metadataKey: rich]
    let metadata = try XCTUnwrap(try json(formatted)["metadata"] as? [String: Any])
    let bodyRich = try XCTUnwrap(metadata["body_rich"] as? [String: Any])
    XCTAssertEqual(bodyRich["text"] as? String, "Hi")
    XCTAssertEqual(bodyRich["version"] as? Int, 1)
  }

  func testCurrentEditorContextPreservesOrganizationStatusAndRawTimes() throws {
    let raw = "2017-07-08T12:34:56.123456+00:00"
    let data = Data(
      """
      {"id":"95000000-0000-4000-8000-000000000001","title":"Memory","body":"Original",
      "item_kind":"entry","item_subtype":"entry","inbox_status":"organized","revision":2,
      "created_at":"2017-07-08T12:34:56Z","occurred_start":"\(raw)","occurred_end":null,
      "date_precision":"exact","occurred_timezone":"UTC","collection_names":["Active"],"tag_names":["memory"]}
      """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let parser = ISO8601DateFormatter()
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = parser.date(from: value) { return date }
      parser.formatOptions = [.withInternetDateTime]
      return try XCTUnwrap(parser.date(from: value))
    }
    let entry = try decoder.decode(InboxEntry.self, from: data)
    XCTAssertEqual(entry.inboxStatus, "organized")
    XCTAssertEqual(entry.itemKind, .entry)
    XCTAssertEqual(entry.itemSubtype, "entry")
    XCTAssertEqual(entry.collectionNames, ["Active"])
    XCTAssertEqual(entry.tagNames, ["memory"])
    let organized = entry.withOrganization(collectionNames: ["Other"], tagNames: [])
    XCTAssertEqual(organized.inboxStatus, "organized")
    XCTAssertEqual(organized.occurredStartRaw, raw)
    let parameters = ReviewEntryParameters(
      entryID: entry.id, expectedRevision: 2, title: entry.title, body: "Edited",
      itemKind: .entry, itemSubtype: "entry", occurredStart: entry.occurredStart,
      occurredTimezone: "UTC",
      collectionNames: [], tagNames: [], markDone: false, occurredStartRaw: entry.occurredStartRaw)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
    XCTAssertEqual(json["p_occurred_start"] as? String, raw)
    XCTAssertFalse(json["p_mark_done"] as? Bool ?? true)
    XCTAssertTrue(json["p_occurred_end"] is NSNull)
  }

  func testEntryDecodesCanonicalWikiClassification() throws {
    let data = Data(
      """
      {"id":"95000000-0000-4000-8000-000000000002","title":"The long way home",\
      "body":"A story worth keeping.","item_kind":"entry",\
      "item_subtype":"entry","inbox_status":"organized","revision":3,\
      "created_at":"2026-09-16T12:00:00Z","occurred_start":null,"occurred_end":null,\
      "date_precision":"unknown","occurred_timezone":"UTC"}
      """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let entry = try decoder.decode(InboxEntry.self, from: data)

    XCTAssertEqual(entry.itemKind, .entry)
    XCTAssertEqual(entry.itemSubtype, "entry")
  }

  func testCurrentKindsRejectRemovedStructuralClassifications() {
    XCTAssertEqual(WikiItemKind.allCases.map(\.rawValue), ["entry", "entity", "goal"])
    for legacy in ["capture", "writing", "event", "story"] {
      XCTAssertNil(WikiItemKind(rawValue: legacy))
    }
    XCTAssertEqual(WikiItemKind.entry.displayName(subtype: "period"), "Period")
    XCTAssertEqual(WikiItemKind.entry.displayName(subtype: "first_time"), "First Time")
  }

  func testPhotoGPSAdoptionRejectsReusableLocationsAndInvalidCoordinates() throws {
    let valid = PhotoPlaceDraft(
      attachmentId: UUID(), name: "Photo Location", latitude: -90, longitude: 180)
    XCTAssertNoThrow(try valid.validate())
    var invalid = valid
    invalid.kind = "existing"
    invalid.placeId = UUID()
    invalid.revision = 1
    XCTAssertThrowsError(try invalid.validate())
    invalid = valid
    invalid.latitude = .infinity
    XCTAssertThrowsError(try invalid.validate())
    invalid = valid
    invalid.name = " "
    XCTAssertThrowsError(try invalid.validate())
  }

  func testOccurrencePreservesLaterRepeatedHourAndFractionalSeconds() throws {
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T09:30:27Z"))
      .addingTimeInterval(0.123)
    let value = EntryOccurrence(
      precision: .exact, start: date, end: nil, label: nil, timezone: "America/Los_Angeles")
    let draft = OccurrenceDraft(value)
    XCTAssertEqual(draft.start, "2026-11-01T01:30:27")
    XCTAssertEqual(try draft.resolve(original: value), value)
    XCTAssertEqual(
      OccurrenceDraft.wallTimeToDate("2026-11-01T01:30:27", timezone: value.timezone),
      ISO8601DateFormatter().date(from: "2026-11-01T08:30:27Z"))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2026-03-08T02:30", timezone: value.timezone))
    XCTAssertNil(OccurrenceDraft.wallTimeToDate("2025-02-29T12:00", timezone: "UTC"))
    XCTAssertEqual(
      OccurrenceDraft.wallTimeToDate("2026-09-12T12:00", timezone: "Asia/Kathmandu"),
      ISO8601DateFormatter().date(from: "2026-09-12T06:15:00Z"))
  }

  func testOccurrencePartialDatesUnknownAgeAndAIAdoption() throws {
    for (precision, input, expected) in [
      (TimelineDatePrecision.year, "2017", "2017"), (.month, "2017-07", "Jul 2017"),
      (.day, "2017-07-08", "Jul 8, 2017"),
    ] {
      var draft = OccurrenceDraft(
        EntryOccurrence(
          precision: precision, start: nil, end: nil, label: nil, timezone: "Pacific/Auckland"))
      draft.start = input
      let resolved = try draft.resolve()
      XCTAssertEqual(resolved.displayLabel, expected)
      XCTAssertEqual(OccurrenceDraft(resolved).start, input)
    }
    let unknown = EntryOccurrence(
      precision: .unknown, start: nil, end: nil, label: nil, timezone: "UTC")
    XCTAssertEqual(unknown.displayLabel, "Date unknown")
    var draft = OccurrenceDraft(unknown)
    draft.useDateSuggestion("17岁，第一次去日本")
    XCTAssertEqual(try draft.resolve().precision, .approximate)
    XCTAssertNil(try draft.resolve().start)
    draft.precision = .age
    XCTAssertEqual(try draft.resolve().displayLabel, "17岁，第一次去日本")
    draft.label = ""
    XCTAssertThrowsError(try draft.resolve())
  }

  func testOccurrenceReviewParametersEncodeNullCalendarDates() throws {
    let parameters = ReviewEntryParameters(
      entryID: UUID(), expectedRevision: 1, title: nil, body: "Memory", itemKind: .entry,
      itemSubtype: "entry",
      occurredStart: nil, occurredTimezone: "UTC", collectionNames: [], tagNames: [],
      markDone: false, datePrecision: .age, occurredEnd: nil, occurredLabel: "At age 17")
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
    XCTAssertTrue(json["p_occurred_start"] is NSNull)
    XCTAssertTrue(json["p_occurred_end"] is NSNull)
    XCTAssertEqual(json["p_date_precision"] as? String, "age")
    XCTAssertEqual(json["p_occurred_label"] as? String, "At age 17")
  }

  func testBodyOnlyCaptureIsTrimmedAndAccepted() throws {
    let capture = try InboxCapture.validate(
      title: "  ",
      body: "  A thought worth keeping.  "
    )

    XCTAssertNil(capture.title)
    XCTAssertEqual(capture.body, "A thought worth keeping.")
  }

  func testTitleOnlyCaptureIsAccepted() throws {
    let capture = try InboxCapture.validate(
      title: " First time skiing ",
      body: "  "
    )

    XCTAssertEqual(capture.title, "First time skiing")
    XCTAssertEqual(capture.body, "")
  }

  func testEmptyCaptureIsRejected() {
    XCTAssertThrowsError(
      try InboxCapture.validate(title: " \n ", body: "  ")
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .empty)
    }
  }

  func testPhotoOnlyCaptureIsAccepted() throws {
    let capture = try InboxCapture.validate(
      title: "",
      body: "",
      hasAttachments: true
    )

    XCTAssertNil(capture.title)
    XCTAssertEqual(capture.body, "")
  }

  func testOversizedTitleAndBodyAreRejected() {
    XCTAssertThrowsError(
      try InboxCapture.validate(
        title: String(repeating: "a", count: InboxCapture.titleLimit + 1),
        body: ""
      )
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .titleTooLong)
    }

    XCTAssertThrowsError(
      try InboxCapture.validate(
        title: "",
        body: String(repeating: "a", count: InboxCapture.bodyLimit + 1)
      )
    ) { error in
      XCTAssertEqual(error as? InboxCaptureError, .bodyTooLong)
    }
  }

  func testBodyOnlyEntryUsesFirstLineAsItsDisplayTitle() {
    let entry = InboxEntry(
      id: UUID(),
      title: nil,
      body: "Why do people keep learning?\nBecause our model of the world keeps changing.",
      createdAt: Date(timeIntervalSince1970: 0),
      occurredStart: nil
    )

    XCTAssertEqual(entry.displayTitle, "Why do people keep learning?")
    XCTAssertEqual(
      entry.displayExcerpt,
      "Because our model of the world keeps changing."
    )
  }

  func testTitledEntryKeepsItsBodyAsTheExcerpt() {
    let entry = InboxEntry(
      id: UUID(),
      title: "How aligners move teeth",
      body: "Small forces trigger bone remodeling.",
      createdAt: Date(timeIntervalSince1970: 0),
      occurredStart: nil
    )

    XCTAssertEqual(entry.displayTitle, "How aligners move teeth")
    XCTAssertEqual(entry.displayExcerpt, "Small forces trigger bone remodeling.")
  }

  func testReviewAcceptsEditableContentTypeAndOccurrence() throws {
    let occurredAt = Date(timeIntervalSince1970: 1_788_278_400)
    let input = try InboxReviewInput.validate(
      entryID: UUID(),
      revision: 2,
      title: "  First time skiing  ",
      body: "  A cold and brilliant day.  ",
      collectionNames: [" Travel ", "travel", "First Times"],
      itemKind: .entry,
      itemSubtype: "entry",
      occurredAt: occurredAt,
      occurredTimezone: "America/Los_Angeles",
      tagNames: [" Skiing ", "skiing", "snow"]
    )

    XCTAssertEqual(input.title, "First time skiing")
    XCTAssertEqual(input.body, "A cold and brilliant day.")
    XCTAssertEqual(input.itemKind, .entry)
    XCTAssertEqual(input.itemSubtype, "entry")
    XCTAssertEqual(input.collectionNames, ["Travel", "First Times"])
    XCTAssertEqual(input.tagNames, ["Skiing", "snow"])
    XCTAssertEqual(input.occurredAt, occurredAt)
    XCTAssertEqual(input.revision, 2)
  }

  func testReviewRejectsSpecializedFirstTimeIdentity() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: " ",
        body: "I tried something new.",
        collectionNames: [],
        itemKind: .entry,
        itemSubtype: "first_time",
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidClassification)
    }
  }

  func testReviewRejectsIncompatibleKindAndSubtype() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A chapter",
        body: "A longer story.",
        collectionNames: [],
        itemKind: .entity,
        itemSubtype: "home",
        occurredAt: nil,
        occurredTimezone: "UTC",
        tagNames: [],
        datePrecision: .unknown
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidClassification)
    }
  }

  func testReviewRejectsInvalidRevisionAndTimezone() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 0,
        title: "A thought",
        body: "",
        collectionNames: [],
        itemKind: .entry,
        itemSubtype: "entry",
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidRevision)
    }

    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [],
        itemKind: .entry,
        itemSubtype: "entry",
        occurredAt: Date(),
        occurredTimezone: "",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidTimezone)
    }
  }

  func testReviewRejectsInvalidOrganizationNames() {
    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [""],
        itemKind: .entry,
        itemSubtype: "entry",
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: []
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidCollections)
    }

    XCTAssertThrowsError(
      try InboxReviewInput.validate(
        entryID: UUID(),
        revision: 1,
        title: "A thought",
        body: "",
        collectionNames: [],
        itemKind: .entry,
        itemSubtype: "entry",
        occurredAt: Date(),
        occurredTimezone: "UTC",
        tagNames: [String(repeating: "t", count: 61)]
      )
    ) { error in
      XCTAssertEqual(error as? InboxReviewError, .invalidTags)
    }
  }

  func testReviewRPCParametersEncodeANilTitleExplicitly() throws {
    let parameters = ReviewEntryParameters(
      entryID: UUID(),
      expectedRevision: 1,
      title: nil,
      body: "A body-only Entry",
      itemKind: .entry,
      itemSubtype: "entry",
      occurredStart: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "UTC",
      collectionNames: [],
      tagNames: [],
      markDone: false
    )
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json.keys.contains("p_title"))
    XCTAssertTrue(json["p_title"] is NSNull)
    XCTAssertEqual(json["p_item_kind"] as? String, "entry")
    XCTAssertEqual(json["p_item_subtype"] as? String, "entry")
  }

  func testDraftStoreRestoresContentForOnlyItsOwner() {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let firstOwner = UUID()
    let secondOwner = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_783_088_200)

    XCTAssertTrue(
      store.save(
        title: " Draft title ",
        body: "  Keep my spacing.\n",
        occurredAt: occurredAt,
        ownerID: firstOwner
      )
    )
    XCTAssertEqual(store.load(ownerID: firstOwner)?.title, " Draft title ")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.body, "  Keep my spacing.\n")
    XCTAssertEqual(store.load(ownerID: firstOwner)?.occurredAt, occurredAt)
    XCTAssertNil(store.load(ownerID: secondOwner))
  }

  func testDraftStoreLoadsLegacyTextDraftWithoutInventingADate() throws {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()
    let legacyDraft = LegacyInboxDraft(
      title: "",
      body: "An earlier draft",
      updatedAt: Date(timeIntervalSince1970: 1_788_278_400)
    )
    defaults.set(
      try JSONEncoder().encode(legacyDraft),
      forKey: InboxDraftStore.storageKey(ownerID: ownerID)
    )

    let loadedDraft = try XCTUnwrap(store.load(ownerID: ownerID))
    XCTAssertEqual(loadedDraft.body, "An earlier draft")
    XCTAssertNil(loadedDraft.occurredAt)
  }

  func testDraftStoreClearsEmptyAndAcceptedDrafts() {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()

    store.save(title: "", body: "Keep me", ownerID: ownerID)
    store.clear(ownerID: ownerID)
    XCTAssertNil(store.load(ownerID: ownerID))

    XCTAssertFalse(store.save(title: "", body: "", ownerID: ownerID))
    XCTAssertNil(store.load(ownerID: ownerID))
  }

  func testDraftStoreDiscardsCorruptedOrOversizedData() throws {
    let defaults = makeDefaults()
    let store = InboxDraftStore(defaults: defaults)
    let ownerID = UUID()
    let key = InboxDraftStore.storageKey(ownerID: ownerID)

    defaults.set(Data("not json".utf8), forKey: key)
    XCTAssertNil(store.load(ownerID: ownerID))

    let oversizedDraft = InboxDraft(
      title: String(repeating: "t", count: InboxCapture.titleLimit + 1),
      body: "",
      updatedAt: Date()
    )
    defaults.set(try JSONEncoder().encode(oversizedDraft), forKey: key)
    XCTAssertNil(store.load(ownerID: ownerID))
  }

  func testQueueStoreKeepsPendingEntriesIsolatedByOwner() {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let firstOwner = UUID()
    let secondOwner = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: firstOwner), [entry])
    XCTAssertEqual(store.load(ownerID: firstOwner), [entry])
    XCTAssertTrue(store.load(ownerID: secondOwner).isEmpty)
  }

  func testQueueStoreDoesNotDuplicateAStableEntryID() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let entry = makeQueuedEntry()

    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
    XCTAssertEqual(store.enqueue(entry, ownerID: ownerID), [entry])
  }

  func testQueueStoreRemovesOnlyTheConfirmedEntry() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let first = makeQueuedEntry()
    let second = makeQueuedEntry(
      id: UUID(),
      title: "Second thought"
    )

    _ = store.enqueue(first, ownerID: ownerID)
    _ = store.enqueue(second, ownerID: ownerID)

    XCTAssertEqual(store.remove(entryID: first.id, ownerID: ownerID), [second])
  }

  func testQueueStoreDiscardsCorruptedObsoleteAndDuplicateData() throws {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let ownerID = UUID()
    let key = InboxQueueStore.storageKey(ownerID: ownerID)

    defaults.set(Data("not json".utf8), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)

    let entry = makeQueuedEntry()
    let duplicateQueue = TestStoredInboxQueue(version: 1, entries: [entry, entry])
    defaults.set(try JSONEncoder().encode(duplicateQueue), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)

    let obsoleteQueue = TestStoredInboxQueue(version: 99, entries: [entry])
    defaults.set(try JSONEncoder().encode(obsoleteQueue), forKey: key)
    XCTAssertTrue(store.load(ownerID: ownerID).isEmpty)
  }

  func testQueueStoreLoadsVersionOneEntriesWithoutInventingAttachments() throws {
    let defaults = makeDefaults()
    let store = InboxQueueStore(defaults: defaults)
    let ownerID = UUID()
    let legacyEntry = LegacyQueuedInboxEntry(
      id: UUID(),
      title: nil,
      body: "An earlier queued thought",
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400)
    )
    let queue = LegacyStoredInboxQueue(version: 1, entries: [legacyEntry])
    defaults.set(
      try JSONEncoder().encode(queue),
      forKey: InboxQueueStore.storageKey(ownerID: ownerID)
    )

    let loaded = try XCTUnwrap(store.load(ownerID: ownerID).first)
    XCTAssertEqual(loaded.id, legacyEntry.id)
    XCTAssertTrue(loaded.attachments.isEmpty)
  }

  func testQueueAcceptsPhotoOnlyEntryAndRejectsDuplicatePhotos() throws {
    let attachment = makeQueuedAttachment()
    let photoOnly = makeQueuedEntry(
      body: "",
      attachments: [attachment]
    )

    XCTAssertTrue(photoOnly.isValid)
    XCTAssertFalse(
      makeQueuedEntry(body: "", attachments: [attachment, attachment]).isValid
    )
  }

  func testQueueStoreRejectsInvalidAndOverCapacityEntries() {
    let store = InboxQueueStore(defaults: makeDefaults())
    let ownerID = UUID()
    let invalidEntry = makeQueuedEntry(body: "  not normalized  ")

    XCTAssertNil(store.enqueue(invalidEntry, ownerID: ownerID))

    for index in 0..<InboxQueueStore.maximumEntryCount {
      XCTAssertNotNil(
        store.enqueue(
          makeQueuedEntry(id: UUID(), title: "Entry \(index)"),
          ownerID: ownerID
        )
      )
    }

    XCTAssertNil(
      store.enqueue(makeQueuedEntry(id: UUID()), ownerID: ownerID)
    )
  }

  func testPhotoStorePersistsPrivateDraftsByOwnerAndRemovesThem() throws {
    let rootURL = makePhotoRoot()
    let store = InboxPhotoStore(rootURL: rootURL)
    let ownerID = UUID()
    let otherOwnerID = UUID()
    let draft = try makePhotoDraft()

    try store.save(draft, ownerID: ownerID)

    XCTAssertEqual(try store.load(ownerID: ownerID), [draft])
    XCTAssertTrue(try store.load(ownerID: otherOwnerID).isEmpty)

    try store.remove(photoID: draft.id, ownerID: ownerID)
    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testPhotoStoreIgnoresMalformedMetadata() throws {
    let rootURL = makePhotoRoot()
    let store = InboxPhotoStore(rootURL: rootURL)
    let ownerID = UUID()
    let ownerURL = rootURL.appending(path: ownerID.uuidString.lowercased())
    try FileManager.default.createDirectory(
      at: ownerURL,
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(
      to: ownerURL.appending(path: "broken.json")
    )

    XCTAssertTrue(try store.load(ownerID: ownerID).isEmpty)
  }

  func testUniversalAttachmentParametersEncodeQueuedMetadata() throws {
    let entryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let attachment = makeQueuedAttachment()
    let parameters = RegisterEntryAttachmentParameters(
      entryID: entryID,
      attachment: attachment,
      objectPath: attachment.objectPath(ownerID: UUID(), entryID: entryID)
    )
    let data = try JSONEncoder().encode(parameters)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["p_attachment_id"] as? String, attachment.id.uuidString)
    XCTAssertEqual(json["p_mime_type"] as? String, "image/png")
    XCTAssertEqual(json["p_byte_size"] as? Int, 8)
    XCTAssertTrue(json["p_original_filename"] is NSNull)
  }

  private func makeQueuedEntry(
    id: UUID = UUID(uuidString: "F4D2DF16-A506-4BE6-A63E-B7B18AFE3468")!,
    title: String? = nil,
    body: String = "A thought worth keeping.",
    attachments: [QueuedInboxAttachment] = []
  ) -> QueuedInboxEntry {
    QueuedInboxEntry(
      id: id,
      title: title,
      body: body,
      occurredAt: Date(timeIntervalSince1970: 1_788_278_400),
      occurredTimezone: "America/Los_Angeles",
      queuedAt: Date(timeIntervalSince1970: 1_788_278_400),
      attachments: attachments
    )
  }

  private func makeQueuedAttachment() -> QueuedInboxAttachment {
    QueuedInboxAttachment(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      mimeType: .png,
      originalFilename: nil,
      byteSize: 8,
      pixelWidth: 12,
      pixelHeight: 8
    )
  }

  private func makePhotoDraft() throws -> FirstTimePhotoDraft {
    try FirstTimePhotoDraft.validate(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      mimeType: .png,
      originalFilename: nil,
      pixelWidth: 12,
      pixelHeight: 8
    )
  }

  private func makePhotoRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "InboxEntryTests.\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  func testInboxEntryKeepsOnlyBodyRichThatMatchesTheNote() throws {
    func entry(body: String, metadata: String) throws -> InboxEntry {
      let data = Data(
        """
        {"id":"95000000-0000-4000-8000-000000000003","title":null,"body":"\(body)",\
        "metadata":\(metadata),"item_kind":"entry","item_subtype":"entry",\
        "inbox_status":"unreviewed","revision":1,"created_at":"2026-09-16T12:00:00Z",\
        "occurred_start":null,"date_precision":"unknown","occurred_timezone":"UTC"}
        """.utf8)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(InboxEntry.self, from: data)
    }
    let document = """
      {"source":"web","body_rich":{"version":1,"text":"Harbor lights","document":{"type":"doc",\
      "content":[{"type":"paragraph","content":[{"type":"text","text":"Harbor",\
      "marks":[{"type":"bold"}]},{"type":"text","text":" lights"}]}]}}}
      """

    let formatted = try entry(body: "Harbor lights", metadata: document)
    XCTAssertEqual(formatted.bodyRich?.text, "Harbor lights")
    XCTAssertEqual(
      formatted.withOrganization(collectionNames: [], tagNames: []).bodyRich,
      formatted.bodyRich)
    XCTAssertNil(try entry(body: "Harbor lights, edited", metadata: document).bodyRich)
    XCTAssertNil(try entry(body: "Harbor lights", metadata: "{}").bodyRich)
    XCTAssertNil(try entry(body: "Harbor lights", metadata: "null").bodyRich)
  }

  @MainActor
  func testReviewEditorKeepsEmphasisButNotWebOnlyStructure() throws {
    let note = NSMutableAttributedString(
      string: "Harbor", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
    note.append(
      NSAttributedString(string: " lights", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
    let emphasis = EntryEmphasisContent(attributedText: note)
    let rich = try XCTUnwrap(EntryRichText(emphasis))
    XCTAssertTrue(rich.isValid(expectedText: "Harbor lights"))
    XCTAssertEqual(EntryEmphasisContent(rich), emphasis)

    let list = try XCTUnwrap(GallerySamples.richText)
    XCTAssertTrue(list.isValid())
    XCTAssertNil(EntryEmphasisContent(list))
  }

  func testReviewRejectsEmptyNotesAndMismatchedFormattingLikeWeb() throws {
    func validate(title: String, body: String, rich: EntryRichText? = nil) throws {
      _ = try InboxReviewInput.validate(
        entryID: UUID(), revision: 1, title: title, body: body, bodyRich: rich,
        collectionNames: [], itemKind: .entry, itemSubtype: "entry", occurredAt: nil,
        occurredTimezone: "UTC", tagNames: [], datePrecision: .unknown)
    }
    XCTAssertThrowsError(try validate(title: " ", body: " ")) { error in
      XCTAssertEqual(error as? InboxReviewError, .empty)
      XCTAssertEqual(error.localizedDescription, "Keep a title or note before saving.")
    }
    let rich = try JSONDecoder().decode(
      EntryRichText.self,
      from: Data(
        """
        {"version":1,"text":"Harbor lights","document":{"type":"doc","content":[\
        {"type":"paragraph","content":[{"type":"text","text":"Harbor lights"}]}]}}
        """.utf8))
    XCTAssertNoThrow(try validate(title: "", body: "  Harbor lights ", rich: rich))
    XCTAssertThrowsError(try validate(title: "", body: "Harbor lights tonight", rich: rich)) {
      XCTAssertEqual($0 as? InboxReviewError, .invalidRichText)
    }
  }

  func testReviewParametersSendBodyRichOrClearIt() throws {
    var parameters = ReviewEntryParameters(
      entryID: UUID(), expectedRevision: 1, title: nil, body: "Harbor lights",
      itemKind: .entry, itemSubtype: "entry", occurredStart: nil, occurredTimezone: "UTC",
      collectionNames: [], tagNames: [], markDone: true, datePrecision: .unknown)
    func json() throws -> [String: Any] {
      try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
    }
    XCTAssertTrue(try json()["p_body_rich"] is NSNull)
    parameters.bodyRich = try JSONDecoder().decode(
      EntryRichText.self,
      from: Data(
        """
        {"version":1,"text":"Harbor lights","document":{"type":"doc","content":[\
        {"type":"paragraph","content":[{"type":"text","text":"Harbor lights"}]}]}}
        """.utf8))
    let rich = try XCTUnwrap(try json()["p_body_rich"] as? [String: Any])
    XCTAssertEqual(rich["text"] as? String, "Harbor lights")
    XCTAssertEqual(rich["version"] as? Int, 1)
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "InboxEntryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
    return defaults
  }
}

private struct TestStoredInboxQueue: Encodable {
  let version: Int
  let entries: [QueuedInboxEntry]
}

private struct LegacyStoredInboxQueue: Encodable {
  let version: Int
  let entries: [LegacyQueuedInboxEntry]
}

private struct LegacyQueuedInboxEntry: Encodable {
  let id: UUID
  let title: String?
  let body: String
  let occurredAt: Date
  let occurredTimezone: String
  let queuedAt: Date
}

private struct LegacyInboxDraft: Encodable {
  let title: String
  let body: String
  let updatedAt: Date
}
