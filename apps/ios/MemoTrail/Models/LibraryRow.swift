import Foundation

/// One `wiki_items_workspace` row: everything in Library, most recently changed first, like Web
/// `WikiItemSummary` in `apps/web/src/lib/data/wiki-items.ts`.
struct LibraryRow: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let subtype: EntrySubtype
  let isFirstTime: Bool
  /// The stored title, blank when the Entry has none.
  let title: String
  let excerpt: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let updatedAt: Date?
  let totalCount: Int

  init(
    id: UUID, subtype: EntrySubtype = .entry, isFirstTime: Bool = false, title: String = "",
    excerpt: String = "", occurredStart: Date? = nil, occurredEnd: Date? = nil,
    datePrecision: DatePrecision = .unknown, occurredLabel: String? = nil,
    occurredTimezone: String? = nil, updatedAt: Date? = nil, totalCount: Int = 1
  ) {
    self.id = id
    self.subtype = subtype
    self.isFirstTime = isFirstTime
    self.title = title
    self.excerpt = excerpt
    self.occurredStart = occurredStart
    self.occurredEnd = occurredEnd
    self.datePrecision = datePrecision
    self.occurredLabel = occurredLabel
    self.occurredTimezone = occurredTimezone
    self.updatedAt = updatedAt
    self.totalCount = totalCount
  }

  enum CodingKeys: String, CodingKey {
    case id = "canonical_item_id"
    case subtype = "item_subtype"
    case isFirstTime = "is_first_time"
    case title, excerpt
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case updatedAt = "updated_at"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    subtype = EntrySubtype(stored: try values.decodeIfPresent(String.self, forKey: .subtype))
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    excerpt = try values.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
    if let count = try? values.decode(Int.self, forKey: .totalCount) {
      totalCount = count
    } else {
      totalCount = Int(try values.decode(String.self, forKey: .totalCount)) ?? 0
    }
  }

  /// Every row opens its Item page, like Web `wikiEntryHref`.
  var link: ItemLink { ItemLink(entryID: id) }

  var marks: EntryMarks { EntryMarks(subtype: subtype, isFirstTime: isFirstTime) }

  var identityLabel: String { marks.identityLabel }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryDisplayTitle`.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// Web `wikiItemDateLabel`: nothing for an untitled row, which its date already names, or for
  /// a row without a date; a Chapter shows the span it covers.
  var dateLabel: String? {
    guard title.trimmed.nonEmpty != nil, occurredStart != nil || occurredLabel != nil else {
      return nil
    }
    return subtype == .chapter ? occurrence.spanLabel : occurrence.displayLabel
  }

  /// Web `EntryList` draws a meta line only for a Chapter or First Time badge or a date.
  var hasMeta: Bool { marks.isChapter || marks.isFirstTime || dateLabel != nil }

  /// What VoiceOver reads: the identity of a Chapter or First Time, the title, then the date.
  var accessibilityLabel: String {
    let identity = marks == .none ? nil : identityLabel
    return [identity, displayTitle, dateLabel].compactMap(\.self).joined(separator: ", ")
  }
}

/// `wiki_items_workspace` arguments.
struct LibraryPageParameters: Encodable, Equatable, Sendable {
  let query: String
  let itemKinds: [String]
  let itemSubtypes: [String]
  let limit: Int
  let offset: Int

  init(
    query: String = "", itemKinds: [String] = [], itemSubtypes: [String] = [], limit: Int,
    offset: Int
  ) {
    self.query = query
    self.itemKinds = itemKinds
    self.itemSubtypes = itemSubtypes
    self.limit = limit
    self.offset = offset
  }

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case itemKinds = "p_item_kinds"
    case itemSubtypes = "p_item_subtypes"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}
