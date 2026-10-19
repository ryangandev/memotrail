import Foundation
@preconcurrency import Supabase

/// An Entry's saved primary Location snapshot, like Web `ExistingLocation`. It decodes the
/// `locations` row that `editable_entry.primary_location` and `entry_locations` reads return,
/// and encodes as the `{"kind":"existing",...}` selection `save_entry` keeps unchanged.
struct EntryLocation: Codable, Equatable, Hashable, Sendable {
  let id: UUID
  let revision: Int
  let formattedAddress: String?
  let address: String?
  let city: String?
  let region: String?
  let postalCode: String?
  let country: String?
  let countryCode: String?
  let latitude: Double?
  let longitude: Double?
  let timezone: String?
  let resultType: String?

  init(
    id: UUID, revision: Int, formattedAddress: String? = nil, address: String? = nil,
    city: String? = nil, region: String? = nil, postalCode: String? = nil,
    country: String? = nil, countryCode: String? = nil, latitude: Double? = nil,
    longitude: Double? = nil, timezone: String? = nil, resultType: String? = nil
  ) {
    self.id = id
    self.revision = revision
    self.formattedAddress = formattedAddress
    self.address = address
    self.city = city
    self.region = region
    self.postalCode = postalCode
    self.country = country
    self.countryCode = countryCode
    self.latitude = latitude
    self.longitude = longitude
    self.timezone = timezone
    self.resultType = resultType
  }

  private enum RowKeys: String, CodingKey {
    case id, revision, address, city, region, country, latitude, longitude
    case formattedAddress = "formatted_address"
    case postalCode = "postal_code"
    case countryCode = "country_code"
    case timezone = "timezone_id"
    case resultType = "result_type"
  }

  private enum SelectionKeys: String, CodingKey {
    case kind, id, revision, formattedAddress, address, city, region, postalCode, country
    case countryCode, latitude, longitude, timezone, resultType
  }

  init(from decoder: Decoder) throws {
    let row = try decoder.container(keyedBy: RowKeys.self)
    id = try row.decode(UUID.self, forKey: .id)
    revision = try row.decode(Int.self, forKey: .revision)
    formattedAddress = try row.decodeIfPresent(String.self, forKey: .formattedAddress)
    address = try row.decodeIfPresent(String.self, forKey: .address)
    city = try row.decodeIfPresent(String.self, forKey: .city)
    region = try row.decodeIfPresent(String.self, forKey: .region)
    postalCode = try row.decodeIfPresent(String.self, forKey: .postalCode)
    country = try row.decodeIfPresent(String.self, forKey: .country)
    countryCode = try row.decodeIfPresent(String.self, forKey: .countryCode)
    latitude = try row.decodeIfPresent(Double.self, forKey: .latitude)
    longitude = try row.decodeIfPresent(Double.self, forKey: .longitude)
    timezone = try row.decodeIfPresent(String.self, forKey: .timezone)
    resultType = try row.decodeIfPresent(String.self, forKey: .resultType)
  }

  /// Web `ExistingLocation`, every field present, so `save_entry` keeps this snapshot.
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: SelectionKeys.self)
    try values.encode("existing", forKey: .kind)
    try values.encode(id.uuidString.lowercased(), forKey: .id)
    try values.encode(revision, forKey: .revision)
    try values.encode(formattedAddress, forKey: .formattedAddress)
    try values.encode(address, forKey: .address)
    try values.encode(city, forKey: .city)
    try values.encode(region, forKey: .region)
    try values.encode(postalCode, forKey: .postalCode)
    try values.encode(country, forKey: .country)
    try values.encode(countryCode, forKey: .countryCode)
    try values.encode(latitude, forKey: .latitude)
    try values.encode(longitude, forKey: .longitude)
    try values.encode(timezone, forKey: .timezone)
    try values.encode(resultType, forKey: .resultType)
  }

  /// Web `locationDisplayLabel`: the formatted address, else the address facts, else the
  /// coordinates a photo's GPS gave.
  var label: String {
    Self.label(
      formattedAddress: formattedAddress, parts: [address, city, region, country],
      latitude: latitude, longitude: longitude)
  }

  static func label(
    formattedAddress: String?, parts: [String?] = [], latitude: Double?, longitude: Double?
  ) -> String {
    if let formattedAddress = formattedAddress?.trimmed.nonEmpty { return formattedAddress }
    if let joined = parts.compactMap({ $0?.nonEmpty }).joined(separator: ", ").nonEmpty {
      return joined
    }
    if let latitude, let longitude {
      return String(format: "%.5f, %.5f", latitude, longitude)
    }
    return "Location not set"
  }
}

/// Web `getPrimaryEntryLocations`: the current primary Location of each requested Entry.
/// A failed load throws, so the workspace reports itself unavailable like Web.
enum EntryPrimaryLocations {
  struct Row: Decodable, Sendable {
    let entryID: UUID
    let location: EntryLocation?

    enum CodingKeys: String, CodingKey {
      case entryID = "entry_id"
      case location
    }
  }

  static func load(client: SupabaseClient, ownerID: UUID, entryIDs: [UUID]) async throws
    -> [UUID: EntryLocation]
  {
    guard !entryIDs.isEmpty else { return [:] }
    let rows: [Row] =
      try await client.from("entry_locations")
      .select(
        "entry_id,location:locations!entry_locations_location_id_owner_id_fkey(id,revision,formatted_address,address,city,region,postal_code,country,country_code,latitude,longitude,timezone_id,result_type)"
      )
      .eq("owner_id", value: ownerID.uuidString)
      .eq("relationship", value: "primary")
      .in("entry_id", values: entryIDs.map(\.uuidString))
      .execute().value
    return assemble(rows)
  }

  static func assemble(_ rows: [Row]) -> [UUID: EntryLocation] {
    var result: [UUID: EntryLocation] = [:]
    for row in rows {
      if let location = row.location { result[row.entryID] = location }
    }
    return result
  }
}
