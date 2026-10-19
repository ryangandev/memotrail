import Foundation

/// What one sync run did, like Web `InboxSyncRun`.
struct CaptureSyncRun: Equatable, Sendable {
  /// The run stopped at a capture that must wait for a later attempt.
  var stoppedWaiting = false
  /// Captures that reached MemoTrail with all their photos.
  var synced = 0
  /// Captures MemoTrail refused for good in this run.
  var rejected = 0
}

/// A scheduled retry that can be cancelled before it runs.
struct CaptureRetryTimer {
  let cancel: @MainActor () -> Void

  /// Runs `action` on the main actor once `delay` has passed, unless cancelled first.
  @MainActor
  static func after(_ delay: Duration, _ action: @escaping @MainActor () -> Void)
    -> CaptureRetryTimer
  {
    let task = Task { @MainActor in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      action()
    }
    return CaptureRetryTimer { task.cancel() }
  }
}

/// Keeps retrying captures that still wait while this iPhone reports a connection, like Web
/// `createCaptureSyncRetry`. A path can be reported as satisfied before requests get through,
/// and MemoTrail can be briefly unreachable while the connection stays up, so one failed attempt
/// must not leave captures waiting until the next launch. Progress restarts the backoff; losing
/// the connection stops it, since regaining it starts a run of its own.
@MainActor
final class CaptureSyncRetry {
  /// Web `captureRetryDelays`: an unreachable MemoTrail is asked once a minute at most.
  static let delays: [Duration] = [1, 2, 4, 8, 15, 30, 60].map { .seconds($0) }

  typealias Schedule = @MainActor (Duration, @escaping @MainActor () -> Void) -> CaptureRetryTimer

  private let delays: [Duration]
  private let isOnline: @MainActor () -> Bool
  /// A run in progress schedules its own retry when it finishes.
  private let isSyncing: @MainActor () -> Bool
  private let retry: @MainActor () -> Void
  private let schedule: Schedule
  private var timer: CaptureRetryTimer?
  private var step = 0

  init(
    delays: [Duration] = CaptureSyncRetry.delays,
    isOnline: @escaping @MainActor () -> Bool,
    isSyncing: @escaping @MainActor () -> Bool,
    retry: @escaping @MainActor () -> Void,
    schedule: @escaping Schedule = CaptureRetryTimer.after
  ) {
    precondition(!delays.isEmpty, "A retry needs at least one delay.")
    self.delays = delays
    self.isOnline = isOnline
    self.isSyncing = isSyncing
    self.retry = retry
    self.schedule = schedule
  }

  /// Whether a retry is waiting to run.
  var isScheduled: Bool { timer != nil }

  /// Schedules the next attempt when a finished run left a capture waiting.
  func afterRun(_ run: CaptureSyncRun) {
    cancel()
    guard run.stoppedWaiting, isOnline() else {
      step = 0
      return
    }
    if run.synced > 0 || run.rejected > 0 { step = 0 }
    let delay = delays[min(step, delays.count - 1)]
    step += 1
    timer = schedule(delay) { [weak self] in
      guard let self else { return }
      self.timer = nil
      if self.isOnline(), !self.isSyncing() { self.retry() }
    }
  }

  /// Cancels a scheduled attempt and starts the next backoff from the beginning.
  func stop() {
    cancel()
    step = 0
  }

  private func cancel() {
    timer?.cancel()
    timer = nil
  }
}

/// Lets one sync run at a time send a person's captures, like Web's lock across tabs. SwiftUI
/// can create more than one controller for the same person, and each must reread the queue
/// only after the other has finished with it, or both could send the same photo.
@MainActor
enum CaptureSyncLock {
  private static var holders: Set<UUID> = []
  private static var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

  static func run<T>(ownerID: UUID, _ body: @MainActor () async -> T) async -> T {
    await acquire(ownerID)
    defer { release(ownerID) }
    return await body()
  }

  private static func acquire(_ ownerID: UUID) async {
    if holders.insert(ownerID).inserted { return }
    await withCheckedContinuation { waiters[ownerID, default: []].append($0) }
  }

  private static func release(_ ownerID: UUID) {
    guard var queue = waiters[ownerID], !queue.isEmpty else {
      holders.remove(ownerID)
      return
    }
    // The lock passes straight to the next run, so no new run can slip in between.
    let next = queue.removeFirst()
    waiters[ownerID] = queue.isEmpty ? nil : queue
    next.resume()
  }
}
