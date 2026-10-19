import Foundation

/// What Trash holds, like Web `TrashItemKind`: Entries and single photos.
enum TrashItemKind: String, Codable, Equatable, Hashable, Sendable {
  case attachment
  case entry

  var displayName: String {
    switch self {
    case .attachment: "Photo"
    case .entry: "Entry"
    }
  }

  var systemImage: String {
    switch self {
    case .attachment: "photo"
    case .entry: "text.line.first.and.arrowtriangle.forward"
    }
  }
}

/// One `trash_workspace` row, like Web `TrashItem` in `apps/web/src/lib/data/trash.ts`. Each row
/// carries its Entry's stored title and date, an Entry's own or the Entry a photo belongs to,
/// so an untitled Entry is named by its date.
struct TrashItem: Decodable, Equatable, Identifiable, Sendable {
  let kind: TrashItemKind
  let itemID: UUID
  /// The stored row title: a photo's file name, or the Entry's title.
  let storedTitle: String
  let storedDetail: String?
  let entryTitle: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let datePrecision: DatePrecision
  let deletedAt: String
  let expiresAt: String
  let revision: Int?
  let wikiItemSubtype: String?
  let parentEntryID: UUID?
  let storagePaths: [String]
  let totalCount: Int
  var signedURL: URL?

  enum CodingKeys: String, CodingKey {
    case kind = "item_kind"
    case itemID = "item_id"
    case storedTitle = "title"
    case storedDetail = "detail"
    case entryTitle = "entry_title"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case deletedAt = "deleted_at"
    case expiresAt = "expires_at"
    case revision
    case wikiItemSubtype = "wiki_item_subtype"
    case parentEntryID = "parent_entry_id"
    case storagePaths = "storage_paths"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(TrashItemKind.self, forKey: .kind)
    itemID = try values.decode(UUID.self, forKey: .itemID)
    storedTitle = try values.decodeIfPresent(String.self, forKey: .storedTitle) ?? ""
    storedDetail = try values.decodeIfPresent(String.self, forKey: .storedDetail)
    entryTitle = try values.decodeIfPresent(String.self, forKey: .entryTitle) ?? ""
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    deletedAt = try values.decode(String.self, forKey: .deletedAt)
    expiresAt = try values.decode(String.self, forKey: .expiresAt)
    revision = try values.decodeIfPresent(Int.self, forKey: .revision)
    wikiItemSubtype = try values.decodeIfPresent(String.self, forKey: .wikiItemSubtype)
    parentEntryID = try values.decodeIfPresent(UUID.self, forKey: .parentEntryID)
    storagePaths = try values.decodeIfPresent([String].self, forKey: .storagePaths) ?? []
    if let count = try? values.decode(Int.self, forKey: .totalCount) {
      totalCount = count
    } else {
      totalCount = Int(try values.decode(String.self, forKey: .totalCount)) ?? 0
    }
  }

  var id: String {
    "\(kind.rawValue)-\(itemID.uuidString.lowercased())"
  }

  /// The Entry's name: its title, or its date in its recorded zone.
  var entryDisplayName: String {
    entryDisplayTitle(
      entryTitle,
      EntryOccurrence(
        storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
        label: occurredLabel, timezone: occurredTimezone))
  }

  /// Web `itemFromRow`: a photo keeps its file name, an Entry is named like everywhere else.
  var title: String { kind == .attachment ? storedTitle : entryDisplayName }

  /// Web `itemFromRow`: a photo says which Entry it came from.
  var detail: String? {
    kind == .attachment ? "Photo from \(entryDisplayName)" : storedDetail
  }

  var displayKind: String {
    kind == .entry && wikiItemSubtype == EntrySubtype.chapter.rawValue
      ? "Chapter" : kind.displayName
  }

  var displayDetail: String? {
    detail?.trimmed.nonEmpty.flatMap { $0 == title ? nil : $0 }
  }

  /// Web `trashDate`: when the item was moved to Trash, in the profile time zone.
  func deletionDateLabel(timezone: String = TimeZone.current.identifier) -> String {
    Self.displayDate(deletedAt, timezone: timezone)
  }

  func expirationDateLabel(timezone: String = TimeZone.current.identifier) -> String {
    Self.displayDate(expiresAt, timezone: timezone)
  }

  /// Web `trashRetention`: how long the item stays restorable, and the date it runs through.
  func retention(referenceDate: Date = Date(), timezone: String = TimeZone.current.identifier)
    -> (status: String, date: String?)
  {
    guard let expirationDate = EntryTimestamp.date(from: expiresAt) else {
      return ("Retention date unavailable", nil)
    }
    let label = expirationDateLabel(timezone: timezone)
    let remainingDays = Int(ceil(expirationDate.timeIntervalSince(referenceDate) / 86_400))
    guard remainingDays > 0 else { return ("Eligible for cleanup since", label) }
    return ("\(countLabel(remainingDays, "day")) to restore · through", label)
  }

  /// Web `deletionDescription`: what Delete forever removes.
  var deletionDescription: String {
    switch kind {
    case .attachment:
      "The private photo file and its attachment record will be removed."
    case .entry:
      "The Entry, private photos, relationships, and specialized details will be removed."
    }
  }

  /// Web `trashDate`: en-US "MMM d, yyyy" in the given zone, UTC when it is not valid.
  static func displayDate(_ timestamp: String, timezone: String) -> String {
    guard let date = EntryTimestamp.date(from: timestamp) else { return "Date unavailable" }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone =
      EntryOccurrence.validTimezone(timezone).flatMap(TimeZone.init(identifier:)) ?? .gmt
    formatter.dateFormat = "MMM d, yyyy"
    return formatter.string(from: date)
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
      EntryTimestamp.date(from: $0.deletedAt) != nil
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
