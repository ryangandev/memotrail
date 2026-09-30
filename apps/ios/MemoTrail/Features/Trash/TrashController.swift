import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
@Observable
final class TrashController {
  private(set) var items: [TrashItem] = []
  private(set) var totalCount = 0
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var pendingItemID: String?
  private(set) var loadErrorMessage: String?
  private(set) var emptySnapshot: [EmptyTrashTarget]?
  private(set) var isEmptying = false
  private(set) var emptyProgress = 0
  private(set) var emptyTotal = 0
  var isBusy: Bool { pendingItemID != nil || emptySnapshot != nil }
  var isPreparingEmptyTrash: Bool { pendingItemID == Self.preparingEmptyTrash }

  private static let preparingEmptyTrash = "prepare-empty-trash"

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var canLoadMore: Bool {
    !isLoading && !isBusy && items.count < totalCount && items.count <= 10_000
  }

  func load() async {
    await fetch(appending: false)
  }

  func loadMore() async {
    guard canLoadMore else { return }
    await fetch(appending: true)
  }

  /// Web `restoreTrashItem`, at the revision and removal time shown.
  func restore(_ item: TrashItem) async -> Notice? {
    guard !isBusy else { return nil }

    pendingItemID = item.id
    defer { pendingItemID = nil }

    do {
      try await validateSessionOwner()
      let rows: [RestoredTrashItem] =
        try await client
        .rpc("restore_trash_item", params: TrashItemMutationParameters(item: item))
        .execute()
        .value

      guard rows.first?.itemKind == item.kind, rows.first?.itemID == item.itemID else {
        return .changedItem
      }
      await reloadAfterMutation()
      return Notice(message: "Item restored.", tone: .success)
    } catch let error as PostgrestError where error.code == "23505" {
      return Notice(
        message:
          "An active Collection already has this name. Rename it in organization settings, then restore this one.",
        tone: .error)
    } catch {
      return Notice(message: "MemoTrail could not restore this item. Try again.", tone: .error)
    }
  }

  /// Web `deleteTrashItemForever`: the private photos first, then the item.
  func deleteForever(_ item: TrashItem) async -> Notice {
    guard !isBusy else {
      return Notice(message: "Wait for the current Trash change to finish.", tone: .error)
    }

    pendingItemID = item.id
    defer { pendingItemID = nil }

    do {
      try await performDeletion(TrashItemMutationParameters(item: item))
      await reloadAfterMutation()
      return Notice(message: "Item permanently deleted.", tone: .success)
    } catch TrashControllerError.changedItem {
      return .changedItem
    } catch TrashControllerError.invalidMedia {
      return Notice(message: "MemoTrail could not verify this item's private photos.", tone: .error)
    } catch TrashControllerError.mediaRemoval {
      return Notice(
        message: "MemoTrail could not remove the private photos, so nothing else was deleted.",
        tone: .error)
    } catch let error as PostgrestError where error.message == "media_cleanup_required" {
      return Notice(
        message: "A photo preview finished while this item was being removed. "
          + "Refresh and try Delete forever again to remove the remaining files.",
        tone: .error
      )
    } catch {
      return Notice(
        message: "MemoTrail could not permanently delete this item. Try again.", tone: .error)
    }
  }

  /// Web `prepareEmptyTrash`: the complete list Empty Trash may delete, or why there is none.
  func prepareEmptyTrash() async -> Notice? {
    guard !isBusy, !isLoading else { return nil }
    pendingItemID = Self.preparingEmptyTrash
    defer { pendingItemID = nil }
    do {
      try await validateSessionOwner()
      let targets: [EmptyTrashTarget] = try await client.rpc("prepare_empty_trash").execute().value
      try await validateSessionOwner()
      try Task.checkCancellation()
      guard EmptyTrashTarget.isValid(targets) else { throw URLError(.badServerResponse) }
      if targets.isEmpty {
        await reloadAfterMutation()
        return Notice(message: "Nothing in Trash. No items were deleted.", tone: .success)
      }
      emptySnapshot = targets
      return nil
    } catch let error as PostgrestError where error.message == "trash_snapshot_too_large" {
      return Notice(
        message:
          "Trash contains more than 10,000 items. Remove some individually before reviewing Empty Trash.",
        tone: .error)
    } catch {
      return Notice(
        message:
          "Could not prepare the complete Trash list. Nothing was deleted. Refresh and try again.",
        tone: .error)
    }
  }

  func cancelEmptyTrash() { if !isEmptying { emptySnapshot = nil } }

  /// Deletes the prepared list one confirmed item at a time, stopping at the first item that
  /// changed. The list stays shown with its progress until the run ends.
  func emptyTrash() async -> Notice? {
    guard pendingItemID == nil, let targets = emptySnapshot, !isEmptying else { return nil }
    pendingItemID = "empty-trash"
    isEmptying = true
    emptyProgress = 0
    emptyTotal = targets.count
    defer {
      pendingItemID = nil
      isEmptying = false
      emptySnapshot = nil
    }
    let outcome = await EmptyTrashOutcome.run(
      targets: targets,
      remove: { target in
        try await self.performDeletion(TrashItemMutationParameters(target: target))
      }, progress: { self.emptyProgress = $0 })
    await reloadAfterMutation()
    return Notice(message: outcome.message, tone: outcome.complete ? .success : .error)
  }

  private func performDeletion(_ parameters: TrashItemMutationParameters) async throws {
    try Task.checkCancellation()
    try await validateSessionOwner()
    let pathRows: [TrashStoragePath] = try await client.rpc(
      "trash_item_storage_paths", params: parameters
    ).execute().value
    let paths = Array(Set(pathRows.map(\.objectPath))).sorted()
    guard paths.allSatisfy(isValidOwnedStoragePath) else { throw TrashControllerError.invalidMedia }
    try Task.checkCancellation()
    try await validateSessionOwner()
    if !paths.isEmpty {
      do {
        _ = try await client.storage.from("entry-media").remove(paths: paths)
      } catch {
        throw TrashControllerError.mediaRemoval
      }
    }
    let rows: [DeletedTrashItem] = try await client.rpc(
      "delete_trash_item_forever", params: parameters
    ).execute().value
    guard rows.first?.itemKind == parameters.itemKind, rows.first?.itemID == parameters.itemID
    else {
      throw TrashControllerError.changedItem
    }
  }

  private func fetch(appending: Bool) async {
    guard !isLoading else { return }

    let request: TrashPageRequest
    do {
      request = try TrashPageRequest.validate(offset: appending ? items.count : 0)
    } catch {
      loadErrorMessage = "MemoTrail could not load Trash. Try again."
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
      var rows: [TrashItem] =
        try await client
        .rpc("trash_workspace", params: request.parameters)
        .execute()
        .value
      let paths = Array(Set(rows.compactMap { $0.storagePaths.first }))
      let signedURLs = await signedURLMap(paths: paths)

      for index in rows.indices {
        if let path = rows[index].storagePaths.first {
          rows[index].signedURL = signedURLs[path]
        }
      }

      if appending {
        let knownIDs = Set(items.map(\.id))
        items.append(contentsOf: rows.filter { !knownIDs.contains($0.id) })
      } else {
        items = rows
      }
      totalCount = rows.first?.totalCount ?? (appending ? totalCount : 0)
    } catch {
      loadErrorMessage = "MemoTrail could not load Trash. Pull to refresh or try again."
      if !appending {
        items = []
        totalCount = 0
      }
    }
  }

  private func reloadAfterMutation() async {
    isLoading = false
    await load()
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw TrashControllerError.ownerChanged
    }
  }

  private func isValidOwnedStoragePath(_ path: String) -> Bool {
    let ownerPrefix = "\(ownerID.uuidString.lowercased())/"
    return path.hasPrefix(ownerPrefix)
      && path.count > ownerPrefix.count
      && !path.contains("..")
      && !path.hasPrefix("/")
      && path.count <= 1_024
  }

  private func signedURLMap(paths: [String]) async -> [String: URL] {
    await MediaDelivery.displayURLs(paths: paths, client: client, ownerID: ownerID, trash: true)
  }
}

extension TrashController {
  struct Notice: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
      case error
      case success
    }

    let message: String
    let tone: Tone

    static let changedItem = Notice(
      message: "This item changed on another device. Refresh before trying again.", tone: .error)
  }
}

private enum TrashControllerError: Error {
  case changedItem
  case invalidMedia
  case mediaRemoval
  case ownerChanged
}
