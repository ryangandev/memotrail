import Foundation

/// The current version of an Entry the editor starts from, as `editable_entry(p_entry_id)`
/// returns it: the `entries` row plus `tag_names` and the full `primary_location` row. Trashed
/// Entries are not returned. Unknown keys are ignored.
struct EditableEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let richText: EntryRichText?
  let subtype: EntrySubtype
  let isFirstTime: Bool
  let revision: Int
  let occurredStart: Date?
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let datePrecision: DatePrecision
  let tagNames: [String]
  let primaryLocation: EntryLocation?
  let createdAt: Date?
  let updatedAt: Date?

  init(
    id: UUID, title: String?, body: String, richText: EntryRichText? = nil,
    subtype: EntrySubtype = .entry, isFirstTime: Bool = false, revision: Int,
    occurredStart: Date? = nil, occurredEnd: Date? = nil, occurredLabel: String? = nil,
    occurredTimezone: String? = nil, datePrecision: DatePrecision = .unknown,
    tagNames: [String] = [], primaryLocation: EntryLocation? = nil, createdAt: Date? = nil,
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.richText = richText
    self.subtype = subtype
    self.isFirstTime = isFirstTime
    self.revision = revision
    self.occurredStart = occurredStart
    self.occurredEnd = occurredEnd
    self.occurredLabel = occurredLabel
    self.occurredTimezone = occurredTimezone
    self.datePrecision = datePrecision
    self.tagNames = tagNames
    self.primaryLocation = primaryLocation
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id, title, body, metadata, revision
    case subtype = "item_subtype"
    case isFirstTime = "is_first_time"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case tagNames = "tag_names"
    case primaryLocation = "primary_location"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    richText = values.decodeEntryRichText(metadataKey: .metadata, body: body)
    subtype = EntrySubtype(
      stored: try values.decodeIfPresent(String.self, forKey: .subtype))
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    revision = try values.decode(Int.self, forKey: .revision)
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    primaryLocation = try values.decodeIfPresent(EntryLocation.self, forKey: .primaryLocation)
    createdAt = try values.decodeTimestamp(forKey: .createdAt)
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
  }

  var marks: EntryMarks { EntryMarks(subtype: subtype, isFirstTime: isFirstTime) }

  /// The stored date, in its recorded zone or `fallbackTimezone` when it has none.
  func occurrence(fallbackTimezone: String = "UTC") -> EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone, fallbackTimezone: fallbackTimezone)
  }

  /// Web `entryDisplayTitle`.
  var displayTitle: String { entryDisplayTitle(title, occurrence()) }
}
