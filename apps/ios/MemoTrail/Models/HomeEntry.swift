import Foundation

struct HomeSnapshot: Decodable, Equatable, Sendable {
  let snapshotDate: String
  let profileDisplayName: String?
  let inboxCount: Int
  let entryCount: Int
  let firstTimeCount: Int
  let collectionCount: Int
  let currentStageCount: Int
  var recentEntries: [HomeEntry]
  let currentStages: [HomeStage]

  enum CodingKeys: String, CodingKey {
    case snapshotDate = "snapshot_date"
    case profileDisplayName = "profile_display_name"
    case inboxCount = "inbox_count"
    case entryCount = "entry_count"
    case firstTimeCount = "first_time_count"
    case collectionCount = "collection_count"
    case currentStageCount = "current_stage_count"
    case recentEntries = "recent_entries"
    case currentStages = "current_stages"
  }

}

struct HomeEntry: Decodable, Equatable, Identifiable, Sendable {
  var attachments: [HomeAttachment]
  let body: String
  let collectionNames: [String]
  let createdAt: Date
  let datePrecision: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let id: UUID
  let inboxStatus: String
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredStart: Date?
  let occurredTimezone: String?
  let revision: Int
  let tagNames: [String]
  let title: String
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case attachments
    case body
    case collectionNames = "collection_names"
    case createdAt = "created_at"
    case datePrecision = "date_precision"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case id = "entry_id"
    case inboxStatus = "inbox_status"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case revision
    case tagNames = "tag_names"
    case title
    case updatedAt = "updated_at"
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      precision: TimelineDatePrecision(rawValue: datePrecision) ?? .unknown,
      start: occurredStart, end: occurredEnd, label: occurredLabel?.trimmed.nonEmpty,
      timezone: occurredTimezone.flatMap { TimeZone(identifier: $0)?.identifier } ?? "UTC")
  }

  /// The Web card title: the title, else the start of the note, else a neutral fallback.
  var cardTitle: String {
    title.trimmed.nonEmpty ?? body.trimmed.nonEmpty?.truncated(to: 72) ?? "Untitled Entry"
  }

  var displayType: String {
    itemKind.displayName(subtype: itemSubtype)
  }

  var coverAttachment: HomeAttachment? {
    attachments.first(where: { $0.signedURL != nil }) ?? attachments.first
  }
}

enum HomeResurfacingKind: String, Decodable, Equatable, Sendable {
  case fromArchive = "from_your_archive"
  case onThisDay = "on_this_day"
}

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

    guard entry.inboxStatus == "organized", entry.occurredStart != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: values,
        debugDescription: "A resurfaced memory must be organized and dated."
      )
    }

    switch kind {
    case .onThisDay:
      guard let yearsAgo, yearsAgo > 0 else {
        throw DecodingError.dataCorruptedError(
          forKey: .yearsAgo,
          in: values,
          debugDescription: "An On This Day memory requires a positive anniversary count."
        )
      }
    case .fromArchive:
      guard yearsAgo == nil else {
        throw DecodingError.dataCorruptedError(
          forKey: .yearsAgo,
          in: values,
          debugDescription: "An archive memory cannot include an anniversary count."
        )
      }
    }
  }
}

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

struct HomeInboxPreview: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, title, body
    case createdAt = "created_at"
  }

  /// The title, else the note's first line, like Web's Ready to organize rows.
  var displayTitle: String {
    title?.trimmed.nonEmpty
      ?? body.trimmed.split(whereSeparator: \.isNewline).first.map(String.init)
      ?? "Untitled capture"
  }

  /// The note is shown under a title only when both exist.
  var excerpt: String? {
    title?.trimmed.nonEmpty == nil ? nil : body.trimmed.nonEmpty
  }
}

struct HomeStage: Decodable, Equatable, Identifiable, Sendable {
  let body: String
  let datePrecision: String
  let id: UUID
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredStart: Date
  let occurredTimezone: String?
  let title: String
  let trackID: UUID
  let trackName: String

  enum CodingKeys: String, CodingKey {
    case body
    case datePrecision = "date_precision"
    case id = "entry_id"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case title
    case trackID = "track_id"
    case trackName = "track_name"
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      precision: TimelineDatePrecision(rawValue: datePrecision) ?? .unknown,
      start: occurredStart, end: occurredEnd, label: occurredLabel?.trimmed.nonEmpty,
      timezone: occurredTimezone.flatMap { TimeZone(identifier: $0)?.identifier } ?? "UTC")
  }
}

struct HomeWorkspaceRequest: Equatable, Sendable {
  static let defaultRecentLimit = 5

  let localDate: String
  let timezone: String
  let recentLimit: Int

  init(
    date: Date,
    timezone: TimeZone,
    recentLimit: Int = defaultRecentLimit
  ) throws {
    try self.init(
      date: date,
      timezoneIdentifier: timezone.identifier,
      recentLimit: recentLimit
    )
  }

  init(
    date: Date,
    timezoneIdentifier: String,
    recentLimit: Int = defaultRecentLimit
  ) throws {
    guard
      !timezoneIdentifier.isEmpty,
      timezoneIdentifier.count <= 100,
      let timezone = TimeZone(identifier: timezoneIdentifier)
    else {
      throw HomeWorkspaceError.invalidTimezone
    }
    guard (1...10).contains(recentLimit) else {
      throw HomeWorkspaceError.invalidRecentLimit
    }

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
    HomeWorkspaceParameters(
      localDate: localDate,
      timezone: timezone,
      recentLimit: recentLimit
    )
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

  static func greeting(at date: Date, timezone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let hour = calendar.component(.hour, from: date)

    if hour < 12 { return "Good morning" }
    if hour < 18 { return "Good afternoon" }
    return "Good evening"
  }
}
