import Foundation
import Observation
@preconcurrency import Supabase

/// Loads People like Web `/people` and `/people/<id>`, and saves or trashes them through the
/// same `save_person` and `trash_person` functions.
@MainActor
@Observable
final class PeopleController {
  /// The loaded pages of `people_workspace`, most recently changed first.
  private(set) var peopleIDs: [UUID] = []
  /// The Items offered for linking: like Web, the 200 most recently changed.
  private(set) var linkOptions: [PersonLinkedEntry] = []
  private(set) var totalCount = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isLoadingMore = false
  private(set) var isSaving = false
  private(set) var loadErrorMessage: String?
  private(set) var moreErrorMessage: String?
  /// Every Person fetched from a page or opened on their own, so a Person's page stays current
  /// whichever way it was reached.
  private var records: [UUID: PersonRecord] = [:]

  private let client: SupabaseClient
  private let ownerID: UUID
  private static let pageSize = 100
  /// Only the newest list load applies its result, so a slower earlier response cannot replace
  /// it. Loading more pages applies only to the list it extends.
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var people: [PersonRecord] { peopleIDs.compactMap { records[$0] } }
  var hasMore: Bool { peopleIDs.count < totalCount }

  func person(id: UUID) -> PersonRecord? { records[id] }

  /// Loads the first page of People and the Items offered for linking.
  func load() async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    isLoadingMore = false
    loadErrorMessage = nil
    moreErrorMessage = nil
    defer {
      if loadGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }
    do {
      try await validateSessionOwner()
      async let page = loadPage(offset: 0)
      async let options = loadLinkOptions()
      let rows = try await page
      let loadedOptions = try await options
      guard loadGeneration == generation else { return }
      linkOptions = loadedOptions
      for row in rows { records[row.id] = row }
      peopleIDs = rows.map(\.id)
      totalCount = rows.first?.totalCount ?? 0
    } catch {
      guard loadGeneration == generation else { return }
      loadErrorMessage = "Could not load People and Item choices. Refresh to try again."
    }
  }

  func loadMore() async {
    guard hasMore, !isLoading, !isLoadingMore else { return }
    let generation = loadGeneration
    isLoadingMore = true
    moreErrorMessage = nil
    defer { if loadGeneration == generation { isLoadingMore = false } }
    do {
      try await validateSessionOwner()
      let rows = try await loadPage(offset: peopleIDs.count)
      guard loadGeneration == generation else { return }
      for row in rows { records[row.id] = row }
      // A change elsewhere can shift a Person onto the next page, so each appears once.
      let known = Set(peopleIDs)
      peopleIDs += rows.map(\.id).filter { !known.contains($0) }
      totalCount = rows.isEmpty ? peopleIDs.count : rows[0].totalCount
    } catch {
      guard loadGeneration == generation else { return }
      moreErrorMessage = "Could not load more People."
    }
  }

  enum PersonLoad: Equatable, Sendable { case loaded, unavailable, failed }

  /// Web `person_record`: one Person by ID, whether or not the loaded pages include them.
  @discardableResult
  func loadPerson(id: UUID) async -> PersonLoad {
    do {
      try await validateSessionOwner()
      async let record: [PersonRecord] = client.rpc(
        "person_record", params: ["p_person_id": id.uuidString]
      ).execute().value
      async let options = loadLinkOptions()
      guard let person = try await record.first else {
        records[id] = nil
        return .unavailable
      }
      records[id] = person
      // Like Web, the page opens even when its link choices cannot load.
      linkOptions = (try? await options) ?? linkOptions
      return .loaded
    } catch {
      return .failed
    }
  }

  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable { case conflict, created, error, saved, trashed }
    let personID: UUID?
    let message: String
    let status: Status

    var succeeded: Bool { [.created, .saved, .trashed].contains(status) }
  }

  func save(_ input: PersonSaveInput) async -> MutationResult {
    guard input.isValid else {
      return MutationResult(
        personID: nil, message: PersonSaveInput.invalidMessage, status: .error)
    }
    guard !isSaving else {
      return MutationResult(
        personID: nil, message: "A Person change is already saving.", status: .error)
    }
    isSaving = true
    defer { isSaving = false }
    do {
      try await validateSessionOwner()
      let rows: [PersonMutation] = try await client.rpc("save_person", params: input).execute()
        .value
      guard let saved = rows.first else {
        return MutationResult(
          personID: nil,
          message: "This Person changed on another device. Refresh before editing again.",
          status: .conflict)
      }
      await reload(after: saved.personID)
      let created = input.personID == nil
      return MutationResult(
        personID: saved.personID, message: created ? "Person created." : "Person saved.",
        status: created ? .created : .saved)
    } catch PeopleControllerError.ownerChanged {
      return MutationResult(
        personID: nil, message: "Sign in again to save this Person.", status: .error)
    } catch is URLError {
      return MutationResult(
        personID: nil,
        message: "Could not reach MemoTrail. Your edits are still here; try again when online.",
        status: .error)
    } catch {
      return MutationResult(
        personID: nil,
        message: "Could not save this Person. Check the Item links and try again.",
        status: .error)
    }
  }

  func moveToTrash(_ person: PersonRecord) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(
        personID: nil, message: "A Person change is already saving.", status: .error)
    }
    isSaving = true
    defer { isSaving = false }
    do {
      try await validateSessionOwner()
      let rows: [PersonMutation] = try await client.rpc(
        "trash_person",
        params: PersonTrashParameters(personID: person.id, expectedRevision: person.revision)
      ).execute().value
      guard !rows.isEmpty else {
        return MutationResult(
          personID: nil,
          message:
            "This Person changed or still has Item links. Unlink and save before moving to Trash.",
          status: .conflict)
      }
      records[person.id] = nil
      peopleIDs.removeAll { $0 == person.id }
      totalCount = max(0, totalCount - 1)
      await reloadList()
      return MutationResult(
        personID: person.id, message: "Person moved to Trash.", status: .trashed)
    } catch PeopleControllerError.ownerChanged {
      return MutationResult(personID: nil, message: "Sign in again to continue.", status: .error)
    } catch is URLError {
      return MutationResult(
        personID: nil,
        message: "Could not reach MemoTrail. Try again when online.",
        status: .error)
    } catch {
      return MutationResult(
        personID: nil,
        message:
          "This Person changed or still has Item links. Unlink and save before moving to Trash.",
        status: .error)
    }
  }

  /// Refreshes the saved Person, and the list when it has loaded, like Web `router.refresh()`.
  private func reload(after personID: UUID) async {
    await loadPerson(id: personID)
    await reloadList()
  }

  /// Reloads the list once it has loaded or started loading. The new load replaces any still
  /// running, so the list reflects the change.
  private func reloadList() async {
    guard hasLoaded || isLoading else { return }
    await load()
  }

  private func loadPage(offset: Int) async throws -> [PersonRecord] {
    try await client.rpc(
      "people_workspace", params: ["p_limit": Self.pageSize, "p_offset": offset]
    ).execute().value
  }

  private func loadLinkOptions() async throws -> [PersonLinkedEntry] {
    try await client.from("entries")
      .select("id,title,body,item_kind,item_subtype")
      .eq("owner_id", value: ownerID.uuidString)
      .is("deleted_at", value: nil)
      .order("updated_at", ascending: false)
      .limit(200)
      .execute()
      .value
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw PeopleControllerError.ownerChanged
    }
  }
}

private enum PeopleControllerError: Error {
  case ownerChanged
}

private struct PersonMutation: Decodable {
  let personID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case personID = "person_id"
    case revision
  }
}

private struct PersonTrashParameters: Encodable {
  let personID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case personID = "p_person_id"
    case expectedRevision = "p_expected_revision"
  }
}
