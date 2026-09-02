import Foundation

enum TimelineKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case stage
  case event

  var displayName: String {
    switch self {
    case .stage:
      "Stage"
    case .event:
      "Event"
    }
  }

  var explanation: String {
    switch self {
    case .stage:
      "A chapter that spans time and may still be ongoing."
    case .event:
      "A meaningful moment on one date."
    }
  }
}

enum TimelineDatePrecision: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case exact
  case day
  case month
  case year
  case approximate
  case age
  case range
  case unknown

  var displayName: String {
    switch self {
    case .exact, .day:
      "Exact day"
    case .month:
      "Month"
    case .year:
      "Year"
    case .approximate:
      "Approximate"
    case .age:
      "Age-based"
    case .range:
      "Date range"
    case .unknown:
      "Unknown"
    }
  }
}

struct TimelineEntry: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let trackID: UUID
  let title: String
  let body: String
  let kind: TimelineKind
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: TimelineDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let revision: Int
  let updatedAt: Date

  var displayDate: String {
    if let occurredLabel = occurredLabel?.trimmed.nonEmpty {
      return occurredLabel
    }

    let start = formatted(occurredStart)

    guard kind == .stage else { return start }
    let end = occurredEnd.map(formatted) ?? "Present"
    return "\(start) - \(end)"
  }

  private func formatted(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(identifier: occurredTimezone) ?? .gmt

    switch datePrecision {
    case .year:
      formatter.setLocalizedDateFormatFromTemplate("yyyy")
    case .month:
      formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    default:
      formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    }

    return formatter.string(from: date)
  }
}

struct TimelineTrack: Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let systemKey: String?
  let sortOrder: Int
  let isHidden: Bool
  var entries: [TimelineEntry]
}

struct TimelineWorkspaceRow: Decodable, Equatable, Sendable {
  let trackID: UUID
  let trackName: String
  let trackSystemKey: String?
  let trackSortOrder: Int
  let trackIsHidden: Bool
  let entryID: UUID?
  let title: String?
  let body: String?
  let timelineKind: String?
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: String?
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case trackID = "track_id"
    case trackName = "track_name"
    case trackSystemKey = "track_system_key"
    case trackSortOrder = "track_sort_order"
    case trackIsHidden = "track_is_hidden"
    case entryID = "entry_id"
    case title
    case body
    case timelineKind = "timeline_kind"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case updatedAt = "updated_at"
  }

  var entry: TimelineEntry? {
    guard
      let entryID,
      let title = title?.trimmed.nonEmpty,
      let body,
      let timelineKind,
      let kind = TimelineKind(rawValue: timelineKind),
      let occurredStart,
      let revision,
      revision > 0,
      let updatedAt
    else {
      return nil
    }

    return TimelineEntry(
      id: entryID,
      trackID: trackID,
      title: title,
      body: body,
      kind: kind,
      occurredStart: occurredStart,
      occurredEnd: kind == .stage ? occurredEnd : nil,
      datePrecision: datePrecision.flatMap(TimelineDatePrecision.init(rawValue:)) ?? .unknown,
      occurredLabel: occurredLabel?.trimmed.nonEmpty,
      occurredTimezone: occurredTimezone?.trimmed.nonEmpty ?? "UTC",
      revision: revision,
      updatedAt: updatedAt
    )
  }
}

enum TimelineWorkspace {
  static func tracks(from rows: [TimelineWorkspaceRow]) -> [TimelineTrack] {
    var tracksByID: [UUID: TimelineTrack] = [:]

    for row in rows {
      var track =
        tracksByID[row.trackID]
        ?? TimelineTrack(
          id: row.trackID,
          name: row.trackName,
          systemKey: row.trackSystemKey,
          sortOrder: row.trackSortOrder,
          isHidden: row.trackIsHidden,
          entries: []
        )

      if let entry = row.entry {
        track.entries.append(entry)
      }

      tracksByID[row.trackID] = track
    }

    return tracksByID.values
      .map { track in
        var track = track
        track.entries.sort {
          $0.occurredStart == $1.occurredStart
            ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            : $0.occurredStart < $1.occurredStart
        }
        return track
      }
      .sorted {
        $0.sortOrder == $1.sortOrder
          ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
          : $0.sortOrder < $1.sortOrder
      }
  }
}

struct TimelineEntryInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000
  static let labelLimit = 200

  let entryID: UUID?
  let expectedRevision: Int?
  let trackID: UUID
  let kind: TimelineKind
  let title: String
  let body: String
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: TimelineDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String

  static func validate(
    entryID: UUID?,
    expectedRevision: Int?,
    trackID: UUID,
    kind: TimelineKind,
    title: String,
    body: String,
    occurredStart: Date,
    occurredEnd: Date?,
    datePrecision: TimelineDatePrecision,
    occurredLabel: String,
    occurredTimezone: String
  ) throws -> TimelineEntryInput {
    let title = title.trimmed
    let body = body.trimmed
    let occurredLabel = occurredLabel.trimmed.nonEmpty
    let occurredTimezone = occurredTimezone.trimmed

    guard !title.isEmpty else { throw TimelineEntryError.titleRequired }
    guard title.count <= titleLimit else { throw TimelineEntryError.titleTooLong }
    guard body.count <= bodyLimit else { throw TimelineEntryError.bodyTooLong }
    guard (occurredLabel?.count ?? 0) <= labelLimit else {
      throw TimelineEntryError.labelTooLong
    }
    guard occurredStart.timeIntervalSinceReferenceDate.isFinite,
      occurredEnd?.timeIntervalSinceReferenceDate.isFinite ?? true
    else {
      throw TimelineEntryError.invalidDate
    }
    guard kind == .stage || occurredEnd == nil else {
      throw TimelineEntryError.eventHasEnd
    }
    guard occurredEnd.map({ $0 >= occurredStart }) ?? true else {
      throw TimelineEntryError.reversedRange
    }
    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100 else {
      throw TimelineEntryError.invalidTimezone
    }
    guard
      (entryID == nil && expectedRevision == nil)
        || (entryID != nil && (expectedRevision ?? 0) > 0)
    else {
      throw TimelineEntryError.invalidRevision
    }

    return TimelineEntryInput(
      entryID: entryID,
      expectedRevision: expectedRevision,
      trackID: trackID,
      kind: kind,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone
    )
  }
}

struct SaveTimelineEntryParameters: Encodable, Equatable, Sendable {
  let input: TimelineEntryInput

  enum CodingKeys: String, CodingKey {
    case trackID = "p_track_id"
    case kind = "p_timeline_kind"
    case title = "p_title"
    case body = "p_body"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case datePrecision = "p_date_precision"
    case occurredLabel = "p_occurred_label"
    case occurredTimezone = "p_occurred_timezone"
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.trackID, forKey: .trackID)
    try values.encode(input.kind, forKey: .kind)
    try values.encode(input.title, forKey: .title)
    try values.encode(input.body, forKey: .body)
    try values.encode(input.occurredStart, forKey: .occurredStart)
    try values.encode(input.datePrecision, forKey: .datePrecision)
    try values.encode(input.occurredTimezone, forKey: .occurredTimezone)
    try values.encodeIfPresent(input.occurredEnd, forKey: .occurredEnd)
    if input.occurredEnd == nil { try values.encodeNil(forKey: .occurredEnd) }
    try values.encodeIfPresent(input.occurredLabel, forKey: .occurredLabel)
    if input.occurredLabel == nil { try values.encodeNil(forKey: .occurredLabel) }
    try values.encodeIfPresent(input.entryID, forKey: .entryID)
    if input.entryID == nil { try values.encodeNil(forKey: .entryID) }
    try values.encodeIfPresent(input.expectedRevision, forKey: .expectedRevision)
    if input.expectedRevision == nil { try values.encodeNil(forKey: .expectedRevision) }
  }
}

struct TimelineWorkspaceParameters: Encodable, Sendable {
  let includeHidden: Bool

  enum CodingKeys: String, CodingKey {
    case includeHidden = "p_include_hidden"
  }
}

struct TrashTimelineEntryParameters: Encodable, Sendable {
  let entryID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct SavedTimelineEntry: Decodable, Sendable {
  let entryID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
  }
}

enum TimelineEntryError: LocalizedError, Equatable {
  case bodyTooLong
  case eventHasEnd
  case invalidDate
  case invalidRevision
  case invalidTimezone
  case labelTooLong
  case reversedRange
  case titleRequired
  case titleTooLong

  var errorDescription: String? {
    switch self {
    case .bodyTooLong:
      "Notes can be up to \(TimelineEntryInput.bodyLimit) characters."
    case .eventHasEnd:
      "Events happen at one point and cannot have an end date."
    case .invalidDate:
      "Choose a valid occurrence date."
    case .invalidRevision:
      "This Timeline version is invalid. Refresh and try again."
    case .invalidTimezone:
      "Choose a valid occurrence time zone."
    case .labelTooLong:
      "Human date labels can be up to \(TimelineEntryInput.labelLimit) characters."
    case .reversedRange:
      "The end date must be on or after the start date."
    case .titleRequired:
      "Add a title for this Timeline moment."
    case .titleTooLong:
      "Titles can be up to \(TimelineEntryInput.titleLimit) characters."
    }
  }
}
