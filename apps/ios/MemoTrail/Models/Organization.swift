import Foundation

/// Web `OrganizationKind`: a curated Collection or a lightweight tag.
enum OrganizationKind: String, CaseIterable, Identifiable, Sendable {
  case collection, tag

  var id: String { rawValue }
  /// Web's `label`, such as "New Tag" or "Collection saved.".
  var label: String { self == .collection ? "Collection" : "Tag" }
  /// Web `validOrganizationInput`: tags up to 60 characters, Collections up to 80.
  var nameLimit: Int { self == .collection ? 80 : 60 }
}

/// Web `OrganizationItem`: one Collection or tag with how many Entries use it.
struct OrganizationItem: Decodable, Identifiable, Hashable, Sendable {
  let id: UUID
  let name: String
  let systemKey: String?
  let sortOrder: Int
  let revision: Int
  let entryCount: Int
  let totalCount: Int

  var isBucketList: Bool { systemKey == "bucket_list" }

  enum CodingKeys: String, CodingKey {
    case id, name, revision
    case systemKey = "system_key"
    case sortOrder = "sort_order"
    case entryCount = "entry_count"
    case totalCount = "total_count"
  }
}

struct OrganizationReadRequest: Encodable {
  static let pageSize = 50

  let kind: OrganizationKind
  let query: String
  let offset: Int
  var limit = pageSize

  enum CodingKeys: String, CodingKey {
    case kind = "p_kind"
    case query = "p_query"
    case offset = "p_offset"
    case limit = "p_limit"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind.rawValue, forKey: .kind)
    try values.encode(String(query.trimmed.prefix(200)), forKey: .query)
    try values.encode(offset, forKey: .offset)
    try values.encode(limit, forKey: .limit)
  }
}

/// Web `OrganizationInput` for `save_organization`.
struct OrganizationSaveRequest: Encodable, Equatable {
  static let orderLimit = 1_000_000

  let kind: OrganizationKind
  let name: String
  let sortOrder: Int
  let id: UUID?
  let expectedRevision: Int?

  /// Web `validOrganizationInput`.
  var isValid: Bool {
    let name = name.trimmed
    return !name.isEmpty && name.unicodeScalars.count <= kind.nameLimit
      && abs(sortOrder) <= Self.orderLimit && (kind != .tag || sortOrder == 0)
      && (id == nil ? expectedRevision == nil : (expectedRevision ?? 0) > 0)
  }

  /// Web `saveOrganization`'s message for an invalid form.
  var invalidMessage: String {
    kind == .tag
      ? "Use a tag name up to 60 characters."
      : "Use a Collection name up to 80 characters and a valid whole-number order."
  }

  enum CodingKeys: String, CodingKey {
    case kind = "p_kind"
    case name = "p_name"
    case sortOrder = "p_sort_order"
    case id = "p_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind.rawValue, forKey: .kind)
    try values.encode(name.trimmed, forKey: .name)
    try values.encode(sortOrder, forKey: .sortOrder)
    try values.encode(id, forKey: .id)
    try values.encode(expectedRevision, forKey: .expectedRevision)
  }
}

struct CollectionTrashRequest: Encodable {
  let id: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case id = "p_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TagMergeRequest: Encodable {
  let sourceID: UUID
  let sourceRevision: Int
  let targetID: UUID
  let targetRevision: Int

  var isValid: Bool { sourceID != targetID && sourceRevision > 0 && targetRevision > 0 }

  enum CodingKeys: String, CodingKey {
    case sourceID = "p_source_id"
    case sourceRevision = "p_source_revision"
    case targetID = "p_target_id"
    case targetRevision = "p_target_revision"
  }
}
