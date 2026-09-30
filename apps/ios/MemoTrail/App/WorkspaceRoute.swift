import Foundation
@preconcurrency import Supabase
import SwiftUI

enum WorkspaceRoute: String, CaseIterable, Identifiable, Hashable {
  case map, people, homes, vehicles, firstTimes, goals, collections, tags, history, trash, settings
  var id: String { rawValue }
  var title: String {
    switch self {
    case .map: "Map"
    case .people: "People"
    case .homes: "Homes"
    case .vehicles: "Vehicles"
    case .firstTimes: "First Times"
    case .goals: "Goals"
    case .collections: "Collections"
    case .tags: "Tags"
    case .history: "Version history"
    case .trash: "Trash"
    case .settings: "Settings"
    }
  }
  var systemImage: String {
    switch self {
    case .map: "map"
    case .people: "person.2"
    case .homes: "house"
    case .vehicles: "car"
    case .firstTimes: "star"
    case .goals: "target"
    case .collections: "square.stack"
    case .tags: "tag"
    case .history: "clock.arrow.circlepath"
    case .trash: "trash"
    case .settings: "gearshape"
    }
  }

  static let groups: [(title: String, routes: [Self])] = [
    ("Explore", [.map]),
    ("Focused views", [.people, .homes, .vehicles, .firstTimes, .goals]),
    ("Organize", [.collections, .tags]),
    ("Archive and account", [.history, .trash, .settings]),
  ]
}

struct MoreView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @Environment(AppNavigator.self) private var navigator

  var body: some View {
    @Bindable var navigator = navigator
    NavigationStack(path: $navigator.morePath) {
      List {
        ForEach(WorkspaceRoute.groups, id: \.title) { group in
          Section(group.title) {
            ForEach(group.routes) { route in
              NavigationLink(value: route) {
                Label(route.title, systemImage: route.systemImage)
              }
              .accessibilityIdentifier("more-\(route.rawValue)")
            }
          }
        }
        #if DEBUG
          Section("Development") {
            NavigationLink {
              DesignSystemGallery()
            } label: {
              Label("Design System", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("more-design-system")
          }
        #endif
      }
      .scrollContentBackground(.hidden).background(MTColor.canvas)
      .navigationTitle("More")
      .navigationDestination(for: WorkspaceRoute.self) { route in
        WorkspaceDestinationView(
          route: route, client: client, user: user, isAuthenticationBusy: isAuthenticationBusy,
          signOut: signOut)
      }
    }
  }
}

struct WorkspaceDestinationView: View {
  let route: WorkspaceRoute
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  var body: some View {
    switch route {
    case .map:
      #if DEBUG
        if NativeReviewMode.current == .navigation {
          LocationMapView(preview: NativeReviewView.mapSnapshot)
        } else {
          LocationMapView(client: client, ownerID: user.id)
        }
      #else
        LocationMapView(client: client, ownerID: user.id)
      #endif
    case .people: PeopleView(client: client, ownerID: user.id)
    case .homes: HomesView(client: client, ownerID: user.id)
    case .vehicles: VehiclesView(client: client, ownerID: user.id)
    case .firstTimes: FirstTimesView(client: client, ownerID: user.id)
    case .goals: GoalsView(client: client, ownerID: user.id)
    case .collections: CollectionsView(client: client, ownerID: user.id)
    case .tags: TagsView(client: client, ownerID: user.id)
    case .history: EntryHistoryIndexView(client: client, ownerID: user.id)
    case .trash: TrashView(client: client, ownerID: user.id, embedded: true)
    case .settings:
      NativeSettingsView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut)
    }
  }
}

/// Canonical detail routing, shared by Library, the Map, the Dashboard, and Connected Items.
/// Like Web `wikiEntryHref`, only a Person from People opens a Person page; a person Entry and
/// any Item without a focused page open as an Item.
struct WikiItemDestinationView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  let kind: WikiItemKind
  let subtype: String
  var personID: UUID? = nil

  var body: some View {
    switch (kind, subtype, personID) {
    case (.entity, "person", let personID?):
      PersonDetailView(client: client, ownerID: ownerID, personID: personID)
    case (.entity, "home", _):
      HomeDetailView(client: client, ownerID: ownerID, entryID: entryID)
    case (.entity, "vehicle", _):
      VehicleDetailView(client: client, ownerID: ownerID, entryID: entryID)
    case (.goal, _, _):
      GoalDetailView(client: client, ownerID: ownerID, entryID: entryID)
    case (.entry, "first_time", _):
      FirstTimeDetailView(client: client, ownerID: ownerID, entryID: entryID)
    default:
      WikiItemDetailView(client: client, ownerID: ownerID, entryID: entryID)
    }
  }
}
