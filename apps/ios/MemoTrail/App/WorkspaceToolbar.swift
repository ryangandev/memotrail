@preconcurrency import Supabase
import SwiftUI

/// The Web workspace header on each primary tab: the MemoTrail brand, search, and the
/// account avatar that opens Settings.
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
        ToolbarItem(placement: .topBarLeading) { MemoTrailBrand() }
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
      }
  }

  /// Web `avatarButton`: the account initial on the accent color.
  private var avatar: some View {
    Button {
      isShowingSettings = true
    } label: {
      Text(user.initial)
        .font(MTFont.caption.weight(.semibold))
        .foregroundStyle(MTColor.accentInk)
        .frame(width: 32, height: 32)
        .background(MTColor.accent, in: Circle())
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open Settings for \(user.name)")
    .accessibilityIdentifier("workspace-settings")
  }
}

/// The MemoTrail mark and wordmark, like the Web header brand.
private struct MemoTrailBrand: View {
  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      MemoTrailMark()
        .frame(width: 28, height: 28)
      Text("MemoTrail")
        .font(.system(size: 18, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("MemoTrail")
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
