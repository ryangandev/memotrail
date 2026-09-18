import Foundation

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
  let totalCount: Int

  var canMoveToTrash: Bool { true }

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

struct PlaceInput: Equatable, Sendable {
  static let nameLimit = 200
  static let addressLimit = 500
  static let locationPartLimit = 200
  static let notesLimit = 10_000

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
    notes: String
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
    try values.encode([UUID](), forKey: .relatedEntryIDs)
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
  case invalidRevision
  case locationTooLong
  case nameRequired
  case nameTooLong
  case notesTooLong

  var errorDescription: String? {
    switch self {
    case .addressTooLong: "Addresses can be up to \(PlaceInput.addressLimit) characters."
    case .invalidCoordinates: "Add both valid latitude and longitude values, or leave both empty."
    case .invalidRevision: "This Place version is invalid. Refresh and try again."
    case .locationTooLong:
      "City, region, and country can each be up to \(PlaceInput.locationPartLimit) characters."
    case .nameRequired: "Add a name for this Place."
    case .nameTooLong: "Place names can be up to \(PlaceInput.nameLimit) characters."
    case .notesTooLong: "Notes can be up to \(PlaceInput.notesLimit) characters."
    }
  }
}

extension Array {
  fileprivate var nonEmpty: Self? { isEmpty ? nil : self }
}
