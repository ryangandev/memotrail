import Foundation
@preconcurrency import Supabase

/// One `save_entry` call: creates an Entry when `expectedRevision` is nil, otherwise saves a new
/// version of it. Every one of the 15 parameters is always sent, so PostgREST resolves the one
/// function and a nil value means what Web's null means:
/// - `richText` nil clears the note's formatting;
/// - `location` nil clears the Location, so an untouched one is resent as the saved snapshot;
/// - `photoLocation` adds a saved photo's GPS position as the Location and needs an existing
///   Entry.
/// Validation mirrors Web `parseInboxReviewInput` (`apps/web/src/lib/data/inbox-review.ts`).
struct SaveEntryParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let expectedRevision: Int?
  let title: String?
  let body: String
  let richText: EntryRichText?
  let occurrence: EntryOccurrence
  let tagNames: [String]
  let location: EntryLocation?
  let photoLocation: PhotoLocationDraft?
  let marks: EntryMarks

  /// Trims and checks the input like Web, or throws `SaveEntryError.invalid` with Web's message.
  init(
    entryID: UUID, expectedRevision: Int?, title: String?, body: String,
    richText: EntryRichText?, occurrence: EntryOccurrence, tagNames: [String],
    location: EntryLocation?, photoLocation: PhotoLocationDraft? = nil, marks: EntryMarks
  ) throws {
    if let location, location.revision < 1 || !Self.validCoordinates(location) {
      throw SaveEntryError.invalid("Choose a valid Location or remove it from this Entry.")
    }
    if let photoLocation, !photoLocation.isValid {
      throw SaveEntryError.invalid(
        "Choose the photo's GPS position again, or remove it from this draft.")
    }
    let title = title?.trimmed ?? ""
    let body = body.trimmed
    if marks.isChapter && title.isEmpty {
      throw SaveEntryError.invalid("Give this Chapter a title.")
    }
    if title.isEmpty && body.isEmpty {
      throw SaveEntryError.invalid("Keep a title or note before saving.")
    }
    if let richText, !richText.isValid(expectedText: body) {
      throw SaveEntryError.invalid(
        "MemoTrail could not keep this note's formatting. Edit the note, then save again.")
    }
    guard let tagNames = EntryLimits.tagNames(tagNames) else {
      throw SaveEntryError.invalid(EntryLimits.tagCountMessage)
    }
    if title.count > EntryLimits.title {
      throw SaveEntryError.invalid("Keep the title under \(EntryLimits.title) characters.")
    }
    if body.count > EntryLimits.body {
      throw SaveEntryError.invalid("Keep the note under 50,000 characters.")
    }
    // A new Entry has no saved photos yet, so it cannot adopt one's GPS position.
    if let expectedRevision, expectedRevision < 1 {
      throw SaveEntryError.invalid("This Entry review is invalid.")
    }
    if expectedRevision == nil, photoLocation != nil {
      throw SaveEntryError.invalid("This Entry review is invalid.")
    }
    var occurrence = occurrence
    occurrence.label = occurrence.label?.trimmed.nonEmpty
    do {
      try occurrence.validate(span: marks.isChapter)
    } catch {
      throw SaveEntryError.invalid(
        error.localizedDescription.nonEmpty ?? "Choose a valid date.")
    }
    self.entryID = entryID
    self.expectedRevision = expectedRevision
    self.title = title.nonEmpty
    self.body = body
    self.richText = richText
    self.occurrence = occurrence
    self.tagNames = tagNames
    self.location = location
    self.photoLocation = photoLocation
    self.marks = marks
  }

  private static func validCoordinates(_ location: EntryLocation) -> Bool {
    switch (location.latitude, location.longitude) {
    case (nil, nil): true
    case (let latitude?, let longitude?):
      latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    default: false
    }
  }

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
    case title = "p_title"
    case body = "p_body"
    case richText = "p_body_rich"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case occurredTimezone = "p_occurred_timezone"
    case occurredLabel = "p_occurred_label"
    case datePrecision = "p_date_precision"
    case tagNames = "p_tag_names"
    case location = "p_primary_location"
    case photoLocation = "p_photo_location"
    case isChapter = "p_is_chapter"
    case isFirstTime = "p_is_first_time"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(entryID.uuidString.lowercased(), forKey: .entryID)
    try values.encode(expectedRevision, forKey: .expectedRevision)
    try values.encode(title, forKey: .title)
    try values.encode(body, forKey: .body)
    try values.encode(richText, forKey: .richText)
    try values.encode(occurrence.start.map(EntryTimestamp.string(from:)), forKey: .occurredStart)
    try values.encode(occurrence.end.map(EntryTimestamp.string(from:)), forKey: .occurredEnd)
    try values.encode(occurrence.timezone, forKey: .occurredTimezone)
    try values.encode(occurrence.label, forKey: .occurredLabel)
    try values.encode(occurrence.precision, forKey: .datePrecision)
    try values.encode(tagNames, forKey: .tagNames)
    try values.encode(location, forKey: .location)
    try values.encode(photoLocation, forKey: .photoLocation)
    try values.encode(marks.isChapter, forKey: .isChapter)
    try values.encode(marks.isFirstTime, forKey: .isFirstTime)
  }
}

/// The row `save_entry` returns.
struct SavedEntry: Decodable, Equatable, Sendable {
  let entryID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
  }
}

/// Why an Entry was not saved, in Web's words (`apps/web/src/app/inbox/actions.ts`).
enum SaveEntryError: LocalizedError, Equatable {
  /// The input was refused before it was sent.
  case invalid(String)
  /// Someone else changed the Entry, its photo, or its Location first, or a create could not be
  /// confirmed; the person refreshes before saving again.
  case conflict(String)
  case sessionExpired
  case failed

  static let savedMessage = "Changes saved."

  var errorDescription: String? {
    switch self {
    case .invalid(let message), .conflict(let message): message
    case .sessionExpired: "Your session expired. Sign in again before saving."
    case .failed: "MemoTrail could not save these changes. Try again."
    }
  }

  /// A refused `save_entry` call.
  static func classify(_ error: Error) -> SaveEntryError {
    if let error = error as? SaveEntryError { return error }
    guard let error = error as? PostgrestError else { return .failed }
    if error.code == "40001" {
      return .conflict(
        "The photo or Location changed. Close this editor, refresh, and confirm the latest version before saving."
      )
    }
    if error.code == "22023" && error.message == "chapter_requires_title" {
      return .invalid("Give this Chapter a title.")
    }
    return .failed
  }

  /// `save_entry` returned no row: a create may have landed before its answer was lost, and an
  /// edit lost to a newer version.
  static func unconfirmed(isCreate: Bool) -> SaveEntryError {
    .conflict(
      isCreate
        ? "MemoTrail could not confirm this Entry was added. Refresh to check before adding it again."
        : "This Entry changed on another device. Close it, refresh, and edit the latest version.")
  }
}
