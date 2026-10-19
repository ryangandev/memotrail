import Foundation
@preconcurrency import Supabase
import SwiftUI

enum WorkspaceRoute: String, CaseIterable, Identifiable, Hashable {
  case firstTimes, tags, trash, settings
  var id: String { rawValue }
  var title: String {
    switch self {
    case .firstTimes: "First Times"
    case .tags: "Tags"
    case .trash: "Trash"
    case .settings: "Settings"
    }
  }
  /// Web's navigation icon for the destination.
  var icon: MTIcon {
    switch self {
    case .firstTimes: .star
    case .tags: .tag
    case .trash: .trash
    case .settings: .settings
    }
  }

  /// Web `mobileMoreGroups`.
  static let groups: [(title: String, routes: [Self])] = [
    ("Focused views", [.firstTimes]),
    ("Organize", [.tags]),
    ("Trash and settings", [.trash, .settings]),
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
      .itemDestination(client: client, ownerID: user.id)
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
        .mtTextRole(.menuHeading)
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
        .font(.mtIcon(MTSize.Icon.s17))
        .foregroundStyle(MTColor.inkMuted)
        .frame(width: MTLayout.More.icon)
        .accessibilityHidden(true)
      Text(title)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.ink)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(MTSpacing.s3)
    .frame(maxWidth: .infinity, minHeight: MTSize.Control.large, alignment: .leading)
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
    case .firstTimes: FirstTimesView(client: client, ownerID: user.id)
    case .tags: TagsView(client: client, ownerID: user.id)
    case .trash: TrashView(client: client, ownerID: user.id)
    case .settings:
      NativeSettingsView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut)
    }
  }
}
