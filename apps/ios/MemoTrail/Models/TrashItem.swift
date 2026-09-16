import Foundation

enum TrashItemKind: String, Codable, Equatable, Hashable, Sendable {
  case attachment
  case entry
  case place
  case person
  case collection

  var displayName: String {
    switch self {
    case .collection:
      "Collection"
    case .attachment:
      "Photo"
    case .entry:
      "Entry"
    case .place:
      "Place"
    case .person:
      "Person"
    }
  }

  var systemImage: String {
    switch self {
    case .collection:
      "archivebox"
    case .attachment:
      "photo"
    case .entry:
      "text.line.first.and.arrowtriangle.forward"
    case .place:
      "map"
    case .person:
      "person.2"
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
  let wikiItemKind: WikiItemKind?
  let wikiItemSubtype: String?
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
    case wikiItemKind = "wiki_item_kind"
    case wikiItemSubtype = "wiki_item_subtype"
    case parentEntryID = "parent_entry_id"
    case storagePaths = "storage_paths"
    case totalCount = "total_count"
  }

  var id: String {
    "\(kind.rawValue)-\(itemID.uuidString.lowercased())"
  }

  var displayKind: String {
    if kind == .entry, wikiItemKind == .event, wikiItemSubtype == "first_time" {
      return "First Time"
    }

    if kind == .entry, let wikiItemKind, let wikiItemSubtype {
      return wikiItemKind.displayName(subtype: wikiItemSubtype)
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

  init(target: EmptyTrashTarget) {
    itemKind = target.kind
    itemID = target.itemID
    expectedRevision = target.revision
    expectedDeletedAt = target.deletedAt
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

struct EmptyTrashTarget: Decodable, Equatable, Sendable {
  let kind: TrashItemKind
  let itemID: UUID
  let deletedAt: String
  let revision: Int?
  enum CodingKeys: String, CodingKey {
    case kind = "item_kind"
    case itemID = "item_id"
    case deletedAt = "deleted_at"
    case revision
  }
  static func isValid(_ items: [Self]) -> Bool {
    guard items.count <= 10000 else { return false }
    var seen = Set<String>()
    return items.allSatisfy {
      TrashTimestamp.date(from: $0.deletedAt) != nil
        && ($0.kind == .attachment ? $0.revision == nil : ($0.revision ?? 0) > 0)
        && seen.insert("\($0.kind.rawValue):\($0.itemID)").inserted
    }
  }
}

struct EmptyTrashOutcome: Equatable, Sendable {
  let deleted: Int
  let total: Int
  var complete: Bool { deleted == total }
  var message: String {
    complete
      ? "\(deleted) confirmed items permanently deleted. Anything added to Trash later was not included."
      : "\(deleted) of \(total) items confirmed deleted. Stopped because an item changed or a request could not be confirmed. Refresh and review Trash before trying again."
  }
  @MainActor
  static func run(
    targets: [EmptyTrashTarget],
    remove: (EmptyTrashTarget) async throws -> Void,
    progress: (Int) -> Void
  ) async -> Self {
    var deleted = 0
    for target in targets {
      if Task.isCancelled { break }
      do { try await remove(target) } catch { break }
      deleted += 1
      progress(deleted)
    }
    return Self(deleted: deleted, total: targets.count)
  }
}
