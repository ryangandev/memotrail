import Foundation

enum WikiItemRecordSource: String, Codable, Equatable, Hashable, Sendable {
  case entry, person
}

struct WikiItemSummary: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let recordSource: WikiItemRecordSource
  let recordID: UUID
  let canonicalItemID: UUID
  let itemKind: WikiItemKind
  let itemSubtype: String
  let title: String
  let excerpt: String
  let inboxStatus: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let updatedAt: Date
  let totalCount: Int

  var id: UUID { canonicalItemID }

  var subtypeLabel: String {
    Self.subtypeLabel(itemKind: itemKind, itemSubtype: itemSubtype)
  }

  var identityLabel: String {
    itemKind.displayName(subtype: itemSubtype)
  }

  var dateLabel: String {
    if let occurredStart {
      let start = occurredStart.formatted(date: .abbreviated, time: .omitted)
      guard let occurredEnd else { return start }
      return "\(start) to \(occurredEnd.formatted(date: .abbreviated, time: .omitted))"
    }
    return "Updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))"
  }

  var isInInbox: Bool { inboxStatus == "unreviewed" }

  enum CodingKeys: String, CodingKey {
    case recordSource = "record_source"
    case recordID = "item_id"
    case canonicalItemID = "canonical_item_id"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case title, excerpt
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case updatedAt = "updated_at"
    case totalCount = "total_count"
  }

  private static func subtypeLabel(itemKind: WikiItemKind, itemSubtype: String) -> String {
    itemKind.displayName(subtype: itemSubtype)
  }
}

struct WikiItemsPageParameters: Encodable, Equatable, Sendable {
  let pQuery: String
  let pItemKinds: [String]
  let pItemSubtypes: [String]
  let pLimit: Int
  let pOffset: Int

  enum CodingKeys: String, CodingKey {
    case pQuery = "p_query"
    case pItemKinds = "p_item_kinds"
    case pItemSubtypes = "p_item_subtypes"
    case pLimit = "p_limit"
    case pOffset = "p_offset"
  }
}
