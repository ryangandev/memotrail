import Supabase
import SwiftUI

struct RootTabView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  var body: some View {
    TabView {
      InboxView(
        client: client,
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut
      )
      .tabItem {
        Label("Inbox", systemImage: "tray")
      }

      SearchView(client: client, ownerID: user.id)
        .tabItem {
          Label("Search", systemImage: "magnifyingglass")
        }

      TimelineView(client: client, ownerID: user.id)
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
