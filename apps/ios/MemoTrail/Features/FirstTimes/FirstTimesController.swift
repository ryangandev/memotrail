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

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var photoCount: Int {
    entries.reduce(0) { $0 + $1.attachments.count }
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

      let rows: [FirstTimeWorkspaceRow] =
        try await client
        .rpc("first_times_workspace_with_occurrence")
        .execute()
        .value
      var loadedEntries = FirstTimesWorkspace.entries(from: rows)
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

      entries = loadedEntries
      collectionOptions = collections.map(\.name)
      tagOptions = tags.map(\.name)
    } catch {
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
    original: FirstTimeEntry? = nil
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
      let results: [SavedFirstTimeEntry] =
        try await client
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
        status: .saved
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

    let path = draft.objectPath(ownerID: ownerID, entryID: entryID)

    do {
      try await validateSessionOwner()
      try await client.storage.from("entry-media").upload(
        path,
        data: draft.data,
        options: FileOptions(
          cacheControl: "3600",
          contentType: draft.mimeType.rawValue,
          upsert: false
        )
      )

      let registered: [RegisteredFirstTimeAttachment] =
        try await client
        .rpc(
          "register_first_time_attachment",
          params: RegisterFirstTimeAttachmentParameters(
            entryID: entryID,
            draft: draft,
            objectPath: path
          )
        )
        .execute()
        .value

      guard registered.first?.attachmentID == draft.id else {
        _ = try? await client.storage.from("entry-media").remove(paths: [path])
        return MutationResult(
          identity: nil,
          message: "The photo uploaded, but MemoTrail could not attach it. Try again.",
          status: .error
        )
      }

      return MutationResult(identity: nil, message: "Photo attached.", status: .saved)
    } catch {
      _ = try? await client.storage.from("entry-media").remove(paths: [path])
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not upload this photo. Try again.",
        status: .error
      )
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
      return MutationResult(identity: nil, message: "Moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this First Time to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw FirstTimesControllerError.ownerChanged
    }
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    guard !paths.isEmpty else { return [:] }

    let results =
      (try? await client.storage.from("entry-media").createSignedURLs(
        paths: paths,
        expiresIn: 60 * 60
      )) ?? []
    var urls: [String: URL] = [:]

    for result in results {
      if case .success(let path, let url) = result {
        urls[path] = url
      }
    }

    return urls
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
      case error
      case saved
      case trashed
    }

    let identity: SavedIdentity?
    let message: String
    let status: Status
  }
}

private enum FirstTimesControllerError: Error {
  case ownerChanged
}
