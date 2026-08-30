import SwiftUI

@main
struct MemoTrailApp: App {
  var body: some Scene {
    WindowGroup {
      RootTabView()
        .tint(MTColor.accent)
    }
  }
}
