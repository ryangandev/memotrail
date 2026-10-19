import Foundation

// The Dashboard's data, like Web `apps/web/src/lib/data/home.ts`, `home-entry.ts`, and
// `home-resurfacing.ts`.

/// The single `home_workspace` row.
struct HomeSnapshot: Decodable, Equatable, Sendable {
  let snapshotDate: String
  let profileDisplayName: String?
  let entryCount: Int
  let firstTimeCount: Int
  let tagCount: Int
  /// How many Chapters have started and not ended.
  let nowCount: Int
  var recentEntries: [HomeEntry]
  /// The Chapters happening now, at most a few.
  let nowItems: [HomeNowItem]

  enum CodingKeys: String, CodingKey {
    case snapshotDate = "snapshot_date"
    case profileDisplayName = "profile_display_name"
    case entryCount = "entry_count"
    case firstTimeCount = "first_time_count"
    case tagCount = "tag_count"
    case nowCount = "now_count"
    case recentEntries = "recent_entries"
    case nowItems = "now_items"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    snapshotDate = try values.decode(String.self, forKey: .snapshotDate)
    profileDisplayName = try values.decodeIfPresent(String.self, forKey: .profileDisplayName)
    entryCount = try Self.count(values, .entryCount)
    firstTimeCount = try Self.count(values, .firstTimeCount)
    tagCount = try Self.count(values, .tagCount)
    nowCount = try Self.count(values, .nowCount)
    recentEntries = try values.decode([HomeEntry].self, forKey: .recentEntries)
    nowItems = try values.decode([HomeNowItem].self, forKey: .nowItems)
  }

  /// The day this snapshot describes, which Now durations are measured to (Web `Now`).
  var asOf: Date {
    EntryTimestamp.date(from: "\(snapshotDate)T12:00:00Z") ?? .now
  }

  /// Web `safeCount`: a non-negative whole number, written as a number or a string.
  private static func count(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys)
    throws -> Int
  {
    let count: Int?
    if let number = try? values.decode(Int.self, forKey: key) {
      count = number
    } else {
      count = Int(try values.decode(String.self, forKey: key))
    }
    guard let count, count >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: values, debugDescription: "A count must be a whole number.")
    }
    return count
  }
}

/// A Chapter that has started and has no end yet, like Web `HomeNowItem`.
struct HomeNowItem: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  /// The stored title, blank when the Chapter has none.
  let title: String
  let isFirstTime: Bool
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title
    case isFirstTime = "is_first_time"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    isFirstTime = try values.decode(Bool.self, forKey: .isFirstTime)
    occurredStart = try values.decodeRequiredTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryDisplayTitle`.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// The span the Chapter covers, then how long it has lasted as of `asOf`, as Web `Now`
  /// writes them. A duration is only as precise as the dates: a Year says "About 2 years",
  /// never months, and a Month or an approximate date says "About".
  func facts(asOf: Date) -> [String] {
    [occurrence.spanLabel, occurrence.durationLabel(now: asOf)]
  }
}

/// A recent Entry or resurfaced memory on the Dashboard, like Web `HomeEntry`. The RPC does not
/// say whether it is a First Time.
struct HomeEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  /// The stored title, blank when the Entry has none.
  let title: String
  let body: String
  let subtype: EntrySubtype
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let createdAt: Date?
  let updatedAt: Date?
  let tagNames: [String]
  var attachments: [HomeAttachment]

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title, body, revision, attachments
    case subtype = "item_subtype"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case tagNames = "tag_names"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    subtype = EntrySubtype(stored: try values.decodeIfPresent(String.self, forKey: .subtype))
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    createdAt = try values.decodeTimestamp(forKey: .createdAt)
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    attachments = try values.decodeIfPresent([HomeAttachment].self, forKey: .attachments) ?? []
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryDisplayTitle`: the title, or the date when there is none.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// The date shown beside the title. An untitled Entry is already named by its date, so the
  /// date is not repeated (Web `EntryCard`).
  var shownDate: String? {
    title.trimmed.isEmpty ? nil : occurrence.displayLabel
  }

  /// The note as a card shows it: trimmed and cut at `limit` characters, or nil when empty.
  func summary(limit: Int) -> String? {
    body.trimmed.nonEmpty.map { $0.truncated(to: limit) }
  }

  /// "Chapter" or "Entry"; the row does not carry the First Time mark.
  var identityLabel: String { EntryMarks(subtype: subtype, isFirstTime: false).identityLabel }

  /// The first photo that has a display URL, else the first photo.
  var coverAttachment: HomeAttachment? {
    attachments.first(where: { $0.signedURL != nil }) ?? attachments.first
  }
}

enum HomeResurfacingKind: String, Decodable, Equatable, Sendable {
  case fromArchive = "from_your_archive"
  case onThisDay = "on_this_day"
}

/// The `home_resurfaced_memory` row: always a dated ordinary Entry, like Web
/// `parseHomeResurfacedMemory`.
struct HomeResurfacedMemory: Decodable, Equatable, Sendable {
  var entry: HomeEntry
  let kind: HomeResurfacingKind
  let yearsAgo: Int?

  enum CodingKeys: String, CodingKey {
    case kind = "resurfacing_kind"
    case yearsAgo = "years_ago"
  }

  init(from decoder: Decoder) throws {
    entry = try HomeEntry(from: decoder)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(HomeResurfacingKind.self, forKey: .kind)
    yearsAgo = try values.decodeIfPresent(Int.self, forKey: .yearsAgo)

    guard entry.occurredStart != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: values, debugDescription: "A resurfaced memory must be dated.")
    }
    switch kind {
    case .onThisDay:
      guard let yearsAgo, yearsAgo > 0 else {
        throw DecodingError.dataCorruptedError(
          forKey: .yearsAgo, in: values,
          debugDescription: "An On This Day memory requires a positive anniversary count.")
      }
    case .fromArchive:
      guard yearsAgo == nil else {
        throw DecodingError.dataCorruptedError(
          forKey: .yearsAgo, in: values,
          debugDescription: "An archive memory cannot include an anniversary count.")
      }
    }
  }
}

/// A saved original photo as the Dashboard and Chapter RPCs list it.
struct HomeAttachment: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let bucketID: String
  let objectPath: String
  let originalFilename: String?
  let mimeType: String
  let byteSize: Int64?
  let pixelWidth: Int?
  let pixelHeight: Int?
  var signedURL: URL?

  enum CodingKeys: String, CodingKey {
    case id = "attachment_id"
    case bucketID = "bucket_id"
    case objectPath = "object_path"
    case originalFilename = "original_filename"
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case pixelWidth = "pixel_width"
    case pixelHeight = "pixel_height"
  }
}

struct HomeWorkspaceRequest: Equatable, Sendable {
  static let defaultRecentLimit = 5

  let localDate: String
  let timezone: String
  let recentLimit: Int

  init(date: Date, timezone: TimeZone, recentLimit: Int = defaultRecentLimit) throws {
    try self.init(date: date, timezoneIdentifier: timezone.identifier, recentLimit: recentLimit)
  }

  init(date: Date, timezoneIdentifier: String, recentLimit: Int = defaultRecentLimit) throws {
    guard !timezoneIdentifier.isEmpty, timezoneIdentifier.count <= 100,
      let timezone = TimeZone(identifier: timezoneIdentifier)
    else { throw HomeWorkspaceError.invalidTimezone }
    guard (1...10).contains(recentLimit) else { throw HomeWorkspaceError.invalidRecentLimit }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timezone
    formatter.dateFormat = "yyyy-MM-dd"

    localDate = formatter.string(from: date)
    self.timezone = timezoneIdentifier
    self.recentLimit = recentLimit
  }

  var parameters: HomeWorkspaceParameters {
    HomeWorkspaceParameters(localDate: localDate, timezone: timezone, recentLimit: recentLimit)
  }

  var resurfacingParameters: HomeResurfacingParameters {
    HomeResurfacingParameters(localDate: localDate, timezone: timezone)
  }
}

struct HomeWorkspaceParameters: Encodable, Equatable, Sendable {
  let localDate: String
  let timezone: String
  let recentLimit: Int

  enum CodingKeys: String, CodingKey {
    case localDate = "p_local_date"
    case timezone = "p_timezone"
    case recentLimit = "p_recent_limit"
  }
}

struct HomeResurfacingParameters: Encodable, Equatable, Sendable {
  let localDate: String
  let timezone: String

  enum CodingKeys: String, CodingKey {
    case localDate = "p_local_date"
    case timezone = "p_timezone"
  }
}

enum HomeWorkspaceError: Error, Equatable {
  case invalidRecentLimit
  case invalidTimezone
}

enum HomePresentation {
  static func firstName(_ value: String) -> String {
    value.trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "there"
  }

  /// The name the greeting uses: the preferred name when there is one, else the account name,
  /// like Web `snapshot.profileDisplayName || viewer.name`.
  static func greetingName(preferred: String?, account: String) -> String {
    firstName(preferred?.trimmed.nonEmpty ?? account)
  }

  /// Web's eyebrow, such as "Thursday, September 3", always in English and in `timezone`.
  static func eyebrow(at date: Date, timezone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = timezone
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: date)
  }

  static func greeting(at date: Date, timezone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let hour = calendar.component(.hour, from: date)

    if hour < 12 { return "Good morning" }
    if hour < 18 { return "Good afternoon" }
    return "Good evening"
  }
}
