import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import Security
import Supabase
import UIKit

struct AuthenticatedUser: Equatable, Sendable {
  let id: UUID
  let email: String
  let name: String

  var initial: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .first
      .map { String($0).uppercased() } ?? "M"
  }
}

@MainActor
@Observable
final class AuthenticationController {
  private static let googleSignInCanceledErrorCode = -5

  enum State: Equatable {
    case checking
    case setupRequired
    case signedOut
    case signedIn(AuthenticatedUser)
  }

  private(set) var state: State
  private(set) var isBusy = false
  private(set) var errorMessage: String?

  var authenticatedClient: SupabaseClient? {
    guard case .signedIn = state else { return nil }
    return client
  }

  private let client: SupabaseClient?
  private let configuration: AppConfiguration.Authentication?
  private var didRestoreSession = false

  init(configuration: AppConfiguration.Authentication? = AppConfiguration.authentication) {
    self.configuration = configuration

    if let configuration {
      client = SupabaseClient(
        supabaseURL: configuration.supabaseURL,
        supabaseKey: configuration.supabasePublishableKey
      )
      state = .checking
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(
        clientID: configuration.googleIOSClientID
      )
    } else {
      client = nil
      state = .setupRequired
    }
  }

  func restoreSession() async {
    guard !didRestoreSession else { return }
    didRestoreSession = true

    guard let client else {
      state = .setupRequired
      return
    }

    do {
      let session = try await client.auth.session
      state = .signedIn(Self.user(from: session))
    } catch {
      state = .signedOut
    }
  }

  func signInWithGoogle() async {
    guard let client, configuration != nil else {
      state = .setupRequired
      return
    }

    guard let presentingViewController = UIApplication.shared.activeViewController else {
      errorMessage = "MemoTrail could not open Google Sign-In. Please try again."
      return
    }

    isBusy = true
    errorMessage = nil
    defer { isBusy = false }

    let rawNonce = Self.randomNonce()
    let hashedNonce = Self.sha256(rawNonce)

    do {
      let googleCredentials = try await googleSignIn(
        presenting: presentingViewController,
        nonce: hashedNonce
      )

      let session = try await client.auth.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .google,
          idToken: googleCredentials.idToken,
          accessToken: googleCredentials.accessToken,
          nonce: rawNonce
        )
      )

      state = .signedIn(Self.user(from: session))
    } catch {
      GIDSignIn.sharedInstance.signOut()
      errorMessage = Self.isCancellation(error) ? nil : Self.message(for: error)
      state = .signedOut
    }
  }

  func signOut() async {
    guard let client else {
      state = .setupRequired
      return
    }

    isBusy = true
    errorMessage = nil

    do {
      try await client.auth.signOut(scope: .local)
      GIDSignIn.sharedInstance.signOut()
      state = .signedOut
    } catch {
      errorMessage = "MemoTrail could not finish signing out. Please try again."
    }

    isBusy = false
  }

  private func googleSignIn(
    presenting viewController: UIViewController,
    nonce: String
  ) async throws -> GoogleCredentials {
    try await withCheckedThrowingContinuation { continuation in
      GIDSignIn.sharedInstance.signIn(
        withPresenting: viewController,
        hint: nil,
        additionalScopes: nil,
        nonce: nonce
      ) { result, error in
        if let result, let idToken = result.user.idToken?.tokenString {
          continuation.resume(
            returning: GoogleCredentials(
              accessToken: result.user.accessToken.tokenString,
              idToken: idToken
            )
          )
        } else {
          continuation.resume(
            throwing: error ?? AuthenticationError.missingGoogleIDToken
          )
        }
      }
    }
  }

  private static func user(from session: Session) -> AuthenticatedUser {
    let email = session.user.email ?? "Signed-in account"
    let metadataName =
      session.user.userMetadata["full_name"]?.stringValue
      ?? session.user.userMetadata["name"]?.stringValue
    let fallbackName = email.split(separator: "@").first.map(String.init) ?? "MemoTrail"

    return AuthenticatedUser(
      id: session.user.id,
      email: email,
      name: metadataName?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty ?? fallbackName
    )
  }

  private static func randomNonce(length: Int = 32) -> String {
    let characters = Array(
      "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
    )
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
      var randomBytes = [UInt8](repeating: 0, count: 16)
      let status = SecRandomCopyBytes(
        kSecRandomDefault,
        randomBytes.count,
        &randomBytes
      )

      guard status == errSecSuccess else {
        return UUID().uuidString
      }

      for randomByte in randomBytes where remainingLength > 0 {
        if Int(randomByte) < characters.count {
          result.append(characters[Int(randomByte)])
          remainingLength -= 1
        }
      }
    }

    return result
  }

  private static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func message(for error: Error) -> String {
    let description = String(describing: error)

    if description.localizedCaseInsensitiveContains("audience") {
      return "Add the iOS client ID to the allowed Google client IDs in Supabase, then try again."
    }

    if description.localizedCaseInsensitiveContains("nonce") {
      return "Google Sign-In could not be verified securely. Please try again."
    }

    return "Google Sign-In did not finish. No MemoTrail session was created."
  }

  private static func isCancellation(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == kGIDSignInErrorDomain
      && error.code == googleSignInCanceledErrorCode
  }
}

private enum AuthenticationError: Error {
  case missingGoogleIDToken
}

private struct GoogleCredentials: Sendable {
  let accessToken: String
  let idToken: String
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

extension UIApplication {
  @MainActor
  fileprivate var activeViewController: UIViewController? {
    let activeScene =
      connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let rootViewController = activeScene?.windows
      .first { $0.isKeyWindow }?
      .rootViewController

    return rootViewController?.topmostViewController
  }
}

extension UIViewController {
  fileprivate var topmostViewController: UIViewController {
    if let presentedViewController {
      return presentedViewController.topmostViewController
    }

    if let navigationController = self as? UINavigationController,
      let visibleViewController = navigationController.visibleViewController
    {
      return visibleViewController.topmostViewController
    }

    if let tabBarController = self as? UITabBarController,
      let selectedViewController = tabBarController.selectedViewController
    {
      return selectedViewController.topmostViewController
    }

    return self
  }
}
