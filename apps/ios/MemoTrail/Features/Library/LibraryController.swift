import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class LibraryController {
  static let pageSize = 36

  var query = ""
  var selectedKind: WikiItemKind?

  private(set) var items: [WikiItemSummary] = []
  private(set) var totalCount = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID
  private var generation = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var canLoadMore: Bool {
    !isLoading && items.count < totalCount && items.count <= 100_000
  }

  var filterIdentity: String {
    "\(selectedKind?.rawValue ?? "all")|\(query.trimmed)"
  }

  func load() async {
    let requestGeneration = UUID()
    generation = requestGeneration
    isLoading = true
    errorMessage = nil

    defer {
      if generation == requestGeneration {
        isLoading = false
        hasLoaded = true
      }
    }

    do {
      let results = try await request(offset: 0)
      try Task.checkCancellation()
      guard generation == requestGeneration else { return }
      items = results
      totalCount = results.first?.totalCount ?? 0
    } catch is CancellationError {
      return
    } catch {
      guard generation == requestGeneration else { return }
      items = []
      totalCount = 0
      errorMessage = "Your Life Wiki could not load. Pull to refresh or try again."
    }
  }

  func loadMore() async {
    guard canLoadMore else { return }

    let requestGeneration = UUID()
    generation = requestGeneration
    isLoading = true
    errorMessage = nil
    defer {
      if generation == requestGeneration { isLoading = false }
    }

    do {
      let results = try await request(offset: items.count)
      try Task.checkCancellation()
      guard generation == requestGeneration else { return }
      let knownIDs = Set(items.map(\.id))
      items.append(contentsOf: results.filter { !knownIDs.contains($0.id) })
      totalCount = results.first?.totalCount ?? totalCount
    } catch is CancellationError {
      return
    } catch {
      guard generation == requestGeneration else { return }
      errorMessage = "Older Life Wiki items could not load. Try again."
    }
  }

  private func request(offset: Int) async throws -> [WikiItemSummary] {
    try await validateSessionOwner()
    let normalizedQuery = String(query.trimmed.prefix(200))
    let parameters = WikiItemsPageParameters(
      pQuery: normalizedQuery,
      pItemKinds: selectedKind.map { [$0.rawValue] } ?? [],
      pItemSubtypes: [],
      pLimit: Self.pageSize,
      pOffset: offset
    )
    let results: [WikiItemSummary] =
      try await client
      .rpc("wiki_items_workspace", params: parameters)
      .execute()
      .value
    try await validateSessionOwner()
    return results
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}
