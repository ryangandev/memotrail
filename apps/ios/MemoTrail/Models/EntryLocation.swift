import Foundation
@preconcurrency import Supabase

/// An Entry's saved primary Location snapshot, like Web `ExistingLocation`.
struct EntryLocation: Decodable, Equatable, Hashable, Sendable {
  let id: UUID
  let revision: Int
  let name: String
  let formattedAddress: String?
  let address: String?
  let city: String?
  let region: String?
  let country: String?
  let latitude: Double?
  let longitude: Double?

  enum CodingKeys: String, CodingKey {
    case id, revision, name, address, city, region, country, latitude, longitude
    case formattedAddress = "formatted_address"
  }

  /// Web `locationDisplayLabel`: the formatted address, else the address facts.
  var label: String {
    formattedAddress?.trimmed.nonEmpty
      ?? [address, city, region, country].compactMap { $0?.trimmed.nonEmpty }
      .joined(separator: ", ").nonEmpty
      ?? "Location not set"
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
      try await client.from("entry_places")
      .select(
        "entry_id,location:locations!entry_places_location_id_owner_id_fkey(id,revision,name,formatted_address,address,city,region,country,latitude,longitude)"
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
