import Foundation
@preconcurrency import Network
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class InboxController {
  private(set) var entries: [InboxEntry] = []
  private(set) var collectionOptions: [String] = []
  private(set) var pendingEntries: [QueuedInboxEntry]
  private(set) var tagOptions: [String] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var isSyncing = false
  private(set) var loadErrorMessage: String?
  private(set) var captureMessage: CaptureMessage?

  private let client: SupabaseClient
  private let ownerID: UUID

  func aiSuggestions(entryID: UUID, revision: Int, retry: Bool = false) async throws
    -> EntryAISuggestionResponse
  {
    try await AIAPI.post(
      "suggestions",
      body: EntryAISuggestionInput(entryID: entryID, revision: revision, retry: retry),
      client: client, ownerID: ownerID)
  }

  func dismissAISuggestion(_ id: UUID) async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw InboxControllerError.ownerChanged
    }
    let success: Bool = try await client.rpc(
      "dismiss_ai_suggestion", params: ["p_id": id.uuidString]
    ).execute().value
    if !success { throw URLError(.cannotParseResponse) }
  }
  private let queueStore: InboxQueueStore
  private let photoStore: InboxPhotoStore
  private let networkMonitor: NWPathMonitor
  private let networkMonitorQueue = DispatchQueue(
    label: "com.rystudio.memotrail.inbox-connectivity"
  )

  init(
    client: SupabaseClient,
    ownerID: UUID,
    queueStore: InboxQueueStore = InboxQueueStore(),
    photoStore: InboxPhotoStore = InboxPhotoStore(),
    networkMonitor: NWPathMonitor = NWPathMonitor()
  ) {
    self.client = client
    self.ownerID = ownerID
    self.queueStore = queueStore
    self.photoStore = photoStore
    self.networkMonitor = networkMonitor
    pendingEntries = queueStore.load(ownerID: ownerID)

    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }

      Task { @MainActor [weak self] in
        guard let self else { return }
        let didSync = await self.synchronizePendingEntries()
        if didSync {
          await self.load()
        }
      }
    }
    networkMonitor.start(queue: networkMonitorQueue)
  }

  deinit {
    networkMonitor.cancel()
  }

  func load() async {
    guard !isLoading else { return }

    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }

      let loadedEntries: [InboxEntry] =
        try await client
        .from("entries")
        .select(
          "id,title,body,entry_type,created_at,occurred_start,occurred_timezone,revision"
        )
        .eq("owner_id", value: ownerID.uuidString)
        .eq("inbox_status", value: "unreviewed")
        .is("deleted_at", value: nil)
        .order("created_at", ascending: false)
        .limit(50)
        .execute()
        .value

      let organization = try await loadOrganization(
        entryIDs: loadedEntries.map(\.id)
      )
      collectionOptions = organization.collectionOptions
      tagOptions = organization.tagOptions
      entries = loadedEntries.map { entry in
        entry.withOrganization(
          collectionNames: organization.collectionNamesByEntry[entry.id] ?? [],
          tagNames: organization.tagNamesByEntry[entry.id] ?? []
        )
      }
    } catch {
      loadErrorMessage = "MemoTrail could not load your Inbox. Pull to refresh or try again."
    }
  }

  func refresh() async {
    _ = await synchronizePendingEntries()
    await load()
  }

  func save(
    title: String,
    body: String,
    occurredAt: Date? = nil,
    photos: [FirstTimePhotoDraft] = []
  ) async -> Bool {
    guard !isSaving, !isSyncing else { return false }

    let capture: InboxCapture
    do {
      capture = try InboxCapture.validate(
        title: title,
        body: body,
        hasAttachments: !photos.isEmpty
      )
    } catch {
      captureMessage = CaptureMessage(
        text: error.localizedDescription,
        style: .error
      )
      return false
    }

    isSaving = true
    captureMessage = nil
    defer { isSaving = false }

    let now = Date()
    let pendingEntry = QueuedInboxEntry(
      id: UUID(),
      title: capture.title,
      body: capture.body,
      occurredAt: occurredAt ?? now,
      occurredTimezone: TimeZone.current.identifier,
      queuedAt: now,
      attachments: photos.map(QueuedInboxAttachment.init)
    )

    guard let nextQueue = queueStore.enqueue(pendingEntry, ownerID: ownerID) else {
      captureMessage = CaptureMessage(
        text: "MemoTrail could not store this Entry on this iPhone. Your draft is still here.",
        style: .error
      )
      return false
    }

    pendingEntries = nextQueue
    captureMessage = CaptureMessage(
      text: "Saved on this iPhone. Syncing when connected.",
      style: .success
    )

    Task { @MainActor [weak self] in
      guard let self else { return }
      let didSync = await self.synchronizePendingEntries()
      if didSync {
        await self.load()
      }
    }

    return true
  }

  func review(
    entry: InboxEntry,
    title: String,
    body: String,
    collectionNames: [String],
    entryType: InboxEntryType,
    occurredAt: Date,
    occurredTimezone: String,
    tagNames: [String],
    intent: ReviewIntent
  ) async -> ReviewResult {
    let input: InboxReviewInput

    do {
      input = try InboxReviewInput.validate(
        entryID: entry.id,
        revision: entry.revision,
        title: title,
        body: body,
        collectionNames: collectionNames,
        entryType: entryType,
        occurredAt: occurredAt,
        occurredTimezone: occurredTimezone,
        tagNames: tagNames
      )
    } catch {
      return ReviewResult(message: error.localizedDescription, status: .error)
    }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }

      let parameters = ReviewEntryParameters(
        entryID: input.entryID,
        expectedRevision: input.revision,
        title: input.title,
        body: input.body,
        entryType: input.entryType,
        occurredStart: input.occurredAt,
        occurredTimezone: input.occurredTimezone,
        collectionNames: input.collectionNames,
        tagNames: input.tagNames,
        markDone: intent == .done
      )
      let reviewResults: [ReviewedEntryResult] =
        try await client
        .rpc("review_entry", params: parameters)
        .execute()
        .value

      guard let reviewResult = reviewResults.first else {
        return ReviewResult(
          message:
            "This Entry changed on another device. Close it, refresh, and review the latest version.",
          status: .conflict
        )
      }

      if intent == .done {
        entries.removeAll { $0.id == reviewResult.entryID }
        return ReviewResult(message: "Entry organized.", status: .done)
      }

      let updatedEntry = InboxEntry(
        id: entry.id,
        title: input.title,
        body: input.body,
        collectionNames: input.collectionNames,
        entryType: input.entryType,
        createdAt: entry.createdAt,
        occurredStart: input.occurredAt,
        occurredTimezone: input.occurredTimezone,
        revision: reviewResult.revision,
        tagNames: input.tagNames
      )

      if let index = entries.firstIndex(where: { $0.id == reviewResult.entryID }) {
        entries[index] = updatedEntry
      }
      collectionOptions = mergedOptions(collectionOptions, input.collectionNames)
      tagOptions = mergedOptions(tagOptions, input.tagNames)
      return ReviewResult(message: "Changes saved.", status: .saved)
    } catch {
      return ReviewResult(
        message: "MemoTrail could not save these changes. Try again.",
        status: .error
      )
    }
  }

  @discardableResult
  func synchronizePendingEntries() async -> Bool {
    guard !isSyncing, !pendingEntries.isEmpty else { return false }

    isSyncing = true
    defer { isSyncing = false }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }
    } catch {
      captureMessage = CaptureMessage(
        text: "Your session expired. Sign in again to sync pending Entries.",
        style: .error
      )
      return false
    }

    var didSyncEntry = false
    var lastSyncedPhotoCount = 0

    for entry in pendingEntries {
      do {
        try await insert(entry)
      } catch {
        guard await entryAlreadyExists(entry.id) else {
          captureMessage = CaptureMessage(
            text: "Saved on this iPhone. MemoTrail will retry when you are online.",
            style: .error
          )
          return didSyncEntry
        }
      }

      do {
        try await synchronizeAttachments(entry)
      } catch {
        captureMessage = CaptureMessage(
          text: attachmentSyncMessage(for: error),
          style: .error
        )
        return didSyncEntry
      }

      guard let nextQueue = queueStore.remove(entryID: entry.id, ownerID: ownerID) else {
        captureMessage = CaptureMessage(
          text: "This Entry reached MemoTrail, but its local pending copy could not be cleared.",
          style: .error
        )
        return didSyncEntry
      }

      pendingEntries = nextQueue
      Task { [weak self] in
        // Optional suggestions cannot delay capture or requeue a successfully saved Entry.
        _ = try? await self?.aiSuggestions(entryID: entry.id, revision: 1)
      }
      didSyncEntry = true
      lastSyncedPhotoCount = entry.attachments.count
    }

    if didSyncEntry {
      captureMessage = CaptureMessage(
        text: lastSyncedPhotoCount > 0
          ? "Saved to Inbox with \(lastSyncedPhotoCount) \(lastSyncedPhotoCount == 1 ? "photo" : "photos")."
          : "Saved to Inbox.",
        style: .success
      )
    }

    return didSyncEntry
  }

  private func insert(_ entry: QueuedInboxEntry) async throws {
    let payload = InboxEntryInsert(
      id: entry.id,
      ownerID: ownerID,
      title: entry.title,
      body: entry.body,
      occurredStart: entry.occurredAt,
      occurredTimezone: entry.occurredTimezone,
      clientID: "ios:\(entry.id.uuidString.lowercased())"
    )

    try await client
      .from("entries")
      .insert(payload)
      .execute()
  }

  private func entryAlreadyExists(_ entryID: UUID) async -> Bool {
    do {
      let matchingEntries: [ExistingEntry] =
        try await client
        .from("entries")
        .select("id")
        .eq("id", value: entryID.uuidString)
        .eq("owner_id", value: ownerID.uuidString)
        .limit(1)
        .execute()
        .value

      return matchingEntries.first?.id == entryID
    } catch {
      return false
    }
  }

  private func synchronizeAttachments(_ entry: QueuedInboxEntry) async throws {
    guard !entry.attachments.isEmpty else { return }

    let photoStore = photoStore
    let ownerID = ownerID
    let drafts = try await Task.detached {
      try photoStore.load(ownerID: ownerID)
    }.value
    let draftsByID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })

    for attachment in entry.attachments {
      let path = attachment.objectPath(ownerID: ownerID, entryID: entry.id)
      let draft = draftsByID[attachment.id]

      if let draft {
        guard attachment.matches(draft) else {
          throw InboxControllerError.photoChanged
        }

        try await client.storage.from("entry-media").upload(
          path,
          data: draft.data,
          options: FileOptions(
            cacheControl: "3600",
            contentType: attachment.mimeType.rawValue,
            upsert: true
          )
        )
      }

      let registered: [RegisteredEntryAttachment]
      do {
        registered =
          try await client
          .rpc(
            "register_entry_attachment",
            params: RegisterEntryAttachmentParameters(
              entryID: entry.id,
              attachment: attachment,
              objectPath: path
            )
          )
          .execute()
          .value
      } catch {
        if draft == nil {
          throw InboxControllerError.photoMissing
        }
        throw error
      }

      guard registered.first?.attachmentID == attachment.id else {
        throw draft == nil
          ? InboxControllerError.photoMissing
          : InboxControllerError.photoRegistrationFailed
      }

      let attachmentID = attachment.id
      try await Task.detached {
        try photoStore.remove(photoID: attachmentID, ownerID: ownerID)
      }.value
    }
  }

  private func attachmentSyncMessage(for error: Error) -> String {
    if let error = error as? InboxControllerError {
      switch error {
      case .photoMissing:
        return "A pending photo is missing from this iPhone and needs your attention."
      case .photoChanged:
        return "A pending photo changed on this iPhone and cannot be synced."
      default:
        break
      }
    }

    return "Photos are saved on this iPhone. MemoTrail will retry when you are online."
  }

  private func loadOrganization(entryIDs: [UUID]) async throws -> OrganizationSnapshot {
    let collectionRows: [OrganizationName] =
      try await client
      .from("collections")
      .select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .is("archived_at", value: nil)
      .order("name")
      .execute()
      .value
    let tagRows: [OrganizationName] =
      try await client
      .from("tags")
      .select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .order("name")
      .execute()
      .value

    guard !entryIDs.isEmpty else {
      return OrganizationSnapshot(
        collectionNamesByEntry: [:],
        tagNamesByEntry: [:],
        collectionOptions: collectionRows.map(\.name),
        tagOptions: tagRows.map(\.name)
      )
    }

    let collectionRelationships: [EntryCollectionRelationship] =
      try await client
      .from("entry_collections")
      .select("entry_id,collection:collections(name)")
      .eq("owner_id", value: ownerID.uuidString)
      .in("entry_id", values: entryIDs)
      .execute()
      .value
    let tagRelationships: [EntryTagRelationship] =
      try await client
      .from("entry_tags")
      .select("entry_id,tag:tags(name)")
      .eq("owner_id", value: ownerID.uuidString)
      .in("entry_id", values: entryIDs)
      .execute()
      .value

    return OrganizationSnapshot(
      collectionNamesByEntry: collectionNamesByEntry(collectionRelationships),
      tagNamesByEntry: tagNamesByEntry(tagRelationships),
      collectionOptions: collectionRows.map(\.name),
      tagOptions: tagRows.map(\.name)
    )
  }
}

extension InboxController {
  struct CaptureMessage: Equatable, Sendable {
    enum Style: Sendable {
      case error
      case success
    }

    let text: String
    let style: Style
  }

  enum ReviewIntent: Sendable {
    case done
    case save
  }

  struct ReviewResult: Equatable, Sendable {
    enum Status: Sendable {
      case conflict
      case done
      case error
      case saved
    }

    let message: String
    let status: Status
  }
}

private struct ExistingEntry: Decodable, Sendable {
  let id: UUID
}

private struct InboxEntryInsert: Encodable, Sendable {
  let id: UUID
  let ownerID: UUID
  let title: String?
  let body: String
  let entryType = "standard"
  let inboxStatus = "unreviewed"
  let occurredStart: Date
  let occurredTimezone: String
  let datePrecision = "exact"
  let clientID: String

  enum CodingKeys: String, CodingKey {
    case id
    case ownerID = "owner_id"
    case title
    case body
    case entryType = "entry_type"
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case clientID = "client_id"
  }
}

struct ReviewEntryParameters: Encodable, Sendable {
  let entryID: UUID
  let expectedRevision: Int
  let title: String?
  let body: String
  let entryType: InboxEntryType
  let occurredStart: Date
  let occurredTimezone: String
  let collectionNames: [String]
  let tagNames: [String]
  let markDone: Bool

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
    case title = "p_title"
    case body = "p_body"
    case entryType = "p_entry_type"
    case occurredStart = "p_occurred_start"
    case occurredTimezone = "p_occurred_timezone"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case markDone = "p_mark_done"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)

    try values.encode(entryID, forKey: .entryID)
    try values.encode(expectedRevision, forKey: .expectedRevision)
    if let title {
      try values.encode(title, forKey: .title)
    } else {
      try values.encodeNil(forKey: .title)
    }
    try values.encode(body, forKey: .body)
    try values.encode(entryType, forKey: .entryType)
    try values.encode(occurredStart, forKey: .occurredStart)
    try values.encode(occurredTimezone, forKey: .occurredTimezone)
    try values.encode(collectionNames, forKey: .collectionNames)
    try values.encode(tagNames, forKey: .tagNames)
    try values.encode(markDone, forKey: .markDone)
  }
}

private struct ReviewedEntryResult: Decodable, Sendable {
  let entryID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
  }
}

private struct OrganizationName: Decodable, Sendable {
  let name: String
}

private struct EntryCollectionRelationship: Decodable, Sendable {
  let entryID: UUID
  let collection: OrganizationName?

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case collection
  }
}

private struct EntryTagRelationship: Decodable, Sendable {
  let entryID: UUID
  let tag: OrganizationName?

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case tag
  }
}

private struct OrganizationSnapshot: Sendable {
  let collectionNamesByEntry: [UUID: [String]]
  let tagNamesByEntry: [UUID: [String]]
  let collectionOptions: [String]
  let tagOptions: [String]
}

private func collectionNamesByEntry(
  _ relationships: [EntryCollectionRelationship]
) -> [UUID: [String]] {
  Dictionary(grouping: relationships, by: \.entryID)
    .mapValues { rows in
      rows.compactMap(\.collection?.name).sortedCaseInsensitively()
    }
}

private func tagNamesByEntry(
  _ relationships: [EntryTagRelationship]
) -> [UUID: [String]] {
  Dictionary(grouping: relationships, by: \.entryID)
    .mapValues { rows in
      rows.compactMap(\.tag?.name).sortedCaseInsensitively()
    }
}

private func mergedOptions(_ existing: [String], _ added: [String]) -> [String] {
  var optionsByName = Dictionary(
    uniqueKeysWithValues: existing.map { ($0.lowercased(), $0) }
  )

  for name in added {
    optionsByName[name.lowercased()] = optionsByName[name.lowercased()] ?? name
  }

  return Array(optionsByName.values).sortedCaseInsensitively()
}

extension Array where Element == String {
  fileprivate func sortedCaseInsensitively() -> [String] {
    sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }
}

private enum InboxControllerError: Error {
  case ownerChanged
  case photoChanged
  case photoMissing
  case photoRegistrationFailed
}
