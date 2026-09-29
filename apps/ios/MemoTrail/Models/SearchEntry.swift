import Foundation

/// Web `wikiItemSearchGroups`: the Library Record filter's canonical Kinds and focused forms,
/// sent to `search_wiki_items` as item classifications.
enum WikiItemClassification: String, CaseIterable, Equatable, Hashable, Sendable {
  case entry, entity, goal
  case firstTime = "first_time"
  case person, home, vehicle

  var title: String {
    switch self {
    case .entry: "Entries"
    case .entity: "Entities"
    case .goal: "Goals"
    case .firstTime: "First Times"
    case .person: "People"
    case .home: "Homes"
    case .vehicle: "Vehicles"
    }
  }

  static let groups: [(title: String, options: [Self])] = [
    ("Records", [.entry, .entity, .goal]),
    ("Focused records", [.firstTime, .person, .home, .vehicle]),
  ]
}

/// One `search_wiki_items` result, like Web `SearchEntry`.
struct SearchEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let inboxStatus: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let recordSource: WikiItemRecordSource
  let recordID: UUID
  let occurredAt: Date?
  let occurredEnd: Date?
  let datePrecision: String?
  let occurredLabel: String?
  let occurredTimezone: String?
  let updatedAt: Date
  let collectionNames: [String]
  let tagNames: [String]
  let matchReasons: [String]
  let totalCount: Int
  /// The note's Web formatting, loaded separately from `metadata.body_rich`.
  var bodyRich: EntryRichText?

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title
    case body
    case inboxStatus = "inbox_status"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case recordSource = "record_source"
    case recordID = "record_id"
    case occurredAt = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case updatedAt = "updated_at"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case matchReasons = "match_reasons"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)?.trimmed.nonEmpty
    body = try values.decode(String.self, forKey: .body)
    inboxStatus = try values.decode(String.self, forKey: .inboxStatus)
    itemKind = try values.decode(WikiItemKind.self, forKey: .itemKind)
    itemSubtype = try values.decode(String.self, forKey: .itemSubtype)
    recordSource =
      try values.decodeIfPresent(WikiItemRecordSource.self, forKey: .recordSource) ?? .entry
    recordID = try values.decodeIfPresent(UUID.self, forKey: .recordID) ?? id
    occurredAt = try values.decodeIfPresent(Date.self, forKey: .occurredAt)
    occurredEnd = try values.decodeIfPresent(Date.self, forKey: .occurredEnd)
    datePrecision = try values.decodeIfPresent(String.self, forKey: .datePrecision)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)?.trimmed
      .nonEmpty
    occurredTimezone =
      try values.decodeIfPresent(String.self, forKey: .occurredTimezone)?.trimmed.nonEmpty
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    collectionNames = try values.decodeIfPresent([String].self, forKey: .collectionNames) ?? []
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    matchReasons = try values.decodeIfPresent([String].self, forKey: .matchReasons) ?? []
    totalCount = try values.decode(Int.self, forKey: .totalCount)
  }

  /// The title, or the note's first useful line.
  var displayTitle: String {
    title
      ?? body.split(whereSeparator: \Character.isNewline).lazy.map { String($0).trimmed }
      .first(where: { !$0.isEmpty }) ?? "Untitled Entry"
  }

  /// The note as results show it, without surrounding blank lines.
  var note: String { body.trimmed }

  /// Web offers "Read full note" past 280 characters.
  var hasLongNote: Bool { note.utf16.count > 280 }

  var identityLabel: String {
    itemKind.displayName(subtype: itemSubtype)
  }

  var displayDate: String {
    if let datePrecision, let precision = TimelineDatePrecision(rawValue: datePrecision) {
      let occurrence = EntryOccurrence(
        precision: precision, start: occurredAt, end: occurredEnd, label: occurredLabel,
        timezone: occurredTimezone ?? "UTC")
      return (itemKind == .entity && ["home", "vehicle"].contains(itemSubtype))
        || itemSubtype == "period"
        ? occurrence.spanLabel : occurrence.displayLabel
    }
    if let occurredLabel {
      return occurredLabel
    }

    guard let occurredAt else { return "Date not set" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = occurredTimezone.flatMap(TimeZone.init(identifier:)) ?? .gmt
    formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    return formatter.string(from: occurredAt)
  }

  var isInInbox: Bool {
    inboxStatus == "unreviewed"
  }
}

/// A validated Library search, like Web `parseSearchRequest`: one keyword phrase with optional
/// Record, Collection, tag, and local date filters.
struct EntrySearchRequest: Equatable, Sendable {
  static let pageSize = 25
  static let queryLimit = 200

  let query: String
  let classifications: [WikiItemClassification]
  let collectionNames: [String]
  let tagNames: [String]
  /// Local calendar dates as `yyyy-MM-dd`.
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  var hasCriteria: Bool {
    !query.isEmpty || !classifications.isEmpty || !collectionNames.isEmpty || !tagNames.isEmpty
      || dateFrom != nil || dateTo != nil
  }

  var parameters: SearchEntryParameters {
    SearchEntryParameters(
      query: query, classifications: classifications.map(\.rawValue),
      collectionNames: collectionNames, tagNames: tagNames, dateFrom: dateFrom, dateTo: dateTo,
      limit: limit, offset: offset)
  }

  /// The same search at another offset.
  func page(offset: Int) throws -> EntrySearchRequest {
    guard offset >= 0, offset <= 10_000 else { throw EntrySearchError.invalidPagination }
    return EntrySearchRequest(
      query: query, classifications: classifications, collectionNames: collectionNames,
      tagNames: tagNames, dateFrom: dateFrom, dateTo: dateTo, limit: limit, offset: offset)
  }

  static func validate(
    query: String,
    classifications: [WikiItemClassification],
    collectionNames: [String],
    tagNames: [String],
    dateFrom: String?,
    dateTo: String?,
    limit: Int = pageSize,
    offset: Int = 0
  ) throws -> EntrySearchRequest {
    let normalizedQuery = query.trimmed
    let normalizedCollections = normalizeSearchNames(collectionNames)
    let normalizedTags = normalizeSearchNames(tagNames)
    let from = dateFrom?.trimmed.nonEmpty
    let to = dateTo?.trimmed.nonEmpty
    guard normalizedQuery.count <= queryLimit else { throw EntrySearchError.queryTooLong }
    guard classifications.count <= 20 else { throw EntrySearchError.invalidClassifications }
    guard normalizedCollections.count <= 20, normalizedCollections.allSatisfy({ $0.count <= 80 })
    else { throw EntrySearchError.invalidCollections }
    guard normalizedTags.count <= 50, normalizedTags.allSatisfy({ $0.count <= 60 }) else {
      throw EntrySearchError.invalidTags
    }
    if let from, !isISODate(from) { throw EntrySearchError.invalidStartDate }
    if let to, !isISODate(to) { throw EntrySearchError.invalidEndDate }
    if let from, let to, from > to { throw EntrySearchError.invalidDateRange }
    guard limit >= 1, limit <= 100, offset >= 0, offset <= 10_000 else {
      throw EntrySearchError.invalidPagination
    }

    var seen: Set<WikiItemClassification> = []
    return EntrySearchRequest(
      query: normalizedQuery,
      classifications: classifications.filter { seen.insert($0).inserted },
      collectionNames: normalizedCollections, tagNames: normalizedTags, dateFrom: from,
      dateTo: to, limit: limit, offset: offset)
  }
}

struct SearchEntryParameters: Encodable, Equatable, Sendable {
  let query: String
  let classifications: [String]
  let collectionNames: [String]
  let tagNames: [String]
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case classifications = "p_item_classifications"
    case collectionNames = "p_collection_names"
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
    try values.encode(collectionNames, forKey: .collectionNames)
    try values.encode(tagNames, forKey: .tagNames)
    // Absent dates are explicit nulls, so the RPC signature always matches.
    try values.encode(dateFrom, forKey: .dateFrom)
    try values.encode(dateTo, forKey: .dateTo)
    try values.encode(limit, forKey: .limit)
    try values.encode(offset, forKey: .offset)
    try values.encode("relevance", forKey: .order)
  }
}

enum EntrySearchError: LocalizedError, Equatable {
  case invalidClassifications
  case invalidCollections
  case invalidDateRange
  case invalidEndDate
  case invalidPagination
  case invalidStartDate
  case invalidTags
  case queryTooLong

  var errorDescription: String? {
    switch self {
    case .invalidClassifications: "Choose up to 20 valid Kinds or types."
    case .invalidCollections: "Choose up to 20 valid Collections."
    case .invalidDateRange: "The start date must be on or before the end date."
    case .invalidEndDate: "Choose a valid end date."
    case .invalidPagination: "This result page is unavailable."
    case .invalidStartDate: "Choose a valid start date."
    case .invalidTags: "Choose up to 50 valid tags."
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
