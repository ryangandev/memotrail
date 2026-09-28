import UIKit
import XCTest

@testable import MemoTrail

@MainActor
final class EntryEmphasisContentTests: XCTestCase {
  func testWebPayloadRetainsCombinedMarksUnicodeAndEmptyParagraphs() throws {
    let json =
      #"{"version":1,"text":"A quiet day\n\n记住 👩🏽‍💻\n","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"A quiet ","marks":[{"type":"bold"},{"type":"italic"}]},{"type":"text","text":"day","marks":[{"type":"underline"}]}]},{"type":"paragraph"},{"type":"paragraph","content":[{"type":"text","text":"记住 👩🏽‍💻","marks":[{"type":"strike"}]}]},{"type":"paragraph"}]}}"#
    let payload = try JSONDecoder().decode(EntryEmphasisContent.self, from: Data(json.utf8))
    XCTAssertTrue(payload.isValid(expectedText: "A quiet day\n\n记住 👩🏽‍💻\n"))
    let text = try XCTUnwrap(payload.attributedText())
    XCTAssertEqual(text.string, payload.text)
    let first = text.attributes(at: 0, effectiveRange: nil)
    XCTAssertTrue(EmphasisStyle.bold.isApplied(to: first))
    XCTAssertTrue(EmphasisStyle.italic.isApplied(to: first))
    XCTAssertTrue(
      EmphasisStyle.underline.isApplied(to: text.attributes(at: 8, effectiveRange: nil)))
    let roundTrip = EntryEmphasisContent(attributedText: text)
    XCTAssertTrue(roundTrip.isValid(expectedText: payload.text))
    let attachment = XCTAttachment(
      data: try JSONEncoder().encode(roundTrip), uniformTypeIdentifier: "public.json")
    attachment.name = "Native emphasis contract"
    attachment.lifetime = .keepAlways
    add(attachment)
    let reloaded = try JSONDecoder().decode(
      EntryEmphasisContent.self,
      from: JSONEncoder().encode(roundTrip))
    XCTAssertEqual(reloaded, roundTrip)
    XCTAssertTrue(try XCTUnwrap(reloaded.attributedText()).isEqual(to: text))
  }

  func testStaleUnsupportedAndInvalidDocumentsAreRejectedInsteadOfFlattened() throws {
    let documents = [
      #"{"version":2,"text":"x","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x"}]}]}}"#,
      #"{"version":1,"text":"wrong","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x"}]}]}}"#,
      #"{"version":1,"text":"x","document":{"type":"doc","content":[{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"x"}]}]}]}}"#,
      #"{"version":1,"text":"x","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"link","attrs":{"href":"javascript:alert(1)"}}]}]}]}}"#,
    ]
    for json in documents {
      let value = try JSONDecoder().decode(EntryEmphasisContent.self, from: Data(json.utf8))
      XCTAssertFalse(value.isValid())
      XCTAssertNil(value.attributedText())
    }
    let value = EntryEmphasisContent(attributedText: NSAttributedString(string: "Valid"))
    XCTAssertFalse(value.isValid(expectedText: "Changed on another client"))
  }

  func testHardBreakAndPlaintextLimitsMatchWeb() throws {
    let json =
      #"{"version":1,"text":"a\nb","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a"},{"type":"hardBreak"},{"type":"text","text":"b"}]}]}}"#
    let value = try JSONDecoder().decode(EntryEmphasisContent.self, from: Data(json.utf8))
    XCTAssertEqual(try XCTUnwrap(value.attributedText()).string, "a\nb")
    XCTAssertTrue(
      EntryEmphasisContent(
        attributedText: NSAttributedString(string: String(repeating: "a", count: 50_000))
      ).isValid())
    XCTAssertFalse(
      EntryEmphasisContent(
        attributedText: NSAttributedString(string: String(repeating: "a", count: 50_001))
      ).isValid())
    XCTAssertFalse(
      EntryEmphasisContent(
        attributedText: NSAttributedString(string: String(repeating: "👋", count: 25_001))
      ).isValid())
  }

  func testSelectionFormattingKeepsUnicodeSelectionAndOtherStyles() {
    let view = UITextView()
    view.attributedText = NSAttributedString(
      string: "Hello 👩🏽‍💻 world", attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
    let range = (view.text! as NSString).range(of: "👩🏽‍💻")
    view.selectedRange = range
    let session = NativeRichTextSession()
    session.view = view
    session.toggle(.bold)
    session.toggle(.italic)
    session.toggle(.underline)
    XCTAssertEqual(view.selectedRange, range)
    XCTAssertEqual(view.text, "Hello 👩🏽‍💻 world")
    for style in [EmphasisStyle.bold, .italic, .underline] {
      XCTAssertTrue(
        style.isApplied(to: view.attributedText.attributes(at: range.location, effectiveRange: nil))
      )
      XCTAssertFalse(
        style.isApplied(to: view.attributedText.attributes(at: 0, effectiveRange: nil)))
    }
    session.toggle(.bold)
    XCTAssertFalse(session.styles.contains(.bold))
    XCTAssertTrue(session.styles.contains(.italic))
    XCTAssertTrue(session.styles.contains(.underline))
  }

  func testMixedSelectionAppliesStyleToAllAndClearFormattingIsScoped() {
    let value = NSMutableAttributedString(
      string: "one two three", attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
    var bold: [NSAttributedString.Key: Any] = [:]
    EmphasisStyle.bold.apply(true, to: &bold, baseFont: .preferredFont(forTextStyle: .body))
    value.addAttributes(bold, range: NSRange(location: 0, length: 3))
    let view = UITextView()
    view.attributedText = value
    view.selectedRange = NSRange(location: 0, length: 7)
    let session = NativeRichTextSession()
    session.view = view
    session.toggle(.bold)
    XCTAssertTrue(
      EmphasisStyle.bold.isApplied(to: view.attributedText.attributes(at: 4, effectiveRange: nil)))
    view.selectedRange = NSRange(location: 4, length: 3)
    session.clearFormatting()
    XCTAssertTrue(
      EmphasisStyle.bold.isApplied(to: view.attributedText.attributes(at: 0, effectiveRange: nil)))
    XCTAssertFalse(
      EmphasisStyle.bold.isApplied(to: view.attributedText.attributes(at: 4, effectiveRange: nil)))
  }

  func testCaretFormattingAffectsNewTextAndCompositionIsNotPublished() {
    let view = UITextView()
    let session = NativeRichTextSession()
    session.view = view
    var published = NSAttributedString(string: "")
    session.onChange = { published = $0 }
    session.toggle(.bold)
    view.insertText("记住")
    session.publish()
    XCTAssertEqual(published.string, "记住")
    XCTAssertTrue(
      EmphasisStyle.bold.isApplied(to: published.attributes(at: 0, effectiveRange: nil)))
    view.setMarkedText("汉", selectedRange: NSRange(location: 1, length: 0))
    XCTAssertNotNil(view.markedTextRange)
    let before = NSAttributedString(attributedString: view.attributedText)
    session.toggle(.underline)
    session.publish()
    XCTAssertTrue(before.isEqual(to: view.attributedText))
    XCTAssertEqual(published.string, "记住")
  }
}
