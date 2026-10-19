import Foundation
@preconcurrency import Network
import Observation
@preconcurrency import Supabase
import UIKit

/// Quick Capture's queue and sync, like Web `capture-provider.tsx` and `inbox-sync.ts`. A capture
/// is saved on this iPhone first, then sent to MemoTrail in order as a plain Entry in the Library.
/// Captures sync when the controller starts, when a capture is saved, when the connection
/// returns, and when the app comes back to the foreground, then keep retrying with backoff while
/// this iPhone reports a connection.
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
  /// The capture a run is sending now, which Pending sync marks as syncing.
  private(set) var syncingEntryID: UUID?
  /// How many of the sending capture's photos reached MemoTrail, like Web's upload progress.
  private(set) var photoUploadProgress: CapturePhotoProgress?
  /// MemoTrail no longer accepts this session, so captures wait until the person signs in again.
  private(set) var isSessionExpired = false
  /// Captures saved while connected whose first attempt has not finished. Like Web's
  /// `firstAttempt`, that brief stage is progress rather than something waiting in Pending sync,
  /// and the attempt decides how each is announced.
  private(set) var firstAttemptIDs: Set<UUID> = []

  /// Waiting captures already confirmed as safe on this iPhone, which retries do not announce.
  @ObservationIgnored private var confirmedOfflineCaptureIDs: Set<UUID> = []
  @ObservationIgnored private var syncTask: Task<Bool, Never>?
  /// A capture or reconnection arrived during a run, so one more run settles it.
  @ObservationIgnored private var rerunRequested = false
  /// Whether this iPhone reports a usable network path; assumed until the monitor first answers.
  @ObservationIgnored private var isNetworkAvailable = true
  /// Set once the person signs out, after which this controller never sends anything again.
  @ObservationIgnored private var isStopped = false
  @ObservationIgnored private var syncRetry: CaptureSyncRetry?

  private let client: SupabaseClient
  private let ownerID: UUID
  private let queueStore: CaptureQueueStore
  private let photoStore: CapturePhotoStore
  private let networkMonitor: NWPathMonitor
  private let lifetime = CaptureControllerLifetime()
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
    #if DEBUG
      CaptureReviewSeed.applyOnce(ownerID: ownerID, queueStore: queueStore)
    #endif
    pendingEntries = queueStore.load(ownerID: ownerID)
    unreadableCaptures = queueStore.unreadableCaptures(ownerID: ownerID)

    syncRetry = CaptureSyncRetry(
      isOnline: { [weak self] in self?.isNetworkAvailable == true && self?.isStopped == false },
      isSyncing: { [weak self] in self?.isSyncing == true },
      retry: { [weak self] in self?.synchronizeInBackground() })
    startWatching()
  }

  deinit {
    lifetime.end()
  }

  /// Rereads the queue on this iPhone, then sends whatever still waits.
  func refresh() async {
    reloadQueue()
    _ = await synchronizePendingEntries()
  }

  /// Shows why a saved draft did not come back in full, like Web's draft notice.
  func showDraftNotice(_ notice: String?) {
    guard let notice else { return }
    captureError = notice
  }

  /// Removes one unreadable capture for good, like Web's Discard for an unreadable capture.
  /// Its photo drafts go first, so a failure leaves it listed for another try. The queue is
  /// rewritten on the main actor, where every other queue change happens, so a capture saved
  /// meanwhile is never written over.
  func discardUnreadable(_ capture: UnreadableCapture) async -> Bool {
    let photoStore = photoStore
    let ownerID = ownerID
    let discarded = queueStore.discardUnreadable(capture, ownerID: ownerID) { photoID in
      try photoStore.remove(photoID: photoID, ownerID: ownerID)
    }
    reloadQueue()
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
    // A sync in progress never holds a capture back: it is stored here first either way.
    guard !isSaving else { return false }

    let capture: CaptureInput
    let occurrence: EntryOccurrence
    let now = Date()
    do {
      occurrence = try CaptureDate.resolve(
        occurrenceDraft, now: occurredAt ?? now, timezone: TimeZone.current.identifier)
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
    if isNetworkAvailable {
      firstAttemptIDs.insert(pendingEntry.id)
    } else {
      // Like Web's offline save, the capture is confirmed at once instead of after an attempt.
      confirmedOfflineCaptureIDs.insert(pendingEntry.id)
      MTToastCenter.shared.info(Self.savedOfflineMessage)
    }
    synchronizeInBackground()
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

  /// Whether Pending sync has anything to show, like Web `hasWaitingCaptures`: a capture on its
  /// first attempt is progress, not a waiting capture.
  var hasWaitingCaptures: Bool {
    !unreadableCaptures.isEmpty || pendingEntries.contains { !firstAttemptIDs.contains($0.id) }
  }

  /// Like Web's pending indicator, tells waiting captures apart from refused and unreadable ones.
  var pendingSummary: String {
    let waiting = waitingEntryCount
    let rejected = rejectedEntryCount
    let unreadable = unreadableCaptures.count
    var parts: [String] = []
    if waiting > 0 { parts.append(countLabel(waiting, "Entry") + " waiting to sync") }
    if rejected > 0 {
      parts.append(
        parts.isEmpty ? countLabel(rejected, "Entry") + " not accepted" : "\(rejected) not accepted")
    }
    if unreadable > 0 {
      parts.append(
        parts.isEmpty
          ? countLabel(unreadable, "saved Entry", plural: "saved Entries") + " could not be read"
          : "\(unreadable) unreadable")
    }
    return parts.joined(separator: " · ")
  }

  /// Sends waiting captures in order, like Web's sync store. A capture MemoTrail refuses is
  /// marked and skipped so later captures still sync; an unreachable MemoTrail stops the run.
  /// A call during a run waits for it, and the run goes once more for what arrived meanwhile.
  /// Returns whether an Entry reached MemoTrail.
  @discardableResult
  func synchronizePendingEntries() async -> Bool {
    if let syncTask {
      rerunRequested = true
      return await syncTask.value
    }
    guard !isStopped else { return false }

    reloadQueue()
    guard pendingEntries.contains(where: { $0.rejection == nil }) else {
      // Only refused captures, if any, remain; they are never sent again.
      return false
    }

    let task = Task { await runUntilSettled() }
    syncTask = task
    return await task.value
  }

  /// Web's Retry now: a person asking is a fresh start, so the backoff begins again.
  func retryNow() async {
    syncRetry?.stop()
    _ = await synchronizePendingEntries()
  }

  /// Rereads what is stored on this iPhone without sending anything.
  func refreshQueue() {
    reloadQueue()
  }

  /// Removes a capture MemoTrail refused, like Web's Discard in Pending sync. Its photo files
  /// go first, so a failure cannot leave them to reappear in the composer without their Entry.
  func discardRejected(_ entryID: UUID) async -> Bool {
    guard let entry = queueStore.load(ownerID: ownerID).first(where: { $0.id == entryID })
    else {
      reloadQueue()
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

  // MARK: Triggers

  private func startWatching() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      let isAvailable = path.status == .satisfied
      Task { @MainActor [weak self] in self?.networkChanged(isAvailable: isAvailable) }
    }
    networkMonitor.start(queue: networkMonitorQueue)
    let networkMonitor = networkMonitor
    lifetime.add { networkMonitor.cancel() }

    // The observer token is only handed back to NotificationCenter, which is thread-safe.
    nonisolated(unsafe) let foreground = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.becameActive() }
    }
    lifetime.add { NotificationCenter.default.removeObserver(foreground) }

    // Retries belong to this signed-in person, so they end with the session and never send one
    // person's captures under a later one.
    Task { [weak self, lifetime, client] in
      let registration = await client.auth.onAuthStateChange { [weak self] event, session in
        let userID = session?.user.id
        Task { @MainActor [weak self] in self?.authChanged(event, userID: userID) }
      }
      lifetime.add { registration.remove() }
    }
  }

  private func networkChanged(isAvailable: Bool) {
    isNetworkAvailable = isAvailable
    guard isAvailable else {
      // Regaining the connection starts a run of its own, like Web's `online` event.
      syncRetry?.stop()
      return
    }
    synchronizeInBackground()
  }

  /// Coming back to the app is a fresh chance to reach MemoTrail, so the backoff starts over.
  private func becameActive() {
    syncRetry?.stop()
    synchronizeInBackground()
  }

  private func authChanged(_ event: AuthChangeEvent, userID: UUID?) {
    switch event {
    case .signedOut, .userDeleted:
      isStopped = true
      syncRetry?.stop()
    case .signedIn, .tokenRefreshed:
      guard userID == ownerID else { return }
      isStopped = false
      // A refreshed session can reach MemoTrail again.
      if isSessionExpired { synchronizeInBackground() }
    default:
      break
    }
  }

  private func synchronizeInBackground() {
    Task { @MainActor [weak self] in
      _ = await self?.synchronizePendingEntries()
    }
  }

  private func reloadQueue() {
    pendingEntries = queueStore.load(ownerID: ownerID)
    let unreadable = queueStore.unreadableCaptures(ownerID: ownerID)
    // Keep the same list while nothing changed, so open rows keep their state.
    if unreadable.map(\.key) != unreadableCaptures.map(\.key) { unreadableCaptures = unreadable }
  }

  // MARK: Runs

  private func runUntilSettled() async -> Bool {
    isSyncing = true
    var didReachLibrary = false
    repeat {
      rerunRequested = false
      let ownerID = ownerID
      let result = await CaptureSyncLock.run(ownerID: ownerID) { await runOnce() }
      didReachLibrary = didReachLibrary || result.reachedLibrary
      syncRetry?.afterRun(result.run)
    } while rerunRequested && !isStopped
      && queueStore.load(ownerID: ownerID).contains(where: { $0.rejection == nil })
    isSyncing = false
    syncTask = nil
    return didReachLibrary
  }

  /// One pass over the queue, oldest first, rereading it before each capture so a capture saved
  /// or discarded meanwhile is seen. It stops at the first capture that must wait.
  private func runOnce() async -> (run: CaptureSyncRun, reachedLibrary: Bool) {
    var run = CaptureSyncRun()
    var reachedLibrary = false
    var attempted = Set<UUID>()
    var considered = Set<UUID>()
    var stop: SyncStop?
    var lastSyncedPhotoCount = 0

    defer {
      syncingEntryID = nil
      photoUploadProgress = nil
    }

    switch await sessionCheck() {
    case .ready:
      sending: while true {
        reloadQueue()
        considered.formUnion(pendingEntries.map(\.id))
        guard
          let entry = pendingEntries.first(where: {
            $0.rejection == nil && !attempted.contains($0.id)
          })
        else { break sending }
        attempted.insert(entry.id)
        syncingEntryID = entry.id
        photoUploadProgress = nil

        switch await attempt(entry) {
        case .synced:
          guard let nextQueue = queueStore.remove(entryID: entry.id, ownerID: ownerID) else {
            stop = .problem(Self.uncleanedQueueMessage)
            reachedLibrary = true
            break sending
          }
          pendingEntries = nextQueue
          confirmedOfflineCaptureIDs.remove(entry.id)
          reachedLibrary = true
          run.synced += 1
          lastSyncedPhotoCount = entry.attachments.count
        case .rejected(let message, let entryReachedLibrary):
          reachedLibrary = reachedLibrary || entryReachedLibrary
          guard reject(entry, message: message) else {
            // Unmarked, the capture would be sent again, so like Web the run stops here instead.
            stop = .problem(message)
            break sending
          }
          run.rejected += 1
        case .wait(let reason, let entryReachedLibrary):
          reachedLibrary = reachedLibrary || entryReachedLibrary
          stop = reason
          break sending
        }
      }
    case .unreachable:
      considered.formUnion(pendingEntries.map(\.id))
      stop = .unreachable
    case .expired:
      considered.formUnion(pendingEntries.map(\.id))
      stop = .session
    }

    // Every capture this run could reach has had its first attempt; one saved after the last
    // read keeps it for the run it requested.
    let firstAttempts = firstAttemptIDs.intersection(considered)
    firstAttemptIDs.subtract(considered)
    syncingEntryID = nil
    reloadQueue()
    run.stoppedWaiting = stop != nil

    if run.rejected > 0 {
      // A refused capture may come from a Quick Capture that is already closed.
      MTToastCenter.shared.error(
        "MemoTrail did not accept \(countLabel(run.rejected, "Entry")). "
          + "Review \(run.rejected == 1 ? "it" : "them") in Pending sync.")
    }
    if reachedLibrary { entriesRevision += 1 }
    if run.synced > 0 || run.rejected > 0 { isSessionExpired = false }

    switch stop {
    case nil:
      // Every capture that can still sync did, so no problem waits in the composer.
      captureError = nil
      isSessionExpired = false
      if run.synced > 0 {
        // Like Web, a synced capture is announced once; only problems stay in the composer.
        MTToastCenter.shared.success(
          lastSyncedPhotoCount > 0
            ? "Saved to Library with \(countLabel(lastSyncedPhotoCount, "photo"))."
            : "Saved to Library.")
      }
    case .unreachable:
      announceUnreachable(firstAttemptIDs: firstAttempts)
    case .session:
      isSessionExpired = true
      captureError = Self.sessionMessage
    case .problem(let message):
      captureError = message
    }

    return (run, reachedLibrary)
  }

  /// Sends one capture and then its photos.
  private func attempt(_ entry: QueuedCapture) async -> AttemptResult {
    do {
      try await insert(entry)
    } catch {
      switch await insertFailure(error, for: entry) {
      case .alreadySynced:
        break
      case .rejected(let message):
        return .rejected(message, reachedLibrary: false)
      case .session:
        return .wait(.session, reachedLibrary: false)
      case .unavailable:
        return .wait(.unreachable, reachedLibrary: false)
      }
    }

    do {
      try await synchronizeAttachments(entry)
      return .synced
    } catch {
      // The Entry itself reached MemoTrail; only its photos stay behind.
      let stop = Self.photoSyncStop(error)
      switch stop.failure {
      case .rejected: return .rejected(stop.message, reachedLibrary: true)
      case .session: return .wait(.session, reachedLibrary: true)
      case .unavailable: return .wait(.problem(stop.message), reachedLibrary: true)
      }
    }
  }

  /// Whether this owner's session can write before anything is sent. An expired access token
  /// cannot be refreshed offline, and an auth server that fails can answer later; only an answer
  /// that refuses the session means the person must sign in again.
  private func sessionCheck() async -> SessionCheck {
    do {
      let session = try await client.auth.session
      return session.user.id == ownerID ? .ready : .expired
    } catch is URLError {
      return .unreachable
    } catch is CancellationError {
      return .unreachable
    } catch AuthError.api(_, _, _, let response) where response.statusCode >= 500 {
      return .unreachable
    } catch {
      return .expired
    }
  }

  // Web `capture-sync-messages.ts` keeps the same wording for a browser.
  private static let sessionMessage = "Your session expired. Sign in again to sync pending Entries."
  private static let savedOfflineMessage =
    "Saved on this iPhone. MemoTrail will sync when you are online."
  private static let uncleanedQueueMessage =
    "This Entry reached MemoTrail, but its local pending copy could not be cleared."
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
  private static let uncleanedPhotoMessage =
    "This photo reached MemoTrail, but its local pending copy could not be cleared. "
    + "Retry to finish."

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
    else { return false }
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

  /// Why a capture's photos stopped syncing; anything this iPhone could not read in its own
  /// photo files waits for a later attempt.
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
      .subtracting(confirmedOfflineCaptureIDs)
    if !newlyWaitingIDs.isEmpty {
      MTToastCenter.shared.info(Self.savedOfflineMessage)
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

  /// Like Web `synchronizeCapturePhotos`: uploads and registers the photos in order once the
  /// Entry exists, removing each local copy after MemoTrail confirms it, and stops at the first
  /// photo that must wait or that MemoTrail refuses.
  private func synchronizeAttachments(_ entry: QueuedCapture) async throws {
    guard !entry.attachments.isEmpty else { return }

    let photoStore = photoStore
    let ownerID = ownerID
    let drafts = try await Task.detached {
      try photoStore.load(ownerID: ownerID)
    }.value
    let draftsByID = Dictionary(drafts.map { ($0.id, $0) }) { first, _ in first }

    var completed = 0
    photoUploadProgress = CapturePhotoProgress(completed: 0, total: entry.attachments.count)
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

      if draft != nil {
        let attachmentID = attachment.id
        do {
          try await Task.detached {
            try photoStore.remove(photoID: attachmentID, ownerID: ownerID)
          }.value
        } catch {
          throw PhotoSyncStop(failure: .unavailable, message: Self.uncleanedPhotoMessage)
        }
      }
      completed += 1
      photoUploadProgress = CapturePhotoProgress(
        completed: completed, total: entry.attachments.count)
    }
  }
}

/// How many of a capture's photos reached MemoTrail while it syncs.
struct CapturePhotoProgress: Equatable, Sendable {
  let completed: Int
  let total: Int
}

/// Work a controller ends when it goes away. Deinit cannot reach main-actor state, so each
/// piece of work registers how to end it here; anything registered after the end ends at once.
private final class CaptureControllerLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var endings: [@Sendable () -> Void] = []
  private var hasEnded = false

  func add(_ ending: @escaping @Sendable () -> Void) {
    let endNow = lock.withLock {
      guard !hasEnded else { return true }
      endings.append(ending)
      return false
    }
    if endNow { ending() }
  }

  func end() {
    let all = lock.withLock {
      hasEnded = true
      defer { endings = [] }
      return endings
    }
    for ending in all { ending() }
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

private enum SessionCheck {
  case ready
  case unreachable
  case expired
}

/// Why a run stopped at a capture that must wait.
private enum SyncStop {
  /// MemoTrail could not be reached.
  case unreachable
  /// The session can no longer write.
  case session
  /// Anything else that a later attempt can resolve, with what the composer says.
  case problem(String)
}

/// What one capture's attempt came to.
private enum AttemptResult {
  case synced
  case rejected(String, reachedLibrary: Bool)
  case wait(SyncStop, reachedLibrary: Bool)
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
