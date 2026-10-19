import Foundation

/// The Entry the Item page shows, as `entry_detail(p_entry_id)` returns it, like Web
/// `apps/web/src/lib/data/entry-detail.ts`. It includes Entries in Trash, which carry
/// `deleted_at`. Unknown keys, such as `links`, are ignored.
struct EntryDetail: Decodable, Equatable, Identifiable, Sendable {
  struct Tag: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
  }

  struct Location: Decodable, Equatable, Hashable, Sendable {
    enum Relationship: String, Decodable, Sendable {
      case primary, photo
    }

    let locationID: UUID
    let relationship: Relationship
    let formattedAddress: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
      case relationship, latitude, longitude
      case locationID = "location_id"
      case formattedAddress = "formatted_address"
    }

    /// Web `locationDisplayLabel`: the address, else the coordinates.
    var label: String {
      EntryLocation.label(
        formattedAddress: formattedAddress, latitude: latitude, longitude: longitude)
    }
  }

  let id: UUID
  let title: String?
  let body: String
  let richText: EntryRichText?
  let subtype: EntrySubtype
  let isFirstTime: Bool
  let revision: Int
  let deletedAt: Date?
  let occurredStart: Date?
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let datePrecision: DatePrecision
  let tags: [Tag]
  let locations: [Location]

  init(
    id: UUID, title: String?, body: String, richText: EntryRichText? = nil,
    subtype: EntrySubtype = .entry, isFirstTime: Bool = false, revision: Int,
    deletedAt: Date? = nil, occurredStart: Date? = nil, occurredEnd: Date? = nil,
    occurredLabel: String? = nil, occurredTimezone: String? = nil,
    datePrecision: DatePrecision = .unknown, tags: [Tag] = [], locations: [Location] = []
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.richText = richText
    self.subtype = subtype
    self.isFirstTime = isFirstTime
    self.revision = revision
    self.deletedAt = deletedAt
    self.occurredStart = occurredStart
    self.occurredEnd = occurredEnd
    self.occurredLabel = occurredLabel
    self.occurredTimezone = occurredTimezone
    self.datePrecision = datePrecision
    self.tags = tags
    self.locations = locations
  }

  enum CodingKeys: String, CodingKey {
    case id, title, body, metadata, revision, tags, locations
    case subtype = "item_subtype"
    case isFirstTime = "is_first_time"
    case deletedAt = "deleted_at"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    richText = values.decodeEntryRichText(metadataKey: .metadata, body: body)
    subtype = EntrySubtype(stored: try values.decodeIfPresent(String.self, forKey: .subtype))
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    revision = try values.decode(Int.self, forKey: .revision)
    deletedAt = try values.decodeTimestamp(forKey: .deletedAt)
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    tags = try values.decodeIfPresent([Tag].self, forKey: .tags) ?? []
    locations = try values.decodeIfPresent([Location].self, forKey: .locations) ?? []
  }

  var marks: EntryMarks { EntryMarks(subtype: subtype, isFirstTime: isFirstTime) }

  var isInTrash: Bool { deletedAt != nil }

  var primaryLocation: Location? { locations.first { $0.relationship == .primary } }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryTitle`: the title, or the date when there is none.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// Web `entryDateAddsToTitle`: an untitled Entry is already headed by its date, so the Date
  /// fact shows only when it says more.
  var dateAddsToTitle: Bool {
    if title?.trimmed.nonEmpty != nil { return true }
    if occurredLabel?.trimmed.nonEmpty != nil || occurredStart == nil { return false }
    switch datePrecision {
    case .exact: return true
    case .day, .month, .year: return occurredEnd != nil
    case .range: return false
    default: return true
    }
  }

  /// Web `entryDateLabel`: the Date fact in en-US and the recorded zone.
  var dateLabel: String {
    if let label = occurredLabel?.trimmed.nonEmpty { return label }
    guard let occurredStart else { return "Unknown" }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone =
      EntryOccurrence.validTimezone(occurredTimezone).flatMap(TimeZone.init(identifier:)) ?? .gmt
    formatter.dateFormat =
      switch datePrecision {
      case .year: "yyyy"
      case .month: "MMM yyyy"
      case .exact: "MMM d, yyyy, h:mm a"
      default: "MMM d, yyyy"
      }
    let start = formatter.string(from: occurredStart)
    return occurredEnd.map { "\(start) to \(formatter.string(from: $0))" } ?? start
  }

  /// Web `chapterDateFacts`: the span a Chapter covers and how long that is. A Chapter without
  /// a calendar date has no duration.
  func chapterDateFacts(now: Date = Date()) -> (span: String, duration: String?) {
    (
      occurrence.spanLabel,
      occurredStart == nil ? nil : occurrence.durationLabel(now: now)
    )
  }
}
