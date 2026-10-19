import Foundation
@preconcurrency import Supabase

// A Chapter's review, read-only. iOS never makes, deletes, or turns on reviews: those stay on
// Web. This reads what Web's review panel reads, `chapter_review(p_chapter_id, p_local_date)`,
// and shows the stored review the way Web's `ReviewPanel` shows it once it exists, with the same
// checks: a citation or quote whose Entry is in Trash is hidden, and so is a quote whose exact
// words are no longer in its Entry. Web `apps/web/src/lib/data/review-input.ts`,
// `components/review-panel.tsx`.

/// An Entry a review cites, like Web `ReviewEntryRef`.
struct ReviewEntryRef: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  /// The stored title, trimmed, blank when the Entry has none.
  let title: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let datePrecision: DatePrecision
  /// Whether the Entry is in Trash now; only cited sources say.
  let isTrashed: Bool

  enum CodingKeys: String, CodingKey {
    case id, entryId, title, occurredStart, occurredEnd, occurredLabel, occurredTimezone
    case datePrecision, trashed
  }

  init(
    id: UUID, title: String = "", occurredStart: Date? = nil, occurredEnd: Date? = nil,
    occurredLabel: String? = nil, occurredTimezone: String? = nil,
    datePrecision: DatePrecision = .unknown, isTrashed: Bool = false
  ) {
    self.id = id
    self.title = title.trimmed
    self.occurredStart = occurredStart
    self.occurredEnd = occurredEnd
    self.occurredLabel = occurredLabel
    self.occurredTimezone = occurredTimezone
    self.datePrecision = datePrecision
    self.isTrashed = isTrashed
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    // Web reads `id`, then `entryId`.
    let raw =
      try values.decodeIfPresent(String.self, forKey: .id)
      ?? values.decodeIfPresent(String.self, forKey: .entryId)
    guard let raw, let id = UUID(uuidString: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .id, in: values, debugDescription: "A cited Entry needs an identifier.")
    }
    self.init(
      id: id, title: try values.decodeIfPresent(String.self, forKey: .title) ?? "",
      occurredStart: try values.decodeTimestamp(forKey: .occurredStart),
      occurredEnd: try values.decodeTimestamp(forKey: .occurredEnd),
      occurredLabel: try values.decodeIfPresent(String.self, forKey: .occurredLabel),
      occurredTimezone: try values.decodeIfPresent(String.self, forKey: .occurredTimezone),
      datePrecision: DatePrecision(
        stored: try values.decodeIfPresent(String.self, forKey: .datePrecision)),
      isTrashed: try values.decodeIfPresent(Bool.self, forKey: .trashed) ?? false)
  }

  /// Web `occurrenceOf`: a missing or unknown zone reads as UTC.
  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `occurrenceLabel`: how a link names the date.
  var dateLabel: String { occurrence.displayLabel }

  var displayTitle: String { entryDisplayTitle(title, occurrence) }
}

/// What Claude wrote, read defensively like Web `parseReviewContent`: a part with the wrong
/// shape is dropped rather than failing the review.
struct ReviewContent: Decodable, Equatable, Sendable {
  struct Phase: Equatable, Sendable {
    let feeling: String
    let description: String
    let entryIDs: [UUID]
    let windowStart: String
    let windowEnd: String
  }

  struct Theme: Equatable, Sendable {
    let name: String
    let description: String
    let entryIDs: [UUID]
  }

  struct Quote: Equatable, Sendable {
    let entryID: UUID
    let start: Int
    let end: Int
    let text: String
    let why: String
  }

  let summary: String
  let overview: String
  let phases: [Phase]
  let themes: [Theme]
  let quotes: [Quote]

  private enum CodingKeys: String, CodingKey {
    case summary, feelings, themes, quotes
  }

  private enum FeelingKeys: String, CodingKey {
    case overview, phases
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    summary = try values.decode(String.self, forKey: .summary)
    let feelings = try values.nestedContainer(keyedBy: FeelingKeys.self, forKey: .feelings)
    overview = try feelings.decodeIfPresent(String.self, forKey: .overview) ?? ""
    phases = feelings.lossy(RawPhase.self, forKey: .phases).compactMap(\.phase)
    themes = values.lossy(RawTheme.self, forKey: .themes).compactMap(\.theme)
    quotes = values.lossy(RawQuote.self, forKey: .quotes).compactMap(\.quote)
  }

  init(
    summary: String = "", overview: String = "", phases: [Phase] = [], themes: [Theme] = [],
    quotes: [Quote] = []
  ) {
    self.summary = summary
    self.overview = overview
    self.phases = phases
    self.themes = themes
    self.quotes = quotes
  }

  private struct RawPhase: Decodable {
    let feeling: String
    let description: String
    let entryIds: [String]?
    let windowStart: String?
    let windowEnd: String?

    var phase: Phase? {
      Phase(
        feeling: feeling, description: description, entryIDs: ReviewContent.ids(entryIds),
        windowStart: windowStart ?? "", windowEnd: windowEnd ?? "")
    }
  }

  private struct RawTheme: Decodable {
    let name: String
    let description: String
    let entryIds: [String]?

    var theme: Theme? {
      Theme(name: name, description: description, entryIDs: ReviewContent.ids(entryIds))
    }
  }

  private struct RawQuote: Decodable {
    let entryId: String
    let start: Int
    let end: Int
    let text: String
    let why: String

    var quote: Quote? {
      UUID(uuidString: entryId).map {
        Quote(entryID: $0, start: start, end: end, text: text, why: why)
      }
    }
  }

  private static func ids(_ values: [String]?) -> [UUID] {
    (values ?? []).compactMap(UUID.init(uuidString:))
  }
}

/// A saved review and the checks the database runs every time it is read, like Web
/// `StoredReview`. A review read here has finished; a job still writing one is Web's to show.
struct StoredReview: Decodable, Equatable, Identifiable, Sendable {
  struct Changes: Decodable, Equatable, Sendable {
    let newEntries: Int
    let editedEntries: Int
    let trashedEntries: Int

    static let none = Changes(newEntries: 0, editedEntries: 0, trashedEntries: 0)

    init(newEntries: Int, editedEntries: Int, trashedEntries: Int) {
      self.newEntries = newEntries
      self.editedEntries = editedEntries
      self.trashedEntries = trashedEntries
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      newEntries = values.count(forKey: .newEntries)
      editedEntries = values.count(forKey: .editedEntries)
      trashedEntries = values.count(forKey: .trashedEntries)
    }

    private enum CodingKeys: String, CodingKey {
      case newEntries, editedEntries, trashedEntries
    }
  }

  let id: UUID
  let content: ReviewContent?
  /// Whether the Chapter had not ended, so the review is a review so far.
  let isOngoing: Bool
  let generatedAt: Date?
  let entriesInPeriod: Int
  let entriesRead: Int
  let trimmedEntries: Int
  /// Whether each quote, in order, may be shown now.
  let quoteAvailable: [Bool]
  let sources: [ReviewEntryRef]
  let changes: Changes
  /// "en" or "zh", which sets the language of the interpretation.
  let language: String

  private enum CodingKeys: String, CodingKey {
    case id, content, ongoing, generatedAt, entriesInPeriod, entriesRead, trimmedEntries
    case quoteAvailable, sources, changes, language
  }

  init(
    id: UUID, content: ReviewContent?, isOngoing: Bool = false, generatedAt: Date? = nil,
    entriesInPeriod: Int = 0, entriesRead: Int = 0, trimmedEntries: Int = 0,
    quoteAvailable: [Bool] = [], sources: [ReviewEntryRef] = [], changes: Changes = .none,
    language: String = "en"
  ) {
    self.id = id
    self.content = content
    self.isOngoing = isOngoing
    self.generatedAt = generatedAt
    self.entriesInPeriod = entriesInPeriod
    self.entriesRead = entriesRead
    self.trimmedEntries = trimmedEntries
    self.quoteAvailable = quoteAvailable
    self.sources = sources
    self.changes = changes
    self.language = language
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    content = try? values.decodeIfPresent(ReviewContent.self, forKey: .content)
    isOngoing = try values.decodeIfPresent(Bool.self, forKey: .ongoing) ?? false
    generatedAt = try? values.decodeTimestamp(forKey: .generatedAt)
    entriesInPeriod = values.count(forKey: .entriesInPeriod)
    entriesRead = values.count(forKey: .entriesRead)
    trimmedEntries = values.count(forKey: .trimmedEntries)
    // Like Web, only a true counts; anything else holds the quote back.
    quoteAvailable =
      ((try? values.decodeIfPresent([OnlyTrue].self, forKey: .quoteAvailable)) ?? nil)?.map(
        \.value) ?? []
    sources = values.lossy(ReviewEntryRef.self, forKey: .sources)
    changes = (try? values.decodeIfPresent(Changes.self, forKey: .changes)) ?? .none
    language = try values.decodeIfPresent(String.self, forKey: .language) == "zh" ? "zh" : "en"
  }

  /// The title: "Review so far" while the Chapter goes on.
  var title: String { isOngoing ? "Review so far" : "Review" }

  /// Web `ReadyHeader`: "Read all 6 Entries", or "Read 40 of 80 Entries".
  var readLabel: String {
    entriesRead == entriesInPeriod
      ? "Read all \(countLabel(entriesInPeriod, "Entry"))"
      : "Read \(entriesRead) of \(entriesInPeriod) Entries"
  }

  /// Web `ReadyHeader`: "Made Oct 18, 2026", in the person's time zone.
  func madeLabel(timezone: TimeZone = .current) -> String? {
    generatedAt.map { "Made \(ReviewDates.mediumDate($0, timezone: timezone))" }
  }
}

/// A Chapter's "From your Entries" facts, computed live from the person's own Entries, like Web
/// `ReviewFacts`.
struct ReviewFacts: Decodable, Equatable, Sendable {
  struct TopTag: Equatable, Sendable {
    let name: String
    let count: Int
  }

  struct BusiestMonth: Equatable, Sendable {
    /// "YYYY-MM".
    let month: String
    let count: Int
  }

  let entryCount: Int
  let firstTimes: [ReviewEntryRef]
  let topTags: [TopTag]
  let busiestMonth: BusiestMonth?

  private enum CodingKeys: String, CodingKey {
    case entryCount, firstTimes, topTags, busiestMonth
  }

  init(
    entryCount: Int, firstTimes: [ReviewEntryRef] = [], topTags: [TopTag] = [],
    busiestMonth: BusiestMonth? = nil
  ) {
    self.entryCount = entryCount
    self.firstTimes = firstTimes
    self.topTags = topTags
    self.busiestMonth = busiestMonth
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    entryCount = values.count(forKey: .entryCount)
    firstTimes = values.lossy(ReviewEntryRef.self, forKey: .firstTimes)
    topTags = values.lossy(RawTag.self, forKey: .topTags).map {
      TopTag(name: $0.name, count: $0.count)
    }
    let month = try? values.decodeIfPresent(RawMonth.self, forKey: .busiestMonth)
    busiestMonth =
      month.flatMap {
        $0.month.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) == nil
          ? nil : BusiestMonth(month: $0.month, count: $0.count)
      }
  }

  private struct RawTag: Decodable {
    let name: String
    let count: Int

    private enum CodingKeys: String, CodingKey { case name, count }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      name = try values.decode(String.self, forKey: .name)
      count = values.count(forKey: .count)
    }
  }

  private struct RawMonth: Decodable {
    let month: String
    let count: Int

    private enum CodingKeys: String, CodingKey { case month, count }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      month = try values.decode(String.self, forKey: .month)
      count = values.count(forKey: .count)
    }
  }
}

/// What `chapter_review` returns that a read-only view needs: the stored review and the facts.
/// The eligibility and settings that decide whether Web offers Make a review are not read.
struct ChapterReview: Decodable, Equatable, Sendable {
  let facts: ReviewFacts?
  let review: StoredReview?

  private enum CodingKeys: String, CodingKey { case facts, review }

  init(facts: ReviewFacts?, review: StoredReview?) {
    self.facts = facts
    self.review = review
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    facts = try? values.decodeIfPresent(ReviewFacts.self, forKey: .facts)
    review = try? values.decodeIfPresent(StoredReview.self, forKey: .review)
  }

  /// The review to show, or nil when there is none or it has no readable content yet, like Web
  /// `ReviewPanel` when it has nothing to read.
  var shown: StoredReview? {
    review.flatMap { $0.content == nil ? nil : $0 }
  }
}

// MARK: - What the panel shows

/// The review as Web `ReadyBody` lays it out: only what is checked and may be shown now.
struct ReviewDisplay: Equatable, Sendable {
  struct Phase: Equatable, Identifiable, Sendable {
    let id: Int
    /// "March - May 2026".
    let range: String
    let feeling: String
    let description: String
    let cited: [ReviewEntryRef]
  }

  struct Theme: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String
    let cited: [ReviewEntryRef]
  }

  struct Quote: Equatable, Identifiable, Sendable {
    let id: Int
    let text: String
    let why: String
    let source: ReviewEntryRef
  }

  let overview: String
  let phases: [Phase]
  let themes: [Theme]
  let quotes: [Quote]
  /// Quotes held back because their Entry was edited or moved to Trash.
  let hiddenQuoteCount: Int

  init(_ review: StoredReview) {
    guard let content = review.content else {
      overview = ""
      phases = []
      themes = []
      quotes = []
      hiddenQuoteCount = 0
      return
    }
    let sources = Dictionary(review.sources.map { ($0.id, $0) }) { first, _ in first }
    func visible(_ ids: [UUID]) -> [ReviewEntryRef] {
      ids.compactMap { id in sources[id].flatMap { $0.isTrashed ? nil : $0 } }
    }
    let withYears = ReviewDates.phasesSpanYears(
      content.phases.map { ($0.windowStart, $0.windowEnd) })
    overview = content.overview
    phases = content.phases.enumerated().compactMap { index, phase in
      let cited = visible(phase.entryIDs)
      return cited.isEmpty
        ? nil
        : Phase(
          id: index,
          range: ReviewDates.phaseRange(
            windowStart: phase.windowStart, windowEnd: phase.windowEnd, withYears: withYears),
          feeling: phase.feeling, description: phase.description, cited: cited)
    }
    themes = content.themes.enumerated().compactMap { index, theme in
      let cited = visible(theme.entryIDs)
      return cited.isEmpty
        ? nil : Theme(id: index, name: theme.name, description: theme.description, cited: cited)
    }
    quotes = content.quotes.enumerated().compactMap { index, quote in
      guard review.quoteAvailable.indices.contains(index), review.quoteAvailable[index],
        let source = sources[quote.entryID], !source.isTrashed
      else { return nil }
      return Quote(id: index, text: quote.text, why: quote.why, source: source)
    }
    hiddenQuoteCount = content.quotes.count - quotes.count
  }

  /// Web's note under "In your words" when quotes are held back.
  var hiddenQuotesNote: String? {
    switch hiddenQuoteCount {
    case 0: nil
    case 1: "1 quote is hidden because its Entry was edited or moved to Trash."
    default:
      "\(hiddenQuoteCount) quotes are hidden because their Entries were edited or moved to Trash."
    }
  }
}

extension StoredReview {
  /// The statements above a review about what changed since it was made, like Web `ReadyBody`.
  /// Web adds a Make a new review action to the first; iOS has none.
  var notices: [String] {
    var notices: [String] = []
    let changed = changes.newEntries + changes.editedEntries
    if changed > 0 {
      notices.append(
        "\(countLabel(changed, "Entry")) in this Chapter \(changed == 1 ? "is" : "are") new or changed since this review."
      )
    }
    let trashed = changes.trashedEntries
    if trashed > 0 {
      let one = trashed == 1
      notices.append(
        "\(countLabel(trashed, "Entry")) this review read \(one ? "is" : "are") in Trash, so what came from \(one ? "it is" : "them is") hidden. Restore \(one ? "it" : "them"), or make a new review without \(one ? "it" : "them") on the Web."
      )
    }
    if entriesRead < entriesInPeriod || trimmedEntries > 0 {
      notices.append(trimmedNotice)
    }
    return notices
  }

  /// Web `trimmedNotice` for a Chapter.
  var trimmedNotice: String {
    let sampled = entriesRead < entriesInPeriod
    let longer = trimmedEntries > 0
    let lead = "This Chapter holds more writing than one review reads."
    if sampled, longer {
      return
        "\(lead) This review read \(entriesRead) of \(entriesInPeriod) Entries, spread evenly across the period, and the first 6,000 characters of longer ones."
    }
    if sampled {
      return
        "\(lead) This review read \(entriesRead) of \(entriesInPeriod) Entries, spread evenly across the period."
    }
    return "\(lead) This review read the first 6,000 characters of longer Entries."
  }
}

extension ReviewFacts {
  /// Web `Records` stats: "6 Entries", the Chapter's dates, and "1 First Time".
  func stats(spanLabel: String?) -> [String] {
    [
      countLabel(entryCount, "Entry"), spanLabel,
      firstTimes.isEmpty ? nil : countLabel(firstTimes.count, "First Time"),
    ].compactMap(\.self).filter { !$0.isEmpty }
  }

  /// Web: "Most writing: March 2026 (3 Entries)".
  var busiestMonthLine: String? {
    busiestMonth.map {
      "Most writing: \(ReviewDates.monthLabel($0.month)) (\(countLabel($0.count, "Entry")))"
    }
  }
}

/// Web's disclosure footer under every review (`REVIEW_FOOTER`).
enum ReviewCopy {
  static let footer =
    "Written by Claude, an AI model made by Anthropic, from the Entries above. It is an interpretation, not a record; your Entries are unchanged."
}

// MARK: - Dates

/// The date labels a review prints, like Web `review-input.ts`: English, and UTC for the day
/// strings the database writes.
enum ReviewDates {
  /// "2026-10-18", today in `timezone`, which `chapter_review` takes as `p_local_date`.
  static func localDate(_ date: Date = Date(), timezone: TimeZone = .current) -> String {
    formatter("yyyy-MM-dd", timezone: timezone, posix: true).string(from: date)
  }

  /// "Oct 18, 2026".
  static func mediumDate(_ date: Date, timezone: TimeZone = .current) -> String {
    formatter("MMM d, yyyy", timezone: timezone).string(from: date)
  }

  /// "March 2026" from a "YYYY-MM" busiest month.
  static func monthLabel(_ month: String) -> String {
    day("\(month)-01").map { formatter("MMMM yyyy", timezone: .gmt).string(from: $0) } ?? month
  }

  /// Web `phaseRangeLabel`: the months a phase covers, from the first day of its earliest Entry
  /// to the day before its exclusive end. A period inside one year names the year once, at the
  /// end ("March - May 2026").
  static func phaseRange(windowStart: String, windowEnd: String, withYears: Bool) -> String {
    guard let first = day(windowStart) else { return "" }
    let last = (day(windowEnd) ?? first).addingTimeInterval(-86_400)
    let end = last < first ? first : last
    let monthYear = formatter("MMMM yyyy", timezone: .gmt)
    let sameMonth =
      formatter("yyyy-MM", timezone: .gmt).string(from: first)
      == formatter("yyyy-MM", timezone: .gmt).string(from: end)
    if sameMonth { return monthYear.string(from: first) }
    let sameYear =
      formatter("yyyy", timezone: .gmt).string(from: first)
      == formatter("yyyy", timezone: .gmt).string(from: end)
    if withYears || !sameYear {
      return "\(monthYear.string(from: first)) - \(monthYear.string(from: end))"
    }
    return "\(formatter("MMMM", timezone: .gmt).string(from: first)) - \(monthYear.string(from: end))"
  }

  /// Web `phasesSpanYears`: whether a review's phases cross a year boundary, so every range
  /// names its years.
  static func phasesSpanYears(_ windows: [(start: String, end: String)]) -> Bool {
    var years: Set<String> = []
    for window in windows {
      if window.start.range(of: #"^\d{4}"#, options: .regularExpression) != nil {
        years.insert(String(window.start.prefix(4)))
      }
      if window.end.range(of: #"^\d{4}"#, options: .regularExpression) != nil,
        let end = day(window.end)
      {
        years.insert(formatter("yyyy", timezone: .gmt).string(from: end.addingTimeInterval(-86_400)))
      }
    }
    return years.count > 1
  }

  /// The first ten characters of a database day, as midnight UTC.
  private static func day(_ value: String) -> Date? {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else {
      return nil
    }
    return formatter("yyyy-MM-dd", timezone: .gmt, posix: true).date(from: String(value.prefix(10)))
  }

  private static func formatter(_ format: String, timezone: TimeZone, posix: Bool = false)
    -> DateFormatter
  {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: posix ? "en_US_POSIX" : "en_US")
    formatter.timeZone = timezone
    formatter.dateFormat = format
    return formatter
  }
}

// MARK: - Reading

struct ChapterReviewParameters: Encodable, Equatable, Sendable {
  let chapterID: UUID
  let localDate: String

  enum CodingKeys: String, CodingKey {
    case chapterID = "p_chapter_id"
    case localDate = "p_local_date"
  }
}

/// Reads a Chapter's saved review, like Web `loadChapterReview`. Each call first checks that the
/// session still belongs to `ownerID`.
@MainActor
struct ChapterReviewAPI {
  let client: SupabaseClient
  let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  /// The Chapter's review and facts, or nil when the database returns none.
  func review(chapterID: UUID, now: Date = Date(), timezone: TimeZone = .current) async throws
    -> ChapterReview?
  {
    try await requireOwner()
    let page: ChapterReview? = try await client.rpc(
      "chapter_review",
      params: ChapterReviewParameters(
        chapterID: chapterID, localDate: ReviewDates.localDate(now, timezone: timezone))
    ).execute().value
    try await requireOwner()
    return page
  }

  private func requireOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

// MARK: - Lenient decoding

extension KeyedDecodingContainer {
  /// A whole number written as a number or as digits, else 0, like Web `count`.
  fileprivate func count(forKey key: Key) -> Int {
    if let value = try? decodeIfPresent(Int.self, forKey: key), value >= 0 { return value }
    if let text = try? decodeIfPresent(String.self, forKey: key), let value = Int(text),
      value >= 0
    {
      return value
    }
    return 0
  }

  /// The elements that decode, leaving out any that do not, like Web's `flatMap` parsers.
  fileprivate func lossy<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
    guard let elements = try? decodeIfPresent([Lossy<Element>].self, forKey: key) else {
      return []
    }
    return elements.compactMap(\.value)
  }
}

private struct OnlyTrue: Decodable {
  let value: Bool

  init(from decoder: Decoder) throws {
    value = (try? decoder.singleValueContainer().decode(Bool.self)) == true
  }
}

private struct Lossy<Element: Decodable>: Decodable {
  let value: Element?

  init(from decoder: Decoder) throws {
    value = try? Element(from: decoder)
  }
}
