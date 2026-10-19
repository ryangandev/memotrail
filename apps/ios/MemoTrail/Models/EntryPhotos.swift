import Foundation
@preconcurrency import Supabase

// Photos on an Entry, like Web `entry-photo-input.ts`, `inbox-photo.ts`, and
// `/api/media/photos`. Originals live in the private `entry-media` bucket at
// `<owner>/<entry>/<attachment>.<extension>` with lowercase identifiers.

/// The image formats MemoTrail accepts, like Web `entryImageMimeTypes`.
enum PhotoImageType: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case heic = "image/heic"
  case heif = "image/heif"
  case jpeg = "image/jpeg"
  case png = "image/png"
  case webp = "image/webp"

  var fileExtension: String {
    switch self {
    case .heic: "heic"
    case .heif: "heif"
    case .jpeg: "jpg"
    case .png: "png"
    case .webp: "webp"
    }
  }

  /// The type the file's bytes declare, then the type its picker reported.
  static func detect(data: Data, typeIdentifiers: [String]) -> PhotoImageType? {
    let bytes = [UInt8](data.prefix(12))
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
    if bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
      String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP"
    {
      return .webp
    }
    if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
      switch String(bytes: bytes[8..<12], encoding: .ascii) {
      case "heic", "heix", "hevc", "hevx": return .heic
      case "heif", "mif1", "msf1": return .heif
      default: break
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

/// Why a picked photo cannot be added, in Web's words.
enum PhotoDraftError: LocalizedError, Equatable {
  case invalidSize
  case filenameTooLong
  case invalidDimensions
  case unsupportedType

  var errorDescription: String? {
    switch self {
    case .invalidSize: "Each photo must be no larger than 50 MB."
    case .filenameTooLong: "Photo filenames can be up to 255 characters."
    case .invalidDimensions: "This photo has invalid dimensions."
    case .unsupportedType: "Use a JPEG, PNG, WebP, HEIC, or HEIF image."
    }
  }
}

/// A photo picked on this iPhone and not yet attached to an Entry.
struct PhotoDraft: Equatable, Identifiable, Sendable {
  /// Web `entryPhotoLimit` and `entryPhotoSizeLimit`.
  static let maximumCount = 12
  static let maximumByteSize = 50 * 1_024 * 1_024
  static let tooManyMessage = "Keep up to \(maximumCount) photos with one Entry."

  let id: UUID
  let data: Data
  let mimeType: PhotoImageType
  let originalFilename: String?
  let pixelWidth: Int?
  let pixelHeight: Int?

  static func validate(
    id: UUID = UUID(), data: Data, mimeType: PhotoImageType, originalFilename: String?,
    pixelWidth: Int?, pixelHeight: Int?
  ) throws -> PhotoDraft {
    let filename = originalFilename?.trimmed.nonEmpty
    guard !data.isEmpty, data.count <= maximumByteSize else { throw PhotoDraftError.invalidSize }
    guard (filename?.count ?? 0) <= 255 else { throw PhotoDraftError.filenameTooLong }
    guard pixelWidth.map({ $0 > 0 }) ?? true, pixelHeight.map({ $0 > 0 }) ?? true else {
      throw PhotoDraftError.invalidDimensions
    }
    return PhotoDraft(
      id: id, data: data, mimeType: mimeType, originalFilename: filename,
      pixelWidth: pixelWidth, pixelHeight: pixelHeight)
  }

  func objectPath(ownerID: UUID, entryID: UUID) -> String {
    EntryPhotoPath.objectPath(
      ownerID: ownerID, entryID: entryID, attachmentID: id, mimeType: mimeType)
  }
}

/// Web `createEntryObjectPath`.
enum EntryPhotoPath {
  static func objectPath(ownerID: UUID, entryID: UUID, attachmentID: UUID, mimeType: PhotoImageType)
    -> String
  {
    [ownerID, entryID].map { $0.uuidString.lowercased() }.joined(separator: "/")
      + "/\(attachmentID.uuidString.lowercased()).\(mimeType.fileExtension)"
  }
}

/// `register_entry_attachment`: records an uploaded original on its Entry. Registering never
/// changes the Entry's revision.
struct RegisterEntryAttachmentParameters: Encodable, Equatable, Sendable {
  let entryID: UUID
  let attachmentID: UUID
  let objectPath: String
  let originalFilename: String?
  let mimeType: PhotoImageType
  let byteSize: Int64
  let pixelWidth: Int?
  let pixelHeight: Int?

  init(
    entryID: UUID, attachmentID: UUID, objectPath: String, originalFilename: String?,
    mimeType: PhotoImageType, byteSize: Int64, pixelWidth: Int?, pixelHeight: Int?
  ) {
    self.entryID = entryID
    self.attachmentID = attachmentID
    self.objectPath = objectPath
    self.originalFilename = originalFilename
    self.mimeType = mimeType
    self.byteSize = byteSize
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  init(entryID: UUID, draft: PhotoDraft, objectPath: String) {
    self.init(
      entryID: entryID, attachmentID: draft.id, objectPath: objectPath,
      originalFilename: draft.originalFilename, mimeType: draft.mimeType,
      byteSize: Int64(draft.data.count), pixelWidth: draft.pixelWidth,
      pixelHeight: draft.pixelHeight)
  }

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
    try values.encode(attachmentID, forKey: .attachmentID)
    try values.encode(objectPath, forKey: .objectPath)
    try values.encode(originalFilename, forKey: .originalFilename)
    try values.encode(mimeType, forKey: .mimeType)
    try values.encode(byteSize, forKey: .byteSize)
    try values.encode(pixelWidth, forKey: .pixelWidth)
    try values.encode(pixelHeight, forKey: .pixelHeight)
  }
}

struct RegisteredEntryAttachment: Decodable, Equatable, Sendable {
  let attachmentID: UUID
  let entryID: UUID?
  let objectPath: String?

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
    case entryID = "entry_id"
    case objectPath = "object_path"
  }
}

/// `trash_entry_attachment`: moves one photo to Trash without changing its Entry's revision.
struct TrashEntryAttachmentParameters: Encodable, Equatable, Sendable {
  let attachmentID: UUID

  enum CodingKeys: String, CodingKey {
    case attachmentID = "p_attachment_id"
  }
}

struct TrashedEntryAttachment: Decodable, Equatable, Sendable {
  let attachmentID: UUID
  let entryID: UUID?

  enum CodingKeys: String, CodingKey {
    case attachmentID = "attachment_id"
    case entryID = "entry_id"
  }
}

/// One saved photo from `POST /api/media/photos?entryId=`, oldest first.
struct EntryPhotoInfo: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let imageUrl: String?

  /// The display URL, kept only when it is MemoTrail's own short-lived image route.
  func displayURL(base: URL?) -> URL? {
    guard let base, let imageUrl else { return nil }
    return MediaDelivery.validatedURLs(
      [id.uuidString: imageUrl], paths: [id.uuidString], base: base)[id.uuidString]
  }
}

/// Web `EntryPhotos`: the first 100 current photos and whether more exist.
struct EntryPhotosResponse: Decodable, Equatable, Sendable {
  let photos: [EntryPhotoInfo]
  let hasMore: Bool
}

/// A photo's GPS position the editor adds as the Entry's Location when it saves, like Web
/// `PhotoLocationDraft`. It has no name; the Location reads as its coordinates.
struct PhotoLocationDraft: Codable, Equatable, Hashable, Sendable {
  let attachmentId: UUID
  let latitude: Double
  let longitude: Double

  /// Web `validPhotoLocation`.
  var isValid: Bool {
    latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(attachmentId.uuidString.lowercased(), forKey: .attachmentId)
    try values.encode(latitude, forKey: .latitude)
    try values.encode(longitude, forKey: .longitude)
  }
}
