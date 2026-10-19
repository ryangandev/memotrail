import Foundation
@preconcurrency import Supabase

/// Web `app/organization/actions.ts`: loads, saves, merges, and removes tags. Each change returns
/// Web's message when it did not happen.
@MainActor
struct OrganizationActions {
  let client: SupabaseClient
  let ownerID: UUID

  /// One page of tags, like Web `getOrganizationWorkspace`.
  func load(query: String = "", offset: Int = 0, limit: Int = TagsPageRequest.pageSize)
    async throws -> [TagItem]
  {
    try await validateSessionOwner()
    let rows: [TagItem] = try await client.rpc(
      "tags_workspace", params: TagsPageRequest(query: query, offset: offset, limit: limit)
    ).execute().value
    try await validateSessionOwner()
    return rows
  }

  /// Web `saveTag`: creates a tag when the request has no id, otherwise renames it.
  func save(_ input: TagSaveRequest) async -> String? {
    guard input.isValid else { return TagSaveRequest.invalidMessage }
    return await run(
      unchanged: "This tag changed on another device. Refresh before editing again."
    ) {
      try await client.rpc("save_tag", params: input).execute().value
    } failed: { error in
      (error as? PostgrestError)?.code == "23505"
        ? "This name already exists. Choose a different name; nothing was merged or overwritten."
        : "Could not save. Your edits are still here to retry."
    }
  }

  /// Web `mergeTags`.
  func mergeTags(_ source: TagItem, into target: TagItem) async -> String? {
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
  func deleteUnusedTag(_ item: TagItem) async -> String? {
    guard item.revision > 0 else { return "Choose a valid tag." }
    return await run(
      unchanged:
        "This tag is still used by an Entry or changed elsewhere. Merge it or remove it from those Entries first."
    ) {
      try await client.rpc(
        "delete_unused_tag", params: TagDeleteRequest(id: item.id, expectedRevision: item.revision)
      ).execute().value
    } failed: { _ in
      "Could not delete this tag. Try again."
    }
  }

  /// Web `getTagEntryPreviews`: the first five Entries using a tag.
  func tagEntryPreviews(_ name: String) async -> Result<[SearchEntry], OrganizationFailure> {
    guard !name.trimmed.isEmpty,
      let request = try? EntrySearchRequest.validate(query: "", tagNames: [name], limit: 5)
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
