import Foundation

enum TrashItemKind: String, Codable, Equatable, Hashable, Sendable {
  case attachment
  case entry
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
    if kind == .entry, wikiItemKind == .entry, wikiItemSubtype == "first_time" {
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

  /// Web `retentionLabel`: how long the item stays restorable, and the date it runs through.
  func retention(referenceDate: Date = Date()) -> (status: String, date: String?) {
    guard let expirationDate = TrashTimestamp.date(from: expiresAt) else {
      return ("Retention date unavailable", nil)
    }

    let remainingDays = Int(ceil(expirationDate.timeIntervalSince(referenceDate) / 86_400))
    guard remainingDays > 0 else {
      return ("Eligible for cleanup since", expirationDateLabel)
    }
    return ("\(countLabel(remainingDays, "day")) to restore · through", expirationDateLabel)
  }

  /// Web `deletionDescription`: what Delete forever removes.
  var deletionDescription: String {
    switch kind {
    case .collection:
      "Only the Collection and its grouping links will be removed. Your Entries and photos stay in the archive."
    case .attachment:
      "The private photo file and its attachment record will be removed."
    case .person:
      "The Person and their version history will be removed."
    case .entry:
      "The Entry, private photos, relationships, specialized details, and version history will be removed."
    }
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

/// Web `media-purge`: the private photo files of items already deleted forever.
enum MediaPurge {
  static let batchSize = 100
  static let pendingMessage =
    "MemoTrail will finish removing private photo files the next time you open Trash."

  struct Request: Encodable, Sendable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
      case limit = "p_limit"
    }
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
  /// Whether the private photo files of the deleted items are already removed.
  var filesRemoved = true
  var complete: Bool { deleted == total }
  var message: String {
    let message =
      complete
      ? "\(countLabel(deleted, "confirmed item")) permanently deleted. Anything added to Trash later was not included."
      : "\(deleted) of \(countLabel(total, "item")) confirmed deleted. Stopped because an item changed or a request could not be confirmed. Refresh and review Trash before trying again."
    return filesRemoved ? message : "\(message) \(MediaPurge.pendingMessage)"
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
