import Foundation
@preconcurrency import Supabase

/// Web `app/organization/actions.ts`: loads, saves, merges, and removes Collections and tags.
/// Each change returns Web's message when it did not happen.
@MainActor
struct OrganizationActions {
  let client: SupabaseClient
  let ownerID: UUID

  /// One page of Collections or tags, like Web `getOrganizationWorkspace`.
  func load(_ kind: OrganizationKind, query: String = "", offset: Int = 0, limit: Int? = nil)
    async throws -> [OrganizationItem]
  {
    try await validateSessionOwner()
    return try await client.rpc(
      "organization_workspace",
      params: OrganizationReadRequest(
        kind: kind, query: query, offset: offset,
        limit: limit ?? OrganizationReadRequest.pageSize)
    ).execute().value
  }

  /// Web `saveOrganization`.
  func save(_ input: OrganizationSaveRequest) async -> String? {
    guard input.isValid else { return input.invalidMessage }
    return await run(
      unchanged:
        "This item changed on another device or moved to Trash. Refresh before editing again."
    ) {
      try await client.rpc("save_organization", params: input).execute().value
    } failed: { error in
      (error as? PostgrestError)?.code == "23505"
        ? "This name already exists. Choose a different name; nothing was merged or overwritten."
        : "Could not save. Your edits are still here to retry."
    }
  }

  /// Web `trashCollection`.
  func trashCollection(_ item: OrganizationItem) async -> String? {
    await run(
      unchanged: "This Collection changed on another device. Refresh before trying again."
    ) {
      try await client.rpc(
        "trash_collection",
        params: CollectionTrashRequest(id: item.id, expectedRevision: item.revision)
      ).execute().value
    } failed: { _ in
      "Could not move this Collection to Trash. Try again."
    }
  }

  /// Web `mergeTags`.
  func mergeTags(_ source: OrganizationItem, into target: OrganizationItem) async -> String? {
    let request = TagMergeRequest(
      sourceID: source.id, sourceRevision: source.revision, targetID: target.id,
      targetRevision: target.revision)
    guard request.isValid else { return "Choose a different destination tag." }
    return await run(
      unchanged: "One of these tags changed on another device. Refresh before merging."
    ) {
      try await client.rpc("merge_tags", params: request).execute().value
    } failed: { _ in
      "Could not merge these tags. Try again."
    }
  }

  /// Web `deleteUnusedTag`.
  func deleteUnusedTag(_ item: OrganizationItem) async -> String? {
    await run(
      unchanged:
        "This tag is still used by an Entry or changed elsewhere. Merge it or remove it from those Entries first."
    ) {
      try await client.rpc(
        "delete_unused_tag",
        params: CollectionTrashRequest(id: item.id, expectedRevision: item.revision)
      ).execute().value
    } failed: { _ in
      "Could not delete this tag. Try again."
    }
  }

  /// Web `getTagEntryPreviews`: the first five Entries using a tag.
  func tagEntryPreviews(_ name: String) async -> Result<[SearchEntry], OrganizationFailure> {
    guard
      let request = try? EntrySearchRequest.validate(
        query: "", classifications: [], collectionNames: [], tagNames: [name], dateFrom: nil,
        dateTo: nil, limit: 5)
    else { return .failure(OrganizationFailure(message: "Choose a valid tag.")) }
    do {
      try await validateSessionOwner()
      let rows: [SearchEntry] = try await client.rpc(
        "search_wiki_items", params: request.parameters
      ).execute().value
      return .success(rows)
    } catch OrganizationActionsError.ownerChanged {
      return .failure(
        OrganizationFailure(message: "Sign in again to browse Entries using this tag."))
    } catch {
      return .failure(
        OrganizationFailure(message: "Could not load Entries using this tag. Try again."))
    }
  }

  /// Runs one change: nil when it saved, Web's conflict message when the server changed
  /// nothing, or the failure message. A lost connection keeps the edits for a retry.
  private func run(
    unchanged: String, _ change: () async throws -> UUID?,
    failed: (Error) -> String
  ) async -> String? {
    do {
      try await validateSessionOwner()
      return try await change() == nil ? unchanged : nil
    } catch OrganizationActionsError.ownerChanged {
      return "Sign in again to organize your archive."
    } catch is URLError {
      return "Could not connect. Your changes are still here to retry."
    } catch {
      return failed(error)
    }
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw OrganizationActionsError.ownerChanged
    }
  }
}

struct OrganizationFailure: Error, Equatable {
  let message: String
}

private enum OrganizationActionsError: Error {
  case ownerChanged
}
