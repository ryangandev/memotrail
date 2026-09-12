import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class TimelineController {
  private(set) var tracks: [TimelineTrack] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var entryCount: Int {
    tracks.reduce(0) { $0 + $1.entries.count }
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
      try await validateSessionOwner()
      let rows: [TimelineWorkspaceRow] =
        try await client
        .rpc(
          "timeline_workspace",
          params: TimelineWorkspaceParameters(includeHidden: false)
        )
        .execute()
        .value

      tracks = TimelineWorkspace.tracks(from: rows)
    } catch {
      loadErrorMessage = "MemoTrail could not load your Timeline. Pull to refresh or try again."
    }
  }

  func save(
    entry: TimelineEntry?,
    trackID: UUID,
    kind: TimelineKind,
    title: String,
    body: String,
    occurredStart: Date?,
    occurredEnd: Date?,
    datePrecision: TimelineDatePrecision,
    occurredLabel: String,
    occurredTimezone: String
  ) async -> MutationResult {
    var input: TimelineEntryInput

    do {
      input = try TimelineEntryInput.validate(
        entryID: entry?.id,
        expectedRevision: entry?.revision,
        trackID: trackID,
        kind: kind,
        title: title,
        body: body,
        occurredStart: occurredStart,
        occurredEnd: kind == .stage ? occurredEnd : nil,
        datePrecision: datePrecision,
        occurredLabel: occurredLabel,
        occurredTimezone: occurredTimezone
      )
    } catch {
      return MutationResult(message: error.localizedDescription, status: .error)
    }

    input.preserveUnchangedBounds(from: entry)

    guard !isSaving else {
      return MutationResult(message: "A Timeline change is already saving.", status: .error)
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedTimelineEntry] =
        try await client
        .rpc(
          "save_timeline_entry_with_occurrence",
          params: SaveTimelineEntryParameters(input: input)
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          message: entry == nil
            ? "This Timeline track is no longer available. Refresh and try again."
            : "This moment changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      await reloadAfterMutation()
      return MutationResult(
        message: entry == nil ? "Added to your Timeline." : "Timeline moment saved.",
        status: .saved
      )
    } catch {
      return MutationResult(
        message: "MemoTrail could not save this moment. Try again.",
        status: .error
      )
    }
  }

  func moveToTrash(_ entry: TimelineEntry) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(message: "A Timeline change is already saving.", status: .error)
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedTimelineEntry] =
        try await client
        .rpc(
          "trash_timeline_entry",
          params: TrashTimelineEntryParameters(
            entryID: entry.id,
            expectedRevision: entry.revision
          )
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          message: "This moment changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      await reloadAfterMutation()
      return MutationResult(message: "Moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        message: "MemoTrail could not move this moment to Trash. Try again.",
        status: .error
      )
    }
  }

  private func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw TimelineControllerError.ownerChanged
    }
  }
}

extension TimelineController {
  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
      case conflict
      case error
      case saved
      case trashed
    }

    let message: String
    let status: Status
  }
}

private enum TimelineControllerError: Error {
  case ownerChanged
}
