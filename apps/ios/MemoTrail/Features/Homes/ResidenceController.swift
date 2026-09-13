import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class ResidenceController {
  private(set) var entries: [ResidenceEntry] = []
  private(set) var collectionOptions: [String] = []
  private(set) var tagOptions: [String] = []
  private(set) var placeOptions: [ResidencePlace] = []
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

  var currentEntries: [ResidenceEntry] { entries.filter(\.isCurrent) }
  var earlierEntries: [ResidenceEntry] { entries.filter { !$0.isCurrent } }
  var photoCount: Int { entries.reduce(0) { $0 + $1.attachments.count } }

  func entry(id: UUID) -> ResidenceEntry? {
    entries.first { $0.id == id }
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

      let rows: [ResidenceWorkspaceRow] =
        try await client
        .rpc(
          "homes_workspace",
          params: ResidenceWorkspaceParameters(limit: 100, offset: 0)
        )
        .execute()
        .value
      var loadedEntries = ResidenceWorkspace.entries(from: rows)
      let paths = Array(Set(loadedEntries.flatMap { $0.attachments.map(\.objectPath) }))
      let signedURLs = await signedURLMap(paths: paths)

      for entryIndex in loadedEntries.indices {
        for attachmentIndex in loadedEntries[entryIndex].attachments.indices {
          let path = loadedEntries[entryIndex].attachments[attachmentIndex].objectPath
          loadedEntries[entryIndex].attachments[attachmentIndex].signedURL = signedURLs[path]
        }
      }

      async let collectionsRequest: [ResidenceOrganizationName] = loadCollections()
      async let tagsRequest: [ResidenceOrganizationName] = loadTags()
      async let placesRequest: [ResidencePlace] = loadPlaces()

      entries = loadedEntries
      collectionOptions = try await collectionsRequest.map(\.name)
      tagOptions = try await tagsRequest.map(\.name)
      placeOptions = try await placesRequest
    } catch {
      loadErrorMessage = "MemoTrail could not load your Homes. Pull to refresh or try again."
    }
  }

  func save(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    occurredStart: Date?,
    occurredEnd: Date?,
    datePrecision: ResidenceDatePrecision,
    occurredLabel: String,
    occurredTimezone: String,
    placeID: UUID?,
    placeName: String,
    address: String,
    city: String,
    region: String,
    country: String,
    latitude: Double?,
    longitude: Double?,
    placeNotes: String,
    moveInReason: String,
    moveOutReason: String,
    collectionNames: [String],
    tagNames: [String],
    originalEntry: ResidenceEntry? = nil
  ) async -> MutationResult {
    var input: ResidenceEntryInput

    do {
      input = try ResidenceEntryInput.validate(
        entryID: entryID,
        expectedRevision: expectedRevision,
        title: title,
        body: body,
        occurredStart: occurredStart,
        occurredEnd: occurredEnd,
        datePrecision: datePrecision,
        occurredLabel: occurredLabel,
        occurredTimezone: occurredTimezone,
        placeID: placeID,
        placeName: placeName,
        address: address,
        city: city,
        region: region,
        country: country,
        latitude: latitude,
        longitude: longitude,
        placeNotes: placeNotes,
        moveInReason: moveInReason,
        moveOutReason: moveOutReason,
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
        message: "A Home change is already saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedResidenceEntry] =
        try await client
        .rpc("save_home_entry_with_occurrence", params: SaveResidenceEntryParameters(input: input))
        .execute()
        .value

      guard let saved = results.first else {
        return MutationResult(
          identity: nil,
          message: entryID == nil
            ? "MemoTrail could not create this Home. Refresh and try again."
            : "This Home changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      return MutationResult(
        identity: SavedIdentity(
          id: saved.entryID,
          revision: saved.revision,
          placeID: saved.placeID
        ),
        message: saved.wasCreated ? "Home added." : "Home saved.",
        status: .saved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not save this Home. Try again.",
        status: .error
      )
    }
  }

  func upload(_ draft: FirstTimePhotoDraft, entryID: UUID) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Home change is still saving.",
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

  func removeAttachment(_ attachment: ResidenceAttachment) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Home change is still saving.",
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
        message: "Another Home change is still saving.",
        status: .error
      )
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [TrashedResidenceEntry] =
        try await client
        .rpc(
          "trash_home_entry",
          params: TrashResidenceEntryParameters(
            entryID: entryID,
            expectedRevision: expectedRevision
          )
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          identity: nil,
          message: "This Home changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      await reloadAfterMutation()
      return MutationResult(identity: nil, message: "Moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this Home to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func loadCollections() async throws -> [ResidenceOrganizationName] {
    try await client
      .from("collections")
      .select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .is("archived_at", value: nil)
      .order("name")
      .execute()
      .value
  }

  private func loadTags() async throws -> [ResidenceOrganizationName] {
    try await client
      .from("tags")
      .select("name")
      .eq("owner_id", value: ownerID.uuidString)
      .order("name")
      .execute()
      .value
  }

  private func loadPlaces() async throws -> [ResidencePlace] {
    try await client
      .from("places")
      .select("id,name,address,city,region,country,latitude,longitude,notes")
      .eq("owner_id", value: ownerID.uuidString)
      .is("deleted_at", value: nil)
      .order("name")
      .execute()
      .value
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw ResidenceControllerError.ownerChanged }
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
  }
}

extension ResidenceController {
  struct SavedIdentity: Equatable, Sendable {
    let id: UUID
    let revision: Int
    let placeID: UUID
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

private struct ResidenceWorkspaceParameters: Encodable, Sendable {
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

private enum ResidenceControllerError: Error {
  case ownerChanged
}
