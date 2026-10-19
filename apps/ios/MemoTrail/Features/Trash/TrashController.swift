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
  /// Only the newest load applies its result, so a slower earlier response cannot replace it.
  /// A further page applies only to the list it extends.
  private var loadGeneration = UUID()

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
    } catch {
      return .restoreFailure(error)
    }
  }

  /// Web `deleteTrashItemForever`: the item first, which records its private photo files in the
  /// same transaction, then those files. Anything left is removed the next time Trash opens.
  func deleteForever(_ item: TrashItem) async -> Notice {
    guard !isBusy else {
      return Notice(message: "Wait for the current Trash change to finish.", tone: .error)
    }

    pendingItemID = item.id
    defer { pendingItemID = nil }

    do {
      try await performDeletion(TrashItemMutationParameters(item: item))
    } catch TrashControllerError.changedItem {
      return .changedItem
    } catch {
      return Notice(
        message: "MemoTrail could not permanently delete this item. Try again.", tone: .error)
    }
    let filesRemoved = await finishPendingMediaRemoval()
    await reloadAfterMutation()
    return Notice(
      message: filesRemoved
        ? "Item permanently deleted." : "Item permanently deleted. \(MediaPurge.pendingMessage)",
      tone: .success)
  }

  /// Web `finishMediaPurges`: removes the private photo files of everything already deleted
  /// forever, including a removal that another device or an interrupted request left unfinished.
  /// Any failure leaves them recorded for the next attempt. Returns whether nothing remains.
  @discardableResult
  func finishPendingMediaRemoval(maxRounds: Int = 10) async -> Bool {
    do {
      for _ in 0..<maxRounds {
        try await validateSessionOwner()
        let rows: [TrashStoragePath] = try await client.rpc(
          "pending_media_purge_paths", params: MediaPurge.Request(limit: MediaPurge.batchSize)
        ).execute().value
        let paths = Array(Set(rows.map(\.objectPath))).sorted()
        guard paths.allSatisfy(isValidOwnedStoragePath) else { return false }
        if !paths.isEmpty {
          _ = try await client.storage.from("entry-media").remove(paths: paths)
        }
        let remaining: Int = try await client.rpc("complete_media_purges").execute().value
        if remaining == 0 { return true }
        // Recorded files that cannot be listed would never finish here.
        if paths.isEmpty { return false }
      }
    } catch {
      return false
    }
    return false
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
    var outcome = await EmptyTrashOutcome.run(
      targets: targets,
      remove: { target in
        try await self.performDeletion(TrashItemMutationParameters(target: target))
      }, progress: { self.emptyProgress = $0 })
    // Records are deleted one at a time; their private photo files go once at the end.
    if outcome.deleted > 0 {
      outcome.filesRemoved = await finishPendingMediaRemoval(maxRounds: 100)
    }
    await reloadAfterMutation()
    return Notice(message: outcome.message, tone: outcome.complete ? .success : .error)
  }

  /// Deletes only the record. The server records its private photo files for removal.
  private func performDeletion(_ parameters: TrashItemMutationParameters) async throws {
    try Task.checkCancellation()
    try await validateSessionOwner()
    let rows: [DeletedTrashItem] = try await client.rpc(
      "delete_trash_item_forever", params: parameters
    ).execute().value
    guard rows.first?.itemKind == parameters.itemKind, rows.first?.itemID == parameters.itemID
    else {
      throw TrashControllerError.changedItem
    }
  }

  private func fetch(appending: Bool) async {
    guard !appending || !isLoading else { return }

    let request: TrashPageRequest
    do {
      request = try TrashPageRequest.validate(offset: appending ? items.count : 0)
    } catch {
      loadErrorMessage = "MemoTrail could not load Trash. Try again."
      return
    }

    let generation = appending ? loadGeneration : UUID()
    loadGeneration = generation
    isLoading = true
    loadErrorMessage = nil
    defer {
      if loadGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
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

      guard loadGeneration == generation else { return }
      if appending {
        let knownIDs = Set(items.map(\.id))
        items.append(contentsOf: rows.filter { !knownIDs.contains($0.id) })
      } else {
        items = rows
      }
      totalCount = rows.first?.totalCount ?? (appending ? totalCount : 0)
    } catch {
      guard loadGeneration == generation else { return }
      loadErrorMessage = "MemoTrail could not load Trash. Pull to refresh or try again."
      if !appending {
        items = []
        totalCount = 0
      }
    }
  }

  /// Replaces any load still running, so Trash reflects the change.
  private func reloadAfterMutation() async {
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

    /// Web `restoreTrashItem` error messages.
    static func restoreFailure(_ error: Error) -> Notice {
      if let error = error as? PostgrestError, error.message == "trash_media_unavailable" {
        return Notice(
          message:
            "This item's original photos are missing, so it cannot be restored. You can still delete it forever.",
          tone: .error)
      }
      return Notice(message: "MemoTrail could not restore this item. Try again.", tone: .error)
    }
  }
}

private enum TrashControllerError: Error {
  case changedItem
  case ownerChanged
}
