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
}
