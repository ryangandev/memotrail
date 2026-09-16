import Foundation

typealias PlaceAttachment = ResidenceAttachment

struct PlaceLinkedEntry: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let entryType: String
  let inboxStatus: String
  let occurredStart: Date?
  let occurredEnd: Date?
  let datePrecision: String
  let occurredLabel: String?
  let occurredTimezone: String?
  let revision: Int
  let updatedAt: Date
  let relationship: String
  var attachments: [PlaceAttachment]

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case entryType = "entry_type"
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredEnd = "occurred_end"
    case datePrecision = "date_precision"
    case occurredLabel = "occurred_label"
    case occurredTimezone = "occurred_timezone"
    case revision
    case updatedAt = "updated_at"
    case relationship
    case attachments
  }

  var displayTitle: String {
    if let title = title?.trimmed.nonEmpty { return title }
    let body = body.trimmed
    guard !body.isEmpty else { return "Untitled Entry" }
    return body.count > 80 ? "\(body.prefix(80).trimmingCharacters(in: .whitespaces))..." : body
  }

  var isEditable: Bool { relationship == "related" }

  var relationshipLabel: String {
    relationship == "home" ? "Home record" : entryType.displayEntryType
  }
}

struct PlaceEntry: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let notes: String?
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  var linkedEntries: [PlaceLinkedEntry]
  let linkedEntryCount: Int
  let homeCount: Int
  let totalCount: Int

  var relatedEntries: [PlaceLinkedEntry] { linkedEntries.filter(\.isEditable) }
  var protectedEntries: [PlaceLinkedEntry] { linkedEntries.filter { !$0.isEditable } }
  var isLinked: Bool { linkedEntryCount > 0 }
  var canMoveToTrash: Bool { linkedEntryCount == 0 }
  var coverAttachment: PlaceAttachment? {
    linkedEntries.lazy.flatMap(\.attachments).first
  }

  var locationLabel: String {
    var seen: Set<String> = []
    let locality = [city, region, country].compactMap { value -> String? in
      guard let value = value?.trimmed.nonEmpty else { return nil }
      guard seen.insert(value.lowercased()).inserted else { return nil }
      return value
    }
    if let address = address?.trimmed.nonEmpty, !locality.isEmpty {
      return "\(address) · \(locality.joined(separator: ", "))"
    }
    return address?.trimmed.nonEmpty ?? locality.nonEmpty?.joined(separator: ", ")
      ?? "Location details not added"
  }

  var coordinateLabel: String? {
    guard let latitude, let longitude else { return nil }
    return "\(Self.coordinate(latitude, positive: "N", negative: "S")), "
      + "\(Self.coordinate(longitude, positive: "E", negative: "W"))"
  }

  private static func coordinate(_ value: Double, positive: String, negative: String) -> String {
    let raw = String(format: "%.4f", abs(value))
    let number = raw.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    return "\(number)°\(value < 0 ? negative : positive)"
  }
}

struct PlaceWorkspaceRow: Decodable, Equatable, Sendable {
  let placeID: UUID
  let name: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let notes: String?
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let linkedEntries: [PlaceLinkedEntry]
  let linkedEntryCount: Int
  let homeCount: Int
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case name
    case address
    case city
    case region
    case country
    case latitude
    case longitude
    case notes
    case revision
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case linkedEntries = "linked_entries"
    case linkedEntryCount = "linked_entry_count"
    case homeCount = "home_count"
    case totalCount = "total_count"
  }

  var entry: PlaceEntry {
    PlaceEntry(
      id: placeID,
      name: name,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      linkedEntries: linkedEntries,
      linkedEntryCount: linkedEntryCount,
      homeCount: homeCount,
      totalCount: totalCount
    )
  }
}

enum PlaceWorkspace {
  static func entries(from rows: [PlaceWorkspaceRow]) -> [PlaceEntry] {
    rows.map(\.entry).sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
      return nameOrder == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString : nameOrder == .orderedAscending
    }
  }
}

struct PlaceLinkOption: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String?
  let entryType: String
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case entryType = "entry_type"
    case updatedAt = "updated_at"
  }

  var displayTitle: String {
    if let title = title?.trimmed.nonEmpty { return title }
    let body = body?.trimmed ?? ""
    guard !body.isEmpty else { return "Untitled Entry" }
    return body.count > 80 ? "\(body.prefix(80).trimmingCharacters(in: .whitespaces))..." : body
  }
}

struct PlaceInput: Equatable, Sendable {
  static let nameLimit = 200
  static let addressLimit = 500
  static let locationPartLimit = 200
  static let notesLimit = 10_000
  static let relatedEntryLimit = 100

  let placeID: UUID?
  let expectedRevision: Int?
  let name: String
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?
  let notes: String?
  let relatedEntryIDs: [UUID]

  static func validate(
    placeID: UUID?,
    expectedRevision: Int?,
    name: String,
    address: String,
    city: String,
    region: String,
    country: String,
    latitude: Double?,
    longitude: Double?,
    notes: String,
    relatedEntryIDs: [UUID]
  ) throws -> PlaceInput {
    let name = name.trimmed
    let address = address.trimmed.nonEmpty
    let city = city.trimmed.nonEmpty
    let region = region.trimmed.nonEmpty
    let country = country.trimmed.nonEmpty
    let notes = notes.trimmed.nonEmpty

    guard !name.isEmpty else { throw PlaceEntryError.nameRequired }
    guard name.count <= nameLimit else { throw PlaceEntryError.nameTooLong }
    guard (address?.count ?? 0) <= addressLimit else { throw PlaceEntryError.addressTooLong }
    guard [city, region, country].allSatisfy({ ($0?.count ?? 0) <= locationPartLimit }) else {
      throw PlaceEntryError.locationTooLong
    }
    guard (notes?.count ?? 0) <= notesLimit else { throw PlaceEntryError.notesTooLong }
    guard
      (placeID == nil && expectedRevision == nil)
        || (placeID != nil && (expectedRevision ?? 0) > 0)
    else { throw PlaceEntryError.invalidRevision }
    guard (latitude == nil) == (longitude == nil) else {
      throw PlaceEntryError.invalidCoordinates
    }
    if let latitude, let longitude {
      guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
        (-180...180).contains(longitude)
      else { throw PlaceEntryError.invalidCoordinates }
    }

    var seen: Set<UUID> = []
    let relatedEntryIDs = relatedEntryIDs.filter { seen.insert($0).inserted }
    guard relatedEntryIDs.count <= relatedEntryLimit else {
      throw PlaceEntryError.invalidRelatedEntries
    }

    return PlaceInput(
      placeID: placeID,
      expectedRevision: expectedRevision,
      name: name,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      relatedEntryIDs: relatedEntryIDs
    )
  }
}

struct SavePlaceParameters: Encodable, Equatable, Sendable {
  let input: PlaceInput

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case address = "p_address"
    case city = "p_city"
    case region = "p_region"
    case country = "p_country"
    case latitude = "p_latitude"
    case longitude = "p_longitude"
    case notes = "p_notes"
    case relatedEntryIDs = "p_related_entry_ids"
    case placeID = "p_place_id"
    case expectedRevision = "p_expected_revision"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.name, forKey: .name)
    try values.encode(input.relatedEntryIDs, forKey: .relatedEntryIDs)
    try encodeNullable(input.address, forKey: .address, into: &values)
    try encodeNullable(input.city, forKey: .city, into: &values)
    try encodeNullable(input.region, forKey: .region, into: &values)
    try encodeNullable(input.country, forKey: .country, into: &values)
    try encodeNullable(input.latitude, forKey: .latitude, into: &values)
    try encodeNullable(input.longitude, forKey: .longitude, into: &values)
    try encodeNullable(input.notes, forKey: .notes, into: &values)
    try encodeNullable(input.placeID, forKey: .placeID, into: &values)
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

struct SavedPlace: Decodable, Equatable, Sendable {
  let placeID: UUID
  let revision: Int
  let wasCreated: Bool

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case revision
    case wasCreated = "was_created"
  }
}

struct TrashPlaceParameters: Encodable, Equatable, Sendable {
  let placeID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case placeID = "p_place_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct TrashedPlace: Decodable, Equatable, Sendable {
  let placeID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case revision
  }
}

enum PlaceEntryError: LocalizedError, Equatable {
  case addressTooLong
  case invalidCoordinates
  case invalidRelatedEntries
  case invalidRevision
  case locationTooLong
  case nameRequired
  case nameTooLong
  case notesTooLong

  var errorDescription: String? {
    switch self {
    case .addressTooLong: "Addresses can be up to \(PlaceInput.addressLimit) characters."
    case .invalidCoordinates: "Add both valid latitude and longitude values, or leave both empty."
    case .invalidRelatedEntries: "Link up to \(PlaceInput.relatedEntryLimit) Entries."
    case .invalidRevision: "This Place version is invalid. Refresh and try again."
    case .locationTooLong:
      "City, region, and country can each be up to \(PlaceInput.locationPartLimit) characters."
    case .nameRequired: "Add a name for this Place."
    case .nameTooLong: "Place names can be up to \(PlaceInput.nameLimit) characters."
    case .notesTooLong: "Notes can be up to \(PlaceInput.notesLimit) characters."
    }
  }
}

extension String {
  fileprivate var displayEntryType: String {
    replacingOccurrences(of: "_", with: " ").capitalized
  }
}

extension Array {
  fileprivate var nonEmpty: Self? { isEmpty ? nil : self }
}
