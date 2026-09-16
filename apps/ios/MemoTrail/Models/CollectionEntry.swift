import Foundation

struct MemoCollection: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let systemKey: String?
  let color: String?
  let sortOrder: Int
  let entryCount: Int
  let unreviewedCount: Int
  let latestEntryAt: Date?
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id = "collection_id"
    case name
    case systemKey = "system_key"
    case color
    case sortOrder = "sort_order"
    case entryCount = "entry_count"
    case unreviewedCount = "unreviewed_count"
    case latestEntryAt = "latest_entry_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var latestEntryLabel: String {
    guard let latestEntryAt else { return "Empty Collection" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    return "Latest \(formatter.string(from: latestEntryAt))"
  }
}

enum CollectionsWorkspace {
  static func collections(from rows: [MemoCollection]) -> [MemoCollection] {
    rows.sorted { left, right in
      if left.sortOrder != right.sortOrder {
        return left.sortOrder < right.sortOrder
      }

      let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
      if nameOrder != .orderedSame {
        return nameOrder == .orderedAscending
      }

      return left.id.uuidString < right.id.uuidString
    }
  }
}

struct CollectionEntry: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let collectionID: UUID
  let collectionName: String
  let totalCount: Int
  let id: UUID
  let title: String?
  let body: String
  let inboxStatus: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let recordSource: WikiItemRecordSource
  let recordID: UUID
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: String
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let collectionNames: [String]
  let tagNames: [String]
  var attachments: [FirstTimeAttachment]

  enum CodingKeys: String, CodingKey {
    case collectionID = "collection_id"
    case collectionName = "collection_name"
    case totalCount = "total_count"
    case id = "entry_id"
    case title
    case body
    case inboxStatus = "inbox_status"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case recordSource = "record_source"
    case recordID = "record_id"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case attachments
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    collectionID = try values.decode(UUID.self, forKey: .collectionID)
    collectionName = try values.decode(String.self, forKey: .collectionName)
    totalCount = try values.decode(Int.self, forKey: .totalCount)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)?.trimmed.nonEmpty
    body = try values.decode(String.self, forKey: .body)
    inboxStatus = try values.decode(String.self, forKey: .inboxStatus)
    itemKind = try values.decode(WikiItemKind.self, forKey: .itemKind)
    itemSubtype = try values.decode(String.self, forKey: .itemSubtype)
    recordSource =
      try values.decodeIfPresent(WikiItemRecordSource.self, forKey: .recordSource) ?? .entry
    recordID = try values.decodeIfPresent(UUID.self, forKey: .recordID) ?? id
    occurredStart = try values.decodeIfPresent(Date.self, forKey: .occurredStart)
    occurredEnd = try values.decodeIfPresent(Date.self, forKey: .occurredEnd)
    datePrecision = try values.decode(String.self, forKey: .datePrecision)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)?.trimmed
      .nonEmpty
    occurredTimezone =
      try values.decodeIfPresent(String.self, forKey: .occurredTimezone)?.trimmed.nonEmpty
    revision = try values.decode(Int.self, forKey: .revision)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    collectionNames = try values.decodeIfPresent([String].self, forKey: .collectionNames) ?? []
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    attachments = try values.decodeIfPresent([FirstTimeAttachment].self, forKey: .attachments) ?? []
  }

  var displayTitle: String {
    if let title {
      return title
    }

    return firstBodyLine?.truncated(to: 90) ?? "Untitled Entry"
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

    return trimmedBody.count > 90
      ? String(trimmedBody.dropFirst(90)).trimmed.nonEmpty?.truncated(to: 280)
      : nil
  }

  var displayType: String {
    let subtype =
      itemSubtype
      .split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
    if itemKind == .capture || subtype == itemKind.displayName {
      return itemKind.displayName
    }
    return "\(itemKind.displayName) · \(subtype)"
  }

  var displayDate: String {
    if let occurredLabel {
      return occurredLabel
    }

    guard let occurredStart else { return "Date not set" }

    let start = formattedDate(occurredStart)
    guard let occurredEnd else { return start }
    return "\(start) - \(formattedDate(occurredEnd))"
  }

  var isInInbox: Bool {
    inboxStatus == "unreviewed"
  }

  var coverAttachment: FirstTimeAttachment? {
    attachments.first(where: { $0.variant == .original }) ?? attachments.first
  }

  private var firstBodyLine: String? {
    body.trimmed
      .split(whereSeparator: \Character.isNewline)
      .first
      .map(String.init)?
      .trimmed.nonEmpty
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = occurredTimezone.flatMap(TimeZone.init(identifier:)) ?? .gmt

    switch datePrecision {
    case "year":
      formatter.setLocalizedDateFormatFromTemplate("yyyy")
    case "month":
      formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    default:
      formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    }

    return formatter.string(from: date)
  }

}

struct CollectionPageRequest: Equatable, Sendable {
  static let pageSize = 25

  let collectionID: UUID
  let limit: Int
  let offset: Int

  var parameters: CollectionPageParameters {
    CollectionPageParameters(collectionID: collectionID, limit: limit, offset: offset)
  }

  static func validate(
    collectionID: UUID,
    limit: Int = pageSize,
    offset: Int = 0
  ) throws -> CollectionPageRequest {
    guard limit >= 1, limit <= 100, offset >= 0, offset <= 10_000 else {
      throw CollectionEntryError.invalidPagination
    }

    return CollectionPageRequest(collectionID: collectionID, limit: limit, offset: offset)
  }
}

struct CollectionPageParameters: Encodable, Equatable, Sendable {
  let collectionID: UUID
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case collectionID = "p_collection_id"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

enum CollectionEntryError: Error, Equatable {
  case invalidPagination
}
