import Foundation

/// How precisely an Entry's date is known, like Web `occurrencePrecisions`.
enum DatePrecision: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case exact
  case day
  case month
  case year
  case approximate
  case age
  case range
  case unknown

  /// A stored value; anything unrecognized reads as unknown, like Web `storedOccurrence`.
  init(stored value: String?) {
    self = value.flatMap(Self.init(rawValue:)) ?? .unknown
  }

  /// The Date type label shared with the Web occurrence editor.
  var displayName: String {
    switch self {
    case .exact: "Exact date & time"
    case .day: "Day"
    case .month: "Month"
    case .year: "Year"
    case .approximate: "Approximate"
    case .age: "Age"
    case .range: "Date range"
    case .unknown: "Unknown"
    }
  }
}

struct EntryOccurrence: Codable, Equatable, Hashable, Sendable {
  var precision: DatePrecision
  var start: Date?
  var end: Date?
  var label: String?
  var timezone: String

  var spanLabel: String {
    if let label, !label.isEmpty { return label }
    guard start != nil, precision != .unknown else { return "Date unknown" }
    var point = self
    point.end = nil
    if point.precision == .range { point.precision = .day }
    let first = point.displayLabel
    guard let end else { return "Since \(first)" }
    point.start = end
    return "\(first) - \(point.displayLabel)"
  }

  func durationLabel(now: Date = Date()) -> String {
    guard let start, precision != .unknown else { return "Duration unavailable" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .gmt
    let first = calendar.dateComponents([.year, .month, .day], from: start)
    let last = calendar.dateComponents([.year, .month, .day], from: end ?? now)
    guard let sy = first.year, let sm = first.month, let sd = first.day, let ey = last.year,
      let em = last.month, let ed = last.day
    else { return "Duration unavailable" }
    if precision == .year {
      let years = max(0, ey - sy)
      return years > 0
        ? "About \(countLabel(years, "year"))" : "Less than a year (approx.)"
    }
    var months = (ey - sy) * 12 + em - sm
    if precision != .month && ed < sd { months -= 1 }
    months = max(0, months)
    let approximate = [.month, .age, .approximate].contains(precision)
    guard months > 0 else {
      return approximate ? "Less than a month (approx.)" : "Less than a month"
    }
    let years = months / 12
    let remainder = months % 12
    let label = [
      years > 0 ? countLabel(years, "year") : "",
      remainder > 0 ? countLabel(remainder, "month") : "",
    ].filter { !$0.isEmpty }.joined(separator: " ")
    return approximate ? "About \(label)" : label
  }

  /// Throws `SaveEntryError.invalid` with Web's message when this cannot be stored.
  func validate(span: Bool = false) throws {
    if let message = OccurrenceRules.problem(self, span: span) {
      throw SaveEntryError.invalid(message)
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

struct OccurrenceDraft: Codable, Equatable, Sendable {
  /// Whether a bounded occurrence ends on a date or is still ongoing.
  enum EndMode: String, Codable, Sendable {
    case date, present
  }

  var precision: DatePrecision
  var start: String
  var end: String
  var endMode: EndMode
  var label: String
  var timezone: String

  /// Undated records store no time zone, so `undatedTimezone` stands in for editing, like the
  /// Web default of the Settings zone or this device's zone.
  init(_ value: EntryOccurrence, undatedTimezone: String? = nil) {
    precision = value.precision
    timezone = value.start == nil ? undatedTimezone ?? value.timezone : value.timezone
    label = value.label ?? ""
    // A saved start without an end is an ongoing period, as on the Web.
    endMode = value.start != nil && value.end == nil ? .present : .date
    let format =
      precision == .exact
      ? "yyyy-MM-dd'T'HH:mm:ss"
      : precision == .year ? "yyyy" : precision == .month ? "yyyy-MM" : "yyyy-MM-dd"
    let formatter = Self.formatter(timezone: timezone, format: format)
    start = value.start.map { formatter.string(from: $0) } ?? ""
    end = value.end.map { formatter.string(from: $0) } ?? ""
  }

  private enum CodingKeys: String, CodingKey {
    case precision, start, end, endMode, label, timezone
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    precision = try container.decode(DatePrecision.self, forKey: .precision)
    start = try container.decode(String.self, forKey: .start)
    end = try container.decode(String.self, forKey: .end)
    // Capture drafts saved before the Present control have no end mode.
    endMode = try container.decodeIfPresent(EndMode.self, forKey: .endMode) ?? .date
    label = try container.decode(String.self, forKey: .label)
    timezone = try container.decode(String.self, forKey: .timezone)
  }

  mutating func useDateSuggestion(_ text: String) {
    precision = .approximate
    label = text
    start = ""
    end = ""
    endMode = .date
  }

  /// Replaces the calendar interpretation when the Date type changes.
  mutating func changePrecision(to precision: DatePrecision) {
    guard precision != self.precision else { return }
    self.precision = precision
    start = ""
    end = ""
    endMode = .date
  }

  /// Web `resolveOccurrenceDraft`: the stored occurrence for this draft. An empty calendar date
  /// is stored as Unknown and keeps its description; unchanged fields keep their original
  /// instant. Throws `SaveEntryError.invalid` with Web's message.
  func resolve(original: EntryOccurrence? = nil, span: Bool = false) throws
    -> EntryOccurrence
  {
    guard OccurrenceRules.validTimezone(timezone) else {
      throw SaveEntryError.invalid(OccurrenceRules.timezoneMessage)
    }
    var draft = self
    // A calendar date left empty means the date is not known.
    if draft.start.isEmpty, [.exact, .day, .month, .year, .range].contains(draft.precision) {
      draft.precision = .unknown
      draft.end = span && draft.endMode != .present ? draft.end : ""
    }
    let previous = original.map { Self($0) }
    func convert(_ text: String, isEnd: Bool) -> Date? {
      guard !text.isEmpty else { return nil }
      if let previous, previous.precision == draft.precision,
        previous.timezone == draft.timezone, (isEnd ? previous.end : previous.start) == text
      {
        return isEnd ? original?.end : original?.start
      }
      let local =
        draft.precision == .exact
        ? text
        : "\(text)\(draft.precision == .year ? "-01-01" : draft.precision == .month ? "-01" : "")T12:00:00"
      return Self.wallTimeToDate(local, timezone: draft.timezone)
    }
    let start = draft.precision == .unknown ? nil : convert(draft.start, isEnd: false)
    let bounded =
      draft.precision != .unknown
      && (span || [.range, .approximate, .age].contains(draft.precision))
    let end = bounded && draft.endMode != .present ? convert(draft.end, isEnd: true) : nil
    if (!draft.start.isEmpty && start == nil && draft.precision != .unknown)
      || (!draft.end.isEmpty && end == nil && bounded)
    {
      throw SaveEntryError.invalid(
        "Choose a valid calendar date and time. This time may not exist during a daylight-saving change."
      )
    }
    if draft.start.isEmpty, !draft.end.isEmpty, draft.endMode != .present {
      throw SaveEntryError.invalid("Add a start date before the end date.")
    }
    let label = draft.label.trimmed
    let value = EntryOccurrence(
      precision: draft.precision, start: start, end: end, label: label.isEmpty ? nil : label,
      timezone: draft.timezone)
    if let message = OccurrenceRules.problem(value, span: span) {
      throw SaveEntryError.invalid(message)
    }
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

/// Web `validTimezone` and `validateOccurrence`, with Web's messages.
enum OccurrenceRules {
  static let timezoneMessage = "Choose a valid IANA time zone, for example America/Los_Angeles."

  static func validTimezone(_ value: String) -> Bool {
    value.count <= 100
      && value.range(of: #"^[A-Za-z][A-Za-z0-9_+./-]*$"#, options: .regularExpression) != nil
      && TimeZone(identifier: value) != nil
  }

  /// Why this occurrence cannot be stored, or nil.
  static func problem(_ value: EntryOccurrence, span: Bool = false) -> String? {
    guard validTimezone(value.timezone) else { return timezoneMessage }
    if let label = value.label, label.count > 200 {
      return "Keep the date description under 200 characters."
    }
    if [.exact, .day, .month, .year, .range].contains(value.precision), value.start == nil {
      return "Add the known date, or choose Unknown."
    }
    if value.precision == .unknown, value.start != nil || value.end != nil {
      return "Unknown dates cannot have calendar dates."
    }
    if [.age, .approximate].contains(value.precision), value.label?.trimmed.isEmpty != false {
      return "Describe the age or approximate period you remember."
    }
    if let end = value.end {
      guard let start = value.start, end >= start else {
        return "The end date must be on or after the start date."
      }
      if !span, ![.range, .approximate, .age].contains(value.precision) {
        return "Only ranges, ages, or approximate periods can have an end date."
      }
    }
    return nil
  }
}
