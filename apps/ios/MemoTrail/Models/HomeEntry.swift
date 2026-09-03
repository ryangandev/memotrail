import Foundation

struct HomeSnapshot: Decodable, Equatable, Sendable {
  let snapshotDate: String
  let profileDisplayName: String?
  let inboxCount: Int
  let entryCount: Int
  let firstTimeCount: Int
  let collectionCount: Int
  let activeHabitCount: Int
  let dueHabitCount: Int
  let completedHabitCount: Int
  let skippedHabitCount: Int
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
    case activeHabitCount = "active_habit_count"
    case dueHabitCount = "due_habit_count"
    case completedHabitCount = "completed_habit_count"
    case skippedHabitCount = "skipped_habit_count"
    case currentStageCount = "current_stage_count"
    case recentEntries = "recent_entries"
    case currentStages = "current_stages"
  }

  var habitProgressLabel: String {
    if dueHabitCount == 0 {
      return activeHabitCount == 0 ? "No Habits yet" : "Nothing scheduled today"
    }

    let skipped = skippedHabitCount > 0 ? " · \(skippedHabitCount) skipped" : ""
    return "\(completedHabitCount) of \(dueHabitCount) due\(skipped)"
  }
}

struct HomeEntry: Decodable, Equatable, Identifiable, Sendable {
  var attachments: [HomeAttachment]
  let body: String
  let collectionNames: [String]
  let createdAt: Date
  let datePrecision: String
  let entryType: String
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
    case entryType = "entry_type"
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

  var displayDate: String {
    if let occurredLabel = occurredLabel?.trimmed.nonEmpty {
      return occurredLabel
    }

    return HomeDateFormatter.entryDate(
      occurredStart ?? createdAt,
      precision: datePrecision,
      timezone: occurredTimezone
    )
  }

  var displayType: String {
    switch entryType {
    case "first_time":
      "First Time"
    case "life_stage":
      "Life Stage"
    default:
      "Entry"
    }
  }

  var displayExcerpt: String? {
    body.trimmed.nonEmpty?.truncated(to: 170)
  }

  var coverAttachment: HomeAttachment? {
    attachments.first
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

  var displayDate: String {
    if let occurredLabel = occurredLabel?.trimmed.nonEmpty {
      return occurredLabel
    }

    let start = HomeDateFormatter.entryDate(
      occurredStart,
      precision: datePrecision,
      timezone: occurredTimezone
    )
    guard let occurredEnd else { return "\(start) - Present" }
    let end = HomeDateFormatter.entryDate(
      occurredEnd,
      precision: datePrecision,
      timezone: occurredTimezone
    )
    return "\(start) - \(end)"
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

enum HomeWorkspaceError: Error, Equatable {
  case invalidRecentLimit
  case invalidTimezone
}

enum HomePresentation {
  static func firstName(_ value: String) -> String {
    value.trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "MemoTrail"
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

private enum HomeDateFormatter {
  static func entryDate(_ date: Date, precision: String, timezone: String?) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .gmt

    switch precision {
    case "year":
      formatter.setLocalizedDateFormatFromTemplate("yyyy")
    case "month":
      formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    default:
      formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    }

    return formatter.string(from: date)
  }
}
