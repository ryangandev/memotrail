import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class VehicleController {
  private(set) var entries: [VehicleEntry] = []
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

  var currentEntries: [VehicleEntry] { entries.filter(\.isCurrent) }
  var earlierEntries: [VehicleEntry] { entries.filter { !$0.isCurrent } }
  var photoCount: Int { entries.reduce(0) { $0 + $1.attachments.count } }

  func entry(id: UUID) -> VehicleEntry? { entries.first { $0.id == id } }

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
      let rows: [VehicleWorkspaceRow] =
        try await client
        .rpc("vehicles_workspace", params: VehicleWorkspaceParameters(limit: 100, offset: 0))
        .execute()
        .value
      var loadedEntries = VehicleWorkspace.entries(from: rows)
      let paths = Array(Set(loadedEntries.flatMap { $0.attachments.map(\.objectPath) }))
      let signedURLs = await signedURLMap(paths: paths)
      for entryIndex in loadedEntries.indices {
        for attachmentIndex in loadedEntries[entryIndex].attachments.indices {
          let path = loadedEntries[entryIndex].attachments[attachmentIndex].objectPath
          loadedEntries[entryIndex].attachments[attachmentIndex].signedURL = signedURLs[path]
        }
      }

      async let collectionsRequest: [VehicleOrganizationName] = loadCollections()
      async let tagsRequest: [VehicleOrganizationName] = loadTags()
      entries = loadedEntries
      collectionOptions = try await collectionsRequest.map(\.name)
      tagOptions = try await tagsRequest.map(\.name)
    } catch {
      loadErrorMessage = "MemoTrail could not load your Vehicles. Pull to refresh or try again."
    }
  }

  func save(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    occurredStart: Date?,
    occurredEnd: Date?,
    datePrecision: VehicleDatePrecision,
    occurredLabel: String,
    occurredTimezone: String,
    make: String,
    model: String,
    modelYear: Int?,
    color: String,
    collectionNames: [String],
    tagNames: [String],
    originalEntry: VehicleEntry? = nil
  ) async -> MutationResult {
    var input: VehicleEntryInput
    do {
      input = try VehicleEntryInput.validate(
        entryID: entryID,
        expectedRevision: expectedRevision,
        title: title,
        body: body,
        occurredStart: occurredStart,
        occurredEnd: occurredEnd,
        datePrecision: datePrecision,
        occurredLabel: occurredLabel,
        occurredTimezone: occurredTimezone,
        make: make,
        model: model,
        modelYear: modelYear,
        color: color,
        collectionNames: collectionNames,
        tagNames: tagNames
      )
    } catch {
      return MutationResult(identity: nil, message: error.localizedDescription, status: .error)
    }

    input.preserveUnchangedBounds(from: originalEntry)
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "A Vehicle change is already saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedVehicleEntry] =
        try await client
        .rpc("save_vehicle_entry_with_occurrence", params: SaveVehicleEntryParameters(input: input))
        .execute()
        .value
      guard let saved = results.first else {
        return MutationResult(
          identity: nil,
          message: entryID == nil
            ? "MemoTrail could not create this Vehicle. Refresh and try again."
            : "This Vehicle changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      return MutationResult(
        identity: SavedIdentity(id: saved.entryID, revision: saved.revision),
        message: saved.wasCreated ? "Vehicle added." : "Vehicle saved.",
        status: .saved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not save this Vehicle. Try again.",
        status: .error
      )
    }
  }

  func upload(_ draft: FirstTimePhotoDraft, entryID: UUID) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Vehicle change is still saving.",
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
      let registered: [RegisteredResidenceAttachment] =
        try await client
        .rpc(
          "register_entry_attachment",
          params: RegisterResidenceAttachmentParameters(
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

  func removeAttachment(_ attachment: VehicleAttachment) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Vehicle change is still saving.",
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
        message: "Another Vehicle change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedVehicleEntry] =
        try await client
        .rpc(
          "trash_vehicle_entry",
          params: TrashVehicleEntryParameters(
            entryID: entryID,
            expectedRevision: expectedRevision
          )
        )
        .execute()
        .value
      guard results.first != nil else {
        return MutationResult(
          identity: nil,
          message: "This Vehicle changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      await reloadAfterMutation()
      return MutationResult(identity: nil, message: "Moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this Vehicle to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func loadCollections() async throws -> [VehicleOrganizationName] {
    try await client.from("collections").select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .is("archived_at", value: nil)
      .order("name").execute().value
  }

  private func loadTags() async throws -> [VehicleOrganizationName] {
    try await client.from("tags").select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .order("name").execute().value
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw VehicleControllerError.ownerChanged }
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
      if case .success(let path, let url) = result { urls[path] = url }
    }
    return urls
  }
}

extension VehicleController {
  struct SavedIdentity: Equatable, Sendable {
    let id: UUID
    let revision: Int
  }

  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable { case conflict, error, saved, trashed }
    let identity: SavedIdentity?
    let message: String
    let status: Status
  }
}

private struct VehicleWorkspaceParameters: Encodable, Sendable {
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

private enum VehicleControllerError: Error { case ownerChanged }
