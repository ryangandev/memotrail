import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class PlaceController {
  private(set) var entries: [PlaceEntry] = []
  private(set) var linkOptions: [PlaceLinkOption] = []
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

  var linkedEntries: [PlaceEntry] { entries.filter(\.isLinked) }
  var unlinkedEntries: [PlaceEntry] { entries.filter { !$0.isLinked } }
  var mappedCount: Int { entries.count { $0.coordinateLabel != nil } }

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
      async let workspaceRequest: [PlaceWorkspaceRow] =
        client
        .rpc("places_workspace", params: PlaceWorkspaceParameters(limit: 100, offset: 0))
        .execute()
        .value
      async let linksRequest: [PlaceLinkOption] = loadLinkOptions()

      var loadedEntries = PlaceWorkspace.entries(from: try await workspaceRequest)
      let paths = Array(
        Set(
          loadedEntries.flatMap { place in
            place.linkedEntries.flatMap { $0.attachments.map(\.objectPath) }
          }
        )
      )
      let signedURLs = await signedURLMap(paths: paths)

      for placeIndex in loadedEntries.indices {
        for entryIndex in loadedEntries[placeIndex].linkedEntries.indices {
          for attachmentIndex in loadedEntries[placeIndex].linkedEntries[entryIndex].attachments
            .indices
          {
            let path =
              loadedEntries[placeIndex].linkedEntries[entryIndex].attachments[attachmentIndex]
              .objectPath
            loadedEntries[placeIndex].linkedEntries[entryIndex].attachments[attachmentIndex]
              .signedURL = signedURLs[path]
          }
        }
      }

      entries = loadedEntries
      linkOptions = try await linksRequest
    } catch {
      loadErrorMessage = "MemoTrail could not load your Places. Pull to refresh or try again."
    }
  }

  func save(
    placeID: UUID?,
    expectedRevision: Int?,
    name: String,
    address: String,
    city: String,
    region: String,
    country: String,
    latitude: Double?,
    longitude: Double?,
    notes: String,
    relatedEntryIDs: [UUID]
  ) async -> MutationResult {
    let input: PlaceInput
    do {
      input = try PlaceInput.validate(
        placeID: placeID,
        expectedRevision: expectedRevision,
        name: name,
        address: address,
        city: city,
        region: region,
        country: country,
        latitude: latitude,
        longitude: longitude,
        notes: notes,
        relatedEntryIDs: relatedEntryIDs
      )
    } catch {
      return MutationResult(identity: nil, message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "A Place change is already saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let rows: [SavedPlace] =
        try await client
        .rpc("save_place", params: SavePlaceParameters(input: input))
        .execute()
        .value
      guard let saved = rows.first else {
        return MutationResult(
          identity: nil,
          message: placeID == nil
            ? "MemoTrail could not create this Place. Refresh and try again."
            : "This Place changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }
      return MutationResult(
        identity: SavedIdentity(id: saved.placeID, revision: saved.revision),
        message: saved.wasCreated ? "Place added." : "Place saved.",
        status: .saved
      )
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not save this Place. Try again.",
        status: .error
      )
    }
  }

  func moveToTrash(placeID: UUID, expectedRevision: Int) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        identity: nil,
        message: "Another Place change is still saving.",
        status: .error
      )
    }
    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let rows: [TrashedPlace] =
        try await client
        .rpc(
          "trash_place",
          params: TrashPlaceParameters(
            placeID: placeID,
            expectedRevision: expectedRevision
          )
        )
        .execute()
        .value
      guard rows.first?.placeID == placeID else {
        return MutationResult(
          identity: nil,
          message: "This Place changed or is still linked to an Entry. Refresh and try again.",
          status: .conflict
        )
      }
      await reloadAfterMutation()
      return MutationResult(identity: nil, message: "Moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        identity: nil,
        message: "MemoTrail could not move this Place to Trash. Try again.",
        status: .error
      )
    }
  }

  func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func loadLinkOptions() async throws -> [PlaceLinkOption] {
    try await client.from("entries").select("id,title,body,entry_type,updated_at")
      .eq("owner_id", value: ownerID.uuidString)
      .is("deleted_at", value: nil)
      .order("updated_at", ascending: false)
      .limit(200)
      .execute().value
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw PlaceControllerError.ownerChanged }
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

extension PlaceController {
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

private struct PlaceWorkspaceParameters: Encodable, Sendable {
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

private enum PlaceControllerError: Error { case ownerChanged }
