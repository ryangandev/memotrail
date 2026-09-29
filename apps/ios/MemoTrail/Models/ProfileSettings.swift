import Foundation

/// The signed-in person's private profile preferences, like Web `profiles` settings.
struct ProfileSettings: Decodable, Equatable, Sendable {
  /// The preferred name, or nil to use the sign-in name.
  var preferredName: String?
  /// A stored `yyyy-MM-dd` birth date, or nil.
  var birthDate: String?
  /// The default time zone for new exact times.
  var timezone: String

  enum CodingKeys: String, CodingKey {
    case preferredName = "display_name"
    case birthDate = "birth_date"
    case timezone
  }

  init(preferredName: String? = nil, birthDate: String? = nil, timezone: String = "UTC") {
    self.preferredName = preferredName
    self.birthDate = birthDate
    self.timezone = timezone
  }

  /// Like Web `storedBirthDate` and `storedProfileTimezone`, invalid stored values read as unset.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    preferredName = try values.decodeIfPresent(String.self, forKey: .preferredName)?.trimmed
      .nonEmpty
    birthDate = try values.decodeIfPresent(String.self, forKey: .birthDate).flatMap {
      ProfileSettings.isDateOnly($0) ? $0 : nil
    }
    let timezone = try values.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
    self.timezone = TimeZone(identifier: timezone) == nil ? "UTC" : timezone
  }

  /// Web `parsePreferredName`: one line, inner spaces collapsed, up to 80 characters; blank
  /// clears it.
  static func parsePreferredName(_ value: String) throws(ProfileSettingsError) -> String? {
    guard value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }) else {
      throw .multilineName
    }
    let name = value.trimmed.replacing(/\ {2,}/, with: " ")
    guard name.utf16.count <= 80 else { throw .longName }
    return name.nonEmpty
  }

  /// Web `parseBirthDate`: a complete date from 1800 through today; blank removes it.
  static func parseBirthDate(_ value: String, today: String = todayText())
    throws(ProfileSettingsError) -> String?
  {
    let date = value.trimmed
    guard !date.isEmpty else { return nil }
    guard isDateOnly(date) else { throw .incompleteBirthDate }
    guard date >= "1800-01-01", date <= today else { throw .birthDateOutOfRange }
    return date
  }

  /// Web `parseProfileTimezone`.
  static func parseTimezone(_ value: String) throws(ProfileSettingsError) -> String {
    let timezone = value.trimmed
    guard !timezone.isEmpty, TimeZone(identifier: timezone) != nil else {
      throw .invalidTimezone
    }
    return timezone
  }

  /// Today in UTC, like Web `new Date().toISOString().slice(0, 10)`.
  static func todayText(_ now: Date = .now) -> String {
    now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
  }

  private static func isDateOnly(_ value: String) -> Bool {
    guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return false }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value).map(formatter.string(from:)) == value
  }
}

enum ProfileSettingsError: LocalizedError, Equatable {
  case multilineName
  case longName
  case incompleteBirthDate
  case birthDateOutOfRange
  case invalidTimezone

  var errorDescription: String? {
    switch self {
    case .multilineName: "Use a single line for your name."
    case .longName: "Keep your name under 80 characters."
    case .incompleteBirthDate: "Choose a complete birth date."
    case .birthDateOutOfRange: "Birth date must be between 1800 and today."
    case .invalidTimezone: "Choose a valid time zone."
    }
  }
}
