import Foundation

enum WikiItemRecordSource: String, Codable, Equatable, Hashable, Sendable {
  case entry, person, place
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
    if itemKind == .capture || subtypeLabel == itemKind.displayName {
      return itemKind.displayName
    }
    return "\(itemKind.displayName) · \(subtypeLabel)"
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
    if itemKind == .capture { return "Unorganized" }
    if itemKind == .goal { return itemSubtype == "bucket_list" ? "Bucket List" : "Goal" }
    if itemKind == .entity {
      switch itemSubtype {
      case "person": return "Person"
      case "place": return "Place"
      case "home": return "Home"
      case "vehicle": return "Vehicle"
      default: break
      }
    }
    return
      itemSubtype
      .split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
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
