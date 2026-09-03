import Foundation

enum TrashItemKind: String, Codable, Equatable, Hashable, Sendable {
  case attachment
  case entry
  case habit
  case place

  var displayName: String {
    switch self {
    case .attachment:
      "Photo"
    case .entry:
      "Entry"
    case .habit:
      "Habit"
    case .place:
      "Place"
    }
  }

  var systemImage: String {
    switch self {
    case .attachment:
      "photo"
    case .entry:
      "text.line.first.and.arrowtriangle.forward"
    case .habit:
      "checkmark"
    case .place:
      "map"
    }
  }
}

struct TrashItem: Decodable, Equatable, Identifiable, Sendable {
  let kind: TrashItemKind
  let itemID: UUID
  let title: String
  let detail: String?
  let deletedAt: String
  let expiresAt: String
  let revision: Int?
  let entryType: String?
  let parentEntryID: UUID?
  let storagePaths: [String]
  let totalCount: Int
  var signedURL: URL?

  enum CodingKeys: String, CodingKey {
    case kind = "item_kind"
    case itemID = "item_id"
    case title
    case detail
    case deletedAt = "deleted_at"
    case expiresAt = "expires_at"
    case revision
    case entryType = "entry_type"
    case parentEntryID = "parent_entry_id"
    case storagePaths = "storage_paths"
    case totalCount = "total_count"
  }

  var id: String {
    "\(kind.rawValue)-\(itemID.uuidString.lowercased())"
  }

  var displayKind: String {
    if kind == .entry, entryType == "first_time" {
      return "First Time"
    }

    return kind.displayName
  }

  var displayDetail: String? {
    detail?.trimmed.nonEmpty.flatMap { $0 == title ? nil : $0 }
  }

  var deletionDateLabel: String {
    Self.displayDate(deletedAt)
  }

  var expirationDateLabel: String {
    Self.displayDate(expiresAt)
  }

  func retentionLabel(referenceDate: Date = Date()) -> String {
    guard let expirationDate = TrashTimestamp.date(from: expiresAt) else {
      return "Retention date unavailable"
    }

    let remainingSeconds = expirationDate.timeIntervalSince(referenceDate)
    guard remainingSeconds > 0 else {
      return "Eligible for cleanup since \(expirationDateLabel)"
    }

    let remainingDays = Int(ceil(remainingSeconds / 86_400))
    let unit = remainingDays == 1 ? "day" : "days"
    return "\(remainingDays) \(unit) to restore · through \(expirationDateLabel)"
  }

  private static func displayDate(_ timestamp: String) -> String {
    guard let date = TrashTimestamp.date(from: timestamp) else {
      return "Date unavailable"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    return formatter.string(from: date)
  }
}

enum TrashTimestamp {
  static func date(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatter.date(from: value) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

struct TrashPageRequest: Equatable, Sendable {
  static let pageSize = 25

  let limit: Int
  let offset: Int

  var parameters: TrashPageParameters {
    TrashPageParameters(limit: limit, offset: offset)
  }

  static func validate(
    limit: Int = pageSize,
    offset: Int = 0
  ) throws -> TrashPageRequest {
    guard limit >= 1, limit <= 100, offset >= 0, offset <= 10_000 else {
      throw TrashItemError.invalidPagination
    }

    return TrashPageRequest(limit: limit, offset: offset)
  }
}

struct TrashPageParameters: Encodable, Equatable, Sendable {
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

struct TrashItemMutationParameters: Encodable, Equatable, Sendable {
  let itemKind: TrashItemKind
  let itemID: UUID
  let expectedRevision: Int?
  let expectedDeletedAt: String

  init(item: TrashItem) {
    itemKind = item.kind
    itemID = item.itemID
    expectedRevision = item.revision
    expectedDeletedAt = item.deletedAt
  }

  enum CodingKeys: String, CodingKey {
    case itemKind = "p_item_kind"
    case itemID = "p_item_id"
    case expectedRevision = "p_expected_revision"
    case expectedDeletedAt = "p_expected_deleted_at"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(itemKind, forKey: .itemKind)
    try values.encode(itemID, forKey: .itemID)
    try values.encode(expectedDeletedAt, forKey: .expectedDeletedAt)
    try values.encodeIfPresent(expectedRevision, forKey: .expectedRevision)
    if expectedRevision == nil { try values.encodeNil(forKey: .expectedRevision) }
  }
}

struct TrashStoragePath: Decodable, Equatable, Sendable {
  let objectPath: String

  enum CodingKeys: String, CodingKey {
    case objectPath = "object_path"
  }
}

struct RestoredTrashItem: Decodable, Equatable, Sendable {
  let itemKind: TrashItemKind
  let itemID: UUID
  let revision: Int?

  enum CodingKeys: String, CodingKey {
    case itemKind = "item_kind"
    case itemID = "item_id"
    case revision
  }
}

struct DeletedTrashItem: Decodable, Equatable, Sendable {
  let itemKind: TrashItemKind
  let itemID: UUID

  enum CodingKeys: String, CodingKey {
    case itemKind = "item_kind"
    case itemID = "item_id"
  }
}

enum TrashItemError: Error, Equatable {
  case invalidPagination
}
