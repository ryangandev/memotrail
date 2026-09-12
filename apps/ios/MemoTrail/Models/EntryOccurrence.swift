import Foundation

struct EntryOccurrence: Equatable, Sendable {
  var precision: TimelineDatePrecision
  var start: Date?
  var end: Date?
  var label: String?
  var timezone: String

  func validate() throws {
    guard timezone.count <= 100, TimeZone(identifier: timezone) != nil else {
      throw OccurrenceError.invalidTimezone
    }
    guard (label?.count ?? 0) <= 200 else { throw OccurrenceError.invalidDescription }
    if [.exact, .day, .month, .year, .range].contains(precision), start == nil {
      throw OccurrenceError.missingDate
    }
    if precision == .unknown, start != nil || end != nil { throw OccurrenceError.invalidDate }
    if [.age, .approximate].contains(precision),
      label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      throw OccurrenceError.invalidDescription
    }
    for date in [start, end].compactMap({ $0 }) where !date.timeIntervalSince1970.isFinite {
      throw OccurrenceError.invalidDate
    }
    if let end {
      guard let start, end >= start, [.range, .approximate, .age].contains(precision) else {
        throw OccurrenceError.invalidRange
      }
    }
  }

  var displayLabel: String {
    if let label, !label.isEmpty { return label }
    guard precision != .unknown, let start else { return "Date unknown" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timezone) ?? .gmt
    formatter.dateFormat =
      precision == .year
      ? "yyyy"
      : precision == .month
        ? "MMM yyyy" : precision == .exact ? "MMM d, yyyy, h:mm a" : "MMM d, yyyy"
    let first = formatter.string(from: start)
    if let end { return "\(first) to \(formatter.string(from: end))" }
    return precision == .range ? "\(first) onward" : first
  }
}

struct OccurrenceDraft: Equatable, Sendable {
  var precision: TimelineDatePrecision
  var start: String
  var end: String
  var label: String
  var timezone: String

  init(_ value: EntryOccurrence) {
    precision = value.precision
    timezone = value.timezone
    label = value.label ?? ""
    let format =
      precision == .exact
      ? "yyyy-MM-dd'T'HH:mm:ss"
      : precision == .year ? "yyyy" : precision == .month ? "yyyy-MM" : "yyyy-MM-dd"
    let formatter = Self.formatter(timezone: timezone, format: format)
    start = value.start.map { formatter.string(from: $0) } ?? ""
    end = value.end.map { formatter.string(from: $0) } ?? ""
  }

  mutating func useDateSuggestion(_ text: String) {
    precision = .approximate
    label = text
    start = ""
    end = ""
  }

  func resolve(original: EntryOccurrence? = nil) throws -> EntryOccurrence {
    guard TimeZone(identifier: timezone) != nil else { throw OccurrenceError.invalidTimezone }
    let previous = original.map(OccurrenceDraft.init)
    func convert(_ text: String, isEnd: Bool) throws -> Date? {
      guard !text.isEmpty else { return nil }
      if let previous, previous.precision == precision, previous.timezone == timezone,
        (isEnd ? previous.end : previous.start) == text
      {
        return isEnd ? original?.end : original?.start
      }
      let local =
        precision == .exact
        ? text
        : "\(text)\(precision == .year ? "-01-01" : precision == .month ? "-01" : "")T12:00:00"
      guard let result = Self.wallTimeToDate(local, timezone: timezone) else {
        throw OccurrenceError.invalidDate
      }
      return result
    }
    let value = EntryOccurrence(
      precision: precision,
      start: precision == .unknown ? nil : try convert(start, isEnd: false),
      end: [.range, .approximate, .age].contains(precision) ? try convert(end, isEnd: true) : nil,
      label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? nil : label.trimmingCharacters(in: .whitespacesAndNewlines),
      timezone: timezone
    )
    try value.validate()
    return value
  }

  static func wallTimeToDate(_ text: String, timezone: String) -> Date? {
    guard let zone = TimeZone(identifier: timezone),
      text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$"#, options: .regularExpression)
        != nil
    else { return nil }
    let target = text.count == 16 ? "\(text):00" : text
    let utc = formatter(timezone: "UTC", format: "yyyy-MM-dd'T'HH:mm:ss")
    guard let naive = utc.date(from: target), utc.string(from: naive) == target else { return nil }
    let local = formatter(timezone: timezone, format: "yyyy-MM-dd'T'HH:mm:ss")
    let candidates = [-24, -12, 0, 12, 24].compactMap { hours -> Date? in
      let sample = naive.addingTimeInterval(Double(hours) * 3600)
      let candidate = naive.addingTimeInterval(-Double(zone.secondsFromGMT(for: sample)))
      return local.string(from: candidate) == target ? candidate : nil
    }
    return candidates.min()
  }

  private static func formatter(timezone: String, format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timezone) ?? .gmt
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter
  }
}

enum OccurrenceError: LocalizedError {
  case invalidTimezone, invalidDate, missingDate, invalidDescription, invalidRange
  var errorDescription: String? {
    switch self {
    case .invalidTimezone: "Choose a valid IANA time zone, for example America/Los_Angeles."
    case .invalidDate:
      "Choose a valid calendar date and time. This time may not exist during a daylight-saving change."
    case .missingDate: "Add the known date, or choose Unknown."
    case .invalidDescription: "Describe the age or approximate period in 200 characters or fewer."
    case .invalidRange:
      "The end date must follow the start and use Range, Approximate, or Age precision."
    }
  }
}
