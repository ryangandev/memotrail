import Foundation

/// Time zone choices and labels shared with the Web `timezones.ts` helpers.
enum TimeZoneOptions {
  static let common = [
    "UTC",
    "America/Los_Angeles",
    "America/Vancouver",
    "America/Denver",
    "America/Chicago",
    "America/New_York",
    "America/Toronto",
    "America/Sao_Paulo",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Africa/Johannesburg",
    "Asia/Dubai",
    "Asia/Kolkata",
    "Asia/Kathmandu",
    "Asia/Singapore",
    "Asia/Shanghai",
    "Asia/Hong_Kong",
    "Asia/Tokyo",
    "Asia/Seoul",
    "Australia/Sydney",
    "Pacific/Auckland",
  ]

  /// Every identifier the system supports, with the curated list first.
  static let all: [String] = {
    var seen = Set<String>()
    return (common + TimeZone.knownTimeZoneIdentifiers).filter { seen.insert($0).inserted }
  }()

  /// "Los Angeles - America", "Argentina / Buenos Aires - America", or "UTC".
  static func label(_ identifier: String) -> String {
    if identifier == "UTC" { return "UTC" }
    let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count > 1 else { return identifier.replacingOccurrences(of: "_", with: " ") }
    let location = parts.dropFirst().joined(separator: " / ").replacingOccurrences(
      of: "_", with: " ")
    return "\(location) - \(parts[0])"
  }

  /// The offset in effect at `date`, such as "UTC-07:00" or "UTC+05:45".
  static func offsetLabel(_ identifier: String, at date: Date) -> String {
    guard let zone = TimeZone(identifier: identifier) else { return "" }
    let seconds = zone.secondsFromGMT(for: date)
    let sign = seconds < 0 ? "-" : "+"
    let minutes = abs(seconds) / 60
    return String(format: "UTC%@%02d:%02d", sign, minutes / 60, minutes % 60)
  }

  /// "(UTC-07:00) Los Angeles - America", as shown in the Web time zone select.
  static func optionLabel(_ identifier: String, at date: Date) -> String {
    let offset = offsetLabel(identifier, at: date)
    return offset.isEmpty ? label(identifier) : "(\(offset)) \(label(identifier))"
  }

  /// The option label on a wall-time reference day ("2026-03-08" or "2026-03-08T09:30:00").
  static func optionLabel(_ identifier: String, reference: String, now: Date = Date()) -> String {
    optionLabel(identifier, at: referenceDate(reference, now: now))
  }

  /// Reads a wall-time reference at noon UTC on its day, matching the Web offset label.
  /// An empty or invalid reference uses `now`.
  static func referenceDate(_ text: String, now: Date = Date()) -> Date {
    guard text.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else {
      return now
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    formatter.isLenient = false
    return formatter.date(from: "\(text.prefix(10))T12:00:00") ?? now
  }
}
