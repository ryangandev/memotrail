import Foundation
@preconcurrency import Network
import Observation
@preconcurrency import Supabase

/// Quick Capture's queue and sync, like Web `capture-provider.tsx` and `inbox-sync.ts`. A capture
/// is saved on this iPhone first, then sent to MemoTrail in order as a plain Entry in the Library.
@MainActor
@Observable
final class CaptureController {
  private(set) var pendingEntries: [QueuedCapture]
  /// Stored captures this iPhone could not read, kept so their writing can be copied.
  private(set) var unreadableCaptures: [UnreadableCapture]
  private(set) var isSaving = false
  private(set) var isSyncing = false
  /// The latest capture or sync problem, shown in the composer until the next attempt.
  private(set) var captureError: String?
  /// Counts the sync runs in which an Entry reached MemoTrail, so lists know to reload.
  private(set) var entriesRevision = 0
  /// Captures saved since the last sync attempt began; that attempt decides how each is announced.
  private var unattemptedCaptureIDs: Set<UUID> = []
  /// Waiting captures already confirmed as safe on this iPhone, which retries do not announce.
  private var confirmedOfflineCaptureIDs: Set<UUID> = []

  private let client: SupabaseClient
  private let ownerID: UUID
  private let queueStore: CaptureQueueStore
  private let photoStore: CapturePhotoStore
  private let networkMonitor: NWPathMonitor
  private let networkMonitorQueue = DispatchQueue(
    label: "com.rystudio.memotrail.inbox-connectivity"
  )

  init(
    client: SupabaseClient,
    ownerID: UUID,
    queueStore: CaptureQueueStore = CaptureQueueStore(),
    photoStore: CapturePhotoStore = CapturePhotoStore(),
    networkMonitor: NWPathMonitor = NWPathMonitor()
  ) {
    self.client = client
    self.ownerID = ownerID
    self.queueStore = queueStore
    self.photoStore = photoStore
    self.networkMonitor = networkMonitor
    pendingEntries = queueStore.load(ownerID: ownerID)
    unreadableCaptures = queueStore.unreadableCaptures(ownerID: ownerID)

    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }

      Task { @MainActor [weak self] in
        _ = await self?.synchronizePendingEntries()
      }
    }
    networkMonitor.start(queue: networkMonitorQueue)
  }

  deinit {
    networkMonitor.cancel()
  }

  /// Rereads the queue on this iPhone, then sends whatever still waits.
  func refresh() async {
    pendingEntries = queueStore.load(ownerID: ownerID)
    unreadableCaptures = queueStore.unreadableCaptures(ownerID: ownerID)
    _ = await synchronizePendingEntries()
  }

  /// Shows why a saved draft did not come back in full, like Web's draft notice.
  func showDraftNotice(_ notice: String?) {
    guard let notice else { return }
    captureError = notice
  }

  /// Removes one unreadable capture for good, like Web's Discard for an unreadable capture.
  /// Its photo drafts go first, so a failure leaves it listed for another try.
  func discardUnreadable(_ capture: UnreadableCapture) async -> Bool {
    let queueStore = queueStore
    let photoStore = photoStore
    let ownerID = ownerID
    let discarded = await Task.detached {
      queueStore.discardUnreadable(capture, ownerID: ownerID) { photoID in
        try photoStore.remove(photoID: photoID, ownerID: ownerID)
      }
    }.value
    pendingEntries = queueStore.load(ownerID: ownerID)
    unreadableCaptures = queueStore.unreadableCaptures(ownerID: ownerID)
    return discarded
  }

  func save(
    title: String,
    body: String,
    bodyRich: EntryEmphasisContent? = nil,
    occurredAt: Date? = nil,
    occurrenceDraft: OccurrenceDraft? = nil,
    photos: [PhotoDraft] = []
  ) async -> Bool {
    guard !isSaving, !isSyncing else { return false }

    let capture: CaptureInput
    let occurrence: EntryOccurrence
    let now = Date()
    do {
      occurrence =
        try occurrenceDraft?.resolve()
        ?? EntryOccurrence(
          precision: .exact, start: occurredAt ?? now, end: nil, label: nil,
          timezone: TimeZone.current.identifier)
      try occurrence.validate()
      capture = try CaptureInput.validate(
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

    var pendingEntry = QueuedCapture(
      id: UUID(),
      title: capture.title,
      body: capture.body,
      occurredAt: occurrence.start,
      occurredTimezone: occurrence.timezone,
      queuedAt: now,
      attachments: photos.map(QueuedCaptureAttachment.init)
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
      _ = await self?.synchronizePendingEntries()
    }

    return true
  }

  /// Saves the composer's note, keeping its Web-compatible formatting.
  func save(
    title: String, note: NSAttributedString, occurrenceDraft: OccurrenceDraft?,
    photos: [PhotoDraft]
  ) async -> Bool {
    let captured = EntryEmphasisContent.capture(note)
    return await save(
      title: title, body: captured.body, bodyRich: captured.rich,
      occurrenceDraft: occurrenceDraft, photos: photos)
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
  /// Returns whether an Entry reached MemoTrail.
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
        throw CaptureControllerError.ownerChanged
      }
    } catch is URLError {
      // An expired access token cannot be refreshed offline; the capture still waits safely.
      announceUnreachable(firstAttemptIDs: firstAttemptIDs)
      return false
    } catch {
      captureError = Self.sessionMessage
      return false
    }

    var didReachLibrary = false
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
          didReachLibrary = true
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
      didReachLibrary = true
      didSyncEntry = true
      lastSyncedPhotoCount = entry.attachments.count
    }

    if rejectedCount > 0 {
      // A refused capture may come from a Quick Capture that is already closed.
      MTToastCenter.shared.error(
        "MemoTrail did not accept \(countLabel(rejectedCount, "Entry")). "
          + "Review \(rejectedCount == 1 ? "it" : "them") in Pending sync.")
    }

    if didReachLibrary { entriesRevision += 1 }
    guard !didStop else { return didReachLibrary }

    // Every capture that can still sync did, so no problem waits in the composer.
    captureError = nil
    if didSyncEntry {
      // Like Web, a synced capture is announced once; only problems stay in the composer.
      MTToastCenter.shared.success(
        lastSyncedPhotoCount > 0
          ? "Saved to Library with \(countLabel(lastSyncedPhotoCount, "photo"))."
          : "Saved to Library.")
    }

    return didReachLibrary
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
    "This Entry is in your Library, but MemoTrail cannot accept one of its photos, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let changedPhotoMessage =
    "This Entry is in your Library, but one of its photos changed on this iPhone, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let tooLargePhotoMessage =
    "This Entry is in your Library, but one of its photos is too large for MemoTrail, "
    + "so they will not sync. Discard to remove them from this iPhone."
  private static let unsupportedPhotoMessage =
    "This Entry is in your Library, but one of its photos is a file type MemoTrail does not "
    + "accept, so they will not sync. Discard to remove them from this iPhone."
  private static let missingPhotoMessage =
    "This Entry is in your Library, but one of its photos is no longer on this iPhone, "
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
  private func reject(_ entry: QueuedCapture, message: String) -> Bool {
    let rejection = QueuedCaptureRejection(message: message, rejectedAt: Date())
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
  private func insertFailure(_ error: Error, for entry: QueuedCapture) async -> InsertFailure {
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

  private func insert(_ entry: QueuedCapture) async throws {
    try await client
      .from("entries")
      .insert(CaptureInsert(entry, ownerID: ownerID))
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

  private func synchronizeAttachments(_ entry: QueuedCapture) async throws {
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

private enum CaptureControllerError: Error {
  case ownerChanged
}
