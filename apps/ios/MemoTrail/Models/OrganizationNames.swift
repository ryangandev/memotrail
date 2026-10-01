import Foundation

/// The Collection and tag limits every Web editor shares, and Web `normalizedNames`.
enum OrganizationNames {
  static let collectionLimit = 20
  static let collectionNameLimit = 80
  static let tagLimit = 50
  static let tagNameLimit = 60

  /// Trims each name and drops blanks and case-insensitive repeats, keeping the first spelling.
  static func normalized(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    return names.compactMap { value in
      let name = value.trimmed
      guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
      return name
    }
  }
}
