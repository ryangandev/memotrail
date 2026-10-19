import Observation
import SwiftUI

/// Cross-tab navigation for links that Web expresses as routes, such as the Dashboard's
/// `/library?tag=` and `/first-times`. Destination screens consume a pending request once.
@MainActor
@Observable
final class AppNavigator {
  var selectedTab = RootTabDestination.home
  /// The More tab's stack: a route, then any Items opened from it.
  var morePath = NavigationPath()
  /// Library should focus its search field, like the Web header's search action.
  var librarySearchRequested = false
  /// Library should open with one filter, like Web `/library?tag=` and `?record=`.
  var libraryFilterRequest: LibraryFilterRequest?
  /// Increases when Settings saves the profile, so the greeting and Timeline refresh.
  var profileRevision = 0
  /// Increases after any Entry is saved, moved to Trash, restored, or synced, so other tabs
  /// reload what they show.
  var entriesRevision = 0
  /// Quick Capture covers the app, from the global button or a page's New entry action.
  var isShowingQuickCapture = false
  /// The captures still on this iPhone, like Web's Pending sync panel.
  var isShowingPendingCaptures = false
  /// A page the Settings sheet opens once it has closed, like Web's Settings links elsewhere.
  var routeAfterSettings: WorkspaceRoute?

  func show(_ tab: RootTabDestination) {
    selectedTab = tab
  }

  func show(_ route: WorkspaceRoute) {
    morePath = NavigationPath([route])
    selectedTab = .more
  }

  func searchLibrary() {
    librarySearchRequested = true
    selectedTab = .library
  }

  /// Web `/library?tag=`: Library showing only the Entries with this tag.
  func openLibrary(tag name: String) {
    libraryFilterRequest = .tag(name)
    selectedTab = .library
  }

  /// Web `/library?record=`: Library showing only Entries, Chapters, or First Times.
  func openLibrary(record: EntryRecordFilter) {
    libraryFilterRequest = .record(record)
    selectedTab = .library
  }

  /// Opens Quick Capture over the current page, like Web's New entry action.
  func startCapture() {
    isShowingQuickCapture = true
  }

  /// Shows the captures still on this iPhone, with Copy text and Discard for refused ones.
  func showPendingCaptures() {
    isShowingPendingCaptures = true
  }

  /// Tells every tab that an Entry changed.
  func entriesChanged() {
    entriesRevision += 1
  }
}

/// A Library filter another screen opens, like Web's `/library?tag=` and `?record=` links.
enum LibraryFilterRequest: Hashable {
  case tag(String)
  case record(EntryRecordFilter)
}

extension View {
  /// Reloads once a pushed page, such as a linked Item, returns, so a change made there shows
  /// at once.
  func reloadOnReturn(from isPresented: Bool, _ reload: @escaping @MainActor () async -> Void)
    -> some View
  {
    onChange(of: isPresented) { _, isPresented in
      if !isPresented { Task { await reload() } }
    }
  }
}
