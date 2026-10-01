import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class GoalController {
  private(set) var entries: [GoalEntry] = []
  private(set) var collectionOptions: [String] = []
  private(set) var tagOptions: [String] = []
  private(set) var linkOptions: [GoalLinkOption] = []
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

  func entry(id: UUID) -> GoalEntry? { entries.first { $0.id == id } }

  /// Loads the first page of Goals, like Web. A Goal's own page passes its ID so a Goal past
  /// that page still loads, like Web `getGoalsWorkspace(targetId)`.
  func load(including targetID: UUID? = nil) async {
    guard !isLoading else { return }
    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      try await validateSessionOwner()
      async let workspaceRequest = loadPage(offset: 0)
      async let collectionsRequest: [GoalOrganizationName] = loadCollections()
      async let tagsRequest: [GoalOrganizationName] = loadTags()
      async let linksRequest: [GoalLinkOption] = loadLinkOptions()

      var rows = try await workspaceRequest
      if let targetID, !rows.contains(where: { $0.entryID == targetID }) {
        var offset = Self.pageSize
        while rows.count >= offset {
          let page = try await loadPage(offset: offset)
          rows += page
          if page.count < Self.pageSize || page.contains(where: { $0.entryID == targetID }) {
            break
          }
          offset += Self.pageSize
        }
      }
      var loadedEntries = GoalWorkspace.entries(from: rows)
      let paths = Array(Set(loadedEntries.flatMap { $0.attachments.map(\.objectPath) }))
      let signedURLs = await signedURLMap(paths: paths)
      for entryIndex in loadedEntries.indices {
        for attachmentIndex in loadedEntries[entryIndex].attachments.indices {
          let path = loadedEntries[entryIndex].attachments[attachmentIndex].objectPath
          loadedEntries[entryIndex].attachments[attachmentIndex].signedURL = signedURLs[path]
        }
      }

      entries = loadedEntries
      // Like Web, the Goals load even when their options cannot.
      collectionOptions = ((try? await collectionsRequest) ?? []).map(\.name)
      tagOptions = ((try? await tagsRequest) ?? []).map(\.name)
      linkOptions = (try? await linksRequest) ?? []
    } catch {
      loadErrorMessage = "MemoTrail could not load your Goals. Pull to refresh or try again."
    }
  }

  func save(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    horizon: GoalHorizon,
    status: GoalStatus,
    targetDate: String?,
    collectionNames: [String],
    tagNames: [String],
    relatedEntryIDs: [UUID],
    sourceCapture: CaptureExtractionSource? = nil
  ) async -> MutationResult {
    var input: GoalEntryInput
    do {
      input = try GoalEntryInput.validate(
        entryID: entryID,
        expectedRevision: expectedRevision,
        title: title,
        body: body,
        horizon: horizon,
        status: status,
        targetDate: targetDate,
        collectionNames: collectionNames,
        tagNames: tagNames,
        relatedEntryIDs: relatedEntryIDs
      )
    } catch {
      return MutationResult(identity: nil, message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "A Goal change is already saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      if let sourceCapture {
        guard entryID == nil, expectedRevision == nil else {
          return MutationResult(
            identity: nil, message: "A Capture can only create a new Goal.", status: .error)
        }
        let results: [ExtractedCaptureGoal] =
          try await client
          .rpc(
            "extract_capture_to_goal",
            params: SaveGoalEntryParameters(input: input, source: sourceCapture)
          )
          .execute()
          .value
        guard let saved = results.first else {
          return MutationResult(
            identity: nil,
            message: "This Capture changed or was already organized. Return to Inbox and refresh.",
            status: .conflict)
        }
        return MutationResult(
          identity: SavedIdentity(
            id: saved.goalEntryID, revision: saved.goalRevision, relatedID: nil),
          message: "Goal created from Capture.",
          status: .created)
      }
      input.expectedRevision = try await EntryPhotoUpload.writingRevision(
        client: client, entryID: entryID, revision: expectedRevision)
      let results: [SavedGoalEntry] =
        try await client
        .rpc("save_goal_entry", params: SaveGoalEntryParameters(input: input))
        .execute()
        .value
      guard let saved = results.first else {
        return MutationResult(
          identity: nil,
          message: entryID == nil
            ? "MemoTrail could not create this Goal. Refresh and try again."
            : "This Goal changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      return MutationResult(
        identity: SavedIdentity(id: saved.entryID, revision: saved.revision, relatedID: nil),
        message: saved.wasCreated ? "Goal added." : "Goal saved.",
        status: saved.wasCreated ? .created : .saved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not save this Goal. Try again.",
        status: .error
      )
    }
  }

  func markAchieved(
    entryID: UUID,
    expectedRevision: Int,
    occurredStart: Date?,
    datePrecision: GoalAchievementPrecision,
    occurredLabel: String,
    occurredTimezone: String,
    occurredEnd: Date? = nil
  ) async -> MutationResult {
    let input: GoalAchievementInput
    do {
      input = try GoalAchievementInput.validate(
        goalEntryID: entryID,
        expectedRevision: expectedRevision,
        occurredStart: occurredStart,
        datePrecision: datePrecision,
        occurredLabel: occurredLabel,
        occurredTimezone: occurredTimezone,
        occurredEnd: occurredEnd
      )
    } catch {
      return MutationResult(identity: nil, message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Goal change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [AchievedGoalEntry] =
        try await client
        .rpc(
          "achieve_goal_with_occurrence",
          params: GoalAchievementParameters(input: input)
        )
        .execute()
        .value
      guard let achieved = results.first else {
        return MutationResult(
          identity: nil,
          message:
            "This Goal changed or is no longer in Bucket List. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      return MutationResult(
        identity: SavedIdentity(
          id: achieved.goalEntryID,
          revision: achieved.goalRevision,
          relatedID: achieved.firstTimeEntryID
        ),
        message: "Achievement saved, with a linked First Time.",
        status: .achieved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not record this achievement. Try again.",
        status: .error
      )
    }
  }

  func upload(_ draft: FirstTimePhotoDraft, entryID: UUID) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Goal change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }
    do {
      let confirmed = try await EntryPhotoUpload.attach(
        draft, entryID: entryID, ownerID: ownerID, client: client)
      guard confirmed else {
        return MutationResult(
          identity: nil,
          message:
            "Photo attachment is not confirmed. Retry with the same selected photo; no original was deleted.",
          status: .error)
      }
      return MutationResult(identity: nil, message: "Photo attached.", status: .saved)
    } catch {
      return MutationResult(
        identity: nil,
        message:
          "Photo attachment is not confirmed. Retry with the same selected photo; no original was deleted.",
        status: .error)
    }
  }

  func removeAttachment(_ attachment: GoalAttachment) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Goal change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedResidenceAttachment] =
        try await client
        .rpc(
          "trash_entry_attachment",
          params: TrashResidenceAttachmentParameters(attachmentID: attachment.id)
        )
        .execute()
        .value
      guard results.first?.attachmentID == attachment.id else {
        return MutationResult(
          identity: nil,
          message: "This photo is no longer available. Refresh and try again.",
          status: .conflict
        )
      }
      return MutationResult(identity: nil, message: "Photo moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not remove this photo. Try again.",
        status: .error
      )
    }
  }

  func moveToTrash(entryID: UUID, expectedRevision: Int) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Goal change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedGoalEntry] =
        try await client
        .rpc(
          "trash_goal_entry",
          params: TrashGoalEntryParameters(
            entryID: entryID,
            expectedRevision: expectedRevision
          )
        )
        .execute()
        .value
      guard results.first != nil else {
        return MutationResult(
          identity: nil,
          message: "This Goal changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      await reloadAfterMutation()
      return MutationResult(identity: nil, message: "Goal moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this Goal to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private static let pageSize = 100

  private func loadPage(offset: Int) async throws -> [GoalWorkspaceRow] {
    try await client
      .rpc("goals_workspace", params: GoalWorkspaceParameters(limit: Self.pageSize, offset: offset))
      .execute()
      .value
  }

  private func loadCollections() async throws -> [GoalOrganizationName] {
    try await client.from("collections").select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .is("archived_at", value: nil)
      .order("name").execute().value
  }

  private func loadTags() async throws -> [GoalOrganizationName] {
    try await client.from("tags").select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .order("name").execute().value
  }

  private func loadLinkOptions() async throws -> [GoalLinkOption] {
    try await client.from("entries").select("id,title,body,item_kind,item_subtype,updated_at")
      .eq("owner_id", value: ownerID.uuidString)
      .is("deleted_at", value: nil)
      .order("updated_at", ascending: false)
      .limit(200)
      .execute().value
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw GoalControllerError.ownerChanged }
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
  }
}

extension GoalController {
  struct SavedIdentity: Equatable, Sendable {
    let id: UUID
    let revision: Int
    let relatedID: UUID?
  }

  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable { case achieved, conflict, created, error, saved, trashed }
    let identity: SavedIdentity?
    let message: String
    let status: Status

    var succeeded: Bool { [.achieved, .created, .saved, .trashed].contains(status) }
  }
}

private struct GoalWorkspaceParameters: Encodable, Sendable {
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

private struct GoalOrganizationName: Decodable, Sendable { let name: String }

private enum GoalControllerError: Error { case ownerChanged }
