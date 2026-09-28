import Foundation
import Observation
@preconcurrency import Supabase

@MainActor
struct LocationMapRepository {
  let client: SupabaseClient
  let ownerID: UUID
  static let pageSize = 250
  static let maximumLinks = 5_000

  func load() async throws -> LocationMapSnapshot {
    try await checkOwner()
    var links: [MapLocationLink] = []
    var truncated = false
    for offset in stride(from: 0, through: Self.maximumLinks, by: Self.pageSize) {
      try Task.checkCancellation()
      let page: [MapLocationLink] = try await client.from("entry_places")
        .select("entry_id,place_id")
        .eq("owner_id", value: ownerID.uuidString)
        .in("relationship", values: ["home", "primary", "related"])
        .order("created_at", ascending: false)
        .order("entry_id").order("place_id").order("relationship")
        .range(from: offset, to: offset + Self.pageSize - 1)
        .execute().value
      if offset == Self.maximumLinks {
        truncated = !page.isEmpty
        break
      }
      links.append(contentsOf: page)
      if page.count < Self.pageSize { break }
    }

    var items: [LocationMapItem] = []
    for offset in stride(from: 0, to: links.count, by: Self.pageSize) {
      try Task.checkCancellation()
      let batch = Array(links[offset..<min(offset + Self.pageSize, links.count)])
      let entryIDs = Set(batch.map { $0.entry_id.uuidString }).sorted()
      let locationIDs = Set(batch.map { $0.place_id.uuidString }).sorted()
      let entries: [MapEntryRow] = try await client.from("entries")
        .select("id,title,body,item_kind,item_subtype,inbox_status,occurred_start")
        .eq("owner_id", value: ownerID.uuidString).is("deleted_at", value: nil)
        .in("id", values: entryIDs).execute().value
      let locations: [MapLocationRow] = try await client.from("locations")
        .select("id,latitude,longitude,formatted_address,name,city,region,country")
        .eq("owner_id", value: ownerID.uuidString).is("deleted_at", value: nil)
        .in("id", values: locationIDs).execute().value
      items.append(
        contentsOf: LocationMapAssembly.items(links: batch, entries: entries, locations: locations))
    }
    try await checkOwner()
    var seen = Set<String>()
    return LocationMapSnapshot(
      items: items.filter { seen.insert($0.id).inserted }, truncated: truncated)
  }

  private func checkOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

@MainActor
@Observable
final class LocationMapController {
  private(set) var items: [LocationMapItem] = []
  private(set) var truncated = false
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  private(set) var errorMessage: String?
  private let fetch: @MainActor () async throws -> LocationMapSnapshot

  init(fetch: @escaping @MainActor () async throws -> LocationMapSnapshot) { self.fetch = fetch }

  convenience init(client: SupabaseClient, ownerID: UUID) {
    self.init { try await LocationMapRepository(client: client, ownerID: ownerID).load() }
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let snapshot = try await fetch()
      try Task.checkCancellation()
      items = snapshot.items
      truncated = snapshot.truncated
      hasLoaded = true
    } catch is CancellationError {
      return
    } catch {
      // A failed later page must never publish a partial map.
      items = []
      truncated = false
      hasLoaded = true
      errorMessage = "Your Locations could not load. Check your connection and try again."
    }
  }
}
