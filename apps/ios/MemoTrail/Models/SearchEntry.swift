import Foundation

/// One `search_wiki_items` result, like Web `SearchEntry` in `apps/web/src/lib/data/search.ts`.
/// iOS searches by keyword only, so the semantic columns are ignored.
struct SearchEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let subtype: EntrySubtype
  let isFirstTime: Bool
  let revision: Int?
  let occurredAt: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let updatedAt: Date?
  let tagNames: [String]
  let matchReasons: [String]
  let totalCount: Int
  /// The note's Web formatting, loaded separately from `metadata.body_rich`.
  var bodyRich: EntryRichText?

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title, body, revision
    case subtype = "item_subtype"
    case isFirstTime = "is_first_time"
    case occurredAt = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case updatedAt = "updated_at"
    case tagNames = "tag_names"
    case matchReasons = "match_reasons"
    case totalCount = "total_count"
  }

  init(
    id: UUID, title: String?, body: String, subtype: EntrySubtype = .entry,
    isFirstTime: Bool = false, revision: Int? = 1, occurredAt: Date? = nil,
    occurredEnd: Date? = nil, datePrecision: DatePrecision = .unknown,
    occurredLabel: String? = nil, occurredTimezone: String? = nil, updatedAt: Date? = nil,
    tagNames: [String] = [], matchReasons: [String] = [], totalCount: Int = 1,
    bodyRich: EntryRichText? = nil
  ) {
    self.id = id
    self.title = title?.trimmed.nonEmpty
    self.body = body
    self.subtype = subtype
    self.isFirstTime = isFirstTime
    self.revision = revision
    self.occurredAt = occurredAt
    self.occurredEnd = occurredEnd
    self.datePrecision = datePrecision
    self.occurredLabel = occurredLabel?.trimmed.nonEmpty
    self.occurredTimezone = occurredTimezone?.trimmed.nonEmpty
    self.updatedAt = updatedAt
    self.tagNames = tagNames
    self.matchReasons = matchReasons
    self.totalCount = totalCount
    self.bodyRich = bodyRich
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)?.trimmed.nonEmpty
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    subtype = EntrySubtype(stored: try values.decodeIfPresent(String.self, forKey: .subtype))
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    revision = try values.decodeIfPresent(Int.self, forKey: .revision)
    occurredAt = try values.decodeTimestamp(forKey: .occurredAt)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)?.trimmed
      .nonEmpty
    occurredTimezone =
      try values.decodeIfPresent(String.self, forKey: .occurredTimezone)?.trimmed.nonEmpty
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    matchReasons = try values.decodeIfPresent([String].self, forKey: .matchReasons) ?? []
    // PostgREST writes `bigint` as a number; a proxy may write it as a string.
    if let count = try? values.decode(Int.self, forKey: .totalCount) {
      totalCount = count
    } else {
      totalCount = Int(try values.decode(String.self, forKey: .totalCount)) ?? 0
    }
  }

  /// Every result opens its Item page, like Web `wikiEntryHref`.
  var link: ItemLink { ItemLink(entryID: id) }

  var marks: EntryMarks { EntryMarks(subtype: subtype, isFirstTime: isFirstTime) }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredAt, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `rowTitle`: the title, or the date when there is none.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// The note as results show it, without surrounding blank lines.
  var note: String { body.trimmed }

  /// Web `compactText`: the note on one line, at most 140 characters.
  var excerpt: String { body.compactExcerpt }

  /// Web offers "Read full note" past 280 characters.
  var hasLongNote: Bool { note.utf16.count > 280 }

  /// Web `wikiItemIdentityLabel`.
  var identityLabel: String { marks.identityLabel }

  /// Web `resultDateLabel`: a Chapter shows the span it covers, anything else its date.
  var displayDate: String {
    subtype == .chapter ? occurrence.spanLabel : occurrence.displayLabel
  }

  /// What VoiceOver reads for a result: its identity, title, and a date only when the title
  /// does not already name it.
  var accessibilityLabel: String {
    [identityLabel, displayTitle, title == nil ? nil : displayDate].compactMap(\.self)
      .joined(separator: ", ")
  }
}

/// A validated Library search, like Web `parseSearchRequest`: one keyword phrase with optional
/// Record, tag, and local date filters.
struct EntrySearchRequest: Equatable, Sendable {
  static let pageSize = 25
  static let queryLimit = 200

  let query: String
  let records: [EntryRecordFilter]
  let tagNames: [String]
  /// Local calendar dates as `yyyy-MM-dd`.
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  var hasCriteria: Bool {
    !query.isEmpty || !records.isEmpty || !tagNames.isEmpty || dateFrom != nil || dateTo != nil
  }

  var parameters: SearchEntryParameters {
    SearchEntryParameters(
      query: query, classifications: records.map(\.rawValue), tagNames: tagNames,
      dateFrom: dateFrom, dateTo: dateTo, limit: limit, offset: offset)
  }

  /// The same search at another offset.
  func page(offset: Int) throws -> EntrySearchRequest {
    guard offset >= 0, offset <= 10_000 else { throw EntrySearchError.invalidPagination }
    return EntrySearchRequest(
      query: query, records: records, tagNames: tagNames, dateFrom: dateFrom, dateTo: dateTo,
      limit: limit, offset: offset)
  }

  static func validate(
    query: String,
    records: [EntryRecordFilter] = [],
    tagNames: [String] = [],
    dateFrom: String? = nil,
    dateTo: String? = nil,
    limit: Int = pageSize,
    offset: Int = 0
  ) throws -> EntrySearchRequest {
    let normalizedQuery = query.trimmed
    let normalizedTags = normalizeSearchNames(tagNames)
    let from = dateFrom?.trimmed.nonEmpty
    let to = dateTo?.trimmed.nonEmpty
    guard normalizedQuery.count <= queryLimit else { throw EntrySearchError.queryTooLong }
    guard normalizedTags.count <= EntryLimits.tagCount,
      normalizedTags.allSatisfy({ $0.count <= EntryLimits.tagName })
    else { throw EntrySearchError.invalidTags }
    if let from, !isISODate(from) { throw EntrySearchError.invalidStartDate }
    if let to, !isISODate(to) { throw EntrySearchError.invalidEndDate }
    if let from, let to, from > to { throw EntrySearchError.invalidDateRange }
    guard limit >= 1, limit <= 100, offset >= 0, offset <= 10_000 else {
      throw EntrySearchError.invalidPagination
    }
    var seen: Set<EntryRecordFilter> = []
    return EntrySearchRequest(
      query: normalizedQuery, records: records.filter { seen.insert($0).inserted },
      tagNames: normalizedTags, dateFrom: from, dateTo: to, limit: limit, offset: offset)
  }
}

/// `search_wiki_items` arguments. iOS is keyword only, so it never sends the embedding
/// arguments; absent dates are explicit nulls so the signature always matches.
struct SearchEntryParameters: Encodable, Equatable, Sendable {
  let query: String
  let classifications: [String]
  let tagNames: [String]
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case classifications = "p_item_classifications"
    case tagNames = "p_tag_names"
    case dateFrom = "p_date_from"
    case dateTo = "p_date_to"
    case limit = "p_limit"
    case offset = "p_offset"
    case order = "p_order"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(query, forKey: .query)
    try values.encode(classifications, forKey: .classifications)
    try values.encode(tagNames, forKey: .tagNames)
    try values.encode(dateFrom, forKey: .dateFrom)
    try values.encode(dateTo, forKey: .dateTo)
    try values.encode(limit, forKey: .limit)
    try values.encode(offset, forKey: .offset)
    try values.encode("relevance", forKey: .order)
  }
}

enum EntrySearchError: LocalizedError, Equatable {
  case invalidDateRange
  case invalidEndDate
  case invalidPagination
  case invalidStartDate
  case invalidTags
  case queryTooLong

  var errorDescription: String? {
    switch self {
    case .invalidDateRange: "The start date must be on or before the end date."
    case .invalidEndDate: "Choose a valid end date."
    case .invalidPagination: "This result page is unavailable."
    case .invalidStartDate: "Choose a valid start date."
    case .invalidTags: "Choose up to \(EntryLimits.tagCount) valid tags."
    case .queryTooLong:
      "Search phrases can be up to \(EntrySearchRequest.queryLimit) characters."
    }
  }
}

/// Trims names and drops blanks and case-insensitive repeats, keeping the first spelling.
private func normalizeSearchNames(_ values: [String]) -> [String] {
  var seen: Set<String> = []
  return values.map(\.trimmed).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
}

/// A real calendar date written as `yyyy-MM-dd`, like Web `isISODate`.
private func isISODate(_ value: String) -> Bool {
  guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return false }
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .gmt
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.date(from: value).map(formatter.string(from:)) == value
}
