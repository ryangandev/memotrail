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
  /// The latest capture or sync problem, shown in the composer until the next attempt.
  private(set) var captureError: String?

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
          "id,title,body,metadata,item_kind,item_subtype,inbox_status,created_at,occurred_start,occurred_end,occurred_label,date_precision,occurred_timezone,revision"
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
    bodyRich: EntryEmphasisContent? = nil,
    occurredAt: Date? = nil,
    occurrenceDraft: OccurrenceDraft? = nil,
    photos: [FirstTimePhotoDraft] = []
  ) async -> Bool {
    guard !isSaving, !isSyncing else { return false }

    let capture: InboxCapture
    let occurrence: EntryOccurrence
    let now = Date()
    do {
      occurrence =
        try occurrenceDraft?.resolve()
        ?? EntryOccurrence(
          precision: .exact, start: occurredAt ?? now, end: nil, label: nil,
          timezone: TimeZone.current.identifier)
      try occurrence.validate()
      capture = try InboxCapture.validate(
        title: title,
        body: body,
        hasAttachments: !photos.isEmpty
      )
    } catch {
      captureError = error.localizedDescription
      return false
    }

    isSaving = true
    captureError = nil
    defer { isSaving = false }

    var pendingEntry = QueuedInboxEntry(
      id: UUID(),
      title: capture.title,
      body: capture.body,
      occurredAt: occurrence.start,
      occurredTimezone: occurrence.timezone,
      queuedAt: now,
      attachments: photos.map(QueuedInboxAttachment.init)
    )
    pendingEntry.occurrence = occurrence
    // Like Web, keep formatting only when it describes exactly the saved note.
    pendingEntry.bodyRich = bodyRich?.isValid(expectedText: capture.body) == true ? bodyRich : nil

    guard let nextQueue = queueStore.enqueue(pendingEntry, ownerID: ownerID) else {
      captureError =
        "MemoTrail could not store this Entry on this iPhone. Your draft is still here."
      return false
    }

    pendingEntries = nextQueue

    Task { @MainActor [weak self] in
      guard let self else { return }
      let didSync = await self.synchronizePendingEntries()
      if didSync {
        await self.load()
      }
    }

    return true
  }

  /// Saves the composer's note, keeping its Web-compatible formatting.
  func save(
    title: String, note: NSAttributedString, occurrenceDraft: OccurrenceDraft?,
    photos: [FirstTimePhotoDraft]
  ) async -> Bool {
    let captured = EntryEmphasisContent.capture(note)
    return await save(
      title: title, body: captured.body, bodyRich: captured.rich,
      occurrenceDraft: occurrenceDraft, photos: photos)
  }

  /// Saves the Review Entry sheet, keeping the Inbox list in step like Web `EntryReviewList`.
  func review(entry: InboxEntry, draft: EntryReviewDraft, intent: ReviewIntent) async
    -> ReviewResult
  {
    let input: InboxReviewInput
    let revision: Int
    switch await Self.submitReview(
      client: client, ownerID: ownerID, entry: entry, draft: draft, intent: intent)
    {
    case .failed(let result):
      return result
    case .saved(let savedInput, let savedRevision):
      input = savedInput
      revision = savedRevision
    }

    if intent == .done {
      entries.removeAll { $0.id == entry.id }
      return ReviewResult(message: "Entry organized.", status: .done)
    }

    var updatedEntry = InboxEntry(
      id: entry.id,
      title: input.title,
      body: input.body,
      collectionNames: input.collectionNames,
      itemKind: input.itemKind,
      itemSubtype: input.itemSubtype,
      createdAt: entry.createdAt,
      occurredStart: input.occurredAt,
      occurredTimezone: input.occurredTimezone,
      revision: revision,
      tagNames: input.tagNames,
      datePrecision: input.occurrence.precision,
      occurredEnd: input.occurrence.end,
      occurredLabel: input.occurrence.label
    )
    updatedEntry.inboxStatus = entry.inboxStatus
    updatedEntry.bodyRich = input.bodyRich

    if let index = entries.firstIndex(where: { $0.id == entry.id }) {
      entries[index] = updatedEntry
    }
    collectionOptions = mergedOptions(collectionOptions, input.collectionNames)
    tagOptions = mergedOptions(tagOptions, input.tagNames)
    return ReviewResult(message: "Entry saved.", status: .saved)
  }

  /// Moves a capture to Trash like Web `trashWikiItem`, only at the revision the person saw.
  /// Returns a message when the capture could not be moved.
  func moveToTrash(_ entry: InboxEntry) async -> String? {
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }
      let rows: [ExistingEntry] =
        try await client
        .from("entries")
        .update(EntryTrashUpdate(deletedAt: Date()))
        .eq("id", value: entry.id.uuidString)
        .eq("owner_id", value: ownerID.uuidString)
        .eq("revision", value: entry.revision)
        .is("deleted_at", value: nil)
        .select("id")
        .execute()
        .value
      guard rows.first?.id == entry.id else {
        return "This item changed on another device or is already in Trash. Refresh and try again."
      }
      entries.removeAll { $0.id == entry.id }
      return nil
    } catch is PostgrestError {
      return "MemoTrail could not move this item to Trash."
    } catch {
      return "Could not confirm the move to Trash. Refresh before trying again."
    }
  }

  /// Web `reviewInboxEntry`: validates a Review Entry draft and saves it, with its formatting,
  /// through the review function that leaves the Entry's Location unchanged.
  static func submitReview(
    client: SupabaseClient, ownerID: UUID, entry: InboxEntry, draft: EntryReviewDraft,
    intent: ReviewIntent
  ) async -> ReviewSubmission {
    let input: InboxReviewInput
    do {
      try draft.photoPlace?.validate()
      input = try InboxReviewInput.validate(
        entryID: entry.id,
        revision: entry.revision,
        title: draft.title,
        body: draft.body,
        bodyRich: draft.bodyRich,
        collectionNames: draft.collectionNames,
        itemKind: entry.itemKind,
        itemSubtype: entry.itemSubtype,
        occurredAt: draft.occurrence.start,
        occurredTimezone: draft.occurrence.timezone,
        tagNames: draft.tagNames,
        datePrecision: draft.occurrence.precision,
        occurredEnd: draft.occurrence.end,
        occurredLabel: draft.occurrence.label
      )
    } catch {
      return .failed(ReviewResult(message: error.localizedDescription, status: .error))
    }

    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }

      var parameters = ReviewEntryParameters(
        entryID: input.entryID,
        expectedRevision: input.revision,
        title: input.title,
        body: input.body,
        itemKind: input.itemKind,
        itemSubtype: input.itemSubtype,
        occurredStart: input.occurredAt,
        occurredTimezone: input.occurredTimezone,
        collectionNames: input.collectionNames,
        tagNames: input.tagNames,
        markDone: intent == .done,
        datePrecision: input.occurrence.precision,
        occurredEnd: input.occurrence.end,
        occurredLabel: input.occurrence.label,
        photoPlace: draft.photoPlace,
        occurredStartRaw: input.occurredAt == entry.occurredStart ? entry.occurredStartRaw : nil,
        occurredEndRaw: input.occurrence.end == entry.occurredEnd ? entry.occurredEndRaw : nil
      )
      parameters.bodyRich = input.bodyRich
      let results: [ReviewedEntryResult] =
        try await client
        .rpc("review_wiki_item_with_photo_place_rich", params: parameters)
        .execute()
        .value

      guard let result = results.first, result.entryID == entry.id else {
        return .failed(
          ReviewResult(
            message:
              "This Entry changed on another device. Close it, refresh, and review the latest version.",
            status: .conflict))
      }
      return .saved(input, revision: result.revision)
    } catch let error as PostgrestError where error.code == "40001" {
      return .failed(
        ReviewResult(
          message:
            "The photo or Location changed. Close this review, refresh, and confirm the latest version before saving.",
          status: .conflict))
    } catch {
      return .failed(
        ReviewResult(message: "MemoTrail could not save these changes. Try again.", status: .error))
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
      captureError = "Your session expired. Sign in again to sync pending Entries."
      return false
    }

    var didSyncEntry = false
    var lastSyncedPhotoCount = 0

    for entry in pendingEntries {
      do {
        try await insert(entry)
      } catch {
        guard await entryAlreadyExists(entry.id) else {
          captureError = "Saved on this iPhone. MemoTrail will retry when you are online."
          return didSyncEntry
        }
      }

      do {
        try await synchronizeAttachments(entry)
      } catch {
        captureError = attachmentSyncMessage(for: error)
        return didSyncEntry
      }

      guard let nextQueue = queueStore.remove(entryID: entry.id, ownerID: ownerID) else {
        captureError =
          "This Entry reached MemoTrail, but its local pending copy could not be cleared."
        return didSyncEntry
      }

      pendingEntries = nextQueue
      if AppConfiguration.aiEnabled {
        Task { [weak self] in
          // Optional suggestions cannot delay capture or requeue a successfully saved Entry.
          guard let self,
            let revision = try? await EntryPhotoUpload.writingRevision(
              client: self.client, entryID: entry.id, revision: 1)
          else { return }
          _ = try? await self.aiSuggestions(entryID: entry.id, revision: revision)
        }
      }
      didSyncEntry = true
      lastSyncedPhotoCount = entry.attachments.count
    }

    if didSyncEntry {
      // Like Web, a synced capture is announced once; only problems stay in the composer.
      captureError = nil
      MTToastCenter.shared.success(
        lastSyncedPhotoCount > 0
          ? "Saved to Inbox with \(countLabel(lastSyncedPhotoCount, "photo"))."
          : "Saved to Inbox.")
    }

    return didSyncEntry
  }

  private func insert(_ entry: QueuedInboxEntry) async throws {
    let payload = InboxEntryInsert(
      id: entry.id,
      ownerID: ownerID,
      title: entry.title,
      body: entry.body,
      occurredStart: entry.effectiveOccurrence.start,
      occurredTimezone: entry.effectiveOccurrence.timezone,
      datePrecision: entry.effectiveOccurrence.precision.rawValue,
      occurredEnd: entry.effectiveOccurrence.end,
      occurredLabel: entry.effectiveOccurrence.label,
      clientID: "ios:\(entry.id.uuidString.lowercased())",
      metadata: entry.bodyRich.map { [EntryRichText.metadataKey: $0] } ?? [:]
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

        do {
          try await client.storage.from("entry-media").upload(
            path,
            data: draft.data,
            options: FileOptions(
              cacheControl: "3600",
              contentType: attachment.mimeType.rawValue,
              upsert: false
            )
          )
        } catch {
          // A lost upload response may already have persisted the immutable original.
          // Registration below validates its existence without overwriting its bytes.
          try Task.checkCancellation()
        }
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
      .select("entry_id,collection:collections(name,archived_at)")
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
  enum ReviewIntent: Sendable {
    case done
    case save
  }

  enum ReviewSubmission: Sendable {
    case saved(InboxReviewInput, revision: Int)
    case failed(ReviewResult)
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

private struct EntryTrashUpdate: Encodable, Sendable {
  let deletedAt: Date

  enum CodingKeys: String, CodingKey {
    case deletedAt = "deleted_at"
  }
}

struct InboxEntryInsert: Encodable, Sendable {
  let id: UUID
  let ownerID: UUID
  let title: String?
  let body: String
  let itemKind = "entry"
  let itemSubtype = "entry"
  let inboxStatus = "unreviewed"
  let occurredStart: Date?
  let occurredTimezone: String
  var datePrecision = "exact"
  var occurredEnd: Date? = nil
  var occurredLabel: String? = nil
  let clientID: String
  /// Web's `metadataWithEntryRichText`: `body_rich` when present, otherwise empty.
  var metadata: [String: EntryEmphasisContent] = [:]

  enum CodingKeys: String, CodingKey {
    case id
    case ownerID = "owner_id"
    case title
    case body
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case clientID = "client_id"
    case metadata
  }
}

struct ReviewEntryParameters: Encodable, Sendable {
  let entryID: UUID
  let expectedRevision: Int
  let title: String?
  let body: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let occurredStart: Date?
  let occurredTimezone: String
  let collectionNames: [String]
  let tagNames: [String]
  let markDone: Bool
  var datePrecision: TimelineDatePrecision = .exact
  var occurredEnd: Date? = nil
  var occurredLabel: String? = nil
  var photoPlace: PhotoPlaceDraft? = nil
  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil
  /// Web `p_body_rich`: the note's formatting, or null to clear formatting that no longer fits.
  var bodyRich: EntryRichText? = nil

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
    case title = "p_title"
    case body = "p_body"
    case itemKind = "p_item_kind"
    case itemSubtype = "p_item_subtype"
    case occurredStart = "p_occurred_start"
    case occurredTimezone = "p_occurred_timezone"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case markDone = "p_mark_done"
    case datePrecision = "p_date_precision"
    case occurredEnd = "p_occurred_end"
    case occurredLabel = "p_occurred_label"
    case photoPlace = "p_photo_place"
    case bodyRich = "p_body_rich"
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
    try values.encode(itemKind, forKey: .itemKind)
    try values.encode(itemSubtype, forKey: .itemSubtype)
    if let occurredStartRaw {
      try values.encode(occurredStartRaw, forKey: .occurredStart)
    } else {
      try values.encode(occurredStart, forKey: .occurredStart)
    }
    try values.encode(occurredTimezone, forKey: .occurredTimezone)
    try values.encode(collectionNames, forKey: .collectionNames)
    try values.encode(tagNames, forKey: .tagNames)
    try values.encode(markDone, forKey: .markDone)
    try values.encode(datePrecision, forKey: .datePrecision)
    if let occurredEndRaw {
      try values.encode(occurredEndRaw, forKey: .occurredEnd)
    } else {
      try values.encode(occurredEnd, forKey: .occurredEnd)
    }
    try values.encode(occurredLabel, forKey: .occurredLabel)
    try values.encode(photoPlace, forKey: .photoPlace)
    try values.encode(bodyRich, forKey: .bodyRich)
  }
}

struct ReviewedEntryResult: Decodable, Sendable {
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
  let collection: InboxCollectionName?

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case collection
  }
}

private struct InboxCollectionName: Decodable, Sendable {
  let name: String
  let archivedAt: String?
  enum CodingKeys: String, CodingKey {
    case name
    case archivedAt = "archived_at"
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
      rows.filter { $0.collection?.archivedAt == nil }.compactMap(\.collection?.name)
        .sortedCaseInsensitively()
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
