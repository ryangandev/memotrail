#if DEBUG
  import Foundation

  /// Debug-only: lets a local review session start with a capture this iPhone cannot read, the
  /// way a queue written by a newer MemoTrail looks, so the unreadable list can be reviewed. It
  /// applies only to `--review-local-session` launches that ask for it, and only to an empty
  /// queue, so nothing already stored is ever written over.
  @MainActor
  enum CaptureReviewSeed {
    static let environmentKey = "MEMOTRAIL_REVIEW_UNREADABLE_CAPTURE"
    private static var hasApplied = false

    static func applyOnce(ownerID: UUID, queueStore: CaptureQueueStore) {
      guard !hasApplied else { return }
      hasApplied = true
      guard NativeReviewMode.current == .localSession,
        let text = ProcessInfo.processInfo.environment[environmentKey], !text.isEmpty
      else { return }

      let defaults = UserDefaults.standard
      let key = CaptureQueueStore.storageKey(ownerID: ownerID)
      guard defaults.object(forKey: key) == nil,
        queueStore.load(ownerID: ownerID).isEmpty,
        queueStore.unreadableCaptures(ownerID: ownerID).isEmpty
      else { return }

      // A version this release does not read keeps every item it holds out of the sync.
      let queue: [String: Any] = [
        "version": CaptureQueueStore.currentVersion + 1,
        "entries": [["title": "Saved by a newer MemoTrail", "body": text]],
      ]
      guard let data = try? JSONSerialization.data(withJSONObject: queue) else { return }
      defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
  }
#endif
