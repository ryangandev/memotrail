import Foundation
import Observation
@preconcurrency import Supabase

/// Web `/library`: browse every Entry, or search them with a keyword phrase and Record, tag,
/// and date filters. iOS searches by keyword only.
@MainActor
@Observable
final class LibraryController {
  static let pageSize = 36

  // The search form. A search runs the form as it is when the person submits it or changes a
  // filter; clearing the form returns to browsing.
  var query = ""
  var record: EntryRecordFilter?
  var tagName: String?
  var dateFrom = ""
  var dateTo = ""

  // Browsing.
  private(set) var items: [LibraryRow] = []
  private(set) var totalCount = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var errorMessage: String?
  private(set) var isLoadingMoreItems = false
  private(set) var moreItemsErrorMessage: String?

  // Searching.
  /// The search whose results are showing, or nil while browsing.
  private(set) var activeSearch: EntrySearchRequest?
  private(set) var results: [SearchEntry] = []
  private(set) var resultCount = 0
  private(set) var isSearching = false
  private(set) var searchErrorMessage: String?
  private(set) var isLoadingMoreResults = false
  private(set) var moreResultsErrorMessage: String?

  // Filter choices.
  private(set) var tagOptions: [String] = []
  private(set) var filtersErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID
  private var browseGeneration = UUID()
  private var searchGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  /// Web shows results, or why a search could not run, instead of the browse list.
  var isShowingResults: Bool { activeSearch != nil || searchErrorMessage != nil }

  var activeFilterCount: Int {
    [record != nil, tagName != nil, !dateFrom.isEmpty, !dateTo.isEmpty].filter { $0 }.count
  }

  var hasCriteria: Bool { !query.trimmed.isEmpty || activeFilterCount > 0 }

  /// Changes whenever a filter changes, so the view can run the search again.
  var filterIdentity: [String] {
    [record?.rawValue ?? "", tagName ?? "", dateFrom, dateTo]
  }

  /// More organized records exist past the loaded pages.
  var hasMoreItems: Bool {
    errorMessage == nil && items.count < totalCount && items.count + Self.pageSize <= 100_000
  }

  /// More results exist past the loaded pages.
  var hasMoreResults: Bool {
    activeSearch != nil && searchErrorMessage == nil && results.count < resultCount
      && results.count <= 10_000
  }

  /// Loads the browse list and filter choices, and refreshes the showing search.
  func load() async {
    async let filters: Void = loadFilterOptions()
    async let browse: Void = loadItems()
    if let activeSearch { await run(activeSearch) }
    _ = await (filters, browse)
  }

  func loadItems() async {
    let generation = UUID()
    browseGeneration = generation
    isLoading = true
    isLoadingMoreItems = false
    errorMessage = nil
    moreItemsErrorMessage = nil
    defer {
      if browseGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }
    do {
      let page = try await itemsPage(offset: 0)
      guard browseGeneration == generation else { return }
      items = page
      totalCount = page.first?.totalCount ?? 0
    } catch {
      guard browseGeneration == generation, !(error is CancellationError) else { return }
      items = []
      totalCount = 0
      errorMessage = "Your Life Wiki could not load. Pull to refresh or try again."
    }
  }

  func loadMoreItems() async {
    guard hasMoreItems, !isLoading, !isLoadingMoreItems else { return }
    let generation = browseGeneration
    isLoadingMoreItems = true
    moreItemsErrorMessage = nil
    defer { if browseGeneration == generation { isLoadingMoreItems = false } }
    do {
      let page = try await itemsPage(offset: items.count)
      guard browseGeneration == generation else { return }
      let known = Set(items.map(\.id))
      items.append(contentsOf: page.filter { !known.contains($0.id) })
      totalCount = page.first?.totalCount ?? items.count
    } catch {
      guard browseGeneration == generation, !(error is CancellationError) else { return }
      moreItemsErrorMessage = "More Life Wiki items could not load."
    }
  }

  /// Runs the form as a search. Without criteria it returns to browsing, like Web `/library`.
  func search() async {
    let request: EntrySearchRequest
    do {
      request = try searchRequest()
    } catch {
      clearResults()
      searchErrorMessage = error.localizedDescription
      return
    }
    guard request.hasCriteria else {
      clearResults()
      return
    }
    await run(request)
  }

  /// The form as a validated search. Record sends its Web classification: `entry`, `chapter`,
  /// or `first_time`, so one Entry can match more than one record.
  func searchRequest() throws -> EntrySearchRequest {
    try Self.searchRequest(
      query: query, record: record, tagName: tagName, dateFrom: dateFrom, dateTo: dateTo)
  }

  nonisolated static func searchRequest(
    query: String, record: EntryRecordFilter?, tagName: String?, dateFrom: String,
    dateTo: String
  ) throws -> EntrySearchRequest {
    try EntrySearchRequest.validate(
      query: query, records: record.map { [$0] } ?? [], tagNames: tagName.map { [$0] } ?? [],
      dateFrom: dateFrom, dateTo: dateTo)
  }

  func loadMoreResults() async {
    guard hasMoreResults, !isSearching, !isLoadingMoreResults,
      let request = try? activeSearch?.page(offset: results.count)
    else { return }
    let generation = searchGeneration
    isLoadingMoreResults = true
    moreResultsErrorMessage = nil
    defer { if searchGeneration == generation { isLoadingMoreResults = false } }
    do {
      let page = try await resultsPage(request)
      guard searchGeneration == generation else { return }
      let known = Set(results.map(\.id))
      results.append(contentsOf: page.filter { !known.contains($0.id) })
      resultCount = page.first?.totalCount ?? results.count
    } catch {
      guard searchGeneration == generation, !(error is CancellationError) else { return }
      moreResultsErrorMessage = "More results could not load."
    }
  }

  /// Web "Clear all": empties the form and returns to browsing.
  func clearAll() {
    query = ""
    record = nil
    tagName = nil
    dateFrom = ""
    dateTo = ""
    clearResults()
  }

  private func run(_ request: EntrySearchRequest) async {
    let generation = UUID()
    searchGeneration = generation
    activeSearch = request
    isSearching = true
    isLoadingMoreResults = false
    searchErrorMessage = nil
    moreResultsErrorMessage = nil
    defer { if searchGeneration == generation { isSearching = false } }
    do {
      let page = try await resultsPage(request)
      guard searchGeneration == generation else { return }
      results = page
      resultCount = page.first?.totalCount ?? 0
    } catch {
      guard searchGeneration == generation, !(error is CancellationError) else { return }
      results = []
      resultCount = 0
      searchErrorMessage = "MemoTrail could not search your Entries. Try again."
    }
  }

  private func clearResults() {
    searchGeneration = UUID()
    activeSearch = nil
    results = []
    resultCount = 0
    isSearching = false
    isLoadingMoreResults = false
    searchErrorMessage = nil
    moreResultsErrorMessage = nil
  }

  private func loadFilterOptions() async {
    do {
      try await validateSessionOwner()
      let tags: [OrganizationName] = try await client.from("tags").select("name")
        .eq("owner_id", value: ownerID.uuidString.lowercased()).order("name").execute().value
      try await validateSessionOwner()
      tagOptions = tags.map(\.name)
      filtersErrorMessage = nil
    } catch {
      guard !(error is CancellationError) else { return }
      filtersErrorMessage = "Tag filters are temporarily unavailable. Keyword search still works."
    }
  }

  private func itemsPage(offset: Int) async throws -> [LibraryRow] {
    try await validateSessionOwner()
    let parameters = LibraryPageParameters(limit: Self.pageSize, offset: offset)
    let page: [LibraryRow] = try await client.rpc("wiki_items_workspace", params: parameters)
      .execute().value
    try await validateSessionOwner()
    return page
  }

  /// One page of results with each note's Web formatting, like Web `loadEntryRichTextMap`.
  private func resultsPage(_ request: EntrySearchRequest) async throws -> [SearchEntry] {
    try await validateSessionOwner()
    var page: [SearchEntry] = try await client.rpc(
      "search_wiki_items", params: request.parameters
    )
    .execute().value
    let richTexts = await EntryRichTextMap.load(
      page.map { ($0.id, $0.body) }, client: client, ownerID: ownerID)
    try await validateSessionOwner()
    for index in page.indices { page[index].bodyRich = richTexts[page[index].id] }
    return page
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

private struct OrganizationName: Decodable, Sendable {
  let name: String
}
