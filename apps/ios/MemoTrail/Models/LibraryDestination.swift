import Foundation

enum LibraryDestination: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
  case collections
  case firstTimes
  case goals
  case homes
  case people
  case places
  case trash
  case vehicles

  var id: String { rawValue }

  var title: String {
    switch self {
    case .collections:
      "Collections"
    case .firstTimes:
      "First Times"
    case .goals:
      "Goals"
    case .homes:
      "Homes"
    case .people:
      "People"
    case .places:
      "Places"
    case .trash:
      "Trash"
    case .vehicles:
      "Vehicles"
    }
  }

  var summary: String {
    switch self {
    case .collections:
      "Browse Entries grouped by meaning."
    case .firstTimes:
      "Revisit beginnings, dates, stories, and photos."
    case .goals:
      "Keep short-term and long-term intentions."
    case .homes:
      "Remember where you lived and for how long."
    case .people:
      "Connect the people who shaped each chapter."
    case .places:
      "Map meaningful locations across your trail."
    case .trash:
      "Restore removed items or delete them permanently."
    case .vehicles:
      "Keep the story of vehicles you owned or used."
    }
  }

  var systemImage: String {
    switch self {
    case .collections:
      "archivebox"
    case .firstTimes:
      "star"
    case .goals:
      "target"
    case .homes:
      "house"
    case .people:
      "person.2"
    case .places:
      "map"
    case .trash:
      "trash"
    case .vehicles:
      "car"
    }
  }

  var isAvailable: Bool {
    self == .collections || self == .firstTimes || self == .goals || self == .homes
      || self == .trash || self == .vehicles
  }

  static let available: [LibraryDestination] = [
    .collections, .firstTimes, .homes, .vehicles, .goals, .trash,
  ]
  static let planned: [LibraryDestination] = [.places, .people]
}
