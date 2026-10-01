import Foundation

struct InboxEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let collectionNames: [String]
  let itemKind: WikiItemKind
  let itemSubtype: String
  let createdAt: Date
  let occurredStart: Date?
  let occurredTimezone: String?
  let revision: Int
  let tagNames: [String]
  let datePrecision: TimelineDatePrecision
  let occurredEnd: Date?
  let occurredLabel: String?
  var inboxStatus: String = "unreviewed"
  var occurredStartRaw: String?
  var occurredEndRaw: String?
  /// The note's Web formatting from `metadata.body_rich`, kept only while it matches `body`.
  var bodyRich: EntryRichText?

  init(
    id: UUID,
    title: String?,
    body: String,
    collectionNames: [String] = [],
    itemKind: WikiItemKind = .entry,
    itemSubtype: String = "entry",
    createdAt: Date,
    occurredStart: Date?,
    occurredTimezone: String? = nil,
    revision: Int = 1,
    tagNames: [String] = [],
    datePrecision: TimelineDatePrecision = .exact,
    occurredEnd: Date? = nil,
    occurredLabel: String? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.collectionNames = collectionNames
    self.itemKind = itemKind
    self.itemSubtype = itemSubtype
    self.createdAt = createdAt
    self.occurredStart = occurredStart
    self.occurredTimezone = occurredTimezone
    self.revision = revision
    self.tagNames = tagNames
    self.datePrecision = occurredStart == nil && datePrecision == .exact ? .unknown : datePrecision
    self.occurredEnd = occurredEnd
    self.occurredLabel = occurredLabel
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case createdAt = "created_at"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case revision
    case inboxStatus = "inbox_status"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case metadata
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decode(String.self, forKey: .body)
    collectionNames = try values.decodeIfPresent([String].self, forKey: .collectionNames) ?? []
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    occurredStart = try values.decodeIfPresent(Date.self, forKey: .occurredStart)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    inboxStatus = try values.decodeIfPresent(String.self, forKey: .inboxStatus) ?? "unreviewed"
    itemKind = try values.decode(WikiItemKind.self, forKey: .itemKind)
    itemSubtype = try values.decode(String.self, forKey: .itemSubtype)
    occurredStartRaw = try? values.decode(String.self, forKey: .occurredStart)
    occurredEndRaw = try? values.decode(String.self, forKey: .occurredEnd)
    let precision =
      try values.decodeIfPresent(TimelineDatePrecision.self, forKey: .datePrecision) ?? .exact
    datePrecision = occurredStart == nil && precision == .exact ? .unknown : precision
    occurredEnd = try values.decodeIfPresent(Date.self, forKey: .occurredEnd)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    bodyRich = values.decodeEntryRichText(metadataKey: .metadata, body: body)
  }

  func withOrganization(collectionNames: [String], tagNames: [String]) -> InboxEntry {
    var result = InboxEntry(
      id: id,
      title: title,
      body: body,
      collectionNames: collectionNames,
      itemKind: itemKind,
      itemSubtype: itemSubtype,
      createdAt: createdAt,
      occurredStart: occurredStart,
      occurredTimezone: occurredTimezone,
      revision: revision,
      tagNames: tagNames,
      datePrecision: datePrecision,
      occurredEnd: occurredEnd,
      occurredLabel: occurredLabel
    )
    result.inboxStatus = inboxStatus
    result.occurredStartRaw = occurredStartRaw
    result.occurredEndRaw = occurredEndRaw
    result.bodyRich = bodyRich
    return result
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      precision: datePrecision, start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 } ?? "UTC")
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

    return firstLine.nonEmpty.map { $0.truncated(to: 90) } ?? "Untitled capture"
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

enum WikiItemKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case entry
  case entity
  case goal

  var displayName: String {
    switch self {
    case .entry: "Entry"
    case .entity: "Entity"
    case .goal: "Goal"
    }
  }

  func displayName(subtype: String) -> String {
    switch (self, subtype) {
    case (.entry, "first_time"): return "First Time"
    case (.entry, "moment"): return "Moment"
    case (.entry, "period"): return "Period"
    case (.entry, _): return "Entry"
    case (.entity, "home"): return "Home"
    case (.entity, "vehicle"): return "Vehicle"
    case (.entity, "person"): return "Person"
    case (.goal, "bucket_list"): return "Bucket List"
    case (.goal, _): return "Goal"
    default: return subtype.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}

struct CaptureExtractionSource: Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let title: String
  let body: String
  let occurrence: EntryOccurrence
  let collectionNames: [String]
  let tagNames: [String]
  let occurredStartRaw: String?
  let occurredEndRaw: String?

  init(
    entry: InboxEntry,
    title: String,
    body: String,
    occurrence: EntryOccurrence,
    collectionNames: [String],
    tagNames: [String]
  ) {
    entryID = entry.id
    revision = entry.revision
    self.title = title
    self.body = body
    self.occurrence = occurrence
    self.collectionNames = collectionNames
    self.tagNames = tagNames
    occurredStartRaw = occurrence.start == entry.occurredStart ? entry.occurredStartRaw : nil
    occurredEndRaw = occurrence.end == entry.occurredEnd ? entry.occurredEndRaw : nil
  }
}

struct InboxCapture: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000

  let title: String?
  let body: String

  static func validate(
    title: String,
    body: String,
    hasAttachments: Bool = false
  ) throws -> InboxCapture {
    let title = title.trimmed
    let body = body.trimmed

    guard !title.isEmpty || !body.isEmpty || hasAttachments else {
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

/// The Review Entry sheet's values before validation, like Web's review form state.
struct EntryReviewDraft: Equatable, Sendable {
  var title: String
  var body: String
  var bodyRich: EntryRichText?
  var collectionNames: [String]
  var tagNames: [String]
  var occurrence: EntryOccurrence
  var photoPlace: PhotoPlaceDraft?
}

struct InboxReviewInput: Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let title: String?
  let body: String
  var bodyRich: EntryRichText?
  let collectionNames: [String]
  let itemKind: WikiItemKind
  let itemSubtype: String
  let occurredAt: Date?
  let occurredTimezone: String
  let tagNames: [String]
  let occurrence: EntryOccurrence

  static func validate(
    entryID: UUID,
    revision: Int,
    title: String,
    body: String,
    bodyRich: EntryRichText? = nil,
    collectionNames: [String],
    itemKind: WikiItemKind,
    itemSubtype: String,
    occurredAt: Date?,
    occurredTimezone: String,
    tagNames: [String],
    datePrecision: TimelineDatePrecision = .exact,
    occurredEnd: Date? = nil,
    occurredLabel: String? = nil
  ) throws -> InboxReviewInput {
    guard revision > 0 else {
      throw InboxReviewError.invalidRevision
    }

    let capture: InboxCapture
    do {
      capture = try InboxCapture.validate(title: title, body: body)
    } catch InboxCaptureError.empty {
      throw InboxReviewError.empty
    }
    // Like Web, formatting must describe exactly the note that is saved.
    if let bodyRich, !bodyRich.isValid(expectedText: capture.body) {
      throw InboxReviewError.invalidRichText
    }

    guard itemKind == .entry, itemSubtype == "entry"
    else {
      throw InboxReviewError.invalidClassification
    }

    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100,
      TimeZone(identifier: occurredTimezone) != nil
    else {
      throw InboxReviewError.invalidTimezone
    }
    let occurrence = EntryOccurrence(
      precision: datePrecision, start: occurredAt, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone)
    try occurrence.validate()

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
      bodyRich: bodyRich,
      collectionNames: normalizedCollections,
      itemKind: itemKind,
      itemSubtype: itemSubtype,
      occurredAt: occurredAt,
      occurredTimezone: occurredTimezone,
      tagNames: normalizedTags,
      occurrence: occurrence
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
  var occurrenceDraft: OccurrenceDraft? = nil
  /// The formatted note, stored like Web's `bodyRich` draft field.
  var bodyRich: EntryEmphasisContent? = nil

  var captureOccurrence: OccurrenceDraft? {
    occurrenceDraft
      ?? occurredAt.map {
        OccurrenceDraft(
          EntryOccurrence(
            precision: .exact, start: $0, end: nil, label: nil,
            timezone: TimeZone.current.identifier))
      }
  }

  init(title: String, body: String, occurredAt: Date? = nil, updatedAt: Date) {
    self.title = title
    self.body = body
    self.occurredAt = occurredAt
    self.updatedAt = updatedAt
  }

  var hasContent: Bool {
    !title.isEmpty || !body.isEmpty || occurrenceDraft != nil
  }

  /// The note to reopen in the editor; formatting returns only when it still matches the text.
  @MainActor
  var note: NSAttributedString {
    if let bodyRich, bodyRich.text == body, let text = bodyRich.attributedText() { return text }
    return NSAttributedString(string: body)
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
  func save(
    title: String, body: String, bodyRich: EntryEmphasisContent? = nil,
    occurredAt: Date? = nil, occurrenceDraft: OccurrenceDraft? = nil, ownerID: UUID
  ) -> Bool {
    let key = Self.storageKey(ownerID: ownerID)
    var draft = InboxDraft(title: title, body: body, occurredAt: occurredAt, updatedAt: Date())
    draft.occurrenceDraft = occurrenceDraft
    draft.bodyRich = bodyRich?.text == body ? bodyRich : nil

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
  let occurredAt: Date?
  let occurredTimezone: String
  let queuedAt: Date
  let attachments: [QueuedInboxAttachment]
  var occurrence: EntryOccurrence? = nil
  /// Web's `metadata.body_rich` for the note, when it was written with formatting.
  var bodyRich: EntryEmphasisContent? = nil

  var effectiveOccurrence: EntryOccurrence {
    occurrence
      ?? EntryOccurrence(
        precision: .exact, start: occurredAt, end: nil, label: nil, timezone: occurredTimezone)
  }

  init(
    id: UUID,
    title: String?,
    body: String,
    occurredAt: Date?,
    occurredTimezone: String,
    queuedAt: Date,
    attachments: [QueuedInboxAttachment] = []
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.occurredAt = occurredAt
    self.occurredTimezone = occurredTimezone
    self.queuedAt = queuedAt
    self.attachments = attachments
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, body, occurredAt, occurredTimezone, queuedAt, attachments, occurrence
    case bodyRich
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title)
    body = try values.decode(String.self, forKey: .body)
    occurredAt = try values.decodeIfPresent(Date.self, forKey: .occurredAt)
    occurredTimezone = try values.decode(String.self, forKey: .occurredTimezone)
    queuedAt = try values.decode(Date.self, forKey: .queuedAt)
    attachments =
      try values.decodeIfPresent([QueuedInboxAttachment].self, forKey: .attachments) ?? []
    occurrence = try values.decodeIfPresent(EntryOccurrence.self, forKey: .occurrence)
    bodyRich = try values.decodeIfPresent(EntryEmphasisContent.self, forKey: .bodyRich)
  }

  var presentedEntry: InboxEntry {
    InboxEntry(
      id: id,
      title: title,
      body: body,
      createdAt: queuedAt,
      occurredStart: effectiveOccurrence.start,
      occurredTimezone: effectiveOccurrence.timezone,
      revision: 1,
      datePrecision: effectiveOccurrence.precision,
      occurredEnd: effectiveOccurrence.end,
      occurredLabel: effectiveOccurrence.label
    )
  }

  var isValid: Bool {
    let normalizedTitle = title?.trimmed.nonEmpty

    return normalizedTitle == title
      && (try? effectiveOccurrence.validate()) != nil
      && body.trimmed == body
      && (title?.count ?? 0) <= InboxCapture.titleLimit
      && body.count <= InboxCapture.bodyLimit
      && !occurredTimezone.isEmpty
      && occurredTimezone.count <= 100
      && attachments.count <= FirstTimePhotoDraft.maximumCount
      && attachments.allSatisfy(\.isValid)
      && Set(attachments.map(\.id)).count == attachments.count
      && (normalizedTitle != nil || !body.isEmpty || !attachments.isEmpty)
      && (bodyRich.map { $0.isValid(expectedText: body) } ?? true)
  }
}

struct QueuedInboxAttachment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let mimeType: FirstTimeImageType
  let originalFilename: String?
  let byteSize: Int64
  let pixelWidth: Int?
  let pixelHeight: Int?

  init(draft: FirstTimePhotoDraft) {
    id = draft.id
    mimeType = draft.mimeType
    originalFilename = draft.originalFilename
    byteSize = Int64(draft.data.count)
    pixelWidth = draft.pixelWidth
    pixelHeight = draft.pixelHeight
  }

  init(
    id: UUID,
    mimeType: FirstTimeImageType,
    originalFilename: String?,
    byteSize: Int64,
    pixelWidth: Int?,
    pixelHeight: Int?
  ) {
    self.id = id
    self.mimeType = mimeType
    self.originalFilename = originalFilename
    self.byteSize = byteSize
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  var isValid: Bool {
    let filename = originalFilename?.trimmed.nonEmpty
    return filename == originalFilename
      && byteSize > 0
      && byteSize <= Int64(FirstTimePhotoDraft.maximumByteSize)
      && (filename?.count ?? 0) <= 255
      && (pixelWidth.map { $0 > 0 } ?? true)
      && (pixelHeight.map { $0 > 0 } ?? true)
  }

  func objectPath(ownerID: UUID, entryID: UUID) -> String {
    "\(ownerID.uuidString.lowercased())/\(entryID.uuidString.lowercased())/\(id.uuidString.lowercased()).\(mimeType.fileExtension)"
  }

  func matches(_ draft: FirstTimePhotoDraft) -> Bool {
    self == QueuedInboxAttachment(draft: draft)
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
      [1, 2, 3].contains(queue.version),
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
    let queue = StoredInboxQueue(version: 3, entries: entries)

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

struct InboxPhotoStore: Sendable {
  private let rootURL: URL

  init(rootURL: URL? = nil) {
    self.rootURL =
      rootURL
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "MemoTrail/Capture Photos", directoryHint: .isDirectory)
  }

  func load(ownerID: UUID) throws -> [FirstTimePhotoDraft] {
    let directory = ownerDirectory(ownerID)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

    let metadataURLs = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }

    return metadataURLs.compactMap { metadataURL -> (Date, FirstTimePhotoDraft)? in
      guard
        let metadata = try? JSONDecoder().decode(
          StoredInboxPhoto.self,
          from: Data(contentsOf: metadataURL)
        ),
        metadata.isValid,
        metadataURL.deletingPathExtension().lastPathComponent
          == metadata.id.uuidString.lowercased(),
        let data = try? Data(contentsOf: dataURL(metadata, ownerID: ownerID)),
        data.count == metadata.byteSize,
        FirstTimeImageType.detect(data: data, typeIdentifiers: []) == metadata.mimeType,
        let draft = try? FirstTimePhotoDraft.validate(
          id: metadata.id,
          data: data,
          mimeType: metadata.mimeType,
          originalFilename: metadata.originalFilename,
          pixelWidth: metadata.pixelWidth,
          pixelHeight: metadata.pixelHeight
        )
      else {
        return nil
      }

      return (metadata.createdAt, draft)
    }
    .sorted {
      if $0.0 == $1.0 {
        return $0.1.id.uuidString < $1.1.id.uuidString
      }
      return $0.0 < $1.0
    }
    .map { $0.1 }
  }

  func save(_ draft: FirstTimePhotoDraft, ownerID: UUID) throws {
    let directory = ownerDirectory(ownerID)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )

    let metadata = StoredInboxPhoto(draft: draft)
    let photoURL = dataURL(metadata, ownerID: ownerID)
    let metadataURL = metadataURL(draft.id, ownerID: ownerID)

    do {
      try draft.data.write(to: photoURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: photoURL.path
      )
      try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: metadataURL.path
      )
    } catch {
      try? FileManager.default.removeItem(at: photoURL)
      try? FileManager.default.removeItem(at: metadataURL)
      throw error
    }
  }

  func remove(photoID: UUID, ownerID: UUID) throws {
    let directory = ownerDirectory(ownerID)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }

    let metadataURL = metadataURL(photoID, ownerID: ownerID)
    let prefix = photoID.uuidString.lowercased()
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    .filter {
      $0 == metadataURL
        || ($0.deletingPathExtension().lastPathComponent == prefix
          && $0.pathExtension != "json")
    }

    for url in urls {
      try FileManager.default.removeItem(at: url)
    }
  }

  private func ownerDirectory(_ ownerID: UUID) -> URL {
    rootURL.appending(
      path: ownerID.uuidString.lowercased(),
      directoryHint: .isDirectory
    )
  }

  private func metadataURL(_ photoID: UUID, ownerID: UUID) -> URL {
    ownerDirectory(ownerID).appending(
      path: "\(photoID.uuidString.lowercased()).json",
      directoryHint: .notDirectory
    )
  }

  private func dataURL(_ metadata: StoredInboxPhoto, ownerID: UUID) -> URL {
    ownerDirectory(ownerID).appending(
      path: "\(metadata.id.uuidString.lowercased()).\(metadata.mimeType.fileExtension)",
      directoryHint: .notDirectory
    )
  }
}

private struct StoredInboxPhoto: Codable {
  let id: UUID
  let mimeType: FirstTimeImageType
  let originalFilename: String?
  let byteSize: Int
  let pixelWidth: Int?
  let pixelHeight: Int?
  let createdAt: Date

  init(draft: FirstTimePhotoDraft) {
    id = draft.id
    mimeType = draft.mimeType
    originalFilename = draft.originalFilename
    byteSize = draft.data.count
    pixelWidth = draft.pixelWidth
    pixelHeight = draft.pixelHeight
    createdAt = Date()
  }

  var isValid: Bool {
    QueuedInboxAttachment(
      id: id,
      mimeType: mimeType,
      originalFilename: originalFilename,
      byteSize: Int64(byteSize),
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    ).isValid
  }
}

struct RegisterEntryAttachmentParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let attachment: QueuedInboxAttachment
  let objectPath: String

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case attachmentID = "p_attachment_id"
    case objectPath = "p_object_path"
    case originalFilename = "p_original_filename"
    case mimeType = "p_mime_type"
    case byteSize = "p_byte_size"
    case pixelWidth = "p_pixel_width"
    case pixelHeight = "p_pixel_height"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(entryID, forKey: .entryID)
    try values.encode(attachment.id, forKey: .attachmentID)
    try values.encode(objectPath, forKey: .objectPath)
    try values.encode(attachment.mimeType, forKey: .mimeType)
    try values.encode(attachment.byteSize, forKey: .byteSize)
    try values.encodeIfPresent(attachment.originalFilename, forKey: .originalFilename)
    if attachment.originalFilename == nil {
      try values.encodeNil(forKey: .originalFilename)
    }
    try values.encodeIfPresent(attachment.pixelWidth, forKey: .pixelWidth)
    if attachment.pixelWidth == nil { try values.encodeNil(forKey: .pixelWidth) }
    try values.encodeIfPresent(attachment.pixelHeight, forKey: .pixelHeight)
    if attachment.pixelHeight == nil { try values.encodeNil(forKey: .pixelHeight) }
  }
}

struct RegisteredEntryAttachment: Decodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
  }
}

enum InboxCaptureError: LocalizedError, Equatable {
  case empty
  case titleTooLong
  case bodyTooLong
  case photoUnavailable

  var errorDescription: String? {
    switch self {
    case .empty:
      "Write a title, a note, or add a photo before saving."
    case .titleTooLong:
      "Keep the title under \(InboxCapture.titleLimit) characters."
    case .bodyTooLong:
      "Keep the note under 50,000 characters."
    case .photoUnavailable:
      "MemoTrail could not read that photo. Select it again."
    }
  }
}

enum InboxReviewError: LocalizedError, Equatable {
  case empty
  case invalidClassification
  case invalidCollections
  case invalidRevision
  case invalidRichText
  case invalidTags
  case invalidTimezone

  var errorDescription: String? {
    switch self {
    case .empty:
      "Keep a title or note before saving."
    case .invalidRichText:
      "This Entry's rich text is invalid."
    case .invalidClassification:
      "Open this item in its focused view to edit it."
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

/// Web `countLabel`, such as "1 Entry", "3 Entries", or "2 people".
/// Nouns ending in a consonant and "y" take "ies"; pass `plural` for any other irregular form.
func countLabel(_ count: Int, _ singular: String, plural: String? = nil) -> String {
  let regular =
    singular.range(of: "[^aeiou]y$", options: [.regularExpression, .caseInsensitive]) != nil
    ? "\(singular.dropLast())ies" : "\(singular)s"
  return "\(count) \(count == 1 ? singular : plural ?? regular)"
}
