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
          RootTabView(
            user: user,
            isAuthenticationBusy: authentication.isBusy,
            signOut: authentication.signOut
          )
        }
      }
        .tint(MTColor.accent)
        .task {
          await authentication.restoreSession()
        }
        .onOpenURL { URL in
          GIDSignIn.sharedInstance.handle(URL)
        }
    }
  }
}
