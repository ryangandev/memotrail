import Foundation

enum AppConfiguration {
  static let supabaseURL = value(forInfoDictionaryKey: "MEMOTRAIL_SUPABASE_URL")
  static let supabasePublishableKey = value(
    forInfoDictionaryKey: "MEMOTRAIL_SUPABASE_PUBLISHABLE_KEY"
  )
  static let googleIOSClientID = value(
    forInfoDictionaryKey: "MEMOTRAIL_GOOGLE_IOS_CLIENT_ID"
  )

  private static func value(forInfoDictionaryKey key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
