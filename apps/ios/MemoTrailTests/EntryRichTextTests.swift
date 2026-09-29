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

  /// An Entry row that reads `body_rich` from its metadata like the app's models.
  private struct Row: Decodable {
    let bodyRich: EntryRichText?

    enum CodingKeys: String, CodingKey { case body, metadata }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      bodyRich = values.decodeEntryRichText(
        metadataKey: .metadata, body: try values.decode(String.self, forKey: .body))
    }
  }

  func testMetadataReadsOnlyAMatchingBodyRichDocument() throws {
    let value = try richText(document)
    let encoded = try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    let body = try String(decoding: JSONEncoder().encode(text), as: UTF8.self)
    func row(_ body: String, _ metadata: String) throws -> Row {
      try JSONDecoder().decode(
        Row.self, from: Data(#"{"body":\#(body),"metadata":\#(metadata)}"#.utf8))
    }
    let metadata = #"{"source":"web","count":3,"body_rich":\#(encoded)}"#
    XCTAssertEqual(try row(body, metadata).bodyRich, value)
    XCTAssertNil(try row(#""Edited on iOS""#, metadata).bodyRich)
    XCTAssertNil(try row(body, #"{"body_rich":7}"#).bodyRich)
    XCTAssertNil(try row(body, "null").bodyRich)
    XCTAssertNil(try JSONDecoder().decode(Row.self, from: Data(#"{"body":"x"}"#.utf8)).bodyRich)
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
