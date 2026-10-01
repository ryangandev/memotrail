import Foundation
import Observation
@preconcurrency import Supabase

/// One Item's current snapshot and earlier versions, with the Web `/items` and `/history`
/// actions: restore a version, move the Item to Trash, and create a linked Goal.
@MainActor
@Observable
final class EntryHistoryController {
  static let pageSize = 20

  private(set) var record: EntryHistoryRecord?
  /// The zero-based page of earlier versions.
  private(set) var page = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isWorking = false
  private(set) var loadFailed = false

  let entryID: UUID
  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.entryID = entryID
  }

  var hasOlderVersions: Bool { (record?.totalCount ?? 0) > (page + 1) * Self.pageSize }

  func load(page requestedPage: Int = 0) async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    // Like Web, one quick retry covers a request that raced a fresh sign-in.
    for attempt in 0..<2 {
      do {
        try await validateSessionOwner()
        record = try await client.rpc(
          "entry_history",
          params: HistoryReadRequest(
            entryID: entryID, limit: Self.pageSize, offset: requestedPage * Self.pageSize)
        ).execute().value
        page = requestedPage
        loadFailed = false
        return
      } catch {
        if attempt == 0 { try? await Task.sleep(for: .milliseconds(50)) }
      }
    }
    loadFailed = true
  }

  /// Web `restoreHistoryVersion`; returns the failure message, if any.
  func restore(version: Int) async -> String? {
    guard let record, !isWorking else { return nil }
    guard version > 0, record.revision > version else { return "Choose a valid earlier version." }
    isWorking = true
    defer { isWorking = false }
    do {
      try await validateSessionOwner()
      let revision: Int? = try await client.rpc(
        "restore_entry_version",
        params: HistoryRestoreRequest(
          entryID: entryID, version: version, expectedRevision: record.revision)
      ).execute().value
      guard revision != nil else {
        return
          "This Entry changed on another device or is in Trash. Refresh or restore it from Trash first."
      }
    } catch let error as PostgrestError {
      return HistoryPresentation.restoreFailureMessage(error.message)
    } catch {
      return
        "Could not confirm restoration. Refresh to check the latest version before trying again."
    }
    isWorking = false
    await reload()
    return nil
  }

  /// Web `trashWikiItem`; returns the failure message, if any.
  func moveToTrash() async -> String? {
    guard let record, !isWorking else { return nil }
    isWorking = true
    defer { isWorking = false }
    do {
      try await validateSessionOwner()
      let rows: [TrashedItem] = try await client.from("entries")
        .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
        .eq("id", value: entryID.uuidString)
        .eq("revision", value: record.revision)
        .is("deleted_at", value: nil)
        .select("id")
        .execute()
        .value
      guard !rows.isEmpty else {
        return
          "This item changed on another device or is already in Trash. Refresh and try again."
      }
      return nil
    } catch {
      return "MemoTrail could not move this item to Trash."
    }
  }

  /// Web `extractGoalFromItem`: the new Goal's ID, or the failure message.
  func extractGoal(
    goalID: UUID, title: String, horizon: GoalHorizon, status: GoalStatus, targetDate: String?
  ) async -> Result<UUID, GoalExtractionFailure> {
    guard let record else { return .failure(GoalExtractionFailure(message: "")) }
    let request = GoalExtractionRequest(
      sourceEntryID: entryID, sourceRevision: record.revision, goalID: goalID, title: title,
      horizon: horizon, status: status, targetDate: targetDate)
    guard request.isValid else {
      return .failure(
        GoalExtractionFailure(
          message: "Add a Goal title up to 200 characters and a valid optional target date."))
    }
    guard !isWorking else { return .failure(GoalExtractionFailure(message: "")) }
    isWorking = true
    defer { isWorking = false }
    do {
      try await validateSessionOwner()
      let results: [ExtractedGoalFromItem] = try await client.rpc(
        "extract_goal_from_item", params: request
      ).execute().value
      guard let goalID = results.first?.goalEntryID else {
        return .failure(
          GoalExtractionFailure(
            message: "The source changed or is in Trash. Refresh before creating this Goal."))
      }
      return .success(goalID)
    } catch {
      return .failure(
        GoalExtractionFailure(
          message:
            "Could not confirm Goal creation. Refresh to check the source before retrying."))
    }
  }

  /// Web `loadEditableEntry`: the Entry in the Inbox review shape, for Edit Entry.
  func editableEntry() async -> InboxEntry? {
    guard !isWorking else { return nil }
    isWorking = true
    defer { isWorking = false }
    do {
      try await validateSessionOwner()
      return try await client.rpc(
        "editable_entry", params: ["p_entry_id": entryID.uuidString]
      ).execute().value
    } catch {
      return nil
    }
  }

  func saveEditedEntry(
    _ entry: InboxEntry, draft: EntryReviewDraft, intent: InboxController.ReviewIntent
  ) async -> InboxController.ReviewResult {
    switch await InboxController.submitReview(
      client: client, ownerID: ownerID, entry: entry, draft: draft, intent: intent)
    {
    case .failed(let result):
      return result
    case .saved:
      await reload()
      return .init(message: "Entry saved.", status: intent == .done ? .done : .saved)
    }
  }

  /// Reloads the first page, like Web `router.refresh()` after a change.
  func reload() async {
    isLoading = false
    await load(page: 0)
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

struct GoalExtractionFailure: Error, Equatable {
  let message: String
}

private struct TrashedItem: Decodable {
  let id: UUID
}
