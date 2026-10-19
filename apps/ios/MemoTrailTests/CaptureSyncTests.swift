import XCTest

@testable import MemoTrail

/// Capture retry, sync ordering, and the composer's date, without the network.
@MainActor
final class CaptureSyncTests: XCTestCase {
  /// Records each scheduled retry instead of waiting for it.
  @MainActor private final class Clock {
    var delays: [Duration] = []
    var pending: [(@MainActor () -> Void)?] = []
    var cancelled = 0

    func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void)
      -> CaptureRetryTimer
    {
      delays.append(delay)
      let index = pending.count
      pending.append(action)
      return CaptureRetryTimer { [weak self] in
        guard let self, self.pending[index] != nil else { return }
        self.pending[index] = nil
        self.cancelled += 1
      }
    }

    /// Fires the latest retry still scheduled.
    func fire() {
      guard let index = pending.lastIndex(where: { $0 != nil }), let action = pending[index]
      else { return XCTFail("No retry is scheduled.") }
      pending[index] = nil
      action()
    }
  }

  private lazy var clock = Clock()
  private var isOnline = true
  private var isSyncing = false
  private var retries = 0

  private func makeRetry() -> CaptureSyncRetry {
    CaptureSyncRetry(
      isOnline: { [unowned self] in isOnline },
      isSyncing: { [unowned self] in isSyncing },
      retry: { [unowned self] in retries += 1 },
      schedule: clock.schedule)
  }

  private let waiting = CaptureSyncRun(stoppedWaiting: true)

  func testRetryBacksOffAndRestartsAfterProgress() {
    let retry = makeRetry()

    for _ in 0..<4 {
      retry.afterRun(waiting)
      clock.fire()
    }
    XCTAssertEqual(clock.delays, [1, 2, 4, 8].map { .seconds($0) })
    XCTAssertEqual(retries, 4)

    // A capture that synced is progress, so the next wait starts from the shortest delay.
    retry.afterRun(CaptureSyncRun(stoppedWaiting: true, synced: 1))
    XCTAssertEqual(clock.delays.last, .seconds(1))
    clock.fire()
    retry.afterRun(waiting)
    XCTAssertEqual(clock.delays.last, .seconds(2))

    // A refusal is progress too: the queue moved past that capture.
    clock.fire()
    retry.afterRun(CaptureSyncRun(stoppedWaiting: true, rejected: 1))
    XCTAssertEqual(clock.delays.last, .seconds(1))
  }

  func testRetryWaitsAtMostOneMinute() {
    let retry = makeRetry()

    for _ in 0..<10 {
      retry.afterRun(waiting)
      clock.fire()
    }

    XCTAssertEqual(
      clock.delays, [1, 2, 4, 8, 15, 30, 60, 60, 60, 60].map { .seconds($0) })
  }

  func testRunThatSettlesEverythingStopsRetryingAndResetsTheBackoff() {
    let retry = makeRetry()
    retry.afterRun(waiting)
    clock.fire()
    retry.afterRun(waiting)
    XCTAssertTrue(retry.isScheduled)

    retry.afterRun(CaptureSyncRun(synced: 2))

    XCTAssertFalse(retry.isScheduled)
    XCTAssertEqual(clock.cancelled, 1)
    retry.afterRun(waiting)
    XCTAssertEqual(clock.delays.last, .seconds(1))
  }

  func testRetryDoesNotRunOfflineSinceReconnectingStartsItsOwnSync() {
    let retry = makeRetry()
    isOnline = false

    retry.afterRun(waiting)

    XCTAssertFalse(retry.isScheduled)
    XCTAssertTrue(clock.delays.isEmpty)

    // Going offline after a retry was scheduled keeps it from sending anything.
    isOnline = true
    retry.afterRun(waiting)
    isOnline = false
    clock.fire()
    XCTAssertEqual(retries, 0)
  }

  func testRetryLeavesARunInProgressToScheduleItsOwn() {
    let retry = makeRetry()
    retry.afterRun(waiting)
    isSyncing = true

    clock.fire()

    XCTAssertEqual(retries, 0)
    XCTAssertFalse(retry.isScheduled)
  }

  func testStopCancelsTheRetryAndStartsTheBackoffOver() {
    let retry = makeRetry()
    retry.afterRun(waiting)
    clock.fire()
    retry.afterRun(waiting)

    retry.stop()

    XCTAssertFalse(retry.isScheduled)
    XCTAssertEqual(clock.cancelled, 1)
    retry.afterRun(waiting)
    XCTAssertEqual(clock.delays.last, .seconds(1))
  }

  /// What closures that outlive one call record, in order.
  @MainActor private final class Log {
    var events: [String] = []
  }

  func testRetryTimerRunsAfterItsDelayUnlessCancelled() async throws {
    let log = Log()
    _ = CaptureRetryTimer.after(.milliseconds(10)) { log.events.append("kept") }
    let cancelled = CaptureRetryTimer.after(.milliseconds(10)) { log.events.append("cancelled") }
    cancelled.cancel()

    try await Task.sleep(for: .milliseconds(200))

    XCTAssertEqual(log.events, ["kept"])
  }

  func testSyncLockLetsOneRunAtATimeSendAPersonsCaptures() async throws {
    let ownerID = UUID()
    let log = Log()
    let (gate, open) = AsyncStream.makeStream(of: Void.self)

    let first = Task {
      await CaptureSyncLock.run(ownerID: ownerID) {
        log.events.append("first start")
        for await _ in gate { break }
        log.events.append("first end")
      }
    }
    try await waitUntil { log.events == ["first start"] }
    let second = Task {
      await CaptureSyncLock.run(ownerID: ownerID) { log.events.append("second") }
    }
    for _ in 0..<5 { await Task.yield() }
    // Another person's captures never wait for this one's.
    await CaptureSyncLock.run(ownerID: UUID()) { log.events.append("other person") }
    XCTAssertEqual(log.events, ["first start", "other person"])

    open.yield()
    await first.value
    await second.value

    XCTAssertEqual(log.events, ["first start", "other person", "first end", "second"])
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertTrue(condition())
  }

  // MARK: Capture date

  func testDateStartsOnTodayInTheCaptureZone() {
    let now = Date(timeIntervalSince1970: 1_760_000_000)  // 2025-10-09 08:53:20 UTC

    let draft = CaptureDate.today(now: now, timezone: "Pacific/Auckland")

    XCTAssertEqual(draft.precision, .day)
    XCTAssertEqual(CaptureDate.value(draft), "2025-10-09")
    XCTAssertEqual(
      CaptureDate.value(CaptureDate.today(now: now, timezone: "America/Los_Angeles")),
      "2025-10-09")
    XCTAssertEqual(
      CaptureDate.value(
        CaptureDate.today(
          now: Date(timeIntervalSince1970: 1_760_050_000), timezone: "Pacific/Auckland")),
      "2025-10-10")
  }

  func testDayAndTimeResolveToDayAndExactOccurrences() throws {
    let now = Date()

    let day = try CaptureDate.resolve(
      CaptureDate.draft(value: "2024-02-29", timezone: "America/New_York"), now: now,
      timezone: "UTC")
    XCTAssertEqual(day.precision, .day)
    XCTAssertEqual(day.timezone, "America/New_York")
    XCTAssertEqual(
      day.start, OccurrenceDraft.wallTimeToDate("2024-02-29T12:00:00", timezone: "America/New_York"))

    let exact = try CaptureDate.resolve(
      CaptureDate.draft(value: "2024-02-29T07:45", timezone: "America/New_York"), now: now,
      timezone: "UTC")
    XCTAssertEqual(exact.precision, .exact)
    XCTAssertEqual(
      exact.start, OccurrenceDraft.wallTimeToDate("2024-02-29T07:45", timezone: "America/New_York"))
  }

  func testNoDateOrAClearedDateSavesTheCaptureTime() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    for draft in [nil, CaptureDate.draft(value: "", timezone: "Europe/Paris")] {
      let occurrence = try CaptureDate.resolve(draft, now: now, timezone: "Asia/Tokyo")
      XCTAssertEqual(occurrence.precision, .exact)
      XCTAssertEqual(occurrence.start, now)
      XCTAssertEqual(occurrence.timezone, "Asia/Tokyo")
    }
  }

  func testInvalidDayIsRefusedInsteadOfSavedAtAnotherTime() {
    XCTAssertThrowsError(
      try CaptureDate.resolve(
        CaptureDate.draft(value: "2023-02-29", timezone: "UTC"), now: Date(), timezone: "UTC"))
  }

  func testDraftsFromEarlierComposersShowTheirDay() {
    let exact = OccurrenceDraft(
      EntryOccurrence(
        precision: .exact, start: OccurrenceDraft.wallTimeToDate("2024-05-01T09:30", timezone: "UTC"),
        end: nil, label: nil, timezone: "UTC"))
    XCTAssertEqual(CaptureDate.value(exact), "2024-05-01T09:30")

    var range = CaptureDate.draft(value: "2024-05-01", timezone: "UTC")
    range.precision = .range
    XCTAssertEqual(CaptureDate.value(range), "2024-05-01")

    var month = CaptureDate.draft(value: "2024-05", timezone: "UTC")
    month.precision = .month
    XCTAssertEqual(CaptureDate.value(month), "")
  }

  func testDayAndTimePartsRoundTrip() {
    XCTAssertEqual(CaptureDate.day(of: "2024-05-01T09:30"), "2024-05-01")
    XCTAssertEqual(CaptureDate.time(of: "2024-05-01T09:30"), "09:30")
    XCTAssertEqual(CaptureDate.time(of: "2024-05-01T09:30:00"), "09:30")
    XCTAssertEqual(CaptureDate.time(of: "2024-05-01"), "")
    XCTAssertEqual(CaptureDate.value(day: "2024-05-01", time: "09:30"), "2024-05-01T09:30")
    XCTAssertEqual(CaptureDate.value(day: "2024-05-01", time: ""), "2024-05-01")
    XCTAssertEqual(CaptureDate.value(day: "", time: "09:30"), "")
  }
}
