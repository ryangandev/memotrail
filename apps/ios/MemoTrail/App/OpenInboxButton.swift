import SwiftUI

/// Web's "Open Inbox" empty-state link, for pages that fill from organizing Inbox Entries.
struct OpenInboxButton: View {
  @Environment(AppNavigator.self) private var navigator

  var body: some View {
    Button("Open Inbox") { navigator.show(.inbox) }
      .mtButtonStyle(.secondary)
  }
}
