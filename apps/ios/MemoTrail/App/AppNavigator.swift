import Observation
import SwiftUI

/// Cross-tab navigation for links that Web expresses as routes, such as the Dashboard's
/// `/inbox?entry=` and `/timeline?entry=`. Destination screens consume a pending request
/// once they have loaded the matching record.
@MainActor
@Observable
final class AppNavigator {
  var selectedTab = RootTabDestination.home
  var morePath: [WorkspaceRoute] = []
  /// An Inbox capture to open for review, like Web `/inbox?entry=`.
  var inboxReviewRequest: UUID?
  /// A Timeline record to open, like Web `/timeline?entry=`.
  var timelineEntryRequest: UUID?
  /// Library should focus its search field, like the Web header's search action.
  var librarySearchRequested = false
  /// Increases when Settings saves the preferred name, so the Dashboard greeting refreshes.
  var profileRevision = 0

  func show(_ tab: RootTabDestination) {
    selectedTab = tab
  }

  func searchLibrary() {
    librarySearchRequested = true
    selectedTab = .library
  }

  func show(_ route: WorkspaceRoute) {
    morePath = [route]
    selectedTab = .more
  }

  func reviewInboxEntry(_ id: UUID) {
    inboxReviewRequest = id
    selectedTab = .inbox
  }

  func openTimelineEntry(_ id: UUID) {
    timelineEntryRequest = id
    selectedTab = .timeline
  }
}

extension View {
  /// Reloads once a pushed page, such as version history or a linked Item, returns, so a change
  /// made there shows at once.
  func reloadOnReturn(from isPresented: Bool, _ reload: @escaping @MainActor () async -> Void)
    -> some View
  {
    onChange(of: isPresented) { _, isPresented in
      if !isPresented { Task { await reload() } }
    }
  }
}
