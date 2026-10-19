import Foundation
import Observation
@preconcurrency import Supabase

/// Web `getTimelineWorkspace`: the Chapters and First Times `timeline_workspace` returns, split
/// into the Timeline's two bands.
@MainActor
@Observable
final class TimelineController {
  private(set) var chapters: [TimelineItem] = []
  /// First Times that are not also Chapters; a First Time Chapter is one bar.
  private(set) var firstTimes: [TimelineItem] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?

  private let client: SupabaseClient
  private let ownerID: UUID
  /// Only the newest load applies its result, so a slower earlier response cannot replace it.
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var items: [TimelineItem] { chapters + firstTimes }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    defer {
      if loadGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }

    do {
      try await validateSessionOwner()
      let rows: [TimelineItem] = try await client.rpc("timeline_workspace").execute().value
      try await validateSessionOwner()
      guard loadGeneration == generation else { return }
      (chapters, firstTimes) = TimelineItems.split(rows)
      loadErrorMessage = nil
    } catch {
      guard loadGeneration == generation, !(error is CancellationError) else { return }
      loadErrorMessage = "MemoTrail could not load your Timeline. Pull to refresh or try again."
    }
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else {
      throw TimelineControllerError.ownerChanged
    }
  }
}

private enum TimelineControllerError: Error {
  case ownerChanged
}
