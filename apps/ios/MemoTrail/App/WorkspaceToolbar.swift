@preconcurrency import Supabase
import SwiftUI

/// The Web workspace header on each primary tab: the MemoTrail brand, New entry, search, and
/// the account avatar that opens Settings.
private struct WorkspaceToolbar: ViewModifier {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void
  @State private var isShowingSettings = false
  @Environment(AppNavigator.self) private var navigator

  func body(content: Content) -> some View {
    content
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // Web's phone header shows only the mark, which links to the Dashboard.
          Button {
            navigator.show(.home)
          } label: {
            MemoTrailMark().frame(width: MTLayout.Toolbar.mark, height: MTLayout.Toolbar.mark)
          }
          .accessibilityLabel("MemoTrail dashboard")
          .accessibilityIdentifier("workspace-brand")
        }
        if #available(iOS 26, *) {
          ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarLeading) {
          // Web's phone header keeps New entry beside the mark, in the accent color.
          Button("New entry", systemImage: MTIcon.plus.systemName) {
            navigator.startCapture()
          }
          .foregroundStyle(MTColor.accent)
          .accessibilityIdentifier("workspace-new-entry")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Search your trail", systemImage: MTIcon.search.systemName) {
            navigator.searchLibrary()
          }
          .accessibilityIdentifier("workspace-search")
        }
        if #available(iOS 26, *) {
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
          ToolbarItem(placement: .topBarTrailing) { avatar }
            .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .topBarTrailing) { avatar }
        }
      }
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $isShowingSettings) {
        // Switching tabs while the sheet closes would cancel the dismissal.
        if let route = navigator.routeAfterSettings {
          navigator.routeAfterSettings = nil
          navigator.show(route)
        }
      } content: {
        NavigationStack {
          NativeSettingsView(
            client: client, user: user, isAuthenticationBusy: isAuthenticationBusy,
            signOut: signOut
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingSettings = false }
            }
          }
        }
        .environment(\.isSettingsSheet, true)
      }
      .onChange(of: navigator.routeAfterSettings) { _, route in
        if route != nil, isShowingSettings { isShowingSettings = false }
      }
  }

  /// Web `avatarButton`: the account initial on the accent color.
  private var avatar: some View {
    Button {
      isShowingSettings = true
    } label: {
      Text(user.initial)
        .font(MTFont.pageEyebrow)
        .foregroundStyle(MTColor.accentInk)
        .frame(width: MTLayout.Avatar.toolbar, height: MTLayout.Avatar.toolbar)
        .background(MTColor.accent, in: Circle())
        .frame(width: MTSize.hitTarget, height: MTSize.hitTarget)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open Settings for \(user.name)")
    .accessibilityIdentifier("workspace-settings")
  }
}

extension View {
  /// Adds the shared workspace header to a primary tab's root page.
  func workspaceToolbar(
    client: SupabaseClient, user: AuthenticatedUser, isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void
  ) -> some View {
    modifier(
      WorkspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut))
  }
}

extension EnvironmentValues {
  /// Settings is in the sheet the account avatar opens, rather than a page in the More tab.
  @Entry var isSettingsSheet = false
}
