import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class HomeController {
  private(set) var snapshot: HomeSnapshot?
  private(set) var resurfacedMemory: HomeResurfacedMemory?
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID
  /// Only the newest load applies its result, so a save that lands while an earlier load is
  /// in flight still shows up and a slower earlier response cannot replace it.
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  func load(date: Date = .now, timezone: TimeZone = .current) async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    defer {
      if loadGeneration == generation {
        isLoading = false
        // A load that was cancelled, such as by leaving the screen, has not loaded anything.
        if !Task.isCancelled { hasLoaded = true }
      }
    }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw HomeControllerError.ownerChanged
      }

      let request = try HomeWorkspaceRequest(date: date, timezone: timezone)
      async let resurfacedMemoryTask: HomeResurfacedMemory? = loadResurfacedMemory(
        parameters: request.resurfacingParameters
      )
      let rows: [HomeSnapshot] =
        try await client
        .rpc("home_workspace", params: request.parameters)
        .execute()
        .value

      guard var loadedSnapshot = rows.first else {
        throw HomeControllerError.missingSnapshot
      }
      var loadedMemory = await resurfacedMemoryTask

      let paths = Array(
        Set(
          loadedSnapshot.recentEntries.flatMap { $0.attachments.map(\.objectPath) }
            + (loadedMemory?.entry.attachments.map(\.objectPath) ?? [])
        )
      )
      let signedURLs = await signedURLMap(paths: paths)

      for entryIndex in loadedSnapshot.recentEntries.indices {
        for attachmentIndex in loadedSnapshot.recentEntries[entryIndex].attachments.indices {
          let path =
            loadedSnapshot.recentEntries[entryIndex].attachments[attachmentIndex].objectPath
          loadedSnapshot.recentEntries[entryIndex].attachments[attachmentIndex].signedURL =
            signedURLs[path]
        }
      }

      if var memory = loadedMemory {
        for attachmentIndex in memory.entry.attachments.indices {
          let path = memory.entry.attachments[attachmentIndex].objectPath
          memory.entry.attachments[attachmentIndex].signedURL = signedURLs[path]
        }
        loadedMemory = memory
      }

      guard loadGeneration == generation else { return }
      snapshot = loadedSnapshot
      resurfacedMemory = loadedMemory
      loadErrorMessage = nil
    } catch {
      guard loadGeneration == generation, !Task.isCancelled else { return }
      loadErrorMessage = "MemoTrail could not load Home. Pull to refresh or try again."
    }
  }

  private func loadResurfacedMemory(
    parameters: HomeResurfacingParameters
  ) async -> HomeResurfacedMemory? {
    let rows: [HomeResurfacedMemory]? =
      try? await client
      .rpc("home_resurfaced_memory", params: parameters)
      .execute()
      .value
    return rows?.first
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
  }
}

private enum HomeControllerError: Error {
  case missingSnapshot
  case ownerChanged
}
