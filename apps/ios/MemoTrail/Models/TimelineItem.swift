import Foundation

/// One `timeline_workspace` row: a Chapter or a First Time with the whole days it covers, like
/// Web `TimelineItem` in `apps/web/src/lib/data/timeline.ts`.
struct TimelineItem: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let isChapter: Bool
  let isFirstTime: Bool
  /// The stored title, blank when the Entry has none.
  let title: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let occurredLabel: String?
  let occurredTimezone: String?
  let datePrecision: DatePrecision
  /// The first day it covers, as `yyyy-MM-dd`; nil without a calendar date.
  let windowStart: String?
  /// The day after the last day it covers, as `yyyy-MM-dd`; nil while it is still going on.
  let windowEnd: String?
  let revision: Int
  let updatedAt: Date?
  let tagNames: [String]

  init(
    id: UUID, isChapter: Bool, isFirstTime: Bool, title: String = "",
    occurredStart: Date? = nil, occurredEnd: Date? = nil, occurredLabel: String? = nil,
    occurredTimezone: String? = "UTC", datePrecision: DatePrecision = .unknown,
    windowStart: String? = nil, windowEnd: String? = nil, revision: Int = 1,
    updatedAt: Date? = nil, tagNames: [String] = []
  ) {
    self.id = id
    self.isChapter = isChapter
    self.isFirstTime = isFirstTime
    self.title = title
    self.occurredStart = occurredStart
    self.occurredEnd = occurredEnd
    self.occurredLabel = occurredLabel
    self.occurredTimezone = occurredTimezone
    self.datePrecision = datePrecision
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.revision = revision
    self.updatedAt = updatedAt
    self.tagNames = tagNames
  }

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case isChapter = "is_chapter"
    case isFirstTime = "is_first_time"
    case title, revision
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case updatedAt = "updated_at"
    case tagNames = "tag_names"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    isChapter = try values.decode(Bool.self, forKey: .isChapter)
    isFirstTime = try values.decode(Bool.self, forKey: .isFirstTime)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    windowStart = try values.decodeIfPresent(String.self, forKey: .windowStart)
    windowEnd = try values.decodeIfPresent(String.self, forKey: .windowEnd)
    revision = try values.decode(Int.self, forKey: .revision)
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
  }

  var marks: EntryMarks { EntryMarks(isChapter: isChapter, isFirstTime: isFirstTime) }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryDisplayTitle`: the title, or the date when there is none.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  /// A Chapter shows the span it covers, a First Time its date. Web `timelineItemDateLabel`.
  var dateLabel: String { isChapter ? occurrence.spanLabel : occurrence.displayLabel }

  /// How long a Chapter lasts, or nil when it has no calendar date to measure from. Web
  /// `timelineItemDurationLabel`.
  func durationLabel(now: Date) -> String? {
    isChapter && windowStart != nil ? occurrence.durationLabel(now: now) : nil
  }

  /// What an item without a calendar date says about when it was. Web `timelineUndatedLabel`.
  var undatedLabel: String {
    let description = occurredLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return description.isEmpty ? "Undated" : "Roughly: \(description)"
  }

  /// The name a bar or point carries for assistive technology. Web `timelineItemAccessibleName`.
  var accessibleName: String { "\(displayTitle), \(dateLabel)" }

  /// This item as the layout takes it, or nil without a calendar date. `titleWidth` is the
  /// title's width at the band item font; a Chapter that is also a First Time adds room for the
  /// star drawn before its title.
  func layoutSource(titleWidth: Double) -> TimelineLayoutSource? {
    guard let windowStart else { return nil }
    return TimelineLayoutSource(
      band: isChapter ? .chapters : .firstTimes, id: id.uuidString.lowercased(),
      labelWidthPixels: titleWidth
        + (isChapter && isFirstTime ? TimelineMetrics.starAllowancePixels : 0),
      shape: isChapter ? .bar : .point, windowEnd: windowEnd, windowStart: windowStart)
  }
}

/// Web `timelineItems`: Chapters, and the First Times that are not Chapters, each by first
/// day. A First Time Chapter is one bar, so it is a Chapter only. Undated items come last, in
/// title order.
enum TimelineItems {
  static func split(_ rows: [TimelineItem]) -> (chapters: [TimelineItem], firstTimes: [TimelineItem])
  {
    let items = rows.sorted {
      let left = $0.windowStart ?? "9999-99-99"
      let right = $1.windowStart ?? "9999-99-99"
      return left == right
        ? $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending
        : left < right
    }
    return (
      items.filter(\.isChapter),
      items.filter { $0.isFirstTime && !$0.isChapter }
    )
  }
}

/// A saved original photo as `first_times_workspace` lists it, like Web `FirstTimeAttachment`.
struct EntryAttachment: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let variant: String
  let bucketID: String
  let objectPath: String
  let originalFilename: String?
  let mimeType: PhotoImageType
  let byteSize: Int64
  let pixelWidth: Int?
  let pixelHeight: Int?
  let createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id, variant, objectPath, originalFilename, mimeType, byteSize, pixelWidth, pixelHeight
    case createdAt
    case bucketID = "bucketId"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    variant = try values.decodeIfPresent(String.self, forKey: .variant) ?? "original"
    bucketID = try values.decode(String.self, forKey: .bucketID)
    objectPath = try values.decode(String.self, forKey: .objectPath)
    originalFilename = try values.decodeIfPresent(String.self, forKey: .originalFilename)
    mimeType = try values.decode(PhotoImageType.self, forKey: .mimeType)
    byteSize = try values.decode(Int64.self, forKey: .byteSize)
    pixelWidth = try values.decodeIfPresent(Int.self, forKey: .pixelWidth)
    pixelHeight = try values.decodeIfPresent(Int.self, forKey: .pixelHeight)
    createdAt = try values.decodeTimestamp(forKey: .createdAt)
  }
}

/// One `first_times_workspace` row: an Entry marked First Time, like Web `getFirstTimesWorkspace`.
struct FirstTimeRow: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  /// The stored title, blank when the Entry has none.
  let title: String
  let isChapter: Bool
  let body: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date?
  let tagNames: [String]
  let attachments: [EntryAttachment]
  /// The primary Location, loaded beside the rows like Web.
  var location: EntryLocation?

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case isChapter = "is_chapter"
    case title, body, revision, attachments
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case updatedAt = "updated_at"
    case tagNames = "tag_names"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    isChapter = try values.decodeIfPresent(Bool.self, forKey: .isChapter) ?? false
    body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    updatedAt = try values.decodeTimestamp(forKey: .updatedAt)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    attachments = try values.decodeIfPresent([EntryAttachment].self, forKey: .attachments) ?? []
    location = nil
  }

  var marks: EntryMarks { EntryMarks(isChapter: isChapter, isFirstTime: true) }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  /// Web `entryDisplayTitle`.
  var displayTitle: String { entryDisplayTitle(title, occurrence) }

  var dateLabel: String { isChapter ? occurrence.spanLabel : occurrence.displayLabel }
}
