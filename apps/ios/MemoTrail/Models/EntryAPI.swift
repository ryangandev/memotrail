import Foundation
@preconcurrency import Supabase

/// The Entry reads and writes every feature shares, like Web `apps/web/src/app/items/actions.ts`
/// and `apps/web/src/app/inbox/actions.ts`. Each call first checks that the session still
/// belongs to `ownerID`, so a request never runs for a person who signed out or switched.
@MainActor
struct EntryAPI {
  let client: SupabaseClient
  let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  /// The current version to edit, or nil when it is in Trash or gone.
  func editable(_ id: UUID) async throws -> EditableEntry? {
    try await requireOwner()
    let entry: EditableEntry? = try await client.rpc(
      "editable_entry", params: EntryIDParameters(entryID: id)
    ).execute().value
    try await requireOwner()
    return entry
  }

  /// What the Item page shows, including an Entry in Trash; nil when it does not exist.
  func detail(_ id: UUID) async throws -> EntryDetail? {
    try await requireOwner()
    let entry: EntryDetail? = try await client.rpc(
      "entry_detail", params: EntryIDParameters(entryID: id)
    ).execute().value
    try await requireOwner()
    return entry
  }

  /// Saves an Entry with `save_entry`. Throws `SaveEntryError` with Web's message.
  func save(_ parameters: SaveEntryParameters) async throws -> SavedEntry {
    do {
      try await requireOwner()
    } catch {
      throw SaveEntryError.sessionExpired
    }
    let rows: [SavedEntry]
    do {
      rows = try await client.rpc("save_entry", params: parameters).execute().value
    } catch {
      throw SaveEntryError.classify(error)
    }
    guard let saved = rows.first, saved.entryID == parameters.entryID else {
      throw SaveEntryError.unconfirmed(isCreate: parameters.expectedRevision == nil)
    }
    return saved
  }

  /// Web `trashWikiItem`: moves this version of an Entry to Trash. Throws `EntryTrashError`.
  func moveToTrash(id: UUID, revision: Int) async throws {
    guard revision > 0 else { throw EntryTrashError.invalid }
    do {
      try await requireOwner()
    } catch {
      throw EntryTrashError.sessionExpired
    }
    let rows: [EntryIDRow]
    do {
      rows =
        try await client.from("entries")
        .update(EntryTrashUpdate(deletedAt: EntryTimestamp.string(from: Date())))
        .eq("id", value: id.uuidString.lowercased())
        .eq("revision", value: revision)
        .is("deleted_at", value: nil)
        .select("id")
        .execute().value
    } catch {
      throw EntryTrashError.failed
    }
    guard rows.contains(where: { $0.id == id }) else { throw EntryTrashError.changed }
  }

  /// The Entry's current photos, oldest first, from `POST /api/media/photos?entryId=`.
  func photos(entryID: UUID) async throws -> EntryPhotosResponse {
    try await MediaDelivery.apiRequest(
      path: "api/media/photos",
      query: URLQueryItem(name: "entryId", value: entryID.uuidString.lowercased()),
      client: client, ownerID: ownerID)
  }

  /// Uploads and registers one photo; true once `register_entry_attachment` confirms it.
  func attachPhoto(_ draft: PhotoDraft, entryID: UUID) async throws -> Bool {
    try await EntryPhotoUpload.attach(
      draft, entryID: entryID, ownerID: ownerID, client: client)
  }

  /// Moves one photo to Trash with `trash_entry_attachment`; the Entry's revision is unchanged.
  func trashPhoto(_ attachmentID: UUID) async throws -> Bool {
    try await requireOwner()
    let rows: [TrashedEntryAttachment] = try await client.rpc(
      "trash_entry_attachment", params: TrashEntryAttachmentParameters(attachmentID: attachmentID)
    ).execute().value
    try await requireOwner()
    return rows.contains { $0.attachmentID == attachmentID }
  }

  /// Web `loadTagOptions`: tag names, most used outside Trash first.
  func tagOptions() async throws -> [String] {
    try await requireOwner()
    let rows: [TagUsageRow] =
      try await client.from("tags")
      .select("name, entry_tags(count, entries!inner())")
      .eq("owner_id", value: ownerID.uuidString.lowercased())
      .is("entry_tags.entries.deleted_at", value: nil)
      .execute().value
    try await requireOwner()
    return TagUsageRow.optionsByUse(rows)
  }

  /// One page of the Entries dated inside a Chapter.
  func chapterEntries(id: UUID, offset: Int, limit: Int = ChapterContents.pageSize)
    async throws -> [ChapterEntry]
  {
    try await requireOwner()
    let rows: [ChapterEntry] = try await client.rpc(
      "chapter_entries",
      params: ChapterEntriesParameters(chapterID: id, limit: limit, offset: offset)
    ).execute().value
    try await requireOwner()
    return rows
  }

  /// The Chapters whose days overlap this Chapter's.
  func chapterOverlaps(id: UUID) async throws -> [ChapterOverlap] {
    try await requireOwner()
    let rows: [ChapterOverlap] = try await client.rpc(
      "chapter_overlaps", params: ChapterOverlapsParameters(chapterID: id)
    ).execute().value
    try await requireOwner()
    return rows
  }

  private func requireOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

/// Why an Entry was not moved to Trash, in Web's words.
enum EntryTrashError: LocalizedError, Equatable {
  case invalid
  case sessionExpired
  case failed
  case changed

  var errorDescription: String? {
    switch self {
    case .invalid: "This item cannot be moved to Trash."
    case .sessionExpired: "Sign in again to move this item to Trash."
    case .failed: "MemoTrail could not move this item to Trash."
    case .changed:
      "This item changed on another device or is already in Trash. Refresh and try again."
    }
  }
}

struct EntryIDParameters: Encodable, Equatable, Sendable {
  let entryID: UUID

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
  }
}

private struct EntryIDRow: Decodable, Sendable {
  let id: UUID
}

private struct EntryTrashUpdate: Encodable, Sendable {
  let deletedAt: String

  enum CodingKeys: String, CodingKey {
    case deletedAt = "deleted_at"
  }
}
