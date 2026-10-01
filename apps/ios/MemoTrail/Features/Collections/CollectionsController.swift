import Foundation
import Observation
@preconcurrency import Supabase

/// Web `getCollectionsWorkspace` without a selected Collection: the Collection summaries and,
/// for each one's editor, its organization identity.
@MainActor
@Observable
final class CollectionsController {
  private(set) var collections: [MemoCollection] = []
  /// The Collections' editor identities, like Web `organizationItems`. A failure here only
  /// hides the editors, as on Web.
  private(set) var organizationItems: [OrganizationItem] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var actions: OrganizationActions { OrganizationActions(client: client, ownerID: ownerID) }

  var entryPlacementCount: Int {
    collections.reduce(0) { $0 + $1.entryCount }
  }

  func item(for collection: MemoCollection) -> OrganizationItem? {
    organizationItems.first { $0.id == collection.id }
  }

  func load() async {
    guard !isLoading else { return }

    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    async let items = actions.load(.collection, limit: 100)
    do {
      collections = try await Self.summary(client: client, ownerID: ownerID)
    } catch {
      collections = []
      loadErrorMessage = "MemoTrail could not load your Collections. Pull to refresh or try again."
    }
    organizationItems = (try? await items) ?? []
  }

  /// Every Collection with its Entry and Inbox counts, in display order.
  static func summary(client: SupabaseClient, ownerID: UUID) async throws -> [MemoCollection] {
    guard try await client.auth.session.user.id == ownerID else {
      throw CollectionsControllerError.ownerChanged
    }
    let rows: [MemoCollection] = try await client.rpc("collections_workspace").execute().value
    return CollectionsWorkspace.collections(from: rows)
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
        .rpc("collection_wiki_items", params: request.parameters)
        .execute()
        .value

      let paths = Array(Set(rows.flatMap { $0.attachments.map(\.objectPath) }))
      async let richTexts = EntryRichTextMap.load(
        rows.map { ($0.id, $0.body) }, client: client, ownerID: ownerID)
      let signedURLs = await signedURLMap(paths: paths)

      let bodies = await richTexts
      for entryIndex in rows.indices {
        rows[entryIndex].bodyRich = bodies[rows[entryIndex].id]
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
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID)
  }
}

private enum CollectionsControllerError: Error {
  case ownerChanged
}
