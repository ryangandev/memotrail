import Foundation

/// How many Entries one page of a Chapter lists, like Web `chapterEntriesPageSize`.
enum ChapterContents {
  static let pageSize = 50
}

/// One `chapter_entries` row: an Entry dated fully inside a Chapter, like Web `ChapterEntry`.
struct ChapterEntry: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  /// The stored title, blank when the Entry has none.
  let title: String
  let excerpt: String
  let isFirstTime: Bool
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let tagNames: [String]
  let coverPhoto: HomeAttachment?
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title, excerpt
    case isFirstTime = "is_first_time"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case tagNames = "tag_names"
    case coverPhoto = "cover_photo"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    excerpt = try values.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    tagNames = try values.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    coverPhoto = try values.decodeIfPresent(HomeAttachment.self, forKey: .coverPhoto)
    if let count = try? values.decode(Int.self, forKey: .totalCount) {
      totalCount = count
    } else {
      totalCount = Int(try values.decode(String.self, forKey: .totalCount)) ?? 0
    }
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  var displayTitle: String { entryDisplayTitle(title, occurrence) }
}

/// One `chapter_overlaps` row: a Chapter whose days overlap this one's, like Web
/// `ChapterOverlap`.
struct ChapterOverlap: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String
  let isFirstTime: Bool
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: DatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let windowStart: String?
  let windowEnd: String?

  enum CodingKeys: String, CodingKey {
    case id = "entry_id"
    case title
    case isFirstTime = "is_first_time"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case windowStart = "window_start"
    case windowEnd = "window_end"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    isFirstTime = try values.decodeIfPresent(Bool.self, forKey: .isFirstTime) ?? false
    occurredStart = try values.decodeTimestamp(forKey: .occurredStart)
    occurredEnd = try values.decodeTimestamp(forKey: .occurredEnd)
    datePrecision = DatePrecision(
      stored: try values.decodeIfPresent(String.self, forKey: .datePrecision))
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    windowStart = try values.decodeIfPresent(String.self, forKey: .windowStart)
    windowEnd = try values.decodeIfPresent(String.self, forKey: .windowEnd)
  }

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      storedPrecision: datePrecision.rawValue, start: occurredStart, end: occurredEnd,
      label: occurredLabel, timezone: occurredTimezone)
  }

  var displayTitle: String { entryDisplayTitle(title, occurrence) }
}

struct ChapterEntriesParameters: Encodable, Equatable, Sendable {
  let chapterID: UUID
  let limit: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case chapterID = "p_chapter_id"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}

struct ChapterOverlapsParameters: Encodable, Equatable, Sendable {
  let chapterID: UUID

  enum CodingKeys: String, CodingKey {
    case chapterID = "p_chapter_id"
  }
}
