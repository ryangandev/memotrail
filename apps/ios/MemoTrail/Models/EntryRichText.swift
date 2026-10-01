import Foundation
@preconcurrency import Supabase

/// Web's versioned `metadata.body_rich` document for read-only rendering: paragraphs, quotes,
/// lists, code blocks, hard breaks, and bold, italic, underline, strike, code, and link marks.
/// Validation mirrors Web `isEntryRichText`, so invalid documents fall back to the plain body.
struct EntryRichText: Codable, Equatable, Sendable {
  enum Value: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case null

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        self = .null
      } else if let integer = try? container.decode(Int.self) {
        self = .integer(integer)
      } else {
        self = .string(try container.decode(String.self))
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .string(let value): try container.encode(value)
      case .integer(let value): try container.encode(value)
      case .null: try container.encodeNil()
      }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var integer: Int? { if case .integer(let value) = self { value } else { nil } }
  }

  struct Mark: Codable, Equatable, Sendable {
    let type: String
    var attrs: [String: Value]?
  }

  struct Node: Codable, Equatable, Sendable {
    let type: String
    var attrs: [String: Value]?
    var content: [Node]?
    var marks: [Mark]?
    var text: String?
  }

  static let metadataKey = "body_rich"
  private static let bodyLimit = 50_000
  private static let maximumDocumentBytes = 250_000
  private static let maximumDepth = 24
  private static let maximumNodes = 4_000
  private static let maximumLinkLength = 2_048
  private static let blockTypes: Set = [
    "blockquote", "bulletList", "codeBlock", "orderedList", "paragraph",
  ]
  private static let markTypes: Set = ["bold", "code", "italic", "link", "strike", "underline"]

  let version: Int
  let text: String
  let document: Node

  func isValid(expectedText: String? = nil) -> Bool {
    guard version == 1, text.utf16.count <= Self.bodyLimit,
      expectedText == nil || expectedText == text,
      let bytes = try? JSONEncoder().encode(document), bytes.count <= Self.maximumDocumentBytes
    else { return false }
    var nodes = 0
    return Self.isValid(document, parent: nil, depth: 0, nodes: &nodes)
      && Self.plainText(document) == text
  }

  static func plainText(_ node: Node) -> String {
    switch node.type {
    case "text": return node.text ?? ""
    case "hardBreak": return "\n"
    default:
      let separator =
        ["blockquote", "bulletList", "doc", "listItem", "orderedList"].contains(node.type)
        ? "\n" : ""
      return (node.content ?? []).map(plainText).joined(separator: separator)
    }
  }

  private static func isValid(_ node: Node, parent: String?, depth: Int, nodes: inout Int)
    -> Bool
  {
    nodes += 1
    guard depth <= maximumDepth, nodes <= maximumNodes, allows(parent, child: node.type),
      validAttributes(node.type, node.attrs)
    else { return false }
    switch node.type {
    case "text":
      return !(node.text ?? "").isEmpty && node.content == nil && validMarks(node.marks)
    case "hardBreak":
      return node.text == nil && node.content == nil && node.marks == nil
    default:
      guard node.text == nil, node.marks == nil else { return false }
      if node.content == nil, !["paragraph", "codeBlock"].contains(node.type) { return false }
      let content = node.content ?? []
      if content.isEmpty, ["doc", "bulletList", "orderedList"].contains(node.type) {
        return false
      }
      return content.allSatisfy {
        isValid($0, parent: node.type, depth: depth + 1, nodes: &nodes)
      }
    }
  }

  private static func allows(_ parent: String?, child: String) -> Bool {
    switch parent {
    case nil: child == "doc"
    case "doc", "blockquote", "listItem": blockTypes.contains(child)
    case "paragraph": child == "text" || child == "hardBreak"
    case "codeBlock": child == "text"
    case "bulletList", "orderedList": child == "listItem"
    default: false
    }
  }

  private static func validAttributes(_ type: String, _ attrs: [String: Value]?) -> Bool {
    guard let attrs else { return true }
    let allowed: Set<String> =
      switch type {
      case "orderedList": ["start", "type"]
      case "bulletList": ["type"]
      case "codeBlock": ["language"]
      default: []
      }
    return attrs.allSatisfy { key, value in
      guard allowed.contains(key) else { return false }
      if value == .null { return true }
      if key == "start" { return (value.integer ?? 0) > 0 }
      return (value.string?.count ?? .max) <= 100
    }
  }

  private static func validMarks(_ marks: [Mark]?) -> Bool {
    (marks ?? []).allSatisfy { mark in
      guard markTypes.contains(mark.type) else { return false }
      guard mark.type == "link" else { return mark.attrs?.isEmpty ?? true }
      guard let attrs = mark.attrs, safeLink(attrs["href"]?.string) else { return false }
      let allowed: Set = ["class", "href", "rel", "target", "title"]
      return attrs.allSatisfy { key, value in
        allowed.contains(key)
          && (value == .null || (value.string?.count ?? .max) <= maximumLinkLength)
      }
    }
  }

  /// Only web, mail, and phone links open from rendered writing.
  static func safeLink(_ value: String?) -> Bool {
    guard let value, value.count <= maximumLinkLength, let url = URL(string: value),
      let scheme = url.scheme?.lowercased()
    else { return false }
    return ["http", "https", "mailto", "tel"].contains(scheme)
  }
}

extension EntryRichText {
  /// The editor's paragraph-and-emphasis document in the full contract's shape.
  init?(_ content: EntryEmphasisContent) {
    guard let data = try? JSONEncoder().encode(content),
      let value = try? JSONDecoder().decode(Self.self, from: data),
      value.isValid(expectedText: content.text)
    else { return nil }
    self = value
  }
}

/// Decodes one metadata value without failing the whole metadata object.
private struct EntryRichTextEnvelope: Decodable {
  let value: EntryRichText?

  init(from decoder: Decoder) throws {
    value = try? EntryRichText(from: decoder)
  }
}

extension KeyedDecodingContainer {
  /// Decodes `body_rich` from an Entry's `metadata` when it is valid for `body`, ignoring any
  /// other metadata, like Web `parseEntryRichText`.
  func decodeEntryRichText(metadataKey key: Key, body: String) -> EntryRichText? {
    guard let metadata = try? decodeIfPresent([String: EntryRichTextEnvelope].self, forKey: key),
      let value = metadata[EntryRichText.metadataKey]?.value, value.isValid(expectedText: body)
    else { return nil }
    return value
  }
}

/// Web `loadEntryRichTextMap`: each Entry's formatting, kept only while it still matches the
/// body on screen. Formatting is optional, so Entries keep their plain notes when it cannot load.
enum EntryRichTextMap {
  static func load(
    _ entries: [(id: UUID, body: String)], client: SupabaseClient, ownerID: UUID
  ) async -> [UUID: EntryRichText] {
    let bodies = Dictionary(
      entries.map { ($0.id, $0.body) }, uniquingKeysWith: { first, _ in first })
    guard !bodies.isEmpty,
      let rows: [Row] = try? await client.from("entries").select("id,body,metadata")
        .eq("owner_id", value: ownerID.uuidString)
        .in("id", values: bodies.keys.map { $0.uuidString.lowercased() }).execute().value
    else { return [:] }
    return rows.reduce(into: [:]) { values, row in
      if bodies[row.id] == row.body, let richText = row.richText { values[row.id] = richText }
    }
  }

  private struct Row: Decodable, Sendable {
    let id: UUID
    let body: String
    let richText: EntryRichText?

    enum CodingKeys: String, CodingKey {
      case id, body, metadata
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(UUID.self, forKey: .id)
      body = try values.decode(String.self, forKey: .body)
      richText = values.decodeEntryRichText(metadataKey: .metadata, body: body)
    }
  }
}
