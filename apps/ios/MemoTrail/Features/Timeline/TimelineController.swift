import Foundation
import Observation
@preconcurrency import Supabase

/// Web `getTimelineWorkspace` and the Timeline actions: tracks with their records, dated First
/// Times not yet placed, and the Collection and tag names editors suggest.
@MainActor
@Observable
final class TimelineController {
  private(set) var tracks: [TimelineTrack] = []
  private(set) var collectionOptions: [String] = []
  private(set) var tagOptions: [String] = []
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

  var entries: [TimelineEntry] { tracks.flatMap(\.entries) }

  func load() async {
    guard !isLoading else { return }

    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      try await validateSessionOwner()
      async let rowsRequest = loadRows()
      async let firstTimesRequest = loadFirstTimes()
      async let collectionsRequest = loadNames(from: "collections")
      async let tagsRequest = loadNames(from: "tags")
      let rows = try await rowsRequest
      // Like Web, optional First Times and suggestions never block the Timeline itself.
      let firstTimes = (try? await firstTimesRequest) ?? []
      collectionOptions = (try? await collectionsRequest) ?? collectionOptions
      tagOptions = (try? await tagsRequest) ?? tagOptions
      tracks = TimelineWorkspace.includingUnplacedFirstTimes(
        TimelineWorkspace.tracks(from: rows), firstTimes: firstTimes)
      loadErrorMessage = nil
    } catch {
      guard !(error is CancellationError) else { return }
      loadErrorMessage = "MemoTrail could not load your Timeline. Pull to refresh or try again."
    }
  }

  func save(
    entry: TimelineEntry?,
    trackID: UUID,
    kind: TimelineKind,
    title: String,
    body: String,
    occurrence: EntryOccurrence,
    collectionNames: [String],
    tagNames: [String]
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
        occurredStart: occurrence.start,
        occurredEnd: kind == .stage ? occurrence.end : nil,
        datePrecision: occurrence.precision,
        occurredLabel: occurrence.label ?? "",
        occurredTimezone: occurrence.timezone,
        collectionNames: collectionNames,
        tagNames: tagNames
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
          "save_timeline_entry_with_organization",
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
      return entry == nil
        ? MutationResult(message: "Moment created.", status: .created)
        : MutationResult(message: "Moment saved.", status: .saved)
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
      return MutationResult(message: "Moment moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        message: "MemoTrail could not move this moment to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func loadRows() async throws -> [TimelineWorkspaceRow] {
    try await client
      .rpc(
        "timeline_workspace_with_organization",
        params: TimelineWorkspaceParameters(includeHidden: false)
      )
      .execute()
      .value
  }

  private func loadFirstTimes() async throws -> [FirstTimeEntry] {
    let rows: [FirstTimeWorkspaceRow] =
      try await client
      .rpc("first_times_workspace_with_occurrence")
      .execute()
      .value
    return FirstTimesWorkspace.entries(from: rows)
  }

  private func loadNames(from table: String) async throws -> [String] {
    var query = client.from(table).select("name").eq("owner_id", value: ownerID.uuidString)
    if table == "collections" { query = query.is("archived_at", value: nil) }
    let rows: [TimelineOrganizationName] = try await query.order("name").execute().value
    return rows.map(\.name)
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
      case created
      case error
      case saved
      case trashed
    }

    let message: String
    let status: Status

    var succeeded: Bool { [.created, .saved, .trashed].contains(status) }
  }
}

private struct TimelineOrganizationName: Decodable, Sendable {
  let name: String
}

private enum TimelineControllerError: Error {
  case ownerChanged
}
