import Foundation

struct InboxEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let collectionNames: [String]
  let entryType: InboxEntryType
  let createdAt: Date
  let occurredStart: Date?
  let occurredTimezone: String?
  let revision: Int
  let tagNames: [String]

  init(
    id: UUID,
    title: String?,
    body: String,
    collectionNames: [String] = [],
    entryType: InboxEntryType = .standard,
    createdAt: Date,
    occurredStart: Date?,
    occurredTimezone: String? = nil,
    revision: Int = 1,
    tagNames: [String] = []
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.collectionNames = collectionNames
    self.entryType = entryType
    self.createdAt = createdAt
    self.occurredStart = occurredStart
    self.occurredTimezone = occurredTimezone
    self.revision = revision
    self.tagNames = tagNames
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case entryType = "entry_type"
    case createdAt = "created_at"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case revision
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decode(String.self, forKey: .body)
    collectionNames = []
    entryType = try values.decode(InboxEntryType.self, forKey: .entryType)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    occurredStart = try values.decodeIfPresent(Date.self, forKey: .occurredStart)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    tagNames = []
  }

  func withOrganization(collectionNames: [String], tagNames: [String]) -> InboxEntry {
    InboxEntry(
      id: id,
      title: title,
      body: body,
      collectionNames: collectionNames,
      entryType: entryType,
      createdAt: createdAt,
      occurredStart: occurredStart,
      occurredTimezone: occurredTimezone,
      revision: revision,
      tagNames: tagNames
    )
  }

  var displayDate: String {
    (occurredStart ?? createdAt).formatted(
      .dateTime
        .month(.abbreviated)
        .day()
        .year()
        .hour()
        .minute()
    )
  }

  var displayTitle: String {
    if let title = title?.trimmed.nonEmpty {
      return title
    }

    let firstLine =
      body.trimmed
      .split(whereSeparator: \Character.isNewline)
      .first
      .map(String.init)?
      .trimmed ?? ""

    return firstLine.nonEmpty.map { $0.truncated(to: 90) } ?? "Untitled Entry"
  }

  var displayExcerpt: String? {
    let trimmedBody = body.trimmed
    guard !trimmedBody.isEmpty else { return nil }

    if title?.trimmed.nonEmpty != nil {
      return trimmedBody.truncated(to: 280)
    }

    if let firstNewline = trimmedBody.firstIndex(where: \Character.isNewline) {
      let remainder = trimmedBody[trimmedBody.index(after: firstNewline)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return remainder.nonEmpty?.truncated(to: 280)
    }

    guard trimmedBody.count > 90 else { return nil }
    let remainingIndex = trimmedBody.index(trimmedBody.startIndex, offsetBy: 90)
    return String(trimmedBody[remainingIndex...]).trimmed.truncated(to: 280)
  }
}

enum InboxEntryType: String, CaseIterable, Codable, Equatable, Sendable {
  case standard
  case firstTime = "first_time"

  var displayName: String {
    switch self {
    case .standard:
      "Standard Entry"
    case .firstTime:
      "First Time"
    }
  }
}

struct InboxCapture: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000

  let title: String?
  let body: String

  static func validate(title: String, body: String) throws -> InboxCapture {
    let title = title.trimmed
    let body = body.trimmed

    guard !title.isEmpty || !body.isEmpty else {
      throw InboxCaptureError.empty
    }

    guard title.count <= titleLimit else {
      throw InboxCaptureError.titleTooLong
    }

    guard body.count <= bodyLimit else {
      throw InboxCaptureError.bodyTooLong
    }

    return InboxCapture(title: title.nonEmpty, body: body)
  }
}

struct InboxReviewInput: Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let title: String?
  let body: String
  let collectionNames: [String]
  let entryType: InboxEntryType
  let occurredAt: Date
  let occurredTimezone: String
  let tagNames: [String]

  static func validate(
    entryID: UUID,
    revision: Int,
    title: String,
    body: String,
    collectionNames: [String],
    entryType: InboxEntryType,
    occurredAt: Date,
    occurredTimezone: String,
    tagNames: [String]
  ) throws -> InboxReviewInput {
    guard revision > 0 else {
      throw InboxReviewError.invalidRevision
    }

    let capture = try InboxCapture.validate(title: title, body: body)

    if entryType == .firstTime, capture.title == nil {
      throw InboxReviewError.firstTimeRequiresTitle
    }

    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100 else {
      throw InboxReviewError.invalidTimezone
    }

    guard
      let normalizedCollections = normalizeNames(
        collectionNames,
        maximumCount: 20,
        maximumNameLength: 80
      )
    else {
      throw InboxReviewError.invalidCollections
    }

    guard
      let normalizedTags = normalizeNames(
        tagNames,
        maximumCount: 50,
        maximumNameLength: 60
      )
    else {
      throw InboxReviewError.invalidTags
    }

    return InboxReviewInput(
      entryID: entryID,
      revision: revision,
      title: capture.title,
      body: capture.body,
      collectionNames: normalizedCollections,
      entryType: entryType,
      occurredAt: occurredAt,
      occurredTimezone: occurredTimezone,
      tagNames: normalizedTags
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

      if normalizedNames.insert(name.lowercased()).inserted {
        names.append(name)
      }
    }

    return names
  }
}

struct InboxDraft: Codable, Equatable, Sendable {
  let title: String
  let body: String
  let occurredAt: Date?
  let updatedAt: Date

  init(title: String, body: String, occurredAt: Date? = nil, updatedAt: Date) {
    self.title = title
    self.body = body
    self.occurredAt = occurredAt
    self.updatedAt = updatedAt
  }

  var hasContent: Bool {
    !title.isEmpty || !body.isEmpty
  }
}

struct InboxDraftStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load(ownerID: UUID) -> InboxDraft? {
    let key = Self.storageKey(ownerID: ownerID)

    guard let data = defaults.data(forKey: key),
      let draft = try? JSONDecoder().decode(InboxDraft.self, from: data),
      draft.hasContent,
      draft.title.count <= InboxCapture.titleLimit,
      draft.body.count <= InboxCapture.bodyLimit
    else {
      defaults.removeObject(forKey: key)
      return nil
    }

    return draft
  }

  @discardableResult
  func save(title: String, body: String, occurredAt: Date? = nil, ownerID: UUID) -> Bool {
    let key = Self.storageKey(ownerID: ownerID)
    let draft = InboxDraft(title: title, body: body, occurredAt: occurredAt, updatedAt: Date())

    guard draft.hasContent else {
      defaults.removeObject(forKey: key)
      return false
    }

    guard let data = try? JSONEncoder().encode(draft) else {
      return false
    }

    defaults.set(data, forKey: key)
    return true
  }

  func clear(ownerID: UUID) {
    defaults.removeObject(forKey: Self.storageKey(ownerID: ownerID))
  }

  static func storageKey(ownerID: UUID) -> String {
    "memotrail.inboxDraft.\(ownerID.uuidString.lowercased())"
  }
}

struct QueuedInboxEntry: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let occurredAt: Date
  let occurredTimezone: String
  let queuedAt: Date

  var presentedEntry: InboxEntry {
    InboxEntry(
      id: id,
      title: title,
      body: body,
      entryType: .standard,
      createdAt: queuedAt,
      occurredStart: occurredAt,
      occurredTimezone: occurredTimezone,
      revision: 1
    )
  }

  var isValid: Bool {
    let normalizedTitle = title?.trimmed.nonEmpty

    return normalizedTitle == title
      && (normalizedTitle != nil || !body.isEmpty)
      && body.trimmed == body
      && (title?.count ?? 0) <= InboxCapture.titleLimit
      && body.count <= InboxCapture.bodyLimit
      && !occurredTimezone.isEmpty
      && occurredTimezone.count <= 100
  }
}

struct InboxQueueStore {
  static let maximumEntryCount = 100

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load(ownerID: UUID) -> [QueuedInboxEntry] {
    let key = Self.storageKey(ownerID: ownerID)

    guard let data = defaults.data(forKey: key),
      let queue = try? JSONDecoder().decode(StoredInboxQueue.self, from: data),
      queue.version == 1,
      queue.entries.count <= Self.maximumEntryCount,
      queue.entries.allSatisfy(\.isValid),
      Set(queue.entries.map(\.id)).count == queue.entries.count
    else {
      defaults.removeObject(forKey: key)
      return []
    }

    return queue.entries
  }

  func enqueue(_ entry: QueuedInboxEntry, ownerID: UUID) -> [QueuedInboxEntry]? {
    let currentQueue = load(ownerID: ownerID)

    if currentQueue.contains(where: { $0.id == entry.id }) {
      return currentQueue
    }

    guard entry.isValid, currentQueue.count < Self.maximumEntryCount else {
      return nil
    }

    let nextQueue = currentQueue + [entry]
    return save(nextQueue, ownerID: ownerID) ? nextQueue : nil
  }

  func remove(entryID: UUID, ownerID: UUID) -> [QueuedInboxEntry]? {
    let nextQueue = load(ownerID: ownerID).filter { $0.id != entryID }

    if nextQueue.isEmpty {
      defaults.removeObject(forKey: Self.storageKey(ownerID: ownerID))
      return []
    }

    return save(nextQueue, ownerID: ownerID) ? nextQueue : nil
  }

  static func storageKey(ownerID: UUID) -> String {
    "memotrail.inboxQueue.\(ownerID.uuidString.lowercased())"
  }

  private func save(_ entries: [QueuedInboxEntry], ownerID: UUID) -> Bool {
    let queue = StoredInboxQueue(version: 1, entries: entries)

    guard let data = try? JSONEncoder().encode(queue) else {
      return false
    }

    defaults.set(data, forKey: Self.storageKey(ownerID: ownerID))
    return true
  }
}

private struct StoredInboxQueue: Codable {
  let version: Int
  let entries: [QueuedInboxEntry]
}

enum InboxCaptureError: LocalizedError, Equatable {
  case empty
  case titleTooLong
  case bodyTooLong

  var errorDescription: String? {
    switch self {
    case .empty:
      "Write a title or a note before saving."
    case .titleTooLong:
      "Keep the title under \(InboxCapture.titleLimit) characters."
    case .bodyTooLong:
      "Keep the note under 50,000 characters."
    }
  }
}

enum InboxReviewError: LocalizedError, Equatable {
  case firstTimeRequiresTitle
  case invalidCollections
  case invalidRevision
  case invalidTags
  case invalidTimezone

  var errorDescription: String? {
    switch self {
    case .firstTimeRequiresTitle:
      "Add a title before marking an Entry as a First Time."
    case .invalidCollections:
      "Use up to 20 Collections with names under 80 characters."
    case .invalidRevision:
      "This Entry review is invalid."
    case .invalidTags:
      "Use up to 50 tags with names under 60 characters."
    case .invalidTimezone:
      "Choose a valid time zone."
    }
  }
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nonEmpty: String? {
    isEmpty ? nil : self
  }

  func truncated(to limit: Int) -> String {
    guard count > limit else { return self }
    let endIndex = index(startIndex, offsetBy: limit)
    return "\(self[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines))…"
  }
}
