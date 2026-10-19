import Foundation

// What every surface calls an Entry, ported from Web `apps/web/src/lib/data/occurrence.ts`:
// its title, or its best-known date when it has none, always in en-US and in the time zone the
// date was recorded in, so iOS and Web print the same name.

extension EntryOccurrence {
  /// Web `storedOccurrence`: a row's stored date fields as an occurrence. An unknown precision
  /// reads as unknown, and a row without a usable recorded zone uses `fallbackTimezone`, then
  /// UTC.
  init(
    storedPrecision precision: String?, start: Date?, end: Date?, label: String?,
    timezone: String?, fallbackTimezone: String = "UTC"
  ) {
    self.init(
      precision: DatePrecision(stored: precision), start: start, end: end, label: label,
      timezone: Self.validTimezone(timezone)
        ?? Self.validTimezone(fallbackTimezone) ?? "UTC")
  }

  /// Web `occurrenceTitle`: the name of an Entry without a title. A description wins; a known
  /// day, month, year, or range is written out; anything else is "Undated entry".
  var title: String {
    if let label = label?.trimmed.nonEmpty { return label }
    guard let start, start.timeIntervalSince1970.isFinite,
      [.exact, .day, .month, .year, .range].contains(precision)
    else { return Self.undatedTitle }
    let zone = Self.validTimezone(timezone) ?? "UTC"
    func format(_ date: Date, _ template: String) -> String {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US")
      formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
      formatter.dateFormat = template
      return formatter.string(from: date)
    }
    switch precision {
    case .year: return format(start, "yyyy")
    case .month: return format(start, "MMMM yyyy")
    case .range: break
    default: return format(start, "EEEE, MMMM d, yyyy")
    }
    guard let end, end.timeIntervalSince1970.isFinite else {
      return "\(format(start, "MMMM d, yyyy")) onward"
    }
    let sameYear = format(start, "yyyy") == format(end, "yyyy")
    let first = format(start, sameYear ? "MMMM d" : "MMMM d, yyyy")
    return "\(first) - \(format(end, "MMMM d, yyyy"))"
  }

  static let undatedTitle = "Undated entry"

  /// An IANA zone name Foundation knows, like Web `validTimezone`.
  static func validTimezone(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.count <= 100,
      value.range(of: #"^[A-Za-z][A-Za-z0-9_+./-]*$"#, options: .regularExpression) != nil,
      TimeZone(identifier: value) != nil
    else { return nil }
    return value
  }
}

/// Web `entryDisplayTitle`: an Entry's trimmed title, or its date when it has none.
func entryDisplayTitle(_ title: String?, _ occurrence: EntryOccurrence) -> String {
  title?.trimmed.nonEmpty ?? occurrence.title
}
