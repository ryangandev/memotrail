import Foundation
@preconcurrency import Supabase

// Captures saved on this iPhone before they reach MemoTrail, like Web
// `inbox-queue.ts`, `inbox-draft.ts`, and `inbox-photo-store.ts`. The storage keys and JSON
// field names keep their Inbox-era names so queues written by earlier builds still load.

struct CaptureInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000

  let title: String?
  let body: String

  static func validate(
    title: String,
    body: String,
    hasAttachments: Bool = false
  ) throws -> CaptureInput {
    let title = title.trimmed
    let body = body.trimmed

    guard !title.isEmpty || !body.isEmpty || hasAttachments else {
      throw CaptureError.empty
    }

    guard title.count <= titleLimit else {
      throw CaptureError.titleTooLong
    }

    guard body.count <= bodyLimit else {
      throw CaptureError.bodyTooLong
    }

    return CaptureInput(title: title.nonEmpty, body: body)
  }
}

struct CaptureDraft: Codable, Equatable, Sendable {
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

/// What reading the stored draft found: the draft, and whether all of it could be read.
struct CaptureDraftReading: Equatable, Sendable {
  static let partialNotice =
    "Some of your saved draft could not be restored. The original stays on this device."
  static let unreadableNotice =
    "Your saved draft could not be read. The original stays on this device."

  let draft: CaptureDraft?
  /// False when reading lost part of the stored draft, such as an overlong note.
  let isComplete: Bool

  /// What the composer says when part of the draft could not come back, like Web.
  var notice: String? {
    guard !isComplete else { return nil }
    return draft == nil ? Self.unreadableNotice : Self.partialNotice
  }
}

/// The composer's draft on this iPhone, like Web `inbox-draft.ts`. Reading never writes. A
/// draft that could not be read in full is set aside under its quarantine key before anything
/// replaces it, and nothing replaces it when that fails.
struct CaptureDraftStore: Sendable {
  private let storage: any CaptureStorage

  init(defaults: UserDefaults = .standard) {
    storage = UserDefaultsCaptureStorage(defaults: defaults)
  }

  init(storage: any CaptureStorage) {
    self.storage = storage
  }

  func load(ownerID: UUID) -> CaptureDraft? {
    read(ownerID: ownerID).draft
  }

  func read(ownerID: UUID) -> CaptureDraftReading {
    Self.inspect(storage.data(forKey: Self.storageKey(ownerID: ownerID)))
  }

  @discardableResult
  func save(
    title: String, body: String, bodyRich: EntryEmphasisContent? = nil,
    occurredAt: Date? = nil, occurrenceDraft: OccurrenceDraft? = nil, ownerID: UUID
  ) -> Bool {
    let key = Self.storageKey(ownerID: ownerID)
    var draft = CaptureDraft(title: title, body: body, occurredAt: occurredAt, updatedAt: Date())
    draft.occurrenceDraft = occurrenceDraft
    draft.bodyRich = bodyRich?.text == body ? bodyRich : nil

    do {
      try keepUnreadableDraft(ownerID: ownerID)
      guard draft.hasContent else {
        try storage.remove(forKey: key)
        return false
      }
      try storage.set(JSONEncoder().encode(draft), forKey: key)
      return true
    } catch {
      return false
    }
  }

  func clear(ownerID: UUID) {
    do {
      try keepUnreadableDraft(ownerID: ownerID)
      try storage.remove(forKey: Self.storageKey(ownerID: ownerID))
    } catch {
      // A draft that could not be set aside stays where it is.
    }
  }

  /// The originals of drafts that could not be read in full, oldest first.
  func quarantinedDrafts(ownerID: UUID) -> [StoredJSON] {
    CaptureQuarantine.read(storage.data(forKey: Self.quarantineKey(ownerID: ownerID)))
      .map(\.value)
  }

  static func storageKey(ownerID: UUID) -> String {
    "memotrail.inboxDraft.\(ownerID.uuidString.lowercased())"
  }

  static func quarantineKey(ownerID: UUID) -> String {
    "memotrail.inboxDraftQuarantine.\(ownerID.uuidString.lowercased())"
  }

  /// Before the stored draft is replaced or removed, sets it aside if reading it loses
  /// anything. Throws when it cannot, so the caller leaves the stored draft alone.
  private func keepUnreadableDraft(ownerID: UUID) throws {
    guard let stored = storage.data(forKey: Self.storageKey(ownerID: ownerID)), !stored.isEmpty,
      !Self.inspect(stored).isComplete
    else { return }
    try CaptureQuarantine.add(
      [StoredJSON(raw: stored)], key: Self.quarantineKey(ownerID: ownerID), storage: storage)
  }

  /// Reads whatever part of a stored draft is usable, like Web `inspectInboxDraft`. Writing
  /// over today's limits comes back cut to them instead of the whole draft disappearing.
  static func inspect(_ data: Data?) -> CaptureDraftReading {
    guard let data, !data.isEmpty else { return CaptureDraftReading(draft: nil, isComplete: true) }
    guard
      let stored = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        as? [String: Any]
    else { return CaptureDraftReading(draft: nil, isComplete: false) }

    var isComplete = true
    func text(_ key: String, limit: Int) -> String {
      guard let value = stored[key] as? String else {
        isComplete = false
        return ""
      }
      let kept = String(value.prefix(limit))
      if kept != value { isComplete = false }
      return kept
    }
    func date(_ key: String, required: Bool) -> Date? {
      switch stored[key] {
      case let seconds as Double: return Date(timeIntervalSinceReferenceDate: seconds)
      case nil, is NSNull:
        if required { isComplete = false }
        return nil
      default:
        isComplete = false
        return nil
      }
    }
    func decoded<Value: Decodable>(_ key: String, as type: Value.Type) -> Value? {
      guard let value = stored[key], !(value is NSNull) else { return nil }
      guard let json = StoredJSON(value), let result = try? JSONDecoder().decode(type, from: json.data)
      else {
        isComplete = false
        return nil
      }
      return result
    }

    let title = text("title", limit: CaptureInput.titleLimit)
    let body = text("body", limit: CaptureInput.bodyLimit)
    let updatedAt = date("updatedAt", required: true) ?? Date(timeIntervalSince1970: 0)
    let occurredAt = date("occurredAt", required: false)
    let occurrenceDraft = decoded("occurrenceDraft", as: OccurrenceDraft.self)
    var bodyRich = decoded("bodyRich", as: EntryEmphasisContent.self)
    if let rich = bodyRich, rich.text != body {
      bodyRich = nil
      isComplete = false
    }

    var draft = CaptureDraft(title: title, body: body, occurredAt: occurredAt, updatedAt: updatedAt)
    draft.occurrenceDraft = occurrenceDraft
    draft.bodyRich = bodyRich
    return CaptureDraftReading(draft: draft.hasContent ? draft : nil, isComplete: isComplete)
  }
}

struct QueuedCapture: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let occurredAt: Date?
  let occurredTimezone: String
  let queuedAt: Date
  let attachments: [QueuedCaptureAttachment]
  var occurrence: EntryOccurrence? = nil
  /// Web's `metadata.body_rich` for the note, when it was written with formatting.
  var bodyRich: EntryEmphasisContent? = nil
  /// Set when MemoTrail permanently refused this capture, which then never syncs again and
  /// waits on this iPhone until the person copies what they need and discards it.
  var rejection: QueuedCaptureRejection? = nil

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
    attachments: [QueuedCaptureAttachment] = []
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
    case bodyRich, rejection
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
      try values.decodeIfPresent([QueuedCaptureAttachment].self, forKey: .attachments) ?? []
    occurrence = try values.decodeIfPresent(EntryOccurrence.self, forKey: .occurrence)
    bodyRich = try values.decodeIfPresent(EntryEmphasisContent.self, forKey: .bodyRich)
    // Like Web, a malformed marker never costs the capture: it only becomes sendable again.
    rejection = (try? values.decodeIfPresent(QueuedCaptureRejection.self, forKey: .rejection))
      .flatMap { $0 }
      .flatMap { $0.isValid ? $0 : nil }
  }

  /// The note text to keep before discarding: the title and note, like Web's Copy text.
  var copyableText: String {
    [title, body.nonEmpty].compactMap { $0 }.joined(separator: "\n\n")
  }


  var isValid: Bool {
    let normalizedTitle = title?.trimmed.nonEmpty

    return normalizedTitle == title
      && (try? effectiveOccurrence.validate()) != nil
      && body.trimmed == body
      && (title?.count ?? 0) <= CaptureInput.titleLimit
      && body.count <= CaptureInput.bodyLimit
      && !occurredTimezone.isEmpty
      && occurredTimezone.count <= 100
      && attachments.count <= PhotoDraft.maximumCount
      && attachments.allSatisfy(\.isValid)
      && Set(attachments.map(\.id)).count == attachments.count
      && (normalizedTitle != nil || !body.isEmpty || !attachments.isEmpty)
      && (bodyRich.map { $0.isValid(expectedText: body) } ?? true)
  }
}

struct QueuedCaptureAttachment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let mimeType: PhotoImageType
  let originalFilename: String?
  let byteSize: Int64
  let pixelWidth: Int?
  let pixelHeight: Int?

  init(draft: PhotoDraft) {
    id = draft.id
    mimeType = draft.mimeType
    originalFilename = draft.originalFilename
    byteSize = Int64(draft.data.count)
    pixelWidth = draft.pixelWidth
    pixelHeight = draft.pixelHeight
  }

  init(
    id: UUID,
    mimeType: PhotoImageType,
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
      && byteSize <= Int64(PhotoDraft.maximumByteSize)
      && (filename?.count ?? 0) <= 255
      && (pixelWidth.map { $0 > 0 } ?? true)
      && (pixelHeight.map { $0 > 0 } ?? true)
  }

  func objectPath(ownerID: UUID, entryID: UUID) -> String {
    "\(ownerID.uuidString.lowercased())/\(entryID.uuidString.lowercased())/\(id.uuidString.lowercased()).\(mimeType.fileExtension)"
  }

  func matches(_ draft: PhotoDraft) -> Bool {
    self == QueuedCaptureAttachment(draft: draft)
  }
}

extension RegisterEntryAttachmentParameters {
  /// Registers a queued capture's photo with the facts saved when it was captured.
  init(entryID: UUID, attachment: QueuedCaptureAttachment, objectPath: String) {
    self.init(
      entryID: entryID, attachmentID: attachment.id, objectPath: objectPath,
      originalFilename: attachment.originalFilename, mimeType: attachment.mimeType,
      byteSize: attachment.byteSize, pixelWidth: attachment.pixelWidth,
      pixelHeight: attachment.pixelHeight)
  }
}

/// Why MemoTrail refused a queued capture, kept with it like Web's queue `rejection`.
struct QueuedCaptureRejection: Codable, Equatable, Sendable {
  static let maximumMessageLength = 500

  let message: String
  let rejectedAt: Date

  var isValid: Bool {
    !message.trimmed.isEmpty && message.count <= Self.maximumMessageLength
  }
}

/// How a capture sync failed, classified from PostgREST and Postgres error codes like Web
/// `classifySyncFailure`, never from message text.
enum CaptureSyncFailure: Equatable, Sendable {
  /// MemoTrail refused this capture, and sending it again cannot change the answer.
  case rejected
  /// The session can no longer write, so the person needs to sign in again.
  case session
  /// MemoTrail could not be reached or answer now; a later attempt can succeed.
  case unavailable

  private static let sessionCodes: Set<String> = ["PGRST301", "PGRST302", "PGRST303"]
  // Invalid data, integrity constraints, and program limits are the capture's own content.
  private static let rejectedSQLStateClasses: Set<Substring> = ["22", "23", "54"]

  init(_ error: Error) {
    // Network failures, gateway pages, and undecodable responses carry no PostgREST code.
    guard let error = error as? PostgrestError, let code = error.code, !code.isEmpty else {
      self = .unavailable
      return
    }
    self.init(code: code)
  }

  init(code: String) {
    if Self.sessionCodes.contains(code) {
      self = .session
    } else if code.count == 8, code.hasPrefix("PGRST1"),
      code.dropFirst(6).allSatisfy({ $0.isASCII && $0.isNumber })
    {
      // PostgREST could not read the request itself.
      self = .rejected
    } else if code == "42501" {
      // Row-level security refused the signed-in person's own write. The session is checked
      // before each sync, and an expired token answers with PGRST303 instead.
      self = .rejected
    } else if code.count == 5, code.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isUppercase) }),
      Self.rejectedSQLStateClasses.contains(code.prefix(2))
    {
      self = .rejected
    } else {
      self = .unavailable
    }
  }
}

/// How a capture photo's Storage upload failed, classified by status like Web
/// `classifyUploadFailure`, never from message text.
enum CaptureUploadFailure: Equatable, Sendable {
  /// MemoTrail refused this file, and uploading it again cannot change the answer.
  case rejected
  /// The session can no longer write, so the person needs to sign in again.
  case session
  /// MemoTrail could not be reached or answer now; a later attempt can succeed.
  case unavailable
  /// Storage refused the signed-in request. It reports an expired session exactly like a policy
  /// denial, so the caller checks the session before calling it a refusal.
  case denied
  /// An earlier attempt already stored this original, perhaps before its response was lost.
  case exists
  case tooLarge
  case unsupportedType

  init(_ error: Error) {
    switch error {
    case let error as StorageError:
      // Storage reports the real status in its error body, beside an HTTP 400.
      self.init(status: error.statusCode.flatMap { Int($0) })
    case let error as HTTPError:
      // A body Storage did not write, such as a gateway page, keeps only the HTTP status.
      self.init(status: error.response.statusCode)
    default:
      // Network failures never reached Storage.
      self = .unavailable
    }
  }

  init(status: Int?) {
    switch status {
    case 409: self = .exists
    case 401: self = .session
    case 403: self = .denied
    case 413: self = .tooLarge
    case 415: self = .unsupportedType
    // Timeouts, locks, early data, rate limits, and server errors can pass.
    case 408, 423, 425, 429: self = .unavailable
    case let status? where (400..<500).contains(status): self = .rejected
    default: self = .unavailable
    }
  }
}

/// Where captures, the draft, and their quarantines are kept on this iPhone. A write can fail,
/// so the stores never replace what they could not set aside first.
protocol CaptureStorage: Sendable {
  func data(forKey key: String) -> Data?
  func set(_ data: Data, forKey key: String) throws
  func remove(forKey key: String) throws
}

/// The standard storage: this app's user defaults. `UserDefaults` is safe to use from any
/// thread, though the SDK does not mark it `Sendable`.
struct UserDefaultsCaptureStorage: CaptureStorage, @unchecked Sendable {
  let defaults: UserDefaults

  /// A value stored in any other form still comes back, so it can be set aside, not lost.
  func data(forKey key: String) -> Data? {
    switch defaults.object(forKey: key) {
    case nil: nil
    case let data as Data: data
    case let text as String: Data(text.utf8)
    case let value?:
      (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
        ?? Data(String(describing: value).utf8)
    }
  }

  func set(_ data: Data, forKey key: String) throws {
    defaults.set(data, forKey: key)
  }

  func remove(forKey key: String) throws {
    defaults.removeObject(forKey: key)
  }
}

/// One stored JSON value, written with sorted keys so the same content always compares equal.
/// Text that is not JSON is kept as a JSON string.
struct StoredJSON: Hashable, Sendable {
  let data: Data

  init?(_ object: Any) {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
    else { return nil }
    self.data = data
  }

  /// Stored bytes as they are: their JSON when they hold JSON, otherwise their text.
  init(raw data: Data) {
    if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
      let json = StoredJSON(object)
    {
      self = json
    } else {
      self = StoredJSON(
        String(data: data, encoding: .utf8) ?? "base64:" + data.base64EncodedString())!
    }
  }

  var object: Any {
    (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
  }

  /// The stored form, which identifies the value until it is discarded.
  var key: String { String(decoding: data, as: UTF8.self) }
}

/// Values set aside because they could not be read, like Web's quarantine: a JSON array of
/// `{quarantinedAt, value}`, each value kept as it was found.
enum CaptureQuarantine {
  struct Item {
    let quarantinedAt: String
    let value: StoredJSON
  }

  private static let unknownDate = "1970-01-01T00:00:00.000Z"

  /// What a quarantine holds. Even a damaged quarantine keeps what it holds.
  static func read(_ data: Data?) -> [Item] {
    guard let data, !data.isEmpty else { return [] }
    guard let items = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      as? [Any]
    else { return [Item(quarantinedAt: unknownDate, value: StoredJSON(raw: data))] }
    return items.compactMap { item in
      if let held = item as? [String: Any], let date = held["quarantinedAt"] as? String,
        let value = held["value"].flatMap(StoredJSON.init)
      {
        return Item(quarantinedAt: date, value: value)
      }
      return StoredJSON(item).map { Item(quarantinedAt: unknownDate, value: $0) }
    }
  }

  /// Adds values the quarantine does not already hold. Throws when it cannot store them.
  static func add(_ values: [StoredJSON], key: String, storage: any CaptureStorage) throws {
    let held = read(storage.data(forKey: key))
    var known = Set(held.map(\.value))
    let now = EntryTimestamp.string(from: Date())
    let added = values.compactMap { value -> Item? in
      known.insert(value).inserted ? Item(quarantinedAt: now, value: value) : nil
    }
    guard !added.isEmpty else { return }
    try write(held + added, key: key, storage: storage)
  }

  /// Stores exactly these items, or removes the quarantine when there are none.
  static func write(_ items: [Item], key: String, storage: any CaptureStorage) throws {
    guard !items.isEmpty else {
      try storage.remove(forKey: key)
      return
    }
    let array = items.map { ["quarantinedAt": $0.quarantinedAt, "value": $0.value.object] }
    try storage.set(
      JSONSerialization.data(withJSONObject: array, options: [.sortedKeys, .withoutEscapingSlashes]),
      forKey: key)
  }
}

/// A stored capture that cannot be sent, as the person sees it, like Web `UnreadableCapture`.
struct UnreadableCapture: Equatable, Identifiable, Sendable {
  /// The stored form, which identifies it until it is discarded.
  let key: String
  /// The title and note it holds, or its stored form when it holds neither, for Copy text.
  let text: String
  /// The photo drafts it names, which stay out of the composer until it is discarded.
  let photoIDs: [UUID]

  var id: String { key }

  init(_ value: StoredJSON) {
    key = value.key
    let object = value.object
    text = Self.recoverableText(object).nonEmpty ?? value.key
    photoIDs = Self.photoIDs(object)
  }

  /// Web `recoverableText`: the title and the note, or the formatted note's text.
  private static func recoverableText(_ object: Any) -> String {
    if let text = object as? String { return text }
    guard let capture = object as? [String: Any] else { return "" }
    let title = capture["title"] as? String ?? ""
    let body = (capture["body"] as? String).flatMap(\.nonEmpty)
      ?? ((capture["bodyRich"] as? [String: Any])?["text"] as? String) ?? ""
    return [title, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  /// Web `unreadableAttachmentIds`.
  private static func photoIDs(_ object: Any) -> [UUID] {
    guard let capture = object as? [String: Any],
      let attachments = capture["attachments"] as? [Any]
    else { return [] }
    return attachments.compactMap {
      (($0 as? [String: Any])?["id"] as? String).flatMap(UUID.init(uuidString:))
    }
  }
}

/// What the stored queue holds: the captures that can be sent, and every stored item that
/// cannot be read as one, which is kept so the person can copy its writing.
struct ParsedCaptureQueue: Sendable {
  var entries: [QueuedCapture] = []
  var unreadable: [StoredJSON] = []
}

/// Captures waiting on this iPhone, like Web `inbox-queue.ts`. Reading never writes. Before
/// any write, whatever could not be read moves to the quarantine, and the write is refused
/// when that fails, so a reduced queue is never stored over what it could not read.
struct CaptureQueueStore: Sendable {
  static let maximumEntryCount = 100
  /// Queue versions this release reads. It always writes the newest.
  static let readableVersions: Set<Int> = [1, 2, 3]
  static let currentVersion = 3

  private let storage: any CaptureStorage

  init(defaults: UserDefaults = .standard) {
    storage = UserDefaultsCaptureStorage(defaults: defaults)
  }

  init(storage: any CaptureStorage) {
    self.storage = storage
  }

  /// The captures that can be sent.
  func load(ownerID: UUID) -> [QueuedCapture] {
    read(ownerID: ownerID).entries
  }

  func enqueue(_ entry: QueuedCapture, ownerID: UUID) -> [QueuedCapture]? {
    let state = read(ownerID: ownerID)

    if state.entries.contains(where: { $0.id == entry.id }) {
      return state.entries
    }

    guard entry.isValid, state.entries.count < Self.maximumEntryCount else {
      return nil
    }

    let nextQueue = state.entries + [entry]
    return write(state, nextQueue, ownerID: ownerID) ? nextQueue : nil
  }

  func remove(entryID: UUID, ownerID: UUID) -> [QueuedCapture]? {
    let state = read(ownerID: ownerID)
    let nextQueue = state.entries.filter { $0.id != entryID }
    return write(state, nextQueue, ownerID: ownerID) ? nextQueue : nil
  }

  /// Marks one capture as refused in place, keeping its content and position, like Web
  /// `rejectInboxQueueEntry`. A capture that is no longer queued is not brought back.
  func markRejected(
    entryID: UUID, rejection: QueuedCaptureRejection, ownerID: UUID
  ) -> [QueuedCapture]? {
    let state = read(ownerID: ownerID)
    guard state.entries.contains(where: { $0.id == entryID }) else { return state.entries }

    let nextQueue = state.entries.map { entry in
      guard entry.id == entryID else { return entry }
      var rejected = entry
      rejected.rejection = rejection
      return rejected
    }
    return write(state, nextQueue, ownerID: ownerID) ? nextQueue : nil
  }

  /// Every stored capture that cannot be sent, in the quarantine or still in the queue.
  func unreadableCaptures(ownerID: UUID) -> [UnreadableCapture] {
    var seen = Set<StoredJSON>()
    return (quarantine(ownerID: ownerID).map(\.value) + read(ownerID: ownerID).unreadable)
      .filter { seen.insert($0).inserted }
      .map(UnreadableCapture.init)
  }

  /// Removes one unreadable capture for good, like Web `discardUnreadableCapture`. Its photo
  /// drafts go first, except any another stored capture still names, so a failure leaves it
  /// listed for another try. Every other unreadable item is set aside, never dropped.
  func discardUnreadable(
    _ capture: UnreadableCapture, ownerID: UUID, removePhoto: (UUID) throws -> Void
  ) -> Bool {
    let state = read(ownerID: ownerID)
    let held = quarantine(ownerID: ownerID)
    let now = EntryTimestamp.string(from: Date())
    var seen = Set<String>()
    let kept = (held + state.unreadable.map { CaptureQuarantine.Item(quarantinedAt: now, value: $0) })
      .filter { $0.value.key != capture.key && seen.insert($0.value.key).inserted }
    let stillNamed = Set(
      state.entries.flatMap { $0.attachments.map(\.id) }
        + kept.flatMap { UnreadableCapture($0.value).photoIDs })

    do {
      for photoID in capture.photoIDs where !stillNamed.contains(photoID) {
        try removePhoto(photoID)
      }
      try CaptureQuarantine.write(kept, key: Self.quarantineKey(ownerID: ownerID), storage: storage)
      // The queue only loses items that are now safe in the quarantine.
      if !state.unreadable.isEmpty {
        try store(state.entries, ownerID: ownerID)
      }
      return true
    } catch {
      return false
    }
  }

  static func storageKey(ownerID: UUID) -> String {
    "memotrail.inboxQueue.\(ownerID.uuidString.lowercased())"
  }

  static func quarantineKey(ownerID: UUID) -> String {
    "memotrail.inboxQueueQuarantine.\(ownerID.uuidString.lowercased())"
  }

  /// Web `parseInboxQueue`: valid captures load; an item that fails to decode or validate, an
  /// id repeated with different content, every item of an unknown version, and a queue that
  /// cannot be read at all become unreadable items. An exact repeat is the same capture.
  static func parse(_ data: Data?) -> ParsedCaptureQueue {
    guard let data, !data.isEmpty else { return ParsedCaptureQueue() }
    guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else { return ParsedCaptureQueue(unreadable: [StoredJSON(raw: data)]) }
    guard let queue = root as? [String: Any], let items = queue["entries"] as? [Any] else {
      return ParsedCaptureQueue(unreadable: [StoredJSON(raw: data)])
    }
    let isReadableVersion = (queue["version"] as? Int).map { readableVersions.contains($0) } ?? false

    var parsed = ParsedCaptureQueue()
    var seen: [UUID: StoredJSON] = [:]
    let decoder = JSONDecoder()
    for item in items {
      guard let stored = StoredJSON(item) else { continue }
      guard isReadableVersion,
        let capture = try? decoder.decode(QueuedCapture.self, from: stored.data),
        capture.isValid
      else {
        parsed.unreadable.append(stored)
        continue
      }
      if let earlier = seen[capture.id] {
        // The same id with different content: keep the first and set this one aside.
        if earlier != stored { parsed.unreadable.append(stored) }
        continue
      }
      seen[capture.id] = stored
      parsed.entries.append(capture)
    }
    return parsed
  }

  private func read(ownerID: UUID) -> ParsedCaptureQueue {
    Self.parse(storage.data(forKey: Self.storageKey(ownerID: ownerID)))
  }

  private func quarantine(ownerID: UUID) -> [CaptureQuarantine.Item] {
    CaptureQuarantine.read(storage.data(forKey: Self.quarantineKey(ownerID: ownerID)))
  }

  /// Stores the captures that can be sent, after setting aside anything unreadable in the
  /// stored queue. Nothing is written when that fails.
  private func write(_ state: ParsedCaptureQueue, _ nextQueue: [QueuedCapture], ownerID: UUID)
    -> Bool
  {
    do {
      if !state.unreadable.isEmpty {
        try CaptureQuarantine.add(
          state.unreadable, key: Self.quarantineKey(ownerID: ownerID), storage: storage)
      }
      try store(nextQueue, ownerID: ownerID)
      return true
    } catch {
      return false
    }
  }

  private func store(_ entries: [QueuedCapture], ownerID: UUID) throws {
    let key = Self.storageKey(ownerID: ownerID)
    guard !entries.isEmpty else {
      try storage.remove(forKey: key)
      return
    }
    try storage.set(
      JSONEncoder().encode(StoredCaptureQueue(version: Self.currentVersion, entries: entries)),
      forKey: key)
  }
}

private struct StoredCaptureQueue: Codable {
  let version: Int
  let entries: [QueuedCapture]
}

struct CapturePhotoStore: Sendable {
  private let rootURL: URL

  init(rootURL: URL? = nil) {
    self.rootURL =
      rootURL
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "MemoTrail/Capture Photos", directoryHint: .isDirectory)
  }

  func load(ownerID: UUID) throws -> [PhotoDraft] {
    let directory = ownerDirectory(ownerID)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

    let metadataURLs = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }

    return metadataURLs.compactMap { metadataURL -> (Date, PhotoDraft)? in
      guard
        let metadata = try? JSONDecoder().decode(
          StoredCapturePhoto.self,
          from: Data(contentsOf: metadataURL)
        ),
        metadata.isValid,
        metadataURL.deletingPathExtension().lastPathComponent
          == metadata.id.uuidString.lowercased(),
        let data = try? Data(contentsOf: dataURL(metadata, ownerID: ownerID)),
        data.count == metadata.byteSize,
        PhotoImageType.detect(data: data, typeIdentifiers: []) == metadata.mimeType,
        let draft = try? PhotoDraft.validate(
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

  func save(_ draft: PhotoDraft, ownerID: UUID) throws {
    let directory = ownerDirectory(ownerID)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )

    let metadata = StoredCapturePhoto(draft: draft)
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

  private func dataURL(_ metadata: StoredCapturePhoto, ownerID: UUID) -> URL {
    ownerDirectory(ownerID).appending(
      path: "\(metadata.id.uuidString.lowercased()).\(metadata.mimeType.fileExtension)",
      directoryHint: .notDirectory
    )
  }
}

private struct StoredCapturePhoto: Codable {
  let id: UUID
  let mimeType: PhotoImageType
  let originalFilename: String?
  let byteSize: Int
  let pixelWidth: Int?
  let pixelHeight: Int?
  let createdAt: Date

  init(draft: PhotoDraft) {
    id = draft.id
    mimeType = draft.mimeType
    originalFilename = draft.originalFilename
    byteSize = draft.data.count
    pixelWidth = draft.pixelWidth
    pixelHeight = draft.pixelHeight
    createdAt = Date()
  }

  var isValid: Bool {
    QueuedCaptureAttachment(
      id: id,
      mimeType: mimeType,
      originalFilename: originalFilename,
      byteSize: Int64(byteSize),
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    ).isValid
  }
}

enum CaptureError: LocalizedError, Equatable {
  case empty
  case titleTooLong
  case bodyTooLong
  case photoUnavailable

  var errorDescription: String? {
    switch self {
    case .empty:
      "Write a title, a note, or add a photo before saving."
    case .titleTooLong:
      "Keep the title under \(CaptureInput.titleLimit) characters."
    case .bodyTooLong:
      "Keep the note under 50,000 characters."
    case .photoUnavailable:
      "MemoTrail could not read that photo. Select it again."
    }
  }
}

/// The `entries` row a queued capture becomes, exactly the columns Web `syncInboxEntry` inserts.
/// Every capture is a plain Entry; the id is the capture's own, so a repeated insert finds it.
struct CaptureInsert: Encodable, Equatable, Sendable {
  let id: UUID
  let ownerID: UUID
  let title: String?
  let body: String
  let occurrence: EntryOccurrence
  /// Web's `metadataWithEntryRichText`: `body_rich` when present, otherwise empty.
  let bodyRich: EntryEmphasisContent?

  init(_ capture: QueuedCapture, ownerID: UUID) {
    id = capture.id
    self.ownerID = ownerID
    title = capture.title
    body = capture.body
    occurrence = capture.effectiveOccurrence
    bodyRich = capture.bodyRich
  }

  var clientID: String { "ios:\(id.uuidString.lowercased())" }

  enum CodingKeys: String, CodingKey {
    case id, title, body, metadata
    case ownerID = "owner_id"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case clientID = "client_id"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id.uuidString.lowercased(), forKey: .id)
    try values.encode(ownerID.uuidString.lowercased(), forKey: .ownerID)
    try values.encode(title, forKey: .title)
    try values.encode(body, forKey: .body)
    try values.encode("entry", forKey: .itemKind)
    try values.encode("entry", forKey: .itemSubtype)
    try values.encode(occurrence.start.map(EntryTimestamp.string(from:)), forKey: .occurredStart)
    try values.encode(occurrence.timezone, forKey: .occurredTimezone)
    try values.encode(occurrence.precision, forKey: .datePrecision)
    try values.encode(occurrence.end.map(EntryTimestamp.string(from:)), forKey: .occurredEnd)
    try values.encode(occurrence.label, forKey: .occurredLabel)
    try values.encode(clientID, forKey: .clientID)
    try values.encode(
      bodyRich.map { [EntryRichText.metadataKey: $0] } ?? [:], forKey: .metadata)
  }
}
