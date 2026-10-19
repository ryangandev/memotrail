import UIKit
import XCTest

@testable import MemoTrail

final class VoiceTranscriptTextTests: XCTestCase {
  func testEmptyDraftUsesTranscriptDirectly() {
    XCTAssertEqual(
      VoiceTranscriptText.merging(existingText: "", transcript: "A thought worth keeping"),
      "A thought worth keeping"
    )
  }

  func testExistingDraftAddsTranscriptOnANewLine() {
    XCTAssertEqual(
      VoiceTranscriptText.merging(existingText: "Written first", transcript: "Spoken next"),
      "Written first\nSpoken next"
    )
  }

  func testExistingWhitespaceDoesNotAddAnotherSeparator() {
    XCTAssertEqual(
      VoiceTranscriptText.merging(existingText: "Written first\n", transcript: "Spoken next"),
      "Written first\nSpoken next"
    )
  }

  func testBlankTranscriptPreservesExistingDraft() {
    XCTAssertEqual(
      VoiceTranscriptText.merging(existingText: "Keep this exactly", transcript: "  \n "),
      "Keep this exactly"
    )
  }

  func testMergedTranscriptRespectsBodyLimit() {
    XCTAssertEqual(
      VoiceTranscriptText.merging(
        existingText: "12345",
        transcript: "67890",
        limit: 8
      ),
      "12345\n67"
    )
  }

  func testDictationKeepsTheNoteFormattingAndAddsPlainWords() throws {
    let note = NSMutableAttributedString(string: "Bold start")
    note.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: NSRange(0..<4))
    let merged = VoiceTranscriptText.merging(existingText: note.string, transcript: "spoken")

    let result = VoiceTranscriptText.applying(merged, to: note)

    XCTAssertEqual(result.string, "Bold start\nspoken")
    let bold = try XCTUnwrap(result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    XCTAssertNil(result.attribute(.font, at: result.length - 1, effectiveRange: nil))
  }

  func testDictationIntoAnEmptyNoteIsPlainText() {
    let result = VoiceTranscriptText.applying(
      VoiceTranscriptText.merging(existingText: "", transcript: "Only spoken"),
      to: NSAttributedString())

    XCTAssertEqual(result.string, "Only spoken")
    XCTAssertNil(result.attribute(.font, at: 0, effectiveRange: nil))
  }

  func testDictationThatNoLongerStartsWithTheNoteFallsBackToPlainText() {
    let note = NSAttributedString(
      string: "Different", attributes: [.font: UIFont.italicSystemFont(ofSize: 17)])

    let result = VoiceTranscriptText.applying("Something else", to: note)

    XCTAssertEqual(result.string, "Something else")
    XCTAssertNil(result.attribute(.font, at: 0, effectiveRange: nil))
  }
}
