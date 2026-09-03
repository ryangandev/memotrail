import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CollectionsController {
  private(set) var collections: [MemoCollection] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var entryPlacementCount: Int {
    collections.reduce(0) { $0 + $1.entryCount }
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
      let rows: [MemoCollection] =
        try await client
        .rpc("collections_workspace")
        .execute()
        .value

      collections = CollectionsWorkspace.collections(from: rows)
    } catch {
      loadErrorMessage = "MemoTrail could not load your Collections. Pull to refresh or try again."
    }
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw CollectionsControllerError.ownerChanged
    }
  }
}

@MainActor
@Observable
final class CollectionDetailController {
  private(set) var entries: [CollectionEntry] = []
  private(set) var totalCount = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let collectionID: UUID
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID, collectionID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.collectionID = collectionID
  }

  var canLoadMore: Bool {
    !isLoading && entries.count < totalCount && entries.count <= 10_000
  }

  func load() async {
    await fetch(appending: false)
  }

  func loadMore() async {
    guard canLoadMore else { return }
    await fetch(appending: true)
  }

  private func fetch(appending: Bool) async {
    guard !isLoading else { return }

    let request: CollectionPageRequest
    do {
      request = try CollectionPageRequest.validate(
        collectionID: collectionID,
        offset: appending ? entries.count : 0
      )
    } catch {
      loadErrorMessage = "MemoTrail could not load this Collection. Try again."
      return
    }

    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      try await validateSessionOwner()
      var rows: [CollectionEntry] =
        try await client
        .rpc("collection_entries", params: request.parameters)
        .execute()
        .value

      let paths = Array(Set(rows.flatMap { $0.attachments.map(\.objectPath) }))
      let signedURLs = await signedURLMap(paths: paths)

      for entryIndex in rows.indices {
        for attachmentIndex in rows[entryIndex].attachments.indices {
          let path = rows[entryIndex].attachments[attachmentIndex].objectPath
          rows[entryIndex].attachments[attachmentIndex].signedURL = signedURLs[path]
        }
      }

      if appending {
        let knownIDs = Set(entries.map(\.id))
        entries.append(contentsOf: rows.filter { !knownIDs.contains($0.id) })
      } else {
        entries = rows
      }
      totalCount = rows.first?.totalCount ?? (appending ? totalCount : 0)
    } catch {
      loadErrorMessage = "MemoTrail could not load this Collection. Pull to refresh or try again."
      if !appending {
        entries = []
        totalCount = 0
      }
    }
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw CollectionsControllerError.ownerChanged
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

private enum CollectionsControllerError: Error {
  case ownerChanged
}
