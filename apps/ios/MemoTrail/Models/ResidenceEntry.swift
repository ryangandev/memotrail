import Foundation

enum ResidenceDatePrecision: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case exact
  case day
  case month
  case year
  case approximate
  case age
  case range

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
    }
  }
}

struct ResidenceAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let bucketID: String
  let objectPath: String
  let originalFilename: String?
  let mimeType: FirstTimeImageType
  let byteSize: Int64
  let pixelWidth: Int?
  let pixelHeight: Int?
  let createdAt: Date
  var signedURL: URL?

  enum CodingKeys: String, CodingKey {
    case id
    case bucketID = "bucket_id"
    case objectPath = "object_path"
    case originalFilename = "original_filename"
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case pixelWidth = "pixel_width"
    case pixelHeight = "pixel_height"
    case createdAt = "created_at"
  }
}

struct ResidenceEntry: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String
  let body: String
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: ResidenceDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let revision: Int
  let updatedAt: Date
  let moveInReason: String?
  let moveOutReason: String?
  let placeID: UUID
  let placeName: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let placeNotes: String?
  let timelineTrackID: UUID?
  let timelineTrackName: String?
  let collectionNames: [String]
  let tagNames: [String]
  var attachments: [ResidenceAttachment]
  let totalCount: Int

  var isCurrent: Bool { occurredEnd == nil }

  var displayLocation: String {
    var seen: Set<String> = []
    let parts = [city, region, country].compactMap { value -> String? in
      guard let value = value?.trimmed.nonEmpty, seen.insert(value).inserted else { return nil }
      return value
    }
    return parts.isEmpty ? placeName : parts.joined(separator: ", ")
  }

  var displayRange: String {
    if let occurredLabel = occurredLabel?.trimmed.nonEmpty {
      return occurredLabel
    }

    let start = formatted(occurredStart)
    guard let occurredEnd else { return "Since \(start)" }
    return "\(start) - \(formatted(occurredEnd))"
  }

  func durationLabel(now: Date = Date()) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: occurredTimezone) ?? .gmt
    let start = calendar.dateComponents([.year, .month, .day], from: occurredStart)
    let end = calendar.dateComponents([.year, .month, .day], from: occurredEnd ?? now)

    guard let startYear = start.year, let startMonth = start.month, let startDay = start.day,
      let endYear = end.year, let endMonth = end.month, let endDay = end.day
    else {
      return "Duration unavailable"
    }

    var months = (endYear - startYear) * 12 + endMonth - startMonth
    if endDay < startDay { months -= 1 }
    months = max(0, months)

    guard months > 0 else { return "Less than a month" }

    let years = months / 12
    let remainingMonths = months % 12
    var parts: [String] = []
    if years > 0 { parts.append("\(years) \(years == 1 ? "year" : "years")") }
    if remainingMonths > 0 {
      parts.append(
        "\(remainingMonths) \(remainingMonths == 1 ? "month" : "months")")
    }
    return parts.joined(separator: " ")
  }

  private func formatted(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(identifier: occurredTimezone) ?? .gmt

    switch datePrecision {
    case .year:
      formatter.setLocalizedDateFormatFromTemplate("yyyy")
    case .month, .approximate, .age, .range:
      formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    case .exact, .day:
      formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
    }

    return formatter.string(from: date)
  }
}

struct ResidenceWorkspaceRow: Decodable, Equatable, Sendable {
  let entryID: UUID
  let title: String
  let body: String
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: ResidenceDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let revision: Int
  let updatedAt: Date
  let moveInReason: String?
  let moveOutReason: String?
  let placeID: UUID
  let placeName: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let placeNotes: String?
  let timelineTrackID: UUID?
  let timelineTrackName: String?
  let collectionNames: [String]
  let tagNames: [String]
  let attachments: [ResidenceAttachment]
  let totalCount: Int

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
    case moveInReason = "move_in_reason"
    case moveOutReason = "move_out_reason"
    case placeID = "place_id"
    case placeName = "place_name"
    case address
    case city
    case region
    case country
    case latitude
    case longitude
    case placeNotes = "place_notes"
    case timelineTrackID = "timeline_track_id"
    case timelineTrackName = "timeline_track_name"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case attachments
    case totalCount = "total_count"
  }

  var entry: ResidenceEntry {
    ResidenceEntry(
      id: entryID,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel?.trimmed.nonEmpty,
      occurredTimezone: occurredTimezone,
      revision: revision,
      updatedAt: updatedAt,
      moveInReason: moveInReason?.trimmed.nonEmpty,
      moveOutReason: moveOutReason?.trimmed.nonEmpty,
      placeID: placeID,
      placeName: placeName,
      address: address?.trimmed.nonEmpty,
      city: city?.trimmed.nonEmpty,
      region: region?.trimmed.nonEmpty,
      country: country?.trimmed.nonEmpty,
      latitude: latitude,
      longitude: longitude,
      placeNotes: placeNotes?.trimmed.nonEmpty,
      timelineTrackID: timelineTrackID,
      timelineTrackName: timelineTrackName?.trimmed.nonEmpty,
      collectionNames: collectionNames,
      tagNames: tagNames,
      attachments: attachments,
      totalCount: totalCount
    )
  }
}

struct ResidencePlace: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let notes: String?
}

enum ResidenceWorkspace {
  static func entries(from rows: [ResidenceWorkspaceRow]) -> [ResidenceEntry] {
    rows.map(\.entry).sorted {
      if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
      if $0.occurredStart != $1.occurredStart { return $0.occurredStart > $1.occurredStart }
      let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
      return titleOrder == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString : titleOrder == .orderedAscending
    }
  }
}

struct ResidenceEntryInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000
  static let labelLimit = 200
  static let placeNameLimit = 200
  static let addressLimit = 500
  static let locationLimit = 200
  static let detailLimit = 10_000
  static let collectionLimit = 20
  static let collectionNameLimit = 80
  static let tagLimit = 50
  static let tagNameLimit = 60

  let entryID: UUID?
  let expectedRevision: Int?
  let title: String
  let body: String
  let occurredStart: Date
  let occurredEnd: Date?
  let datePrecision: ResidenceDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String
  let placeID: UUID?
  let placeName: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let placeNotes: String?
  let moveInReason: String?
  let moveOutReason: String?
  let collectionNames: [String]
  let tagNames: [String]

  static func validate(
    entryID: UUID?,
    expectedRevision: Int?,
    title: String,
    body: String,
    occurredStart: Date,
    occurredEnd: Date?,
    datePrecision: ResidenceDatePrecision,
    occurredLabel: String,
    occurredTimezone: String,
    placeID: UUID?,
    placeName: String,
    address: String,
    city: String,
    region: String,
    country: String,
    latitude: Double?,
    longitude: Double?,
    placeNotes: String,
    moveInReason: String,
    moveOutReason: String,
    collectionNames: [String],
    tagNames: [String]
  ) throws -> ResidenceEntryInput {
    let title = title.trimmed
    let body = body.trimmed
    let placeName = placeName.trimmed
    let address = address.trimmed.nonEmpty
    let city = city.trimmed.nonEmpty
    let region = region.trimmed.nonEmpty
    let country = country.trimmed.nonEmpty
    let placeNotes = placeNotes.trimmed.nonEmpty
    let moveInReason = moveInReason.trimmed.nonEmpty
    let moveOutReason = moveOutReason.trimmed.nonEmpty
    let occurredLabel = occurredLabel.trimmed.nonEmpty
    let occurredTimezone = occurredTimezone.trimmed

    guard !title.isEmpty else { throw ResidenceEntryError.titleRequired }
    guard title.count <= titleLimit else { throw ResidenceEntryError.titleTooLong }
    guard body.count <= bodyLimit else { throw ResidenceEntryError.bodyTooLong }
    guard !placeName.isEmpty else { throw ResidenceEntryError.placeRequired }
    guard placeName.count <= placeNameLimit else { throw ResidenceEntryError.placeTooLong }
    guard (address?.count ?? 0) <= addressLimit,
      (city?.count ?? 0) <= locationLimit,
      (region?.count ?? 0) <= locationLimit,
      (country?.count ?? 0) <= locationLimit,
      (placeNotes?.count ?? 0) <= detailLimit,
      (moveInReason?.count ?? 0) <= detailLimit,
      (moveOutReason?.count ?? 0) <= detailLimit
    else {
      throw ResidenceEntryError.detailsTooLong
    }
    guard (occurredLabel?.count ?? 0) <= labelLimit else {
      throw ResidenceEntryError.labelTooLong
    }
    guard occurredStart.timeIntervalSinceReferenceDate.isFinite,
      occurredEnd?.timeIntervalSinceReferenceDate.isFinite ?? true
    else {
      throw ResidenceEntryError.invalidDate
    }
    guard occurredEnd.map({ $0 >= occurredStart }) ?? true else {
      throw ResidenceEntryError.reversedRange
    }
    guard moveOutReason == nil || occurredEnd != nil else {
      throw ResidenceEntryError.moveOutRequiresDate
    }
    guard !occurredTimezone.isEmpty, occurredTimezone.count <= 100,
      TimeZone(identifier: occurredTimezone) != nil
    else {
      throw ResidenceEntryError.invalidTimezone
    }
    guard (latitude == nil) == (longitude == nil),
      latitude.map({ $0.isFinite && (-90...90).contains($0) }) ?? true,
      longitude.map({ $0.isFinite && (-180...180).contains($0) }) ?? true
    else {
      throw ResidenceEntryError.invalidCoordinates
    }
    guard
      (entryID == nil && expectedRevision == nil)
        || (entryID != nil && (expectedRevision ?? 0) > 0)
    else {
      throw ResidenceEntryError.invalidRevision
    }
    guard
      let collectionNames = normalizeNames(
        collectionNames,
        maximumCount: collectionLimit,
        maximumNameLength: collectionNameLimit
      )
    else {
      throw ResidenceEntryError.invalidCollections
    }
    guard
      let tagNames = normalizeNames(
        tagNames,
        maximumCount: tagLimit,
        maximumNameLength: tagNameLimit
      )
    else {
      throw ResidenceEntryError.invalidTags
    }

    return ResidenceEntryInput(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      occurredEnd: occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      placeID: placeID,
      placeName: placeName,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: latitude,
      longitude: longitude,
      placeNotes: placeNotes,
      moveInReason: moveInReason,
      moveOutReason: moveOutReason,
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

struct SaveResidenceEntryParameters: Encodable, Equatable, Sendable {
  let input: ResidenceEntryInput

  enum CodingKeys: String, CodingKey {
    case title = "p_title"
    case body = "p_body"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case datePrecision = "p_date_precision"
    case occurredLabel = "p_occurred_label"
    case occurredTimezone = "p_occurred_timezone"
    case placeID = "p_place_id"
    case placeName = "p_place_name"
    case address = "p_address"
    case city = "p_city"
    case region = "p_region"
    case country = "p_country"
    case latitude = "p_latitude"
    case longitude = "p_longitude"
    case placeNotes = "p_place_notes"
    case moveInReason = "p_move_in_reason"
    case moveOutReason = "p_move_out_reason"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.title, forKey: .title)
    try values.encode(input.body, forKey: .body)
    try values.encode(input.occurredStart, forKey: .occurredStart)
    try values.encode(input.datePrecision, forKey: .datePrecision)
    try values.encode(input.occurredTimezone, forKey: .occurredTimezone)
    try values.encode(input.placeName, forKey: .placeName)
    try values.encode(input.collectionNames, forKey: .collectionNames)
    try values.encode(input.tagNames, forKey: .tagNames)
    try encodeNullable(input.occurredEnd, forKey: .occurredEnd, into: &values)
    try encodeNullable(input.occurredLabel, forKey: .occurredLabel, into: &values)
    try encodeNullable(input.placeID, forKey: .placeID, into: &values)
    try encodeNullable(input.address, forKey: .address, into: &values)
    try encodeNullable(input.city, forKey: .city, into: &values)
    try encodeNullable(input.region, forKey: .region, into: &values)
    try encodeNullable(input.country, forKey: .country, into: &values)
    try encodeNullable(input.latitude, forKey: .latitude, into: &values)
    try encodeNullable(input.longitude, forKey: .longitude, into: &values)
    try encodeNullable(input.placeNotes, forKey: .placeNotes, into: &values)
    try encodeNullable(input.moveInReason, forKey: .moveInReason, into: &values)
    try encodeNullable(input.moveOutReason, forKey: .moveOutReason, into: &values)
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

struct SavedResidenceEntry: Decodable, Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let placeID: UUID
  let wasCreated: Bool

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
    case placeID = "place_id"
    case wasCreated = "was_created"
  }
}

struct TrashResidenceEntryParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TrashedResidenceEntry: Decodable, Sendable {
  let entryID: UUID

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
  }
}

struct RegisterResidenceAttachmentParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let draft: FirstTimePhotoDraft
  let objectPath: String

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case attachmentID = "p_attachment_id"
    case objectPath = "p_object_path"
    case originalFilename = "p_original_filename"
    case mimeType = "p_mime_type"
    case byteSize = "p_byte_size"
    case pixelWidth = "p_pixel_width"
    case pixelHeight = "p_pixel_height"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(entryID, forKey: .entryID)
    try values.encode(draft.id, forKey: .attachmentID)
    try values.encode(objectPath, forKey: .objectPath)
    try values.encode(draft.mimeType, forKey: .mimeType)
    try values.encode(Int64(draft.data.count), forKey: .byteSize)
    try values.encodeIfPresent(draft.originalFilename, forKey: .originalFilename)
    if draft.originalFilename == nil { try values.encodeNil(forKey: .originalFilename) }
    try values.encodeIfPresent(draft.pixelWidth, forKey: .pixelWidth)
    if draft.pixelWidth == nil { try values.encodeNil(forKey: .pixelWidth) }
    try values.encodeIfPresent(draft.pixelHeight, forKey: .pixelHeight)
    if draft.pixelHeight == nil { try values.encodeNil(forKey: .pixelHeight) }
  }
}

struct RegisteredResidenceAttachment: Decodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
  }
}

struct TrashResidenceAttachmentParameters: Encodable, Equatable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "p_attachment_id"
  }
}

struct TrashedResidenceAttachment: Decodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
  }
}

struct ResidenceOrganizationName: Decodable, Sendable {
  let name: String
}

enum ResidenceEntryError: LocalizedError, Equatable {
  case bodyTooLong
  case detailsTooLong
  case invalidCollections
  case invalidCoordinates
  case invalidDate
  case invalidRevision
  case invalidTags
  case invalidTimezone
  case labelTooLong
  case moveOutRequiresDate
  case placeRequired
  case placeTooLong
  case reversedRange
  case titleRequired
  case titleTooLong

  var errorDescription: String? {
    switch self {
    case .bodyTooLong:
      "Memories can be up to \(ResidenceEntryInput.bodyLimit) characters."
    case .detailsTooLong:
      "One of this Home's Place or move details is too long."
    case .invalidCollections:
      "Use up to 20 Collections with names under 80 characters."
    case .invalidCoordinates:
      "Add valid latitude and longitude together, or leave both empty."
    case .invalidDate:
      "Choose valid move-in and move-out dates."
    case .invalidRevision:
      "This Home version is invalid. Refresh and try again."
    case .invalidTags:
      "Use up to 50 tags with names under 60 characters."
    case .invalidTimezone:
      "Choose a valid occurrence time zone."
    case .labelTooLong:
      "Human date labels can be up to \(ResidenceEntryInput.labelLimit) characters."
    case .moveOutRequiresDate:
      "Add a move-out date before recording why you left."
    case .placeRequired:
      "Add a Place name for this Home."
    case .placeTooLong:
      "Place names can be up to \(ResidenceEntryInput.placeNameLimit) characters."
    case .reversedRange:
      "The move-out date must be on or after the move-in date."
    case .titleRequired:
      "Add a name for this Home."
    case .titleTooLong:
      "Home names can be up to \(ResidenceEntryInput.titleLimit) characters."
    }
  }
}
