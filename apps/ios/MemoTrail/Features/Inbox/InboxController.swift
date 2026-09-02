import Foundation
@preconcurrency import Network
import Observation
import Supabase

@MainActor
@Observable
final class InboxController {
  private(set) var entries: [InboxEntry] = []
  private(set) var pendingEntries: [QueuedInboxEntry]
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var isSyncing = false
  private(set) var loadErrorMessage: String?
  private(set) var captureMessage: CaptureMessage?

  private let client: SupabaseClient
  private let ownerID: UUID
  private let queueStore: InboxQueueStore
  private let networkMonitor: NWPathMonitor
  private let networkMonitorQueue = DispatchQueue(
    label: "com.rystudio.memotrail.inbox-connectivity"
  )

  init(
    client: SupabaseClient,
    ownerID: UUID,
    queueStore: InboxQueueStore = InboxQueueStore(),
    networkMonitor: NWPathMonitor = NWPathMonitor()
  ) {
    self.client = client
    self.ownerID = ownerID
    self.queueStore = queueStore
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

      entries = loadedEntries
    } catch {
      loadErrorMessage = "MemoTrail could not load your Inbox. Pull to refresh or try again."
    }
  }

  func refresh() async {
    _ = await synchronizePendingEntries()
    await load()
  }

  func save(title: String, body: String) async -> Bool {
    guard !isSaving, !isSyncing else { return false }

    let capture: InboxCapture
    do {
      capture = try InboxCapture.validate(title: title, body: body)
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
      occurredAt: now,
      occurredTimezone: TimeZone.current.identifier,
      queuedAt: now
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
    entryType: InboxEntryType,
    occurredAt: Date,
    occurredTimezone: String,
    intent: ReviewIntent
  ) async -> ReviewResult {
    let input: InboxReviewInput

    do {
      input = try InboxReviewInput.validate(
        entryID: entry.id,
        revision: entry.revision,
        title: title,
        body: body,
        entryType: entryType,
        occurredAt: occurredAt,
        occurredTimezone: occurredTimezone
      )
    } catch {
      return ReviewResult(message: error.localizedDescription, status: .error)
    }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw InboxControllerError.ownerChanged
      }

      let payload = InboxEntryUpdate(
        title: input.title,
        body: input.body,
        entryType: input.entryType,
        inboxStatus: intent == .done ? "organized" : "unreviewed",
        occurredStart: input.occurredAt,
        occurredTimezone: input.occurredTimezone
      )
      let updatedEntries: [InboxEntry] =
        try await client
        .from("entries")
        .update(payload)
        .eq("id", value: input.entryID.uuidString)
        .eq("owner_id", value: ownerID.uuidString)
        .eq("inbox_status", value: "unreviewed")
        .eq("revision", value: input.revision)
        .select(
          "id,title,body,entry_type,created_at,occurred_start,occurred_timezone,revision"
        )
        .execute()
        .value

      guard let updatedEntry = updatedEntries.first else {
        return ReviewResult(
          message:
            "This Entry changed on another device. Close it, refresh, and review the latest version.",
          status: .conflict
        )
      }

      if intent == .done {
        entries.removeAll { $0.id == updatedEntry.id }
        return ReviewResult(message: "Entry organized.", status: .done)
      }

      if let index = entries.firstIndex(where: { $0.id == updatedEntry.id }) {
        entries[index] = updatedEntry
      }
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

      guard let nextQueue = queueStore.remove(entryID: entry.id, ownerID: ownerID) else {
        captureMessage = CaptureMessage(
          text: "This Entry reached MemoTrail, but its local pending copy could not be cleared.",
          style: .error
        )
        return didSyncEntry
      }

      pendingEntries = nextQueue
      didSyncEntry = true
    }

    if didSyncEntry {
      captureMessage = CaptureMessage(text: "Saved to Inbox.", style: .success)
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

private struct InboxEntryUpdate: Encodable, Sendable {
  let title: String?
  let body: String
  let entryType: InboxEntryType
  let inboxStatus: String
  let occurredStart: Date
  let occurredTimezone: String

  enum CodingKeys: String, CodingKey {
    case title
    case body
    case entryType = "entry_type"
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
  }
}

private enum InboxControllerError: Error {
  case ownerChanged
}
