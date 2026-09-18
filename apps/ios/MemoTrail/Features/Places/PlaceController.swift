import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class PlaceController {
  private(set) var entries: [PlaceEntry] = []
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
      entries = PlaceWorkspace.entries(from: try await workspaceRequest)
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
    notes: String
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
        notes: notes
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
          message: "This Place changed on another device. Refresh and try again.",
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

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw PlaceControllerError.ownerChanged }
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
