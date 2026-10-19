import Foundation

// Every item in MemoTrail is an Entry. A Chapter is an Entry whose subtype is `chapter`, and a
// First Time is an Entry marked `is_first_time`; both marks can sit on the same Entry. Every
// row's `item_kind` is `entry`, so decoders ignore it. Web `apps/web/src/lib/data/wiki-item.ts`.

/// An Entry's subtype: a plain Entry or a Chapter, a named stretch of time.
enum EntrySubtype: String, CaseIterable, Codable, Hashable, Sendable {
  case entry
  case chapter

  /// Any other stored subtype reads as a plain Entry, like Web `wikiItemSubtypeLabel`.
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .entry
  }

  init(stored value: String?) {
    self = value.flatMap(Self.init(rawValue:)) ?? .entry
  }
}

/// The two marks an Entry can carry, like Web `entry-marks-fields.tsx`: a Chapter and a First
/// Time. A new Entry starts with the marks of the place that opened its editor.
struct EntryMarks: Equatable, Hashable, Sendable {
  var isChapter: Bool
  var isFirstTime: Bool

  init(isChapter: Bool = false, isFirstTime: Bool = false) {
    self.isChapter = isChapter
    self.isFirstTime = isFirstTime
  }

  init(subtype: EntrySubtype, isFirstTime: Bool) {
    self.init(isChapter: subtype == .chapter, isFirstTime: isFirstTime)
  }

  static let none = Self()
  static let chapter = Self(isChapter: true)
  static let firstTime = Self(isFirstTime: true)

  var subtype: EntrySubtype { isChapter ? .chapter : .entry }

  /// Web `wikiItemIdentityLabel`: "Chapter · First Time", "Chapter", "First Time", or "Entry".
  var identityLabel: String {
    switch (isChapter, isFirstTime) {
    case (true, true): "Chapter · First Time"
    case (true, false): "Chapter"
    case (false, true): "First Time"
    case (false, false): "Entry"
    }
  }
}

/// The Library Record filter, like Web `wikiItemRecordFilters`. The raw values are the
/// `search_wiki_items` item classifications.
enum EntryRecordFilter: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case entry
  case chapter
  case firstTime = "first_time"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .entry: "Entries"
    case .chapter: "Chapters"
    case .firstTime: "First Times"
    }
  }
}

/// The limits every Web Entry form shares (`inbox-input.ts`, `organization.ts`).
enum EntryLimits {
  static let title = 200
  static let body = 50_000
  static let tagCount = 70
  static let tagName = 80
  static let tagCountMessage =
    "Use up to \(tagCount) tags with names up to \(tagName) characters."

  /// Web `parseTagNames`: trims each name and drops case-insensitive repeats, keeping the first
  /// spelling. Returns nil for a blank or too long name or too many names.
  static func tagNames(_ values: [String]) -> [String]? {
    guard values.count <= tagCount else { return nil }
    var names: [String] = []
    var seen: Set<String> = []
    for value in values {
      let name = value.trimmed
      guard !name.isEmpty, name.count <= tagName else { return nil }
      if seen.insert(name.lowercased()).inserted { names.append(name) }
    }
    return names
  }
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nonEmpty: String? {
    isEmpty ? nil : self
  }

  func truncated(to limit: Int) -> String {
    guard count > limit else { return self }
    let endIndex = index(startIndex, offsetBy: limit)
    return "\(self[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines))…"
  }

  /// Web `compactText` in `search.ts`: whitespace collapsed to single spaces and at most 140
  /// characters, the last three of them "...".
  var compactExcerpt: String {
    let compact = split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .joined(separator: " ")
    return compact.count > 140 ? "\(compact.prefix(137))..." : compact
  }
}

/// Web `countLabel`, such as "1 Entry", "3 Entries", or "2 people".
/// Nouns ending in a consonant and "y" take "ies"; pass `plural` for any other irregular form.
func countLabel(_ count: Int, _ singular: String, plural: String? = nil) -> String {
  let regular =
    singular.range(of: "[^aeiou]y$", options: [.regularExpression, .caseInsensitive]) != nil
    ? "\(singular.dropLast())ies" : "\(singular)s"
  return "\(count) \(count == 1 ? singular : plural ?? regular)"
}

/// Accepts the date strings PostgREST and `to_jsonb` write: ISO 8601 with or without fractional
/// seconds, a `T` or a space between date and time, and `+00:00` or `+00` offsets.
enum EntryTimestamp {
  static func date(from value: String) -> Date? {
    var text = value.trimmed
    if text.count > 10, text[text.index(text.startIndex, offsetBy: 10)] == " " {
      text.replaceSubrange(
        text.index(text.startIndex, offsetBy: 10)...text.index(text.startIndex, offsetBy: 10),
        with: "T")
    }
    // `to_jsonb` writes a two-digit offset such as `+00`.
    if text.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil { text += ":00" }
    // Postgres keeps microseconds; the formatter reads milliseconds.
    if let fraction = text.range(of: #"\.\d+"#, options: .regularExpression) {
      // Pad short fractions with zeros, then keep the first three digits.
      let milliseconds = String((text[fraction].dropFirst() + "000").prefix(3))
      text.replaceSubrange(fraction, with: "." + milliseconds)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }

  /// The UTC ISO 8601 form Web's `Date.toISOString()` writes, such as
  /// `2026-10-18T19:00:00.000Z`.
  static func string(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = .gmt
    return formatter.string(from: date)
  }
}

extension KeyedDecodingContainer {
  /// A timestamp that may be missing, null, or written in any `EntryTimestamp` form.
  func decodeTimestamp(forKey key: Key) throws -> Date? {
    guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
    guard let date = EntryTimestamp.date(from: text) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "Invalid timestamp \(text)")
    }
    return date
  }

  /// A required timestamp in any `EntryTimestamp` form.
  func decodeRequiredTimestamp(forKey key: Key) throws -> Date {
    guard let date = try decodeTimestamp(forKey: key) else {
      throw DecodingError.keyNotFound(
        key, .init(codingPath: codingPath, debugDescription: "Missing timestamp"))
    }
    return date
  }
}
