import Foundation

// Tags, like Web `apps/web/src/lib/data/organization.ts`, `organization-workspace.ts`, and
// `apps/web/src/app/organization/actions.ts`. Collections became tags with the same names.

/// One `tags_workspace` row: a tag with how many Entries outside Trash use it.
struct TagItem: Decodable, Identifiable, Hashable, Sendable {
  let id: UUID
  let name: String
  let revision: Int
  let entryCount: Int
  let totalCount: Int

  init(id: UUID, name: String, revision: Int, entryCount: Int, totalCount: Int) {
    self.id = id
    self.name = name
    self.revision = revision
    self.entryCount = entryCount
    self.totalCount = totalCount
  }

  enum CodingKeys: String, CodingKey {
    case id, name, revision
    case entryCount = "entry_count"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    revision = try values.decode(Int.self, forKey: .revision)
    entryCount = try Self.count(values, .entryCount)
    totalCount = try Self.count(values, .totalCount)
  }

  /// PostgREST writes `bigint` counts as numbers; Web also accepts them as strings.
  private static func count(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys)
    throws -> Int
  {
    if let count = try? values.decode(Int.self, forKey: key) { return count }
    return Int(try values.decode(String.self, forKey: key)) ?? 0
  }
}

/// `tags_workspace` arguments.
struct TagsPageRequest: Encodable, Equatable, Sendable {
  static let pageSize = 50

  let query: String
  let offset: Int
  var limit = pageSize

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case offset = "p_offset"
    case limit = "p_limit"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(String(query.trimmed.prefix(200)), forKey: .query)
    try values.encode(offset, forKey: .offset)
    try values.encode(limit, forKey: .limit)
  }
}

/// `save_tag`: creates a tag when `id` is nil, otherwise renames it.
struct TagSaveRequest: Encodable, Equatable, Sendable {
  let name: String
  let id: UUID?
  let expectedRevision: Int?

  /// Web `validTagInput`.
  var isValid: Bool {
    let name = name.trimmed
    return !name.isEmpty && name.count <= EntryLimits.tagName
      && (id == nil ? expectedRevision == nil : (expectedRevision ?? 0) > 0)
  }

  static let invalidMessage = "Use a tag name up to \(EntryLimits.tagName) characters."

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case id = "p_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(name.trimmed, forKey: .name)
    try values.encode(id, forKey: .id)
    try values.encode(expectedRevision, forKey: .expectedRevision)
  }
}

/// `merge_tags`: moves every Entry from the source tag to the target, then removes the source.
struct TagMergeRequest: Encodable, Equatable, Sendable {
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

/// `delete_unused_tag`: removes a tag no Entry uses.
struct TagDeleteRequest: Encodable, Equatable, Sendable {
  let id: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case id = "p_id"
    case expectedRevision = "p_expected_revision"
  }
}

/// Web `tagOptionsByUse` input: a tag name with its Entry count outside Trash.
struct TagUsageRow: Decodable, Equatable, Sendable {
  struct Count: Decodable, Equatable, Sendable {
    let count: Int
  }

  let name: String
  let entryTags: [Count]

  enum CodingKeys: String, CodingKey {
    case name
    case entryTags = "entry_tags"
  }

  /// Web `tagOptionsByUse`: most used first, then by name ignoring case.
  static func optionsByUse(_ rows: [Self]) -> [String] {
    func uses(_ row: Self) -> Int { row.entryTags.first?.count ?? 0 }
    func precedes(_ left: Self, _ right: Self) -> Bool {
      let (leftUses, rightUses) = (uses(left), uses(right))
      if leftUses != rightUses { return leftUses > rightUses }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
    return rows.sorted(by: precedes).map(\.name)
  }
}

/// Web `existingTagName`: a typed name that differs from an existing tag only by case is that
/// tag, written the way it already is.
func existingTagName(_ name: String, options: [String]) -> String {
  let trimmed = name.trimmed
  return options.first { $0.lowercased() == trimmed.lowercased() } ?? trimmed
}
