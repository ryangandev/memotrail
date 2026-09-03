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

      LibraryView(client: client, ownerID: user.id)
        .tabItem {
          Label("Library", systemImage: "books.vertical")
        }
    }
  }
}
