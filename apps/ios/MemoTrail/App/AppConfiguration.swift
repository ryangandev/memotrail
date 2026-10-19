import Foundation

enum AppConfiguration {
  static var apiURL: URL? {
    #if DEBUG
      if NativeReviewMode.current == .localSession { return NativeReviewSession.current?.apiURL }
    #endif
    guard let raw = value(forInfoDictionaryKey: "MEMOTRAIL_API_URL"),
      let url = URL(string: raw), let host = url.host,
      url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
    else { return nil }
    return url
  }
  struct Authentication: Sendable {
    let googleIOSClientID: String
    let googleIOSURLScheme: String
    let supabasePublishableKey: String
    let supabaseURL: URL
  }

  static let supabaseURL = value(forInfoDictionaryKey: "MEMOTRAIL_SUPABASE_URL")
  static let supabasePublishableKey = value(
    forInfoDictionaryKey: "MEMOTRAIL_SUPABASE_PUBLISHABLE_KEY"
  )
  static let googleIOSClientID = value(
    forInfoDictionaryKey: "MEMOTRAIL_GOOGLE_IOS_CLIENT_ID"
  )
  static let googleIOSURLScheme = value(
    forInfoDictionaryKey: "MEMOTRAIL_GOOGLE_IOS_URL_SCHEME"
  )

  static var authentication: Authentication? {
    guard
      let supabaseURLString = supabaseURL,
      let supabaseURL = URL(string: supabaseURLString),
      let supabasePublishableKey,
      let googleIOSClientID,
      let googleIOSURLScheme,
      hasRegisteredURLScheme(googleIOSURLScheme)
    else {
      return nil
    }

    return Authentication(
      googleIOSClientID: googleIOSClientID,
      googleIOSURLScheme: googleIOSURLScheme,
      supabasePublishableKey: supabasePublishableKey,
      supabaseURL: supabaseURL
    )
  }

  private static func value(forInfoDictionaryKey key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func hasRegisteredURLScheme(_ expectedScheme: String) -> Bool {
    guard
      let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        as? [[String: Any]]
    else {
      return false
    }

    return urlTypes.contains { urlType in
      guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else {
        return false
      }

      return schemes.contains(expectedScheme)
    }
  }
}
