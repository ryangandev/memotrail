import Foundation

struct InboxEntry: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let createdAt: Date
  let occurredStart: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case createdAt = "created_at"
    case occurredStart = "occurred_start"
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

struct InboxDraft: Codable, Equatable, Sendable {
  let title: String
  let body: String
  let updatedAt: Date

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
  func save(title: String, body: String, ownerID: UUID) -> Bool {
    let key = Self.storageKey(ownerID: ownerID)
    let draft = InboxDraft(title: title, body: body, updatedAt: Date())

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
      createdAt: queuedAt,
      occurredStart: occurredAt
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
