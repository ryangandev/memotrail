import Foundation
import Observation
@preconcurrency import Supabase

/// Web `getFirstTimesWorkspace`: the Entries marked First Time, with their primary Locations
/// and photo display URLs.
@MainActor
@Observable
final class FirstTimesController {
  private(set) var entries: [FirstTimeRow] = []
  /// Display URLs by Storage object path.
  private(set) var photoURLs: [String: URL] = [:]
  private(set) var hasLoaded = false
  private(set) var isLoading = false
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
    entries.reduce(0) { $0 + $1.attachments.count { $0.variant == "original" } }
  }

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
      var rows: [FirstTimeRow] = try await client.rpc("first_times_workspace").execute().value
      let locations = try await EntryPrimaryLocations.load(
        client: client, ownerID: ownerID, entryIDs: rows.map(\.id))
      for index in rows.indices {
        rows[index].location = locations[rows[index].id]
      }
      let paths = Array(Set(rows.flatMap { $0.attachments.map(\.objectPath) }))
      let urls = await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
      try await validateSessionOwner()

      guard loadGeneration == generation else { return }
      entries = rows
      photoURLs = urls
    } catch {
      guard loadGeneration == generation, !(error is CancellationError) else { return }
      loadErrorMessage = "MemoTrail could not load your First Times. Pull to refresh or try again."
    }
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw FirstTimesControllerError.ownerChanged
    }
  }
}

private enum FirstTimesControllerError: Error {
  case ownerChanged
}
