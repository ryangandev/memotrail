import GoogleSignIn
import SwiftUI

@main
struct MemoTrailApp: App {
  @State private var authentication = AuthenticationController(
    configuration: Self.authenticationConfiguration)
  @AppStorage("native-appearance") private var appearance = NativeAppearance.system
  #if DEBUG
    @State private var reviewAppearance: NativeAppearance?
  #endif

  private var effectiveColorScheme: ColorScheme? {
    #if DEBUG
      return (reviewAppearance ?? appearance).colorScheme
    #else
      return appearance.colorScheme
    #endif
  }

  init() {
    MTToastCenter.shared.trackKeyboard()
  }

  // Let the mark finish even when the session resolves immediately.
  @State private var splashFloorElapsed = false
  // A slow session restore eventually yields to the existing loading UI.
  @State private var splashCeilingElapsed = false

  private static var authenticationConfiguration: AppConfiguration.Authentication? {
    #if DEBUG
      if NativeReviewMode.current != nil { return nil }
    #endif
    return AppConfiguration.authentication
  }

  private var isShowingSplash: Bool {
    #if DEBUG
      if NativeReviewMode.current != nil { return false }
    #endif
    return !splashFloorElapsed || (authentication.state == .checking && !splashCeilingElapsed)
  }

  var body: some Scene {
    WindowGroup {
      ZStack {
        Group {
          #if DEBUG
            if let mode = NativeReviewMode.current {
              NativeReviewView(mode: mode)
            } else {
              authenticatedContent
            }
          #else
            authenticatedContent
          #endif
        }
        .accessibilityHidden(isShowingSplash)

        if isShowingSplash {
          SplashView()
            .transition(.opacity)
        }
      }
      .tint(MTColor.accent)
      .preferredColorScheme(effectiveColorScheme)
      #if DEBUG
        .onPreferenceChange(NativeReviewAppearancePreference.self) { reviewAppearance = $0 }
      #endif
      .animation(MTEasing.enter.animation(duration: MTMotion.splashFade), value: isShowingSplash)
      .task {
        #if DEBUG
          guard NativeReviewMode.current == nil else { return }
        #endif
        await authentication.restoreSession()
      }
      .task {
        try? await Task.sleep(for: .milliseconds(1_100))
        splashFloorElapsed = true
        try? await Task.sleep(for: .milliseconds(1_900))
        splashCeilingElapsed = true
      }
      .onOpenURL { url in
        GIDSignIn.sharedInstance.handle(url)
      }
    }
  }

  @ViewBuilder private var authenticatedContent: some View {
    switch authentication.state {
    case .checking, .setupRequired, .signedOut:
      AuthenticationView(
        state: authentication.state,
        isBusy: authentication.isBusy,
        errorMessage: authentication.errorMessage,
        signIn: authentication.signInWithGoogle
      )
    case .signedIn(let user):
      if let client = authentication.authenticatedClient {
        RootTabView(
          client: client,
          user: user,
          isAuthenticationBusy: authentication.isBusy,
          signOut: authentication.signOut
        )
      } else {
        AuthenticationView(
          state: .setupRequired,
          isBusy: false,
          errorMessage: "MemoTrail could not open the authenticated workspace.",
          signIn: authentication.signInWithGoogle
        )
      }
    }
  }
}
