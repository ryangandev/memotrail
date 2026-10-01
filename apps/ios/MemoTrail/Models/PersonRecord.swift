import Foundation

/// Web `PersonEntry`: an Item linked to a Person, or one offered for linking. Existing links to
/// Items in Trash are kept so they can be removed explicitly.
struct PersonLinkedEntry: Decodable, Identifiable, Hashable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let isDeleted: Bool

  enum CodingKeys: String, CodingKey {
    case id, title, body
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case isDeleted = "is_deleted"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    itemKind = try values.decode(WikiItemKind.self, forKey: .itemKind)
    itemSubtype = try values.decode(String.self, forKey: .itemSubtype)
    // Link choices come from active Items, which omit the flag.
    isDeleted = try values.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
  }

  /// Web `personEntryTitle`.
  var displayTitle: String {
    title?.trimmed.nonEmpty ?? body.trimmed.nonEmpty.map { String($0.prefix(80)) }
      ?? "Untitled Entry"
  }
}

/// Web `Person`: one row of `people_workspace` or `person_record`.
struct PersonRecord: Decodable, Identifiable, Hashable, Sendable {
  let id: UUID
  let name: String
  let relationshipLabel: String?
  let notes: String?
  let revision: Int
  let linkedEntries: [PersonLinkedEntry]
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case id, name, notes, revision
    case relationshipLabel = "relationship_label"
    case linkedEntries = "linked_entries"
    case totalCount = "total_count"
  }
}

/// Web `parsePersonInput` and the `save_person` parameters.
struct PersonSaveInput: Encodable, Sendable {
  static let nameLimit = 200
  static let relationshipLimit = 200
  static let notesLimit = 10_000
  static let linkLimit = 100
  static let invalidMessage =
    "Add a name of up to 200 characters, a relationship up to 200, notes up to 10,000, and at most 100 Item links."

  let personID: UUID?
  let expectedRevision: Int?
  let name: String
  let relationshipLabel: String
  let notes: String
  let relatedEntryIDs: [UUID]

  var isValid: Bool {
    !name.trimmed.isEmpty && name.trimmed.count <= Self.nameLimit
      && relationshipLabel.count <= Self.relationshipLimit
      && notes.count <= Self.notesLimit && relatedEntryIDs.count <= Self.linkLimit
      && ((personID == nil && expectedRevision == nil)
        || (personID != nil && (expectedRevision ?? 0) > 0))
  }

  enum CodingKeys: String, CodingKey {
    case personID = "p_person_id"
    case expectedRevision = "p_expected_revision"
    case name = "p_name"
    case relationshipLabel = "p_relationship_label"
    case notes = "p_notes"
    case relatedEntryIDs = "p_related_entry_ids"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(personID, forKey: .personID)
    try values.encode(expectedRevision, forKey: .expectedRevision)
    try values.encode(name.trimmed, forKey: .name)
    try values.encode(relationshipLabel.trimmed, forKey: .relationshipLabel)
    try values.encode(notes.trimmed, forKey: .notes)
    // Like Web, each Item is linked once.
    var seen = Set<UUID>()
    try values.encode(relatedEntryIDs.filter { seen.insert($0).inserted }, forKey: .relatedEntryIDs)
  }
}
