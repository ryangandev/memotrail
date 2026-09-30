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
  /// Web's navigation icon for the destination.
  var icon: MTIcon {
    switch self {
    case .map: .map
    case .people: .person
    case .homes: .home
    case .vehicles: .car
    case .firstTimes: .star
    case .goals: .target
    case .collections: .archive
    case .tags: .tag
    case .history: .clock
    case .trash: .trash
    case .settings: .settings
    }
  }

  /// Web's mobile More groups.
  static let groups: [(title: String, routes: [Self])] = [
    ("Explore", [.map]),
    ("Focused views", [.people, .homes, .vehicles, .firstTimes, .goals]),
    ("Organize", [.collections, .tags]),
    ("Archive and account", [.history, .trash, .settings]),
  ]
}

/// Web's mobile More menu as the More tab: each group's destinations as two columns of tiles.
struct MoreView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @Environment(AppNavigator.self) private var navigator

  var body: some View {
    @Bindable var navigator = navigator
    NavigationStack(path: $navigator.morePath) {
      MTPage(width: .standard, spacing: MTSpacing.s5) {
        ForEach(WorkspaceRoute.groups, id: \.title) { group in
          MoreGroup(title: group.title) {
            ForEach(group.routes) { route in
              NavigationLink(value: route) {
                MoreTile(title: route.title, icon: route.icon)
              }
              .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
              .accessibilityIdentifier("more-\(route.rawValue)")
            }
          }
        }
        #if DEBUG
          MoreGroup(title: "Development") {
            NavigationLink {
              DesignSystemGallery()
            } label: {
              MoreTile(title: "Design System", icon: .dashboard)
            }
            .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
            .accessibilityIdentifier("more-design-system")
          }
        #endif
      }
      .navigationTitle("More")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .navigationDestination(for: WorkspaceRoute.self) { route in
        WorkspaceDestinationView(
          route: route, client: client, user: user, isAuthenticationBusy: isAuthenticationBusy,
          signOut: signOut)
      }
    }
  }
}

/// Web `mobileMoreGroup`: an uppercase label above two columns of destinations.
private struct MoreGroup<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .tracking(1.1)
        .textCase(.uppercase)
        .foregroundStyle(MTColor.inkFaint)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: MTSpacing.s2), count: 2),
        spacing: MTSpacing.s2
      ) {
        content
      }
    }
  }
}

/// Web `mobileMoreLinks a`: the destination's icon and name.
private struct MoreTile: View {
  let title: String
  let icon: MTIcon

  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      Image(icon)
        .font(.system(size: 17))
        .foregroundStyle(MTColor.inkMuted)
        .frame(width: 22)
        .accessibilityHidden(true)
      Text(title)
        .font(MTFont.caption.weight(.medium))
        .foregroundStyle(MTColor.ink)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(MTSpacing.s3)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
    case .trash: TrashView(client: client, ownerID: user.id)
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
