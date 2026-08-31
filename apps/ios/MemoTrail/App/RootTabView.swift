import SwiftUI

struct RootTabView: View {
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  var body: some View {
    TabView {
      InboxView(
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut
      )
        .tabItem {
          Label("Inbox", systemImage: "tray")
        }

      PlaceholderView(
        title: "Timeline",
        subtitle: "Life stages and moments will live here.",
        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
      )
      .tabItem {
        Label("Timeline", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
      }

      PlaceholderView(
        title: "First Times",
        subtitle: "A record of things you did for the first time.",
        systemImage: "star"
      )
      .tabItem {
        Label("Firsts", systemImage: "star")
      }

      PlaceholderView(
        title: "Collections",
        subtitle: "Entries will gather here through categories and tags.",
        systemImage: "archivebox"
      )
      .tabItem {
        Label("Collections", systemImage: "archivebox")
      }
    }
  }
}

private struct PlaceholderView: View {
  let title: String
  let subtitle: String
  let systemImage: String

  var body: some View {
    NavigationStack {
      ContentUnavailableView(title, systemImage: systemImage, description: Text(subtitle))
        .foregroundStyle(MTColor.inkMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MTColor.canvas)
        .navigationTitle(title)
    }
  }
}

#Preview {
  RootTabView(
    user: AuthenticatedUser(email: "ryan@example.com", name: "Ryan"),
    isAuthenticationBusy: false,
    signOut: {}
  )
}
