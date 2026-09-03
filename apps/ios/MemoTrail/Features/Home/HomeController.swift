import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class HomeController {
  private(set) var snapshot: HomeSnapshot?
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  func load(date: Date = .now, timezone: TimeZone = .current) async {
    guard !isLoading else { return }

    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else {
        throw HomeControllerError.ownerChanged
      }

      let request = try HomeWorkspaceRequest(date: date, timezone: timezone)
      let rows: [HomeSnapshot] =
        try await client
        .rpc("home_workspace", params: request.parameters)
        .execute()
        .value

      guard var loadedSnapshot = rows.first else {
        throw HomeControllerError.missingSnapshot
      }

      let paths = Array(
        Set(loadedSnapshot.recentEntries.flatMap { $0.attachments.map(\.objectPath) })
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

      snapshot = loadedSnapshot
    } catch {
      loadErrorMessage = "MemoTrail could not load Home. Pull to refresh or try again."
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

private enum HomeControllerError: Error {
  case missingSnapshot
  case ownerChanged
}
