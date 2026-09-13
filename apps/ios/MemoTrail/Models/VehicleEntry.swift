import Foundation

typealias VehicleDatePrecision = TimelineDatePrecision

typealias VehicleAttachment = ResidenceAttachment

struct VehicleEntry: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String
  let body: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: VehicleDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let revision: Int
  let updatedAt: Date
  let make: String?
  let model: String?
  let modelYear: Int?
  let color: String?
  let timelineTrackID: UUID?
  let timelineTrackName: String?
  let collectionNames: [String]
  let tagNames: [String]
  var attachments: [VehicleAttachment]
  let totalCount: Int

  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil
  var occurrence: EntryOccurrence {
    EntryOccurrence(
      precision: datePrecision, start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone)
  }

  var isCurrent: Bool { occurredEnd == nil }

  var factsLabel: String {
    let identity = [modelYear.map(String.init), make, model]
      .compactMap { $0?.trimmed.nonEmpty }
      .joined(separator: " ")
    return [identity.nonEmpty, color?.trimmed.nonEmpty]
      .compactMap { $0 }
      .joined(separator: " · ")
      .nonEmpty ?? "Details not recorded"
  }

  var displayRange: String { occurrence.spanLabel }
  func durationLabel(now: Date = Date()) -> String { occurrence.durationLabel(now: now) }

}

struct VehicleWorkspaceRow: Decodable, Equatable, Sendable {
  let entryID: UUID
  let title: String
  let body: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: VehicleDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date
  let make: String?
  let model: String?
  let modelYear: Int?
  let color: String?
  let timelineTrackID: UUID?
  let timelineTrackName: String?
  let collectionNames: [String]
  let tagNames: [String]
  let attachments: [VehicleAttachment]
  let totalCount: Int

  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case title
    case body
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case updatedAt = "updated_at"
    case make
    case model
    case modelYear = "model_year"
    case color
    case timelineTrackID = "timeline_track_id"
    case timelineTrackName = "timeline_track_name"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case attachments
    case totalCount = "total_count"
  }

  var entry: VehicleEntry {
    VehicleEntry(
      id: entryID,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel?.trimmed.nonEmpty,
      occurredTimezone: occurredTimezone ?? "UTC",
      revision: revision,
      updatedAt: updatedAt,
      make: make?.trimmed.nonEmpty,
      model: model?.trimmed.nonEmpty,
      modelYear: modelYear,
      color: color?.trimmed.nonEmpty,
      timelineTrackID: timelineTrackID,
      timelineTrackName: timelineTrackName?.trimmed.nonEmpty,
      collectionNames: collectionNames,
      tagNames: tagNames,
      attachments: attachments,
      totalCount: totalCount,
      occurredStartRaw: occurredStartRaw,
      occurredEndRaw: occurredEndRaw
    )
  }
}

enum VehicleWorkspace {
  static func entries(from rows: [VehicleWorkspaceRow]) -> [VehicleEntry] {
    rows.map(\.entry).sorted {
      if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
      if $0.occurredStart != $1.occurredStart {
        return ($0.occurredStart ?? .distantPast) > ($1.occurredStart ?? .distantPast)
      }
      let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
      return titleOrder == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString : titleOrder == .orderedAscending
    }
  }
}

struct VehicleEntryInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000
  static let labelLimit = 200
  static let makeLimit = 120
  static let modelLimit = 120
  static let colorLimit = 80
  static let collectionLimit = 20
  static let collectionNameLimit = 80
  static let tagLimit = 50
  static let tagNameLimit = 60

  let entryID: UUID?
  var expectedRevision: Int?
  let title: String
  let body: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: VehicleDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let make: String?
  let model: String?
  let modelYear: Int?
  let color: String?
  let collectionNames: [String]
  let tagNames: [String]

  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil
  mutating func preserveUnchangedBounds(from original: VehicleEntry?) {
    guard let original, original.datePrecision == datePrecision,
      original.occurredTimezone == occurredTimezone
    else { return }
    if original.occurredStart == occurredStart { occurredStartRaw = original.occurredStartRaw }
    if original.occurredEnd == occurredEnd { occurredEndRaw = original.occurredEndRaw }
  }

  static func validate(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    occurredStart: Date?,
    occurredEnd: Date?,
    datePrecision: VehicleDatePrecision,
    occurredLabel: String,
    occurredTimezone: String,
    make: String,
    model: String,
    modelYear: Int?,
    color: String,
    collectionNames: [String],
    tagNames: [String]
  ) throws -> VehicleEntryInput {
    let title = title.trimmed
    let body = body.trimmed
    let occurredLabel = occurredLabel.trimmed.nonEmpty
    let occurredTimezone = occurredTimezone.trimmed
    let make = make.trimmed.nonEmpty
    let model = model.trimmed.nonEmpty
    let color = color.trimmed.nonEmpty

    guard !title.isEmpty else { throw VehicleEntryError.titleRequired }
    guard title.count <= titleLimit else { throw VehicleEntryError.titleTooLong }
    guard body.count <= bodyLimit else { throw VehicleEntryError.bodyTooLong }
    guard (occurredLabel?.count ?? 0) <= labelLimit else { throw VehicleEntryError.labelTooLong }
    guard (make?.count ?? 0) <= makeLimit, (model?.count ?? 0) <= modelLimit,
      (color?.count ?? 0) <= colorLimit
    else { throw VehicleEntryError.factsTooLong }
    guard modelYear.map({ 1886...2200 ~= $0 }) ?? true else {
      throw VehicleEntryError.invalidModelYear
    }
    guard occurredStart?.timeIntervalSinceReferenceDate.isFinite ?? true,
      occurredEnd?.timeIntervalSinceReferenceDate.isFinite ?? true
    else { throw VehicleEntryError.invalidDate }
    guard occurredEnd.map({ end in occurredStart.map { end >= $0 } ?? false }) ?? true else {
      throw VehicleEntryError.reversedRange
    }
    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100,
      TimeZone(identifier: occurredTimezone) != nil
    else { throw VehicleEntryError.invalidTimezone }
    guard
      (entryID == nil && expectedRevision == nil)
        || (entryID != nil && (expectedRevision ?? 0) > 0)
    else { throw VehicleEntryError.invalidRevision }
    guard
      let collectionNames = normalizeNames(
        collectionNames,
        maximumCount: collectionLimit,
        maximumNameLength: collectionNameLimit
      )
    else { throw VehicleEntryError.invalidCollections }
    guard
      let tagNames = normalizeNames(
        tagNames,
        maximumCount: tagLimit,
        maximumNameLength: tagNameLimit
      )
    else { throw VehicleEntryError.invalidTags }

    try EntryOccurrence(
      precision: datePrecision, start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone
    ).validate(span: true)
    return VehicleEntryInput(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      make: make,
      model: model,
      modelYear: modelYear,
      color: color,
      collectionNames: collectionNames,
      tagNames: tagNames
    )
  }

  private static func normalizeNames(
    _ values: [String],
    maximumCount: Int,
    maximumNameLength: Int
  ) -> [String]? {
    guard values.count <= maximumCount else { return nil }
    var names: [String] = []
    var normalizedNames: Set<String> = []
    for value in values {
      let name = value.trimmed
      guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
      if normalizedNames.insert(name.lowercased()).inserted { names.append(name) }
    }
    return names
  }
}

struct SaveVehicleEntryParameters: Encodable, Equatable, Sendable {
  let input: VehicleEntryInput

  enum CodingKeys: String, CodingKey {
    case title = "p_title"
    case body = "p_body"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case datePrecision = "p_date_precision"
    case occurredLabel = "p_occurred_label"
    case occurredTimezone = "p_occurred_timezone"
    case make = "p_make"
    case model = "p_model"
    case modelYear = "p_model_year"
    case color = "p_color"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.title, forKey: .title)
    try values.encode(input.body, forKey: .body)
    if let raw = input.occurredStartRaw {
      try values.encode(raw, forKey: .occurredStart)
    } else {
      try encodeNullable(input.occurredStart, forKey: .occurredStart, into: &values)
    }
    try values.encode(input.datePrecision, forKey: .datePrecision)
    try values.encode(input.occurredTimezone, forKey: .occurredTimezone)
    try values.encode(input.collectionNames, forKey: .collectionNames)
    try values.encode(input.tagNames, forKey: .tagNames)
    if let raw = input.occurredEndRaw {
      try values.encode(raw, forKey: .occurredEnd)
    } else {
      try encodeNullable(input.occurredEnd, forKey: .occurredEnd, into: &values)
    }
    try encodeNullable(input.occurredLabel, forKey: .occurredLabel, into: &values)
    try encodeNullable(input.make, forKey: .make, into: &values)
    try encodeNullable(input.model, forKey: .model, into: &values)
    try encodeNullable(input.modelYear, forKey: .modelYear, into: &values)
    try encodeNullable(input.color, forKey: .color, into: &values)
    try encodeNullable(input.entryID, forKey: .entryID, into: &values)
    try encodeNullable(input.expectedRevision, forKey: .expectedRevision, into: &values)
  }

  private func encodeNullable<T: Encodable>(
    _ value: T?,
    forKey key: CodingKeys,
    into values: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if let value {
      try values.encode(value, forKey: key)
    } else {
      try values.encodeNil(forKey: key)
    }
  }
}

struct SavedVehicleEntry: Decodable, Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let wasCreated: Bool

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
    case wasCreated = "was_created"
  }
}

struct TrashVehicleEntryParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TrashedVehicleEntry: Decodable, Sendable {
  let entryID: UUID

  enum CodingKeys: String, CodingKey { case entryID = "entry_id" }
}

struct VehicleOrganizationName: Decodable, Sendable { let name: String }

enum VehicleEntryError: LocalizedError, Equatable {
  case bodyTooLong
  case factsTooLong
  case invalidCollections
  case invalidDate
  case invalidModelYear
  case invalidRevision
  case invalidTags
  case invalidTimezone
  case labelTooLong
  case reversedRange
  case titleRequired
  case titleTooLong

  var errorDescription: String? {
    switch self {
    case .bodyTooLong: "Memories can be up to \(VehicleEntryInput.bodyLimit) characters."
    case .factsTooLong: "One of this Vehicle's facts is too long."
    case .invalidCollections: "Use up to 20 Collections with names under 80 characters."
    case .invalidDate: "Choose valid start and end dates."
    case .invalidModelYear: "Use a model year from 1886 to 2200, or leave it empty."
    case .invalidRevision: "This Vehicle version is invalid. Refresh and try again."
    case .invalidTags: "Use up to 50 tags with names under 60 characters."
    case .invalidTimezone: "Choose a valid occurrence time zone."
    case .labelTooLong:
      "Human date labels can be up to \(VehicleEntryInput.labelLimit) characters."
    case .reversedRange: "The end date must be on or after the start date."
    case .titleRequired: "Add a name or nickname for this Vehicle."
    case .titleTooLong: "Vehicle names can be up to \(VehicleEntryInput.titleLimit) characters."
    }
  }
}

extension VehicleWorkspaceRow {
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    entryID = try values.decode(UUID.self, forKey: .entryID)
    title = try values.decode(String.self, forKey: .title)
    body = try values.decode(String.self, forKey: .body)
    occurredStart = try values.decodeIfPresent(Date.self, forKey: .occurredStart)
    occurredEnd = try values.decodeIfPresent(Date.self, forKey: .occurredEnd)
    datePrecision = try values.decode(VehicleDatePrecision.self, forKey: .datePrecision)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    make = try values.decodeIfPresent(String.self, forKey: .make)
    model = try values.decodeIfPresent(String.self, forKey: .model)
    modelYear = try values.decodeIfPresent(Int.self, forKey: .modelYear)
    color = try values.decodeIfPresent(String.self, forKey: .color)
    timelineTrackID = try values.decodeIfPresent(UUID.self, forKey: .timelineTrackID)
    timelineTrackName = try values.decodeIfPresent(String.self, forKey: .timelineTrackName)
    collectionNames = try values.decode([String].self, forKey: .collectionNames)
    tagNames = try values.decode([String].self, forKey: .tagNames)
    attachments = try values.decode([VehicleAttachment].self, forKey: .attachments)
    totalCount = try values.decode(Int.self, forKey: .totalCount)
    occurredStartRaw = try values.decodeIfPresent(String.self, forKey: .occurredStart)
    occurredEndRaw = try values.decodeIfPresent(String.self, forKey: .occurredEnd)
  }
}
