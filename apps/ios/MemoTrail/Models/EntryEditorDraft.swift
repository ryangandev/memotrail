import Foundation
import UIKit

// The Entry editor's draft and the rules it follows, ported from Web:
// `components/entry-editor-dialog.tsx` (marks, save), `components/occurrence-editor.tsx` (the
// date controls), `lib/data/occurrence.ts` (`occurrenceDraft`, `resolveOccurrenceDraft`,
// `validateOccurrence`), and `lib/data/organization.ts` (tags). Everything here is pure, so the
// editor view and its tests share one implementation.

/// What the editor holds between opening and saving.
struct EntryEditorDraft: Equatable, Sendable {
  /// Drafted once, so a retried save of a new Entry cannot add it twice.
  let entryID: UUID
  /// The Entry as the editor opened it, or nil for a new one.
  let original: EditableEntry?
  /// The version the next save expects: nil until a new Entry is first saved.
  var revision: Int?
  var title: String
  private(set) var marks: EntryMarks
  var occurrence: OccurrenceDraft
  var tagNames: [String]
  /// The saved Location, resent untouched, or nil once removed.
  var location: EntryLocation?
  /// A saved photo's GPS position to add as the Location when this draft is saved.
  var photoLocation: PhotoLocationDraft?

  /// `timezone` stands in for a new or undated Entry's zone, like Web's Settings default.
  init(mode: EntryEditorMode, timezone: String, entryID: UUID = UUID()) {
    switch mode {
    case .new(let marks):
      self.entryID = entryID
      original = nil
      revision = nil
      title = ""
      self.marks = marks
      occurrence = .editing(
        EntryOccurrence(precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone))
      tagNames = []
      location = nil
    case .edit(let entry):
      self.entryID = entry.id
      original = entry
      revision = entry.revision
      title = entry.title ?? ""
      marks = entry.marks
      occurrence = .editing(
        entry.occurrence(fallbackTimezone: timezone), undatedTimezone: timezone)
      tagNames = entry.tagNames
      location = entry.primaryLocation
    }
    photoLocation = nil
  }

  var isNew: Bool { original == nil }

  /// Web `changeMarks`: a Chapter can have a Day with an end, a Month or Year with an end, or
  /// still be going on. Checking Chapter keeps a Day's own end; unchecking it keeps a Day's end
  /// as a date range and drops the end of every other date. A Not sure date keeps its end.
  mutating func changeMarks(_ next: EntryMarks) {
    if next.isChapter != marks.isChapter {
      if next.isChapter {
        if occurrence.precision == .range { occurrence.precision = .day }
      } else if occurrence.precision == .day, !occurrence.end.isEmpty {
        occurrence.endMode = .date
        occurrence.precision = .range
      } else if ![.range, .approximate, .age].contains(occurrence.precision) {
        occurrence.end = ""
        occurrence.endMode = .date
      }
    }
    marks = next
  }

  /// Uses the Settings time zone once it is known, for a date nobody has entered yet.
  mutating func useDefaultTimezone(_ timezone: String) {
    guard occurrence.start.isEmpty, occurrence.end.isEmpty, original?.occurredStart == nil,
      TimeZone(identifier: timezone) != nil
    else { return }
    occurrence.timezone = timezone
  }

  /// The `save_entry` call for this draft, checked in Web's order: a Chapter's title, the date,
  /// then everything `parseInboxReviewInput` checks. Throws `SaveEntryError.invalid`.
  func parameters(body: String, richText: EntryRichText?, tagOptions: [String]) throws
    -> SaveEntryParameters
  {
    if marks.isChapter && title.trimmed.isEmpty {
      throw SaveEntryError.invalid("Give this Chapter a title.")
    }
    let resolved = try occurrence.resolvedForSave(
      original: original?.occurrence(fallbackTimezone: occurrence.timezone),
      span: marks.isChapter)
    return try SaveEntryParameters(
      entryID: entryID, expectedRevision: revision, title: title, body: body,
      richText: richText, occurrence: resolved,
      tagNames: EntryTagField.namesToSave(tagNames, options: tagOptions),
      location: location, photoLocation: isNew ? nil : photoLocation, marks: marks)
  }
}

/// The note an editor saves: an untouched note keeps the document it opened with, including
/// Web-only structure such as lists, quotes, links, and code; an edited note saves what the
/// native editor holds, paragraphs and emphasis.
enum EntryEditorNote {
  @MainActor
  static func toSave(
    current: NSAttributedString, opening: NSAttributedString, original: EditableEntry?
  ) -> (body: String, richText: EntryRichText?) {
    let edited = EntryEmphasisContent.capture(current)
    if let original, edited == EntryEmphasisContent.capture(opening) {
      return (original.body, original.richText)
    }
    return (edited.body, edited.rich.flatMap(EntryRichText.init))
  }

  /// The note as the native editor opens it, and whether it holds Web-only formatting that
  /// editing here would turn into plain paragraphs.
  @MainActor
  static func opening(_ entry: EditableEntry?)
    -> (note: NSAttributedString, hasWebOnlyFormatting: Bool)
  {
    guard let entry else { return (NSAttributedString(), false) }
    let editable = entry.richText.flatMap(EntryEmphasisContent.init)
    return (
      editable?.attributedText() ?? NSAttributedString(string: entry.body),
      entry.richText != nil && editable == nil
    )
  }
}

// MARK: Tags

/// Web `EntryOrganizationEditor` and `organization.ts`.
enum EntryTagField {
  /// Reusing a tag takes one tap, so the most used ones are offered as suggestions.
  static let suggestionCount = 6
  /// The tag count limit is shown only once an Entry gets close to it.
  static let limitNoticeCount = EntryLimits.tagCount - 10

  /// The person's tags not on this Entry yet, most used first.
  static func available(_ names: [String], options: [String]) -> [String] {
    let added = Set(names.map { $0.lowercased() })
    return options.filter { !added.contains($0.lowercased()) }
  }

  static func suggestions(_ names: [String], options: [String]) -> [String] {
    guard names.count < EntryLimits.tagCount else { return [] }
    return Array(available(names, options: options).prefix(suggestionCount))
  }

  static func showsLimit(_ names: [String]) -> Bool { names.count >= limitNoticeCount }

  /// Web `tagNamesIncludingDraft`: the tags to save, including a name still typed, each one
  /// written the way an existing tag already is.
  static func namesToSave(_ names: [String], draft: String = "", options: [String]) -> [String] {
    var result = names.map { existingTagName($0, options: options) }
    let name = existingTagName(draft, options: options)
    if !name.isEmpty, !result.contains(where: { $0.lowercased() == name.lowercased() }) {
      result.append(name)
    }
    return result
  }
}

// MARK: Dates

/// How precisely a date is known, as the editor offers it: Web's Day, Month, Year, and Not sure.
/// Exact times, day ranges, ages, and unknown dates remain stored precisions, reached through
/// the toggles, the Not sure description, or an empty date.
enum DateSegment: String, CaseIterable, Identifiable, Sendable {
  case day, month, year, unsure

  var id: String { rawValue }

  var title: String {
    switch self {
    case .day: "Day"
    case .month: "Month"
    case .year: "Year"
    case .unsure: "Not sure"
    }
  }

  init(_ precision: DatePrecision) {
    switch precision {
    case .month: self = .month
    case .year: self = .year
    case .approximate, .age: self = .unsure
    default: self = .day
    }
  }
}

extension OccurrenceDraft {
  /// Web `occurrenceDraft`: a saved date without an end reads as still going on.
  static func editing(_ value: EntryOccurrence, undatedTimezone: String? = nil) -> Self {
    var draft = Self(value, undatedTimezone: undatedTimezone)
    draft.endMode = value.end == nil ? .present : .date
    return draft
  }

  /// An unknown date is a Day left empty; any edit stores it as a Day again.
  var shownPrecision: DatePrecision { precision == .unknown ? .day : precision }
  var segment: DateSegment { DateSegment(shownPrecision) }

  /// Whether the date shows an end: always for a Chapter or a day range, and for a Not sure
  /// date once its end is added.
  func endAdded(span: Bool) -> Bool {
    span || shownPrecision == .range || (segment == .unsure && !span && endMode == .date)
  }

  /// Whether Present can stand in for the end.
  func presentShown(span: Bool) -> Bool { span || shownPrecision == .range }

  /// The end mode the controls show.
  func shownEndMode(span: Bool) -> EndMode { presentShown(span: span) ? endMode : .date }

  /// Add time: a Day can carry a time, except an ordinary Entry's day range.
  func timeToggleShown(span: Bool) -> Bool {
    segment == .day && (span || shownPrecision != .range)
  }

  /// Add end date: outside a Chapter, only a Day or Not sure date can end, and never with a time.
  func endToggleShown(span: Bool) -> Bool {
    !span && (segment == .day || segment == .unsure) && shownPrecision != .exact
  }

  /// Web's `change`: every edit stores the shown precision, so an unknown date becomes a Day.
  mutating func edit(_ change: (inout Self) -> Void) {
    precision = shownPrecision
    change(&self)
  }

  /// Web `changeSegment`: a coarser choice keeps the part of the date it can hold, a finer one
  /// starts empty, and Not sure keeps an age as an age.
  mutating func changeSegment(to next: DateSegment, span: Bool, unsurePrecision: DatePrecision) {
    guard next != segment else { return }
    let keepsEnd = span || next == .day || next == .unsure
    func date(_ text: String) -> String {
      switch next {
      case .year: String(text.prefix(4))
      case .month: text.count >= 7 ? String(text.prefix(7)) : ""
      case .day, .unsure: text.count >= 10 ? String(text.prefix(10)) : ""
      }
    }
    let end = keepsEnd ? date(self.end) : ""
    let nextPrecision: DatePrecision =
      switch next {
      case .unsure: unsurePrecision
      case .day: !end.isEmpty && !span ? .range : .day
      case .month: .month
      case .year: .year
      }
    let endMode: EndMode =
      next == .unsure && !span && end.isEmpty ? .present : !end.isEmpty ? .date : self.endMode
    edit {
      $0.precision = nextPrecision
      $0.start = date($0.start)
      $0.end = end
      $0.endMode = endMode
    }
  }

  /// Web `toggleTime`: the date stays, and a new time starts empty rather than at an invented
  /// hour.
  mutating func toggleTime(_ isOn: Bool, span: Bool) {
    edit {
      $0.precision = isOn ? .exact : .day
      $0.start = String($0.start.prefix(10))
      $0.end = span ? String($0.end.prefix(10)) : ""
    }
  }

  /// Web `toggleEnd`: a Not sure date ends on a date or not at all; a Day becomes a range.
  mutating func toggleEnd(_ isOn: Bool) {
    let unsure = segment == .unsure
    edit {
      $0.end = ""
      if unsure {
        $0.endMode = isOn ? .date : .present
      } else {
        $0.precision = isOn ? .range : .day
        $0.endMode = .date
      }
    }
  }

  /// Present: the period is still going on, so it has no end date.
  mutating func setPresent(_ isOn: Bool) {
    edit {
      if isOn { $0.end = "" }
      $0.endMode = isOn ? .present : .date
    }
  }

  /// Web `photoCalendarDateDraft`: a photo's calendar date as a Day, replacing the draft's
  /// range and description but keeping its zone. Throws for an invalid date.
  mutating func useCalendarDate(_ date: String) throws {
    guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
      MTDateText.date(date, granularity: .day, includesTime: false) != nil
    else { throw SaveEntryError.invalid("This camera date is invalid. Edit the date manually.") }
    precision = .day
    start = date
    end = ""
    endMode = .date
    label = ""
  }

  /// Web `resolveOccurrenceDraft`: the stored occurrence for this draft. An empty calendar date
  /// is stored as Unknown and keeps its description; unchanged fields keep their original
  /// instant. Throws `SaveEntryError.invalid` with Web's message.
  func resolvedForSave(original: EntryOccurrence? = nil, span: Bool = false) throws
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
