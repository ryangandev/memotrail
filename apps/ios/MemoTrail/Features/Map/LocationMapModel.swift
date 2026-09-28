import Foundation

struct LocationMapItem: Identifiable, Equatable, Sendable {
  let entryID: UUID
  let locationID: UUID
  let title: String
  let kind: WikiItemKind
  let subtype: String
  let inboxStatus: String
  let occurredAt: Date?
  let latitude: Double
  let longitude: Double
  let address: String
  let city: String?
  let region: String?
  let country: String?

  var id: String { "\(entryID.uuidString):\(locationID.uuidString)" }
  var year: Int? {
    guard let occurredAt else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.component(.year, from: occurredAt)
  }
}

struct LocationMapSnapshot: Sendable {
  let items: [LocationMapItem]
  let truncated: Bool
}

struct LocationMapFilter: Equatable {
  var kind: WikiItemKind?
  var fromYear: Int?
  var toYear: Int?

  var isValid: Bool {
    [fromYear, toYear].compactMap { $0 }.allSatisfy { (1...9999).contains($0) }
      && (fromYear == nil || toYear == nil || fromYear! <= toYear!)
  }

  func apply(to items: [LocationMapItem]) -> [LocationMapItem] {
    guard isValid else { return [] }
    return items.filter { item in
      if let kind, item.kind != kind { return false }
      if let fromYear, item.year.map({ $0 >= fromYear }) != true { return false }
      if let toYear, item.year.map({ $0 <= toYear }) != true { return false }
      return true
    }
  }
}

struct LocationMapArea: Identifiable {
  let id: String
  let title: String
  let items: [LocationMapItem]
  var entryCount: Int { Set(items.map(\.entryID)).count }

  static func shortcuts(for items: [LocationMapItem]) -> [Self] {
    let grouped = Dictionary(grouping: items.filter { $0.city?.trimmed.nonEmpty != nil }) { item in
      [item.city, item.region, item.country].map { $0?.trimmed.lowercased() ?? "" }.joined(
        separator: "\u{0}")
    }
    return grouped.map { key, values in
      let first = values[0]
      return Self(
        id: key,
        title: [
          first.city?.trimmed, first.region?.trimmed.nonEmpty ?? first.country?.trimmed.nonEmpty,
        ]
        .compactMap { $0 }.joined(separator: ", "),
        items: values
      )
    }.sorted {
      $0.entryCount == $1.entryCount
        ? $0.title.localizedCompare($1.title) == .orderedAscending : $0.entryCount > $1.entryCount
    }.prefix(4).map { $0 }
  }

  static func uniqueEntries(in items: [LocationMapItem]) -> [LocationMapItem] {
    var seen = Set<UUID>()
    return items.sorted {
      if $0.occurredAt == $1.occurredAt { return $0.id < $1.id }
      return ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast)
    }.filter { seen.insert($0.entryID).inserted }
  }
}

struct MapLocationLink: Decodable {
  let entry_id: UUID
  let place_id: UUID
}

struct MapEntryRow: Decodable {
  let id: UUID
  let title: String
  let body: String?
  let item_kind: WikiItemKind
  let item_subtype: String
  let inbox_status: String
  let occurred_start: Date?
}

struct MapLocationRow: Decodable {
  let id: UUID
  let latitude: Double?
  let longitude: Double?
  let formatted_address: String?
  let name: String
  let city: String?
  let region: String?
  let country: String?
}

enum LocationMapAssembly {
  static func items(links: [MapLocationLink], entries: [MapEntryRow], locations: [MapLocationRow])
    -> [LocationMapItem]
  {
    let entriesByID = Dictionary(
      entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let locationsByID = Dictionary(
      locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    return links.compactMap { link in
      guard let entry = entriesByID[link.entry_id], let location = locationsByID[link.place_id],
        let latitude = location.latitude, let longitude = location.longitude,
        latitude.isFinite, longitude.isFinite,
        (-90...90).contains(latitude), (-180...180).contains(longitude)
      else { return nil }
      let item = LocationMapItem(
        entryID: entry.id, locationID: location.id,
        title: entry.title.trimmed.nonEmpty ?? entry.body?.trimmed.nonEmpty.map {
          String($0.prefix(120))
        } ?? "Untitled record",
        kind: entry.item_kind, subtype: entry.item_subtype, inboxStatus: entry.inbox_status,
        occurredAt: entry.occurred_start, latitude: latitude, longitude: longitude,
        address: location.formatted_address?.trimmed.nonEmpty ?? location.name,
        city: location.city, region: location.region, country: location.country
      )
      return seen.insert(item.id).inserted ? item : nil
    }
  }
}
