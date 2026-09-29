import UIKit

/// The paragraph and emphasis subset of Web's versioned `metadata.body_rich` contract.
/// Decoding fails for other block structures instead of flattening Web-authored writing.
struct EntryEmphasisContent: Codable, Equatable, Sendable {
  struct Mark: Codable, Equatable, Sendable { let type: String }
  struct Node: Codable, Equatable, Sendable {
    let type: String
    var content: [Node]?
    var text: String?
    var marks: [Mark]?
  }

  let version: Int
  let text: String
  let document: Node

  @MainActor
  init(attributedText: NSAttributedString) {
    version = 1
    text = attributedText.string
    let source = text as NSString
    var offset = 0
    let paragraphs = text.components(separatedBy: "\n").map { line -> Node in
      let range = NSRange(location: offset, length: (line as NSString).length)
      offset += range.length + 1
      var runs: [Node] = []
      attributedText.enumerateAttributes(in: range) { attributes, run, _ in
        let marks = EmphasisStyle.allCases.filter { $0.isApplied(to: attributes) }
          .map { Mark(type: $0.rawValue) }
        let value = source.substring(with: run)
        if let previous = runs.last, previous.marks == (marks.isEmpty ? nil : marks) {
          runs[runs.count - 1].text = (previous.text ?? "") + value
        } else {
          runs.append(Node(type: "text", text: value, marks: marks.isEmpty ? nil : marks))
        }
      }
      return Node(type: "paragraph", content: runs.isEmpty ? nil : runs)
    }
    document = Node(type: "doc", content: paragraphs)
  }

  /// The note as Web stores it: surrounding whitespace trimmed, formatting kept, and
  /// nothing at all when only whitespace remains.
  @MainActor
  static func capture(_ note: NSAttributedString) -> (body: String, rich: Self?) {
    let trimmed = note.trimmingWhitespace()
    guard trimmed.length > 0 else { return ("", nil) }
    let rich = Self(attributedText: trimmed)
    return (trimmed.string, rich.isValid(expectedText: trimmed.string) ? rich : nil)
  }

  /// Validate the exact plaintext alongside the document, as Web does.
  func isValid(expectedText: String? = nil) -> Bool {
    guard version == 1, text.utf16.count <= 50_000,
      expectedText == nil || expectedText == text,
      document.type == "doc", document.text == nil, document.marks == nil,
      let paragraphs = document.content, !paragraphs.isEmpty,
      let bytes = try? JSONEncoder().encode(document), bytes.count <= 250_000
    else { return false }
    var nodes = 1
    var lines: [String] = []
    for paragraph in paragraphs {
      nodes += 1
      guard paragraph.type == "paragraph", paragraph.text == nil, paragraph.marks == nil else {
        return false
      }
      var line = ""
      for run in paragraph.content ?? [] {
        nodes += 1
        guard nodes <= 4_000, run.content == nil else { return false }
        if run.type == "hardBreak" {
          guard run.text == nil, run.marks == nil else { return false }
          line += "\n"
        } else {
          guard run.type == "text", let value = run.text, !value.isEmpty,
            (run.marks ?? []).allSatisfy({ EmphasisStyle(rawValue: $0.type) != nil })
          else { return false }
          line += value
        }
      }
      lines.append(line)
    }
    return nodes <= 4_000 && lines.joined(separator: "\n") == text
  }

  @MainActor
  func attributedText(font: UIFont = .preferredFont(forTextStyle: .body)) -> NSAttributedString? {
    guard isValid() else { return nil }
    let result = NSMutableAttributedString(string: "")
    for (index, paragraph) in (document.content ?? []).enumerated() {
      if index > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
      for run in paragraph.content ?? [] {
        var attributes: [NSAttributedString.Key: Any] = [
          .font: font, .foregroundColor: UIColor.label,
        ]
        for mark in run.marks ?? [] {
          EmphasisStyle(rawValue: mark.type)?.apply(true, to: &attributes, baseFont: font)
        }
        result.append(
          NSAttributedString(
            string: run.type == "hardBreak" ? "\n" : run.text ?? "", attributes: attributes))
      }
    }
    return result
  }
}

enum EmphasisStyle: String, CaseIterable {
  case bold, italic, underline, strike

  var title: String {
    switch self {
    case .bold: "Bold"
    case .italic: "Italic"
    case .underline: "Underline"
    case .strike: "Strikethrough"
    }
  }
  var symbol: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .underline: "underline"
    case .strike: "strikethrough"
    }
  }

  func isApplied(to attributes: [NSAttributedString.Key: Any]) -> Bool {
    let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
    switch self {
    case .bold: return traits.contains(.traitBold)
    case .italic: return traits.contains(.traitItalic)
    case .underline: return (attributes[.underlineStyle] as? Int ?? 0) != 0
    case .strike: return (attributes[.strikethroughStyle] as? Int ?? 0) != 0
    }
  }

  func apply(_ enabled: Bool, to attributes: inout [NSAttributedString.Key: Any], baseFont: UIFont)
  {
    switch self {
    case .bold, .italic:
      let trait: UIFontDescriptor.SymbolicTraits = self == .bold ? .traitBold : .traitItalic
      var traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
      if enabled { traits.insert(trait) } else { traits.remove(trait) }
      let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
      attributes[.font] = UIFont(descriptor: descriptor, size: baseFont.pointSize)
    case .underline, .strike:
      let key: NSAttributedString.Key = self == .underline ? .underlineStyle : .strikethroughStyle
      if enabled {
        attributes[key] = NSUnderlineStyle.single.rawValue
      } else {
        attributes.removeValue(forKey: key)
      }
    }
  }
}

extension NSAttributedString {
  /// Removes leading and trailing whitespace and newlines while keeping inner formatting.
  func trimmingWhitespace() -> NSAttributedString {
    let text = string as NSString
    let characters = CharacterSet.whitespacesAndNewlines
    var start = 0
    var end = text.length
    while start < end, let scalar = UnicodeScalar(text.character(at: start)),
      characters.contains(scalar)
    {
      start += 1
    }
    while end > start, let scalar = UnicodeScalar(text.character(at: end - 1)),
      characters.contains(scalar)
    {
      end -= 1
    }
    return attributedSubstring(from: NSRange(location: start, length: end - start))
  }
}
