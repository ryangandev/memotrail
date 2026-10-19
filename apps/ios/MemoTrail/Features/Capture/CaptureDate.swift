import Foundation

/// The composer's date, like Web `inbox-capture-date.ts`: a calendar day with an optional time.
/// The Entry editor owns every other precision. It is kept in the shared draft as an ordinary
/// occurrence draft, so drafts saved by earlier composers still load.
enum CaptureDate {
  /// The Date field value for a draft: `yyyy-MM-dd`, or `yyyy-MM-ddTHH:mm` with a time. A draft
  /// an earlier composer saved at another precision shows its day when it has one, and is empty
  /// otherwise.
  static func value(_ draft: OccurrenceDraft) -> String {
    switch draft.precision {
    case .exact: return String(draft.start.prefix(16))
    case .day: return draft.start
    default:
      return draft.start.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
        ? String(draft.start.prefix(10)) : ""
    }
  }

  /// The draft for a Date field value: a Day, or an exact time once a time is set.
  static func draft(value: String, timezone: String) -> OccurrenceDraft {
    var draft = OccurrenceDraft(
      EntryOccurrence(precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone))
    draft.precision = value.contains("T") ? .exact : .day
    draft.start = value
    draft.end = ""
    draft.endMode = .date
    draft.label = ""
    draft.timezone = timezone
    return draft
  }

  /// Today in the capture's time zone, the day a newly opened Date starts on.
  static func today(now: Date, timezone: String) -> OccurrenceDraft {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timezone) ?? .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return draft(value: formatter.string(from: now), timezone: timezone)
  }

  /// The date a capture saves with: the chosen day or time, or the capture time itself when no
  /// day is chosen.
  static func resolve(_ draft: OccurrenceDraft?, now: Date, timezone: String) throws
    -> EntryOccurrence
  {
    guard let draft, !value(draft).isEmpty else {
      return EntryOccurrence(precision: .exact, start: now, end: nil, label: nil, timezone: timezone)
    }
    return try Self.draft(value: value(draft), timezone: draft.timezone).resolve()
  }

  /// The `yyyy-MM-dd` day a value names, or an empty string.
  static func day(of value: String) -> String {
    value.count >= 10 ? String(value.prefix(10)) : ""
  }

  /// The `HH:mm` time a value names, or an empty string when it has only a day.
  static func time(of value: String) -> String {
    guard let separator = value.firstIndex(of: "T") else { return "" }
    return String(value[value.index(after: separator)...].prefix(5))
  }

  /// Web `DatePickerField`'s value for a day and an optional time.
  static func value(day: String, time: String) -> String {
    day.isEmpty ? "" : time.isEmpty ? day : "\(day)T\(time)"
  }
}
