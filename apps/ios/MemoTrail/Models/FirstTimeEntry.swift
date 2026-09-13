import Foundation

enum FirstTimeDatePrecision: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
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

  var supportsMissingDate: Bool {
    self == .approximate || self == .age || self == .unknown
  }
}

enum FirstTimeImageType: String, Codable, Equatable, Hashable, Sendable {
  case heic = "image/heic"
  case heif = "image/heif"
  case jpeg = "image/jpeg"
  case png = "image/png"
  case webp = "image/webp"

  var fileExtension: String {
    switch self {
    case .heic:
      "heic"
    case .heif:
      "heif"
    case .jpeg:
      "jpg"
    case .png:
      "png"
    case .webp:
      "webp"
    }
  }

  static func detect(data: Data, typeIdentifiers: [String]) -> FirstTimeImageType? {
    let bytes = [UInt8](data.prefix(12))

    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
      return .jpeg
    }
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      return .png
    }
    if bytes.count >= 12,
      String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
      String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP"
    {
      return .webp
    }
    if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
      switch String(bytes: bytes[8..<12], encoding: .ascii) {
      case "heic", "heix", "hevc", "hevx":
        return .heic
      case "heif", "mif1", "msf1":
        return .heif
      default:
        break
      }
    }

    if typeIdentifiers.contains("public.jpeg") { return .jpeg }
    if typeIdentifiers.contains("public.png") { return .png }
    if typeIdentifiers.contains("org.webmproject.webp") { return .webp }
    if typeIdentifiers.contains("public.heic") { return .heic }
    if typeIdentifiers.contains("public.heif") { return .heif }
    return nil
  }
}

enum FirstTimeAttachmentVariant: String, Codable, Equatable, Hashable, Sendable {
  case display
  case original
  case thumbnail
}

struct FirstTimeAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let parentAttachmentID: UUID?
  let variant: FirstTimeAttachmentVariant
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
    case parentAttachmentID = "parentAttachmentId"
    case variant
    case bucketID = "bucketId"
    case objectPath
    case originalFilename
    case mimeType
    case byteSize
    case pixelWidth
    case pixelHeight
    case createdAt
  }
}

struct FirstTimeEntry: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String
  let body: String
  let inboxStatus: String
  let occurredStart: Date?
  let datePrecision: FirstTimeDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date
  let collectionNames: [String]
  let tagNames: [String]
  var attachments: [FirstTimeAttachment]
  var occurredEnd: Date? = nil
  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil

  var occurrence: EntryOccurrence {
    EntryOccurrence(
      precision: TimelineDatePrecision(rawValue: datePrecision.rawValue) ?? .unknown,
      start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone ?? "UTC")
  }

  var displayDate: String { occurrence.displayLabel }
}

struct FirstTimeWorkspaceRow: Decodable, Equatable, Sendable {
  let entryID: UUID
  let title: String
  let body: String
  let inboxStatus: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: FirstTimeDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date
  let collectionNames: [String]
  let tagNames: [String]
  let attachments: [FirstTimeAttachment]
  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case title
    case body
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case updatedAt = "updated_at"
    case collectionNames = "collection_names"
    case tagNames = "tag_names"
    case attachments
  }

  var entry: FirstTimeEntry {
    FirstTimeEntry(
      id: entryID,
      title: title,
      body: body,
      inboxStatus: inboxStatus,
      occurredStart: occurredStart,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel?.trimmed.nonEmpty,
      occurredTimezone: occurredTimezone?.trimmed.nonEmpty,
      revision: revision,
      updatedAt: updatedAt,
      collectionNames: collectionNames,
      tagNames: tagNames,
      attachments: attachments,
      occurredEnd: occurredEnd,
      occurredStartRaw: occurredStartRaw,
      occurredEndRaw: occurredEndRaw
    )
  }
}

extension FirstTimeWorkspaceRow {
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    entryID = try values.decode(UUID.self, forKey: .entryID)
    title = try values.decode(String.self, forKey: .title)
    body = try values.decode(String.self, forKey: .body)
    inboxStatus = try values.decode(String.self, forKey: .inboxStatus)
    occurredStart = try values.decodeIfPresent(Date.self, forKey: .occurredStart)
    occurredEnd = try values.decodeIfPresent(Date.self, forKey: .occurredEnd)
    occurredStartRaw = try values.decodeIfPresent(String.self, forKey: .occurredStart)
    occurredEndRaw = try values.decodeIfPresent(String.self, forKey: .occurredEnd)
    datePrecision = try values.decode(FirstTimeDatePrecision.self, forKey: .datePrecision)
    occurredLabel = try values.decodeIfPresent(String.self, forKey: .occurredLabel)
    occurredTimezone = try values.decodeIfPresent(String.self, forKey: .occurredTimezone)
    revision = try values.decode(Int.self, forKey: .revision)
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    collectionNames = try values.decode([String].self, forKey: .collectionNames)
    tagNames = try values.decode([String].self, forKey: .tagNames)
    attachments = try values.decode([FirstTimeAttachment].self, forKey: .attachments)
  }
}

enum FirstTimesWorkspace {
  static func entries(from rows: [FirstTimeWorkspaceRow]) -> [FirstTimeEntry] {
    rows.map(\.entry).sorted {
      switch ($0.occurredStart, $1.occurredStart) {
      case (let left?, let right?):
        left == right
          ? $0.updatedAt > $1.updatedAt
          : left > right
      case (_?, nil):
        true
      case (nil, _?):
        false
      case (nil, nil):
        $0.updatedAt > $1.updatedAt
      }
    }
  }
}

struct FirstTimeEntryInput: Equatable, Sendable {
  static let titleLimit = 200
  static let bodyLimit = 50_000
  static let labelLimit = 200
  static let collectionLimit = 20
  static let collectionNameLimit = 80
  static let tagLimit = 50
  static let tagNameLimit = 60

  let entryID: UUID?
  var expectedRevision: Int?
  let title: String
  let body: String
  let occurredStart: Date?
  let datePrecision: FirstTimeDatePrecision
  let occurredLabel: String?
  let occurredTimezone: String?
  let collectionNames: [String]
  let tagNames: [String]
  var occurredEnd: Date? = nil
  var occurredStartRaw: String? = nil
  var occurredEndRaw: String? = nil

  mutating func preserveUnchangedBounds(from original: FirstTimeEntry?) {
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
    datePrecision: FirstTimeDatePrecision,
    occurredLabel: String,
    occurredTimezone: String?,
    collectionNames: [String],
    tagNames: [String],
    occurredEnd: Date? = nil
  ) throws -> FirstTimeEntryInput {
    let title = title.trimmed
    let body = body.trimmed
    let occurredLabel = occurredLabel.trimmed.nonEmpty
    let occurredTimezone = occurredTimezone?.trimmed.nonEmpty

    guard !title.isEmpty else { throw FirstTimeEntryError.titleRequired }
    guard title.count <= titleLimit else { throw FirstTimeEntryError.titleTooLong }
    guard body.count <= bodyLimit else { throw FirstTimeEntryError.bodyTooLong }
    guard (occurredLabel?.count ?? 0) <= labelLimit else {
      throw FirstTimeEntryError.labelTooLong
    }
    guard occurredStart?.timeIntervalSinceReferenceDate.isFinite ?? true else {
      throw FirstTimeEntryError.invalidDate
    }

    if occurredStart == nil {
      guard datePrecision.supportsMissingDate, occurredTimezone == nil else {
        throw FirstTimeEntryError.invalidOccurrence
      }
    } else {
      guard let occurredTimezone, occurredTimezone.count <= 100 else {
        throw FirstTimeEntryError.invalidTimezone
      }
    }

    try EntryOccurrence(
      precision: TimelineDatePrecision(rawValue: datePrecision.rawValue) ?? .unknown,
      start: occurredStart, end: occurredEnd, label: occurredLabel,
      timezone: occurredTimezone ?? "UTC"
    ).validate()

    guard
      (entryID == nil && expectedRevision == nil)
        || (entryID != nil && (expectedRevision ?? 0) > 0)
    else {
      throw FirstTimeEntryError.invalidRevision
    }

    guard
      let collectionNames = normalizeNames(
        collectionNames,
        maximumCount: collectionLimit,
        maximumNameLength: collectionNameLimit
      )
    else {
      throw FirstTimeEntryError.invalidCollections
    }

    guard
      let tagNames = normalizeNames(
        tagNames,
        maximumCount: tagLimit,
        maximumNameLength: tagNameLimit
      )
    else {
      throw FirstTimeEntryError.invalidTags
    }

    return FirstTimeEntryInput(
      entryID: entryID,
      expectedRevision: expectedRevision,
      title: title,
      body: body,
      occurredStart: occurredStart,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      collectionNames: collectionNames,
      tagNames: tagNames,
      occurredEnd: occurredEnd
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

      if normalizedNames.insert(name.lowercased()).inserted {
        names.append(name)
      }
    }

    return names
  }
}

struct SaveFirstTimeEntryParameters: Encodable, Equatable, Sendable {
  let input: FirstTimeEntryInput

  enum CodingKeys: String, CodingKey {
    case title = "p_title"
    case body = "p_body"
    case occurredStart = "p_occurred_start"
    case occurredEnd = "p_occurred_end"
    case datePrecision = "p_date_precision"
    case occurredLabel = "p_occurred_label"
    case occurredTimezone = "p_occurred_timezone"
    case collectionNames = "p_collection_names"
    case tagNames = "p_tag_names"
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.title, forKey: .title)
    try values.encode(input.body, forKey: .body)
    try values.encode(input.datePrecision, forKey: .datePrecision)
    try values.encode(input.collectionNames, forKey: .collectionNames)
    try values.encode(input.tagNames, forKey: .tagNames)
    if let raw = input.occurredStartRaw {
      try values.encode(raw, forKey: .occurredStart)
    } else {
      try values.encode(input.occurredStart, forKey: .occurredStart)
    }
    if let raw = input.occurredEndRaw {
      try values.encode(raw, forKey: .occurredEnd)
    } else {
      try values.encode(input.occurredEnd, forKey: .occurredEnd)
    }
    try values.encodeIfPresent(input.occurredLabel, forKey: .occurredLabel)
    if input.occurredLabel == nil { try values.encodeNil(forKey: .occurredLabel) }
    try values.encodeIfPresent(input.occurredTimezone, forKey: .occurredTimezone)
    if input.occurredTimezone == nil { try values.encodeNil(forKey: .occurredTimezone) }
    try values.encodeIfPresent(input.entryID, forKey: .entryID)
    if input.entryID == nil { try values.encodeNil(forKey: .entryID) }
    try values.encodeIfPresent(input.expectedRevision, forKey: .expectedRevision)
    if input.expectedRevision == nil { try values.encodeNil(forKey: .expectedRevision) }
  }
}

struct SavedFirstTimeEntry: Decodable, Equatable, Sendable {
  let entryID: UUID
  let revision: Int
  let wasCreated: Bool

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
    case revision
    case wasCreated = "was_created"
  }
}

struct FirstTimePhotoDraft: Equatable, Identifiable, Sendable {
  static let maximumCount = 12
  static let maximumByteSize = 50 * 1_024 * 1_024

  let id: UUID
  let data: Data
  let mimeType: FirstTimeImageType
  let originalFilename: String?
  let pixelWidth: Int?
  let pixelHeight: Int?

  static func validate(
    id: UUID = UUID(),
    data: Data,
    mimeType: FirstTimeImageType,
    originalFilename: String?,
    pixelWidth: Int?,
    pixelHeight: Int?
  ) throws -> FirstTimePhotoDraft {
    let filename = originalFilename?.trimmed.nonEmpty

    guard !data.isEmpty, data.count <= maximumByteSize else {
      throw FirstTimeEntryError.invalidPhotoSize
    }
    guard (filename?.count ?? 0) <= 255 else {
      throw FirstTimeEntryError.photoFilenameTooLong
    }
    guard pixelWidth.map({ $0 > 0 }) ?? true, pixelHeight.map({ $0 > 0 }) ?? true else {
      throw FirstTimeEntryError.invalidPhotoDimensions
    }

    return FirstTimePhotoDraft(
      id: id,
      data: data,
      mimeType: mimeType,
      originalFilename: filename,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    )
  }

  func objectPath(ownerID: UUID, entryID: UUID) -> String {
    "\(ownerID.uuidString.lowercased())/\(entryID.uuidString.lowercased())/\(id.uuidString.lowercased()).\(mimeType.fileExtension)"
  }
}

struct RegisterFirstTimeAttachmentParameters: Encodable, Equatable, Sendable {
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

struct RegisteredFirstTimeAttachment: Decodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
  }
}

struct TrashFirstTimeEntryParameters: Encodable, Sendable {
  let entryID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TrashFirstTimeAttachmentParameters: Encodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "p_attachment_id"
  }
}

struct TrashedFirstTimeAttachment: Decodable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
  }
}

struct TrashedFirstTimeEntry: Decodable, Sendable {
  let entryID: UUID

  enum CodingKeys: String, CodingKey {
    case entryID = "entry_id"
  }
}

struct FirstTimeOrganizationName: Decodable, Sendable {
  let name: String
}

enum FirstTimeEntryError: LocalizedError, Equatable {
  case bodyTooLong
  case invalidCollections
  case invalidDate
  case invalidOccurrence
  case invalidPhotoDimensions
  case invalidPhotoSize
  case invalidRevision
  case invalidTags
  case invalidTimezone
  case labelTooLong
  case photoFilenameTooLong
  case titleRequired
  case titleTooLong
  case unsupportedPhotoType

  var errorDescription: String? {
    switch self {
    case .bodyTooLong:
      "Notes can be up to \(FirstTimeEntryInput.bodyLimit) characters."
    case .invalidCollections:
      "Use up to 20 Collections with names under 80 characters."
    case .invalidDate:
      "Choose a valid date or leave it empty."
    case .invalidOccurrence:
      "Add a date, or use Approximate, Age-based, or Unknown precision."
    case .invalidPhotoDimensions:
      "This photo has invalid dimensions."
    case .invalidPhotoSize:
      "Each photo must be no larger than 50 MB."
    case .invalidRevision:
      "This First Time version is invalid. Refresh and try again."
    case .invalidTags:
      "Use up to 50 tags with names under 60 characters."
    case .invalidTimezone:
      "Choose a valid occurrence time zone."
    case .labelTooLong:
      "Human date labels can be up to \(FirstTimeEntryInput.labelLimit) characters."
    case .photoFilenameTooLong:
      "Photo filenames can be up to 255 characters."
    case .titleRequired:
      "Add a title for this First Time."
    case .titleTooLong:
      "Titles can be up to \(FirstTimeEntryInput.titleLimit) characters."
    case .unsupportedPhotoType:
      "Use a JPEG, PNG, WebP, HEIC, or HEIF image."
    }
  }
}
