import GoogleSignIn
import SwiftUI

@main
struct MemoTrailApp: App {
  @State private var authentication = AuthenticationController()

  var body: some Scene {
    WindowGroup {
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
      .tint(MTColor.accent)
      .task {
        await authentication.restoreSession()
      }
      .onOpenURL { url in
        GIDSignIn.sharedInstance.handle(url)
      }
    }
  }
}
