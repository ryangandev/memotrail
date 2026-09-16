import Foundation

enum GoalHorizon: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case shortTerm = "short_term"
  case longTerm = "long_term"
  case someday

  var displayName: String {
    switch self {
    case .shortTerm: "Short-term"
    case .longTerm: "Long-term"
    case .someday: "Someday"
    }
  }
}

enum GoalStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case considering
  case active
  case paused
  case achieved
  case letGo = "let_go"

  var displayName: String {
    switch self {
    case .considering: "Considering"
    case .active: "Active"
    case .paused: "Paused"
    case .achieved: "Achieved"
    case .letGo: "Let go"
    }
  }
}

typealias GoalAchievementPrecision = TimelineDatePrecision

typealias GoalAttachment = ResidenceAttachment

struct GoalRelatedEntry: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let entryType: String
  let occurredStart: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date
  let relationship: String

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case entryType = "entry_type"
    case occurredStart = "occurred_start"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case updatedAt = "updated_at"
    case relationship
  }

  var displayTitle: String {
    if let title = title?.trimmed.nonEmpty { return title }
    let body = body.trimmed
    guard !body.isEmpty else { return "Untitled Entry" }
    return body.count > 80 ? "\(body.prefix(80).trimmingCharacters(in: .whitespaces))..." : body
  }
}

struct GoalEntry: Equatable, Hashable, Identifiable, Sendable {
  var bucketListRole: Bool? = nil
  let id: UUID
  let title: String
  let body: String
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let horizon: GoalHorizon
  let status: GoalStatus
  let targetDate: String?
  let collectionNames: [String]
  let tagNames: [String]
  let relatedEntries: [GoalRelatedEntry]
  var attachments: [GoalAttachment]
  let totalCount: Int

  var isBucketList: Bool {
    bucketListRole ?? collectionNames.contains { $0.trimmed.lowercased() == "bucket list" }
  }

  var editableRelatedEntries: [GoalRelatedEntry] {
    relatedEntries.filter { $0.relationship == "related" }
  }

  var achievementEntries: [GoalRelatedEntry] {
    relatedEntries.filter { $0.relationship == "achievement" }
  }

  var targetLabel: String {
    guard let targetDate, let date = GoalCalendarDate.date(from: targetDate) else {
      return "No target date"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .gmt
    formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    return "Target \(formatter.string(from: date))"
  }
}

struct GoalWorkspaceRow: Decodable, Equatable, Sendable {
  var bucketListRole: Bool? = nil
  let entryID: UUID
  let title: String
  let body: String
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let horizon: GoalHorizon
  let status: GoalStatus
  let targetDate: String?
  let collectionNames: [String]
  let tagNames: [String]
  let relatedEntries: [GoalRelatedEntry]
  let attachments: [GoalAttachment]
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case bucketListRole = "is_bucket_list"
    case entryID = "entry_id"
    case title
    case body
    case revision
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case horizon
    case status
    case targetDate = "target_date"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case relatedEntries = "related_entries"
    case attachments
    case totalCount = "total_count"
  }

  var entry: GoalEntry {
    GoalEntry(
      bucketListRole: bucketListRole,
      id: entryID,
      title: title,
      body: body,
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      horizon: horizon,
      status: status,
      targetDate: targetDate,
      collectionNames: collectionNames,
      tagNames: tagNames,
      relatedEntries: relatedEntries,
      attachments: attachments,
      totalCount: totalCount
    )
  }
}

enum GoalWorkspace {
  static func entries(from rows: [GoalWorkspaceRow]) -> [GoalEntry] {
    rows.map(\.entry).sorted(by: sortsBefore)
  }

  static func entries(_ entries: [GoalEntry], matching statuses: Set<GoalStatus>) -> [GoalEntry] {
    entries.filter { statuses.contains($0.status) }.sorted(by: sortsBefore)
  }

  private static func sortsBefore(_ first: GoalEntry, _ second: GoalEntry) -> Bool {
    if first.status.sortOrder != second.status.sortOrder {
      return first.status.sortOrder < second.status.sortOrder
    }
    if first.targetDate != second.targetDate {
      switch (first.targetDate, second.targetDate) {
      case (.some(let firstDate), .some(let secondDate)): return firstDate < secondDate
      case (.some, .none): return true
      case (.none, .some): return false
      case (.none, .none): break
      }
    }
    if first.updatedAt != second.updatedAt { return first.updatedAt > second.updatedAt }
    let titleOrder = first.title.localizedCaseInsensitiveCompare(second.title)
    return titleOrder == .orderedSame
      ? first.id.uuidString < second.id.uuidString : titleOrder == .orderedAscending
  }
}

extension GoalStatus {
  fileprivate var sortOrder: Int {
    switch self {
    case .active: 10
    case .considering: 20
    case .paused: 30
    case .achieved: 40
    case .letGo: 50
    }
  }
}

struct GoalLinkOption: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String?
  let entryType: String
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case entryType = "entry_type"
    case updatedAt = "updated_at"
  }

  var displayTitle: String {
    if let title = title?.trimmed.nonEmpty { return title }
    let body = body?.trimmed ?? ""
    guard !body.isEmpty else { return "Untitled Entry" }
    return body.count > 80 ? "\(body.prefix(80).trimmingCharacters(in: .whitespaces))..." : body
  }
}

struct GoalEntryInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000
  static let collectionLimit = 20
  static let collectionNameLimit = 80
  static let tagLimit = 50
  static let tagNameLimit = 60
  static let relatedEntryLimit = 100

  let entryID: UUID?
  var expectedRevision: Int?
  let title: String
  let body: String
  let horizon: GoalHorizon
  let status: GoalStatus
  let targetDate: String?
  let collectionNames: [String]
  let tagNames: [String]
  let relatedEntryIDs: [UUID]

  static func validate(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    horizon: GoalHorizon,
    status: GoalStatus,
    targetDate: String?,
    collectionNames: [String],
    tagNames: [String],
    relatedEntryIDs: [UUID]
  ) throws -> GoalEntryInput {
    let title = title.trimmed
    let body = body.trimmed
    let targetDate = targetDate?.trimmed.nonEmpty

    guard !title.isEmpty else { throw GoalEntryError.titleRequired }
    guard title.count <= titleLimit else { throw GoalEntryError.titleTooLong }
    guard body.count <= bodyLimit else { throw GoalEntryError.bodyTooLong }
    guard targetDate.map(GoalCalendarDate.isValid) ?? true else {
      throw GoalEntryError.invalidTargetDate
    }
    guard
      (entryID == nil && expectedRevision == nil)
        || (entryID != nil && (expectedRevision ?? 0) > 0)
    else { throw GoalEntryError.invalidRevision }
    guard
      let collectionNames = normalizeNames(
        collectionNames,
        maximumCount: collectionLimit,
        maximumNameLength: collectionNameLimit
      )
    else { throw GoalEntryError.invalidCollections }
    guard
      let tagNames = normalizeNames(
        tagNames,
        maximumCount: tagLimit,
        maximumNameLength: tagNameLimit
      )
    else { throw GoalEntryError.invalidTags }
    let relatedEntryIDs = uniqueIDs(relatedEntryIDs)
    guard relatedEntryIDs.count <= relatedEntryLimit,
      !relatedEntryIDs.contains(where: { $0 == entryID })
    else { throw GoalEntryError.invalidRelatedEntries }

    return GoalEntryInput(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      horizon: horizon,
      status: status,
      targetDate: targetDate,
      collectionNames: collectionNames,
      tagNames: tagNames,
      relatedEntryIDs: relatedEntryIDs
    )
  }

  private static func normalizeNames(
    _ values: [String],
    maximumCount: Int,
    maximumNameLength: Int
  ) -> [String]? {
    guard values.count <= maximumCount else { return nil }
    var names: [String] = []
    var normalizedNames: Set<String> = []
    for value in values {
      let name = value.trimmed
      guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
      if normalizedNames.insert(name.lowercased()).inserted { names.append(name) }
    }
    return names
  }

  private static func uniqueIDs(_ values: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return values.filter { seen.insert($0).inserted }
  }
}

struct SaveGoalEntryParameters: Encodable, Equatable, Sendable {
  let input: GoalEntryInput
  let source: CaptureExtractionSource?

  init(input: GoalEntryInput, source: CaptureExtractionSource? = nil) {
    self.input = input
    self.source = source
  }

  enum CodingKeys: String, CodingKey {
    case captureID = "p_capture_id"
    case captureRevision = "p_capture_revision"
    case title = "p_title"
    case body = "p_body"
    case horizon = "p_horizon"
    case status = "p_status"
    case targetDate = "p_target_date"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case relatedEntryIDs = "p_related_entry_ids"
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    if let source {
      try values.encode(source.entryID, forKey: .captureID)
      try values.encode(source.revision, forKey: .captureRevision)
    }
    try values.encode(input.title, forKey: .title)
    try values.encode(input.body, forKey: .body)
    try values.encode(input.horizon, forKey: .horizon)
    try values.encode(input.status, forKey: .status)
    try values.encode(input.collectionNames, forKey: .collectionNames)
    try values.encode(input.tagNames, forKey: .tagNames)
    try values.encode(input.relatedEntryIDs, forKey: .relatedEntryIDs)
    try encodeNullable(input.targetDate, forKey: .targetDate, into: &values)
    if source == nil {
      try encodeNullable(input.entryID, forKey: .entryID, into: &values)
      try encodeNullable(input.expectedRevision, forKey: .expectedRevision, into: &values)
    }
  }

  private func encodeNullable<T: Encodable>(
    _ value: T?,
    forKey key: CodingKeys,
    into values: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if let value {
      try values.encode(value, forKey: key)
    } else {
      try values.encodeNil(forKey: key)
    }
  }
}

struct ExtractedCaptureGoal: Decodable, Equatable, Sendable {
  let captureID: UUID
  let captureRevision: Int
  let goalEntryID: UUID
  let goalRevision: Int

  enum CodingKeys: String, CodingKey {
    case captureID = "capture_id"
    case captureRevision = "capture_revision"
    case goalEntryID = "goal_entry_id"
    case goalRevision = "goal_revision"
  }
}

struct SavedGoalEntry: Decodable, Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let wasCreated: Bool

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
    case wasCreated = "was_created"
  }
}

struct TrashGoalEntryParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TrashedGoalEntry: Decodable, Sendable {
  let entryID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
  }
}

struct GoalAchievementInput: Equatable, Sendable {
  static let labelLimit = 200

  let goalEntryID: UUID
  let expectedRevision: Int
  let occurredStart: Date?
  let datePrecision: GoalAchievementPrecision
  let occurredLabel: String?
  let occurredTimezone: String
  var occurredEnd: Date? = nil

  static func validate(
    goalEntryID: UUID,
    expectedRevision: Int,
    occurredStart: Date?,
    datePrecision: GoalAchievementPrecision,
    occurredLabel: String,
    occurredTimezone: String,
    occurredEnd: Date? = nil
  ) throws -> GoalAchievementInput {
    let occurredLabel = occurredLabel.trimmed.nonEmpty
    let occurredTimezone = occurredTimezone.trimmed
    guard expectedRevision > 0 else { throw GoalEntryError.invalidRevision }
    guard (occurredLabel?.count ?? 0) <= labelLimit else {
      throw GoalEntryError.achievementLabelTooLong
    }
    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100,
      TimeZone(identifier: occurredTimezone) != nil
    else { throw GoalEntryError.invalidTimezone }
    try EntryOccurrence(
      precision: datePrecision, start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone
    ).validate()
    return GoalAchievementInput(
      goalEntryID: goalEntryID,
      expectedRevision: expectedRevision,
      occurredStart: occurredStart,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      occurredEnd: occurredEnd
    )
  }
}

struct GoalAchievementParameters: Encodable, Equatable, Sendable {
  let input: GoalAchievementInput

  enum CodingKeys: String, CodingKey {
    case goalEntryID = "p_goal_entry_id"
    case expectedRevision = "p_expected_revision"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case datePrecision = "p_date_precision"
    case occurredLabel = "p_occurred_label"
    case occurredTimezone = "p_occurred_timezone"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.goalEntryID, forKey: .goalEntryID)
    try values.encode(input.expectedRevision, forKey: .expectedRevision)
    if let start = input.occurredStart {
      try values.encode(start, forKey: .occurredStart)
    } else {
      try values.encodeNil(forKey: .occurredStart)
    }
    if let end = input.occurredEnd {
      try values.encode(end, forKey: .occurredEnd)
    } else {
      try values.encodeNil(forKey: .occurredEnd)
    }
    try values.encode(input.datePrecision, forKey: .datePrecision)
    try values.encode(input.occurredTimezone, forKey: .occurredTimezone)
    if let occurredLabel = input.occurredLabel {
      try values.encode(occurredLabel, forKey: .occurredLabel)
    } else {
      try values.encodeNil(forKey: .occurredLabel)
    }
  }
}

struct AchievedGoalEntry: Decodable, Equatable, Sendable {
  let goalEntryID: UUID
  let goalRevision: Int
  let firstTimeEntryID: UUID

  enum CodingKeys: String, CodingKey {
    case goalEntryID = "goal_entry_id"
    case goalRevision = "goal_revision"
    case firstTimeEntryID = "first_time_entry_id"
  }
}

enum GoalCalendarDate {
  static func string(from date: Date) -> String {
    makeFormatter().string(from: date)
  }

  static func date(from value: String) -> Date? {
    makeFormatter().date(from: value)
  }

  static func isValid(_ value: String) -> Bool {
    date(from: value).map { string(from: $0) == value } ?? false
  }

  private static func makeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter
  }
}

enum GoalEntryError: LocalizedError, Equatable {
  case achievementLabelTooLong
  case bodyTooLong
  case invalidAchievementDate
  case invalidCollections
  case invalidRelatedEntries
  case invalidRevision
  case invalidTags
  case invalidTargetDate
  case invalidTimezone
  case titleRequired
  case titleTooLong

  var errorDescription: String? {
    switch self {
    case .achievementLabelTooLong:
      "Human date labels can be up to \(GoalAchievementInput.labelLimit) characters."
    case .bodyTooLong: "Reflections can be up to \(GoalEntryInput.bodyLimit) characters."
    case .invalidAchievementDate: "Choose a valid achievement date."
    case .invalidCollections: "Use up to 20 Collections with names under 80 characters."
    case .invalidRelatedEntries: "Link up to 100 other Entries, excluding this Goal."
    case .invalidRevision: "This Goal version is invalid. Refresh and try again."
    case .invalidTags: "Use up to 50 tags with names under 60 characters."
    case .invalidTargetDate: "Choose a valid target date or leave it empty."
    case .invalidTimezone: "Choose a valid occurrence time zone."
    case .titleRequired: "Add a title for this Goal."
    case .titleTooLong: "Goal titles can be up to \(GoalEntryInput.titleLimit) characters."
    }
  }
}
