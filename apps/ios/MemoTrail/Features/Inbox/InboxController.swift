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
  /// Captures saved since the last sync attempt began; that attempt decides how each is announced.
  private var unattemptedCaptureIDs: Set<UUID> = []
  /// Waiting captures already confirmed as safe on this iPhone, which retries do not announce.
  private var confirmedOfflineCaptureIDs: Set<UUID> = []

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
    unattemptedCaptureIDs.insert(pendingEntry.id)

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

  /// Pending captures that still try to reach MemoTrail.
  var waitingEntryCount: Int { pendingEntries.count { $0.rejection == nil } }

  /// Pending captures MemoTrail refused, kept until the person discards them.
  var rejectedEntryCount: Int { pendingEntries.count { $0.rejection != nil } }

  /// Like Web's pending indicator, tells waiting captures apart from refused ones.
  var pendingSummary: String {
    let waiting = waitingEntryCount
    let rejected = rejectedEntryCount
    guard waiting > 0 else { return countLabel(rejected, "Entry") + " not accepted" }
    let summary = countLabel(waiting, "Entry") + " waiting to sync"
    return rejected > 0 ? summary + " · \(rejected) not accepted" : summary
  }

  /// Sends waiting captures in order, like Web's sync store. A capture MemoTrail refuses is
  /// marked and skipped so later captures still sync; an unreachable MemoTrail stops the run.
  /// Returns whether an Entry reached the Inbox.
  @discardableResult
  func synchronizePendingEntries() async -> Bool {
    guard !isSyncing, pendingEntries.contains(where: { $0.rejection == nil }) else {
      return false
    }

    isSyncing = true
    defer { isSyncing = false }
    let firstAttemptIDs = unattemptedCaptureIDs
    unattemptedCaptureIDs = []

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }
    } catch is URLError {
      // An expired access token cannot be refreshed offline; the capture still waits safely.
      announceUnreachable(firstAttemptIDs: firstAttemptIDs)
      return false
    } catch {
      captureError = Self.sessionMessage
      return false
    }

    var didReachInbox = false
    var didSyncEntry = false
    var lastSyncedPhotoCount = 0
    var rejectedCount = 0
    var didStop = false

    sending: for entry in pendingEntries where entry.rejection == nil {
      do {
        try await insert(entry)
      } catch {
        switch await insertFailure(error, for: entry) {
        case .alreadySynced:
          break
        case .rejected(let message):
          guard reject(entry, message: message) else {
            didStop = true
            break sending
          }
          rejectedCount += 1
          continue sending
        case .session:
          captureError = Self.sessionMessage
          didStop = true
          break sending
        case .unavailable:
          announceUnreachable(firstAttemptIDs: firstAttemptIDs)
          didStop = true
          break sending
        }
      }

      do {
        try await synchronizeAttachments(entry)
      } catch {
        let stop = Self.photoSyncStop(error)
        switch stop.failure {
        case .rejected:
          guard reject(entry, message: stop.message) else {
            didStop = true
            break sending
          }
          // The Entry itself reached MemoTrail; only its photos stay behind.
          didReachInbox = true
          rejectedCount += 1
          continue sending
        case .session:
          captureError = Self.sessionMessage
        case .unavailable:
          captureError = stop.message
        }
        didStop = true
        break sending
      }

      guard let nextQueue = queueStore.remove(entryID: entry.id, ownerID: ownerID) else {
        captureError =
          "This Entry reached MemoTrail, but its local pending copy could not be cleared."
        didStop = true
        break sending
      }

      pendingEntries = nextQueue
      confirmedOfflineCaptureIDs.remove(entry.id)
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
      didReachInbox = true
      didSyncEntry = true
      lastSyncedPhotoCount = entry.attachments.count
    }

    if rejectedCount > 0 {
      // A refused capture may come from a Quick Capture that is already closed.
      MTToastCenter.shared.error(
        "MemoTrail did not accept \(countLabel(rejectedCount, "Entry")). "
          + "Review \(rejectedCount == 1 ? "it" : "them") in your Inbox.")
    }

    guard !didStop else { return didReachInbox }

    // Every capture that can still sync did, so no problem waits in the composer.
    captureError = nil
    if didSyncEntry {
      // Like Web, a synced capture is announced once; only problems stay in the composer.
      MTToastCenter.shared.success(
        lastSyncedPhotoCount > 0
          ? "Saved to Inbox with \(countLabel(lastSyncedPhotoCount, "photo"))."
          : "Saved to Inbox.")
    }

    return didReachInbox
  }

  /// Removes a capture MemoTrail refused, like Web's Discard in Pending sync. Its photo files
  /// go first, so a failure cannot leave them to reappear in the composer without their Entry.
  func discardRejected(_ entryID: UUID) async -> Bool {
    guard let entry = queueStore.load(ownerID: ownerID).first(where: { $0.id == entryID })
    else {
      pendingEntries = queueStore.load(ownerID: ownerID)
      return true
    }
    // A capture that may still sync is never discarded.
    guard entry.rejection != nil else { return false }

    let photoStore = photoStore
    let ownerID = ownerID
    let photoIDs = entry.attachments.map(\.id)
    do {
      try await Task.detached {
        for photoID in photoIDs {
          try photoStore.remove(photoID: photoID, ownerID: ownerID)
        }
      }.value
    } catch {
      return false
    }

    guard let nextQueue = queueStore.remove(entryID: entryID, ownerID: ownerID) else {
      return false
    }
    pendingEntries = nextQueue
    return true
  }

  // Web `capture-sync-messages.ts` keeps the same wording for a browser.
  private static let sessionMessage = "Your session expired. Sign in again to sync pending Entries."
  private static let rejectedEntryMessage =
    "MemoTrail cannot accept this Entry, so it will not sync. "
    + "Copy its text to keep it, then discard it."
  private static let deletedForeverMessage =
    "This Entry was deleted forever, so MemoTrail will not create it again. "
    + "Copy its text to keep it, then discard it."
  private static let trashedEntryMessage =
    "This Entry is already in Trash, so it will not sync again. "
    + "Restore it from Trash to keep it, then discard this copy."
  private static let rejectedPhotoMessage =
    "This Entry is in your Inbox, but MemoTrail cannot accept one of its photos, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let changedPhotoMessage =
    "This Entry is in your Inbox, but one of its photos changed on this iPhone, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let tooLargePhotoMessage =
    "This Entry is in your Inbox, but one of its photos is too large for MemoTrail, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let unsupportedPhotoMessage =
    "This Entry is in your Inbox, but one of its photos is a file type MemoTrail does not "
    + "accept, so they will not sync. Discard to remove them from this iPhone."
  private static let missingPhotoMessage =
    "This Entry is in your Inbox, but one of its photos is no longer on this iPhone, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let trashedPhotoMessage =
    "This Entry is in Trash, so its photos will not be attached. "
    + "Discard to remove them from this iPhone."
  private static let offlinePhotoMessage =
    "Photos are saved on this iPhone. MemoTrail will retry when you are online."
  private static let photosElsewhereMessage =
    "MemoTrail will retry attaching this Entry's photos when you are online."

  /// MemoTrail names its own refusals in the error message, beside a standard SQLSTATE that
  /// deployed clients already classify, like Web `app/inbox/actions.ts`.
  private static func isRefusal(_ error: Error, code: String, named name: String) -> Bool {
    guard let error = error as? PostgrestError else { return false }
    return error.code == code && error.message == name
  }

  /// The Entry was deleted forever, so its ID can never be created again.
  private static func isDeletedForever(_ error: Error) -> Bool {
    isRefusal(error, code: "23505", named: "entry_deleted_forever")
  }

  /// Keeps a refused capture on this iPhone, marked so no later sync sends it again.
  private func reject(_ entry: QueuedInboxEntry, message: String) -> Bool {
    let rejection = QueuedInboxRejection(message: message, rejectedAt: Date())
    guard
      let nextQueue = queueStore.markRejected(
        entryID: entry.id, rejection: rejection, ownerID: ownerID)
    else {
      // Unmarked, the capture would be sent again, so like Web the run stops here instead.
      captureError = message
      return false
    }
    pendingEntries = nextQueue
    confirmedOfflineCaptureIDs.remove(entry.id)
    return true
  }

  /// Like Web `syncInboxEntry`, decides what a failed insert means for the capture.
  private func insertFailure(_ error: Error, for entry: QueuedInboxEntry) async -> InsertFailure {
    if Self.isDeletedForever(error) { return .rejected(Self.deletedForeverMessage) }

    // A lost response may hide an insert that succeeded, so an existing Entry counts as synced
    // whatever the error was, unless it is now in Trash, where sending it again only repeats the
    // duplicate-key refusal.
    let existing = await existingEntry(entry.id)
    switch existing {
    case .active:
      return .alreadySynced
    case .trashed:
      return .rejected(
        entry.attachments.isEmpty ? Self.trashedEntryMessage : Self.trashedPhotoMessage)
    case .absent, nil:
      var failure = CaptureSyncFailure(error)
      // Only a confirmed absence makes a refusal final; an unanswered lookup could hide an Entry
      // an earlier attempt already created.
      if existing == nil, failure == .rejected { failure = .unavailable }
      switch failure {
      case .rejected: return .rejected(Self.rejectedEntryMessage)
      case .session: return .session
      case .unavailable: return .unavailable
      }
    }
  }

  /// Why a capture's photos stopped syncing; anything this iPhone could not read or clear in its
  /// own photo files waits for a later attempt.
  private static func photoSyncStop(_ error: Error) -> PhotoSyncStop {
    error as? PhotoSyncStop ?? PhotoSyncStop(failure: .unavailable, message: offlinePhotoMessage)
  }

  /// Like Web `synchronizeCapturePhotos`, turns a refused upload into a final or waiting state.
  private static func uploadStop(_ failure: CaptureUploadFailure) -> PhotoSyncStop {
    switch failure {
    case .tooLarge:
      return PhotoSyncStop(failure: .rejected, message: tooLargePhotoMessage)
    case .unsupportedType:
      return PhotoSyncStop(failure: .rejected, message: unsupportedPhotoMessage)
    case .rejected:
      return PhotoSyncStop(failure: .rejected, message: rejectedPhotoMessage)
    case .session:
      return PhotoSyncStop(failure: .session, message: sessionMessage)
    case .unavailable, .denied, .exists:
      return PhotoSyncStop(failure: .unavailable, message: offlinePhotoMessage)
    }
  }

  /// Like Web `registerEntryAttachment`, turns a failed registration into a final or waiting
  /// state. An original that never reached Storage waits only while this iPhone can upload it.
  private static func registrationStop(_ error: Error, originalOnDevice: Bool) -> PhotoSyncStop {
    if isRefusal(error, code: "22023", named: "entry_in_trash") {
      return PhotoSyncStop(failure: .rejected, message: trashedPhotoMessage)
    }
    if isDeletedForever(error) {
      return PhotoSyncStop(failure: .rejected, message: deletedForeverMessage)
    }
    if isRefusal(error, code: "22023", named: "attachment_object_missing") {
      return originalOnDevice
        ? PhotoSyncStop(failure: .unavailable, message: offlinePhotoMessage)
        : PhotoSyncStop(failure: .rejected, message: missingPhotoMessage)
    }
    switch CaptureSyncFailure(error) {
    case .rejected:
      return PhotoSyncStop(failure: .rejected, message: rejectedPhotoMessage)
    case .session:
      return PhotoSyncStop(failure: .session, message: sessionMessage)
    case .unavailable:
      return waitingRegistration(originalOnDevice: originalOnDevice)
    }
  }

  private static func waitingRegistration(originalOnDevice: Bool) -> PhotoSyncStop {
    PhotoSyncStop(
      failure: .unavailable,
      message: originalOnDevice ? offlinePhotoMessage : photosElsewhereMessage)
  }

  /// Storage answers an expired session like a policy denial, so a denied upload is a refusal
  /// only while MemoTrail still confirms this owner's session.
  private func deniedUploadFailure() async -> CaptureUploadFailure {
    do {
      return try await client.auth.user().id == ownerID ? .rejected : .session
    } catch is URLError {
      return .unavailable
    } catch is CancellationError {
      return .unavailable
    } catch AuthError.api(_, _, _, let response) where response.statusCode >= 500 {
      return .unavailable
    } catch {
      return .session
    }
  }

  /// Deletes an original MemoTrail refused to register, such as one for an Entry that went to
  /// Trash or was deleted forever on its way. Storage keeps a registered original, so this only
  /// clears an unused upload; if it fails, the refusal stands and the file stays.
  private func removeUnusedUpload(_ path: String) async {
    _ = try? await client.storage.from("entry-media").remove(paths: [path])
  }

  /// When MemoTrail cannot be reached, like Web's offline save, captures on their first sync
  /// attempt are confirmed once with a toast instead of in the composer, which may already be
  /// closed. The composer keeps the retry note only while a waiting capture has had no toast,
  /// such as one saved before the app relaunched.
  private func announceUnreachable(firstAttemptIDs: Set<UUID>) {
    let waitingIDs = Set(pendingEntries.filter { $0.rejection == nil }.map(\.id))
    let newlyWaitingIDs = firstAttemptIDs.intersection(waitingIDs)
    if !newlyWaitingIDs.isEmpty {
      MTToastCenter.shared.info("Saved on this iPhone. MemoTrail will sync when you are online.")
    }
    confirmedOfflineCaptureIDs.formUnion(newlyWaitingIDs)
    confirmedOfflineCaptureIDs.formIntersection(waitingIDs)
    captureError =
      waitingIDs.isSubset(of: confirmedOfflineCaptureIDs)
      ? nil : "Saved on this iPhone. MemoTrail will retry when you are online."
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

  /// Where the Entry is, or nil when MemoTrail could not answer.
  private func existingEntry(_ entryID: UUID) async -> ExistingEntryState? {
    do {
      let matchingEntries: [ExistingEntry] =
        try await client
        .from("entries")
        .select("id,deleted_at")
        .eq("id", value: entryID.uuidString)
        .eq("owner_id", value: ownerID.uuidString)
        .limit(1)
        // Offline, backoff retries would hold the capture's confirmation for seconds; an
        // unconfirmed check only leaves the capture queued for the next sync.
        .retry(enabled: false)
        .execute()
        .value

      guard let entry = matchingEntries.first, entry.id == entryID else { return .absent }
      return entry.deletedAt == nil ? .active : .trashed
    } catch {
      return nil
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
          throw PhotoSyncStop(failure: .rejected, message: Self.changedPhotoMessage)
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
          try Task.checkCancellation()
          var failure = CaptureUploadFailure(error)
          if failure == .denied { failure = await deniedUploadFailure() }
          // A stored original, perhaps from an attempt whose response was lost, continues to
          // registration, which verifies it without overwriting its bytes.
          if failure != .exists { throw Self.uploadStop(failure) }
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
        // Without its photo, this iPhone can only register an original already in Storage.
        let stop = Self.registrationStop(error, originalOnDevice: draft != nil)
        if stop.failure == .rejected { await removeUnusedUpload(path) }
        throw stop
      }

      guard registered.first?.attachmentID == attachment.id else {
        throw Self.waitingRegistration(originalOnDevice: draft != nil)
      }

      let attachmentID = attachment.id
      try await Task.detached {
        try photoStore.remove(photoID: attachmentID, ownerID: ownerID)
      }.value
    }
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
  /// Absent when the lookup selected only `id`.
  let deletedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case deletedAt = "deleted_at"
  }
}

private enum ExistingEntryState: Equatable {
  case absent
  case active
  case trashed
}

/// What a failed Entry insert means for its capture.
private enum InsertFailure {
  /// An earlier attempt already created the Entry, perhaps before its response was lost.
  case alreadySynced
  case rejected(String)
  case session
  case unavailable
}

/// Why a capture's photos stopped syncing, with what the person sees.
private struct PhotoSyncStop: Error {
  let failure: CaptureSyncFailure
  let message: String
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
}
