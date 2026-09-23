import GoogleSignIn
import SwiftUI

@main
struct MemoTrailApp: App {
  @State private var authentication = AuthenticationController()

  // Let the mark finish even when the session resolves immediately.
  @State private var splashFloorElapsed = false
  // A slow session restore eventually yields to the existing loading UI.
  @State private var splashCeilingElapsed = false

  private var isShowingSplash: Bool {
    !splashFloorElapsed || (authentication.state == .checking && !splashCeilingElapsed)
  }

  var body: some Scene {
    WindowGroup {
      ZStack {
        Group {
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
        .accessibilityHidden(isShowingSplash)

        if isShowingSplash {
          SplashView()
            .transition(.opacity)
        }
      }
      .tint(MTColor.accent)
      .animation(.easeOut(duration: 0.3), value: isShowingSplash)
      .task {
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
}
