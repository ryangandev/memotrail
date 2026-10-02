import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class FirstTimesController {
  private(set) var entries: [FirstTimeEntry] = []
  private(set) var collectionOptions: [String] = []
  private(set) var tagOptions: [String] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID
  /// Only the newest load applies its result, so a slower earlier response cannot replace it.
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  /// Web counts each uploaded photo once, not its generated variants.
  var photoCount: Int {
    entries.reduce(0) { $0 + $1.originalAttachments.count }
  }

  func entry(id: UUID) -> FirstTimeEntry? { entries.first { $0.id == id } }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    loadErrorMessage = nil
    defer {
      if loadGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }

    do {
      try await validateSessionOwner()

      let rows: [FirstTimeWorkspaceRow] =
        try await client
        .rpc("first_times_workspace_with_occurrence")
        .execute()
        .value
      var loadedEntries = FirstTimesWorkspace.entries(from: rows)
      let locations = try await EntryPrimaryLocations.load(
        client: client, ownerID: ownerID, entryIDs: loadedEntries.map(\.id))
      for index in loadedEntries.indices {
        loadedEntries[index].location = locations[loadedEntries[index].id]
      }
      let paths = Array(Set(loadedEntries.flatMap { $0.attachments.map(\.objectPath) }))
      let signedURLs = await signedURLMap(paths: paths)

      for entryIndex in loadedEntries.indices {
        for attachmentIndex in loadedEntries[entryIndex].attachments.indices {
          let path = loadedEntries[entryIndex].attachments[attachmentIndex].objectPath
          loadedEntries[entryIndex].attachments[attachmentIndex].signedURL = signedURLs[path]
        }
      }

      let collections: [FirstTimeOrganizationName] =
        (try? await client
          .from("collections")
          .select("name")
          .eq("owner_id", value: ownerID.uuidString)
          .is("archived_at", value: nil)
          .order("name")
          .execute()
          .value) ?? []
      let tags: [FirstTimeOrganizationName] =
        (try? await client
          .from("tags")
          .select("name")
          .eq("owner_id", value: ownerID.uuidString)
          .order("name")
          .execute()
          .value) ?? []

      guard loadGeneration == generation else { return }
      entries = loadedEntries
      collectionOptions = collections.map(\.name)
      tagOptions = tags.map(\.name)
    } catch {
      guard loadGeneration == generation else { return }
      loadErrorMessage = "MemoTrail could not load your First Times. Pull to refresh or try again."
    }
  }

  func save(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    occurredStart: Date?,
    datePrecision: FirstTimeDatePrecision,
    occurredLabel: String,
    occurredTimezone: String?,
    collectionNames: [String],
    tagNames: [String],
    occurredEnd: Date? = nil,
    original: FirstTimeEntry? = nil,
    removingLocation: Bool = false
  ) async -> MutationResult {
    var input: FirstTimeEntryInput

    do {
      input = try FirstTimeEntryInput.validate(
        entryID: entryID,
        expectedRevision: expectedRevision,
        title: title,
        body: body,
        occurredStart: occurredStart,
        datePrecision: datePrecision,
        occurredLabel: occurredLabel,
        occurredTimezone: occurredTimezone,
        collectionNames: collectionNames,
        tagNames: tagNames,
        occurredEnd: occurredEnd
      )
      input.preserveUnchangedBounds(from: original)
    } catch {
      return MutationResult(identity: nil, message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "A First Time change is already saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      input.expectedRevision = try await EntryPhotoUpload.writingRevision(
        client: client, entryID: entryID, revision: expectedRevision)
      // Like Web, the Location RPC runs only when the Location changed.
      let results: [SavedFirstTimeEntry] =
        removingLocation
        ? try await client
          .rpc(
            "save_first_time_with_location",
            params: RemoveFirstTimeLocationParameters(input: input)
          )
          .execute()
          .value
        : try await client
          .rpc(
            "save_first_time_with_occurrence",
            params: SaveFirstTimeEntryParameters(input: input)
          )
          .execute()
          .value

      guard let saved = results.first else {
        return MutationResult(
          identity: nil,
          message: entryID == nil
            ? "MemoTrail could not create this First Time. Refresh and try again."
            : "This First Time changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      return MutationResult(
        identity: SavedIdentity(id: saved.entryID, revision: saved.revision),
        message: saved.wasCreated ? "First Time added." : "First Time saved.",
        status: saved.wasCreated ? .created : .saved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not save this First Time. Try again.",
        status: .error
      )
    }
  }

  func upload(_ draft: FirstTimePhotoDraft, entryID: UUID) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another First Time change is still saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      let confirmed = try await EntryPhotoUpload.attach(
        draft, entryID: entryID, ownerID: ownerID, client: client,
        registration: "register_first_time_attachment")
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

  func removeAttachment(_ attachment: FirstTimeAttachment) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another First Time change is still saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedFirstTimeAttachment] =
        try await client
        .rpc(
          "trash_first_time_attachment",
          params: TrashFirstTimeAttachmentParameters(attachmentID: attachment.id)
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
        message: "Another First Time change is still saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedFirstTimeEntry] =
        try await client
        .rpc(
          "trash_first_time_entry",
          params: TrashFirstTimeEntryParameters(
            entryID: entryID,
            expectedRevision: expectedRevision
          )
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          identity: nil,
          message: "This First Time changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      await reloadAfterMutation()
      return MutationResult(
        identity: nil, message: "First Time moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this First Time to Trash. Try again.",
        status: .error
      )
    }
  }

  /// Replaces any load still running, so the First Times reflect the change.
  func reloadAfterMutation() async {
    await load()
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw FirstTimesControllerError.ownerChanged
    }
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
  }
}

extension FirstTimesController {
  struct SavedIdentity: Equatable, Sendable {
    let id: UUID
    let revision: Int
  }

  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
      case conflict
      case created
      case error
      case saved
      case trashed
    }

    let identity: SavedIdentity?
    let message: String
    let status: Status

    var succeeded: Bool { [.created, .saved, .trashed].contains(status) }
  }
}

private enum FirstTimesControllerError: Error {
  case ownerChanged
}
