import XCTest

@testable import MemoTrail

final class EntryRichTextTests: XCTestCase {
  private let document = """
    {"type":"doc","content":[
      {"type":"paragraph","content":[
        {"type":"text","text":"Bold","marks":[{"type":"bold"}]},
        {"type":"hardBreak"},
        {"type":"text","text":"link","marks":[{"type":"link","attrs":{"href":"https://example.com","target":"_blank","rel":null}}]}]},
      {"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Quote"}]}]},
      {"type":"orderedList","attrs":{"start":2,"type":null},"content":[
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"One"}]},
          {"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Nested"}]}]}]}]}]},
      {"type":"codeBlock","attrs":{"language":"text"},"content":[{"type":"text","text":"a\\nb"}]},
      {"type":"paragraph"}]}
    """
  private let text = "Bold\nlink\nQuote\nOne\nNested\na\nb\n"

  private func richText(_ json: String, text: String? = nil) throws -> EntryRichText {
    let node = try JSONDecoder().decode(EntryRichText.Node.self, from: Data(json.utf8))
    return EntryRichText(version: 1, text: text ?? EntryRichText.plainText(node), document: node)
  }

  func testWebShapedDocumentValidatesAndDerivesThePlainBody() throws {
    let value = try richText(document)
    XCTAssertEqual(value.text, text)
    XCTAssertTrue(value.isValid(expectedText: text))
    XCTAssertFalse(value.isValid(expectedText: "Different body"))
  }

  func testInvalidStructuresFallBackToThePlainBody() throws {
    let invalid = [
      #"{"type":"doc","content":[{"type":"listItem","content":[]}]}"#,
      #"{"type":"doc","content":[]}"#,
      #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":""}]}]}"#,
      #"{"type":"doc","content":[{"type":"bulletList","content":[]}]}"#,
      #"{"type":"doc","content":[{"type":"orderedList","attrs":{"start":0},"content":[{"type":"listItem","content":[{"type":"paragraph"}]}]}]}"#,
      #"{"type":"doc","content":[{"type":"paragraph","attrs":{"align":"left"}}]}"#,
      #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"highlight"}]}]}]}"#,
      #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"link","attrs":{"href":"javascript:alert(1)"}}]}]}]}"#,
      #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"bold","attrs":{"level":1}}]}]}]}"#,
    ]
    for json in invalid {
      XCTAssertFalse(try richText(json).isValid(), json)
    }
    XCTAssertFalse(try richText(document, text: "Tampered").isValid())
  }

  func testMetadataReadsOnlyAMatchingBodyRichDocument() throws {
    let value = try richText(document)
    let encoded = try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    let metadata = Data(#"{"source":"web","count":3,"body_rich":\#(encoded)}"#.utf8)
    XCTAssertEqual(EntryRichText.from(metadataJSON: metadata, body: text), value)
    XCTAssertNil(EntryRichText.from(metadataJSON: metadata, body: "Edited on iOS"))
    XCTAssertNil(EntryRichText.from(metadataJSON: Data(#"{"body_rich":7}"#.utf8), body: text))
    XCTAssertNil(EntryRichText.from(metadataJSON: nil, body: text))
  }

  func testOnlyWebMailAndPhoneLinksAreSafe() {
    for link in ["https://example.com", "http://example.com", "mailto:a@example.com", "tel:+1555"] {
      XCTAssertTrue(EntryRichText.safeLink(link), link)
    }
    for link in ["javascript:alert(1)", "file:///etc/hosts", "example.com", nil] {
      XCTAssertFalse(EntryRichText.safeLink(link), link ?? "nil")
    }
  }
}
