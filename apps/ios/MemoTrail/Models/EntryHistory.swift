import Foundation

/// A JSON value in a History snapshot, which keeps whatever each snapshot schema recorded.
indirect enum HistoryJSON: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: HistoryJSON])
  case array([HistoryJSON])
  case null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let v = try? value.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? value.decode(Double.self) {
      self = .number(v)
    } else if let v = try? value.decode(String.self) {
      self = .string(v)
    } else if let v = try? value.decode([String: HistoryJSON].self) {
      self = .object(v)
    } else {
      self = .array(try value.decode([HistoryJSON].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .null: try value.encodeNil()
    case .string(let v): try value.encode(v)
    case .number(let v): try value.encode(v)
    case .bool(let v): try value.encode(v)
    case .object(let v): try value.encode(v)
    case .array(let v): try value.encode(v)
    }
  }

  var text: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  var number: Int? {
    if case .number(let v) = self, v.isFinite, v >= 0, v < Double(Int.max) { return Int(v) }
    return nil
  }
  var object: [String: HistoryJSON]? {
    if case .object(let v) = self { return v }
    return nil
  }
  var array: [HistoryJSON]? {
    if case .array(let v) = self { return v }
    return nil
  }
  var isNull: Bool { self == .null }

  /// Web's `JSON.stringify(value, null, 2)`, for the collapsed snapshot details.
  var display: String {
    if let text { return text }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? ""
  }

  /// The value without the keys Web leaves out of snapshot details.
  func removingKeys(_ keys: Set<String>) -> HistoryJSON {
    switch self {
    case .object(let values):
      .object(
        values.filter { !keys.contains($0.key) }.mapValues { $0.removingKeys(keys) })
    case .array(let values): .array(values.map { $0.removingKeys(keys) })
    default: self
    }
  }
}

/// Web `HistoryIndexEntry`: one Item in Version history.
struct HistoryIndexEntry: Decodable, Identifiable, Sendable {
  let entryID: UUID
  let title: String?
  let excerpt: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let revision: Int
  let isDeleted: Bool
  let versionCount: Int
  let lastChanged: String
  let totalCount: Int

  var id: UUID { entryID }
  var displayTitle: String { HistoryPresentation.title(title: title, body: excerpt) }

  enum CodingKeys: String, CodingKey {
    case title, excerpt, revision
    case entryID = "entry_id"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case isDeleted = "is_deleted"
    case versionCount = "version_count"
    case lastChanged = "last_changed"
    case totalCount = "total_count"
  }
}

struct EntryHistoryVersion: Decodable, Identifiable, Sendable {
  let version: Int
  let operation: String
  let createdAt: String
  let snapshot: [String: HistoryJSON]

  var id: Int { version }
  var savedAt: Date? { HistoryPresentation.timestamp(createdAt) }

  enum CodingKeys: String, CodingKey {
    case version, operation, snapshot
    case createdAt = "created_at"
  }
}

/// Web `EntryHistory`: an Item's current snapshot and one page of earlier versions.
struct EntryHistoryRecord: Decodable, Sendable {
  let current: [String: HistoryJSON]
  let versions: [EntryHistoryVersion]
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case current, versions
    case totalCount = "total_count"
  }

  var title: String { HistoryPresentation.title(current) }
  var revision: Int { current["revision"]?.number ?? 0 }
  var isDeleted: Bool { current["deleted_at"]?.isNull == false }
  var itemKind: WikiItemKind? { current["item_kind"]?.text.flatMap(WikiItemKind.init(rawValue:)) }
  var itemSubtype: String { current["item_subtype"]?.text ?? "" }

  /// Web `wikiItemIdentityLabel`, such as Entry, Moment, or Bucket List.
  var identityLabel: String {
    itemKind?.displayName(subtype: itemSubtype) ?? "Item"
  }

  /// Web's provenance links: where an extracted Item came from, what it produced, and an
  /// exploration's source or saved conclusion.
  var provenanceLinks: [(targetID: UUID, title: String)] {
    (current["links"]?.array ?? []).compactMap { value in
      guard let link = value.object, let raw = link["target_entry_id"]?.text,
        let targetID = UUID(uuidString: raw), let relationship = link["relationship"]?.text
      else { return nil }
      switch relationship {
      case "derived": return (targetID, "Open extracted item")
      case "derived_from", "exploration_source": return (targetID, "Open source item")
      case "exploration_conclusion": return (targetID, "Open saved conclusion")
      default: return nil
      }
    }
  }
}

/// Web `lib/data/history.ts` presentation rules.
enum HistoryPresentation {
  /// Matches the snapshot contract accepted by `restore_entry_version`, like Web
  /// `SUPPORTED_HISTORY_SCHEMA`.
  static let supportedSchema = 3
  /// Web `UNSUPPORTED_HISTORY_RESTORE_MESSAGE`.
  static let unsupportedRestoreMessage =
    "This version was saved in a format that cannot be restored. You can still review its recorded content."

  /// Web `canRestoreHistorySnapshot`: only the schema the restore RPC accepts.
  static func canRestore(_ snapshot: [String: HistoryJSON]?) -> Bool {
    snapshot?["history_schema"] == .number(Double(supportedSchema))
  }

  /// Web `restoreHistoryVersion` messages for the restore RPC's named failures.
  static func restoreFailureMessage(_ code: String) -> String {
    switch code {
    case "history_schema_unsupported": unsupportedRestoreMessage
    case "history_reference_unavailable":
      "A linked item is missing or in Trash. Restore it first; no part of this Entry was changed."
    case "history_attachment_unavailable":
      "An original photo is no longer available. Nothing was restored."
    case "history_details_unavailable":
      "This early version did not record the specialized details needed for a safe restore."
    default: "Could not restore this version. Your current Entry is unchanged."
    }
  }

  /// Web `historyFields`, in order, with the names shown for differences.
  static let fields: [(key: String, label: String)] = [
    ("title", "Title"), ("body", "Writing"), ("item_kind", "Kind"), ("item_subtype", "Subtype"),
    ("inbox_status", "Inbox status"), ("occurred_start", "Start date"),
    ("occurred_end", "End date"), ("date_precision", "Date precision"),
    ("occurred_label", "Date description"), ("occurred_timezone", "Time zone"),
    ("collections", "Collections"), ("tags", "Tags"), ("people", "People links"),
    ("places", "Location links"), ("timeline_items", "Timeline placement"),
    ("home", "Home details"), ("vehicle", "Vehicle details"), ("goal", "Goal details"),
    ("links", "Entry links"), ("attachments", "Photos"), ("metadata", "Other metadata"),
    ("source_language", "Language"),
  ]

  /// Relationship groups a snapshot lists by name.
  static let relationshipGroups = ["collections", "tags", "people", "places", "timeline_items"]

  /// Web `historyTitle`.
  static func title(title: String?, body: String?) -> String {
    title?.trimmed.nonEmpty ?? String((body ?? "").trimmed.prefix(80)).nonEmpty
      ?? "Untitled item"
  }

  static func title(_ snapshot: [String: HistoryJSON]) -> String {
    title(title: snapshot["title"]?.text, body: snapshot["body"]?.text)
  }

  /// Web `historyDateLabel`: the date description, else the dates in the record's time zone.
  static func date(_ snapshot: [String: HistoryJSON]) -> String {
    if let label = snapshot["occurred_label"]?.text?.trimmed.nonEmpty { return label }
    guard let raw = snapshot["occurred_start"]?.text else { return "Unknown" }
    let timeZone =
      TimeZone(identifier: snapshot["occurred_timezone"]?.text ?? "UTC") ?? .gmt
    let precision = snapshot["date_precision"]?.text
    func style(_ style: Date.FormatStyle) -> Date.FormatStyle {
      var style = style
      style.timeZone = timeZone
      style.locale = Locale(identifier: "en_US")
      return style
    }
    func format(_ raw: String) -> String {
      guard let date = timestamp(raw) else { return "Unknown" }
      switch precision {
      case "year": return date.formatted(style(Date.FormatStyle().year()))
      case "month": return date.formatted(style(Date.FormatStyle().month(.abbreviated).year()))
      case "exact":
        // Web's `dateStyle: "medium", timeStyle: "short"`, such as "Jan 1, 2021, 3:30 PM".
        return date.formatted(style(Date.FormatStyle(date: .abbreviated, time: .omitted)))
          + ", " + date.formatted(style(Date.FormatStyle(date: .omitted, time: .shortened)))
      default: return date.formatted(style(Date.FormatStyle(date: .abbreviated, time: .omitted)))
      }
    }
    return format(raw) + (snapshot["occurred_end"]?.text.map { " to \(format($0))" } ?? "")
  }

  /// Web `historyDifferences`: the fields an earlier version recorded differently.
  static func differences(current: [String: HistoryJSON], previous: [String: HistoryJSON])
    -> [String]
  {
    fields.filter { previous[$0.key] != nil && current[$0.key] != previous[$0.key] }.map(\.label)
  }

  /// The names in a snapshot's relationship list, like Web's snapshot facts.
  static func names(_ values: [HistoryJSON]) -> String {
    values.compactMap { value in
      let item = value.object ?? [:]
      return ["name", "track_name", "original_filename", "id", "person_id", "place_id"]
        .lazy.compactMap { item[$0]?.text }.first
    }.joined(separator: ", ")
  }

  /// The snapshot's Web formatting from `metadata.body_rich`, when it still matches the body.
  static func richText(_ snapshot: [String: HistoryJSON]) -> EntryRichText? {
    guard let value = snapshot["metadata"]?.object?[EntryRichText.metadataKey],
      let data = try? JSONEncoder().encode(value),
      let richText = try? JSONDecoder().decode(EntryRichText.self, from: data),
      richText.isValid(expectedText: snapshot["body"]?.text ?? "")
    else { return nil }
    return richText
  }

  static func timestamp(_ raw: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = parser.date(from: raw) { return date }
    parser.formatOptions = [.withInternetDateTime]
    return parser.date(from: raw)
  }
}

struct HistoryIndexRequest: Encodable {
  let query: String
  let limit: Int
  let offset: Int
  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

struct HistoryReadRequest: Encodable {
  let entryID: UUID
  let limit: Int
  let offset: Int
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

struct HistoryRestoreRequest: Encodable {
  let entryID: UUID
  let version: Int
  let expectedRevision: Int
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case version = "p_version"
    case expectedRevision = "p_expected_revision"
  }
}

struct GoalExtractionRequest: Encodable {
  let sourceEntryID: UUID
  let sourceRevision: Int
  let goalID: UUID
  let title: String
  let horizon: GoalHorizon
  let status: GoalStatus
  let targetDate: String?

  var isValid: Bool {
    sourceRevision > 0 && sourceEntryID != goalID && !title.trimmed.isEmpty
      && title.trimmed.count <= 200
      && (targetDate.map(GoalCalendarDate.isValid) ?? true)
  }

  enum CodingKeys: String, CodingKey {
    case sourceEntryID = "p_source_entry_id"
    case sourceRevision = "p_source_revision"
    case goalID = "p_goal_id"
    case title = "p_title"
    case horizon = "p_horizon"
    case status = "p_status"
    case targetDate = "p_target_date"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(sourceEntryID, forKey: .sourceEntryID)
    try values.encode(sourceRevision, forKey: .sourceRevision)
    try values.encode(goalID, forKey: .goalID)
    try values.encode(title.trimmed, forKey: .title)
    try values.encode(horizon, forKey: .horizon)
    try values.encode(status, forKey: .status)
    if let targetDate {
      try values.encode(targetDate, forKey: .targetDate)
    } else {
      try values.encodeNil(forKey: .targetDate)
    }
  }
}

struct ExtractedGoalFromItem: Decodable, Equatable, Sendable {
  let sourceEntryID: UUID
  let sourceRevision: Int
  let goalEntryID: UUID
  let goalRevision: Int

  enum CodingKeys: String, CodingKey {
    case sourceEntryID = "source_entry_id"
    case sourceRevision = "source_revision"
    case goalEntryID = "goal_entry_id"
    case goalRevision = "goal_revision"
  }
}
