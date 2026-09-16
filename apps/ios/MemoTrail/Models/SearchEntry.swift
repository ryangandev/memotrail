import Foundation

enum SearchRecordSource: String, Codable, Equatable, Hashable, Sendable {
  case entry, person, place
}

struct AISearchRequest: Encodable, Equatable, Sendable {
  let parameters: [String: [String]]
  let timeZone: String
  init(request: EntrySearchRequest, timeZone: String = TimeZone.current.identifier) {
    self.timeZone = timeZone
    parameters = [
      "q": [request.query], "type": request.entryTypes.map(\.rawValue),
      "collection": request.collectionNames, "tag": request.tagNames,
      "from": request.dateFrom.map { [$0] } ?? [], "to": request.dateTo.map { [$0] } ?? [],
    ]
  }
}
struct AISearchAnswer: Decodable, Sendable {
  let question: String
  let findings: [AISearchFinding]
  let sources: [AISearchSource]
  let notices: [String]
  let insufficientEvidence: Bool
  let queries: [String]
}
struct AISearchFinding: Decodable, Sendable {
  let text: String
  let citations: [AISearchCitation]
}
struct AISearchCitation: Decodable, Sendable {
  let sourceID: String
  let quote: String
}
struct AISearchSource: Decodable, Identifiable, Sendable {
  let id: String
  let recordID: UUID
  let kind: String
  let title: String
  let text: String
  let truncated: Bool
}

struct SearchEntry: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let entryType: String
  let inboxStatus: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let recordSource: SearchRecordSource
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

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title
    case body
    case entryType = "entry_type"
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
    entryType = try values.decode(String.self, forKey: .entryType)
    inboxStatus = try values.decode(String.self, forKey: .inboxStatus)
    let compatibility = Self.compatibilityIdentity(
      entryType: entryType,
      inboxStatus: inboxStatus
    )
    itemKind =
      try values.decodeIfPresent(WikiItemKind.self, forKey: .itemKind)
      ?? compatibility.kind
    itemSubtype =
      try values.decodeIfPresent(String.self, forKey: .itemSubtype)?.trimmed.nonEmpty
      ?? compatibility.subtype
    recordSource =
      try values.decodeIfPresent(SearchRecordSource.self, forKey: .recordSource) ?? .entry
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

  var displayTitle: String {
    if let title {
      return title
    }

    let firstLine =
      body.trimmed
      .split(whereSeparator: \Character.isNewline)
      .first
      .map(String.init)?
      .trimmed ?? ""

    return firstLine.nonEmpty.map { $0.truncated(to: 90) } ?? "Untitled Entry"
  }

  var displayExcerpt: String? {
    let trimmedBody = body.trimmed
    guard !trimmedBody.isEmpty else { return nil }

    if title != nil {
      return trimmedBody.truncated(to: 280)
    }

    if let firstNewline = trimmedBody.firstIndex(where: \Character.isNewline) {
      let remainder = trimmedBody[trimmedBody.index(after: firstNewline)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return remainder.nonEmpty?.truncated(to: 280)
    }

    guard trimmedBody.count > 90 else { return nil }
    let remainingIndex = trimmedBody.index(trimmedBody.startIndex, offsetBy: 90)
    return String(trimmedBody[remainingIndex...]).trimmed.truncated(to: 280)
  }

  var displayType: String {
    let subtype =
      itemSubtype
      .split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
    if itemSubtype == itemKind.rawValue || (itemKind == .goal && itemSubtype == "goal") {
      return itemKind.displayName
    }
    return "\(itemKind.displayName) · \(subtype)"
  }

  var displayDate: String {
    if let datePrecision, let precision = TimelineDatePrecision(rawValue: datePrecision) {
      let occurrence = EntryOccurrence(
        precision: precision, start: occurredAt, end: occurredEnd, label: occurredLabel,
        timezone: occurredTimezone ?? "UTC")
      return (itemKind == .entity && ["home", "vehicle"].contains(itemSubtype))
        || (itemKind == .event && itemSubtype == "life_stage")
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

  private static func compatibilityIdentity(
    entryType: String,
    inboxStatus: String
  ) -> (kind: WikiItemKind, subtype: String) {
    switch entryType {
    case "first_time": (.event, "first_time")
    case "life_stage": (.event, "life_stage")
    case "home": (.entity, "home")
    case "vehicle": (.entity, "vehicle")
    case "goal": (.goal, "goal")
    default:
      inboxStatus == "unreviewed"
        ? (.capture, "quick_capture")
        : (.writing, "note")
    }
  }
}

enum SearchEntryType: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case capture
  case writing
  case entity
  case event
  case story
  case goal

  var displayName: String {
    switch self {
    case .capture: "Capture"
    case .writing: "Writing"
    case .entity: "Entity"
    case .event: "Event"
    case .story: "Story"
    case .goal: "Goal"
    }
  }
}

struct EntrySearchRequest: Equatable, Sendable {
  static let pageSize = 25
  static let queryLimit = 200

  let query: String
  let entryTypes: [SearchEntryType]
  let collectionNames: [String]
  let tagNames: [String]
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  var hasCriteria: Bool {
    !query.isEmpty
      || !entryTypes.isEmpty
      || !collectionNames.isEmpty
      || !tagNames.isEmpty
      || dateFrom != nil
      || dateTo != nil
  }

  var parameters: SearchEntryParameters {
    SearchEntryParameters(
      query: query,
      entryTypes: entryTypes.map(\.rawValue),
      collectionNames: collectionNames,
      tagNames: tagNames,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
      offset: offset
    )
  }

  static func validate(
    query: String,
    entryTypes: [SearchEntryType],
    collectionNames: [String],
    tagNames: [String],
    dateFrom: Date?,
    dateTo: Date?,
    limit: Int = pageSize,
    offset: Int = 0,
    calendar: Calendar = .current
  ) throws -> EntrySearchRequest {
    let normalizedQuery = query.trimmed
    guard normalizedQuery.count <= queryLimit else {
      throw EntrySearchError.queryTooLong
    }

    guard entryTypes.count <= 20 else {
      throw EntrySearchError.invalidEntryTypes
    }

    guard
      let normalizedCollections = normalizeSearchNames(
        collectionNames,
        maximumCount: 20,
        maximumNameLength: 80
      )
    else {
      throw EntrySearchError.invalidCollections
    }

    guard
      let normalizedTags = normalizeSearchNames(
        tagNames,
        maximumCount: 50,
        maximumNameLength: 60
      )
    else {
      throw EntrySearchError.invalidTags
    }

    if let dateFrom, let dateTo,
      calendar.compare(dateFrom, to: dateTo, toGranularity: .day) == .orderedDescending
    {
      throw EntrySearchError.invalidDateRange
    }

    guard limit >= 1, limit <= 100, offset >= 0, offset <= 10_000 else {
      throw EntrySearchError.invalidPagination
    }

    return EntrySearchRequest(
      query: normalizedQuery,
      entryTypes: Array(Set(entryTypes)).sorted { $0.rawValue < $1.rawValue },
      collectionNames: normalizedCollections,
      tagNames: normalizedTags,
      dateFrom: dateFrom.map { dateOnlyString($0, calendar: calendar) },
      dateTo: dateTo.map { dateOnlyString($0, calendar: calendar) },
      limit: limit,
      offset: offset
    )
  }
}

struct SearchEntryParameters: Encodable, Equatable, Sendable {
  let query: String
  let entryTypes: [String]
  let collectionNames: [String]
  let tagNames: [String]
  let dateFrom: String?
  let dateTo: String?
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case entryTypes = "p_entry_types"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case dateFrom = "p_date_from"
    case dateTo = "p_date_to"
    case limit = "p_limit"
    case offset = "p_offset"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)

    try values.encode(query, forKey: .query)
    try values.encode(entryTypes, forKey: .entryTypes)
    try values.encode(collectionNames, forKey: .collectionNames)
    try values.encode(tagNames, forKey: .tagNames)
    try values.encodeIfPresent(dateFrom, forKey: .dateFrom)
    if dateFrom == nil {
      try values.encodeNil(forKey: .dateFrom)
    }
    try values.encodeIfPresent(dateTo, forKey: .dateTo)
    if dateTo == nil {
      try values.encodeNil(forKey: .dateTo)
    }
    try values.encode(limit, forKey: .limit)
    try values.encode(offset, forKey: .offset)
  }
}

enum EntrySearchError: LocalizedError, Equatable {
  case invalidCollections
  case invalidDateRange
  case invalidEntryTypes
  case invalidPagination
  case invalidTags
  case queryTooLong

  var errorDescription: String? {
    switch self {
    case .invalidCollections:
      "Choose up to 20 valid Collections."
    case .invalidDateRange:
      "The start date must be on or before the end date."
    case .invalidEntryTypes:
      "Choose up to 20 valid Entry Types."
    case .invalidPagination:
      "This result page is unavailable."
    case .invalidTags:
      "Choose up to 50 valid tags."
    case .queryTooLong:
      "Search phrases can be up to \(EntrySearchRequest.queryLimit) characters."
    }
  }
}

private func normalizeSearchNames(
  _ values: [String],
  maximumCount: Int,
  maximumNameLength: Int
) -> [String]? {
  var names: [String] = []
  var normalizedNames: Set<String> = []

  for value in values {
    let name = value.trimmed
    guard !name.isEmpty, name.count <= maximumNameLength else { return nil }

    if normalizedNames.insert(name.lowercased()).inserted {
      names.append(name)
    }
  }

  return names.count <= maximumCount ? names : nil
}

private func dateOnlyString(_ date: Date, calendar: Calendar) -> String {
  let components = calendar.dateComponents([.year, .month, .day], from: date)
  return String(
    format: "%04d-%02d-%02d",
    components.year ?? 0,
    components.month ?? 0,
    components.day ?? 0
  )
}
