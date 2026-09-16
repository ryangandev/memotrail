import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class SearchController {
  var query = "" { didSet { clearAIResult() } }
  var selectedEntryType: SearchEntryType? { didSet { clearAIResult() } }
  var selectedCollectionName: String? { didSet { clearAIResult() } }
  var selectedTagName: String? { didSet { clearAIResult() } }
  var dateFrom: Date? { didSet { clearAIResult() } }
  var dateTo: Date? { didSet { clearAIResult() } }
  private(set) var aiAnswer: AISearchAnswer?
  private(set) var aiError: String?
  private(set) var isAskingAI = false

  private(set) var entries: [SearchEntry] = []
  private(set) var collectionOptions: [String] = []
  private(set) var tagOptions: [String] = []
  private(set) var totalCount = 0
  private(set) var hasSearched = false
  private(set) var isLoading = false
  private(set) var isLoadingFilters = false
  private(set) var hasLoadedFilters = false
  private(set) var searchErrorMessage: String?
  private(set) var filterErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var canLoadMore: Bool {
    !isLoading && entries.count < totalCount && entries.count <= 10_000
  }

  var activeFilterCount: Int {
    [
      selectedEntryType != nil, selectedCollectionName != nil, selectedTagName != nil,
      dateFrom != nil, dateTo != nil,
    ]
    .filter { $0 }
    .count
  }

  var hasCriteria: Bool {
    !query.trimmed.isEmpty || activeFilterCount > 0
  }

  func loadFilterOptions() async {
    guard !hasLoadedFilters, !isLoadingFilters else { return }

    isLoadingFilters = true
    filterErrorMessage = nil
    defer {
      isLoadingFilters = false
      hasLoadedFilters = true
    }

    do {
      try await validateSessionOwner()

      let collections: [SearchOrganizationName] =
        try await client
        .from("collections")
        .select("name")
        .eq("owner_id", value: ownerID.uuidString)
        .is("archived_at", value: nil)
        .order("name")
        .execute()
        .value
      let tags: [SearchOrganizationName] =
        try await client
        .from("tags")
        .select("name")
        .eq("owner_id", value: ownerID.uuidString)
        .order("name")
        .execute()
        .value

      collectionOptions = collections.map(\.name)
      tagOptions = tags.map(\.name)
    } catch {
      filterErrorMessage =
        "Collection and tag filters are temporarily unavailable. Keyword search still works."
    }
  }

  func search() async {
    guard !isAskingAI else { return }
    aiAnswer = nil
    aiError = nil
    await runSearch(appending: false)
  }

  private func clearAIResult() {
    aiAnswer = nil
    aiError = nil
  }

  private func aiInput() throws -> AISearchRequest {
    AISearchRequest(
      request: try EntrySearchRequest.validate(
        query: query,
        entryTypes: selectedEntryType.map { [$0] } ?? [],
        collectionNames: selectedCollectionName.map { [$0] } ?? [],
        tagNames: selectedTagName.map { [$0] } ?? [], dateFrom: dateFrom, dateTo: dateTo))
  }

  func askAI() async {
    guard !isAskingAI, !isLoading else { return }
    guard !query.trimmed.isEmpty else {
      aiError = "Enter a question in the search field first."
      return
    }
    isAskingAI = true
    aiAnswer = nil
    aiError = nil
    defer { isAskingAI = false }
    do {
      let input = try aiInput()
      let result: AISearchAnswer = try await AIAPI.post(
        "search", body: input, client: client, ownerID: ownerID, timeout: 95)
      try await validateSessionOwner()
      guard input == (try aiInput()) else {
        aiError = "Your search changed. Ask again with the new question or filters."
        return
      }
      aiAnswer = result
    } catch { aiError = error.localizedDescription }
  }

  func loadMore() async {
    guard canLoadMore else { return }
    await runSearch(appending: true)
  }

  func clearAll() {
    aiAnswer = nil
    aiError = nil
    query = ""
    selectedEntryType = nil
    selectedCollectionName = nil
    selectedTagName = nil
    dateFrom = nil
    dateTo = nil
    entries = []
    totalCount = 0
    hasSearched = false
    searchErrorMessage = nil
  }

  private func runSearch(appending: Bool) async {
    guard !isLoading else { return }

    let request: EntrySearchRequest
    do {
      request = try EntrySearchRequest.validate(
        query: query,
        entryTypes: selectedEntryType.map { [$0] } ?? [],
        collectionNames: selectedCollectionName.map { [$0] } ?? [],
        tagNames: selectedTagName.map { [$0] } ?? [],
        dateFrom: dateFrom,
        dateTo: dateTo,
        offset: appending ? entries.count : 0
      )
    } catch {
      searchErrorMessage = error.localizedDescription
      if !appending {
        entries = []
        totalCount = 0
        hasSearched = true
      }
      return
    }

    guard request.hasCriteria else {
      entries = []
      totalCount = 0
      hasSearched = false
      searchErrorMessage = nil
      return
    }

    isLoading = true
    searchErrorMessage = nil
    if !appending {
      hasSearched = true
    }
    defer { isLoading = false }

    do {
      try await validateSessionOwner()

      let results: [SearchEntry] =
        try await client
        .rpc("search_entries_with_occurrence", params: request.parameters)
        .execute()
        .value

      if appending {
        let knownIDs = Set(entries.map(\.id))
        entries.append(contentsOf: results.filter { !knownIDs.contains($0.id) })
      } else {
        entries = results
      }
      totalCount = results.first?.totalCount ?? (appending ? totalCount : 0)
    } catch {
      searchErrorMessage = "MemoTrail could not search your Life Wiki. Try again."
      if !appending {
        entries = []
        totalCount = 0
      }
    }
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw SearchControllerError.ownerChanged
    }
  }
}

private struct SearchOrganizationName: Decodable, Sendable {
  let name: String
}

private enum SearchControllerError: Error {
  case ownerChanged
}
