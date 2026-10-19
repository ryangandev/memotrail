import XCTest

@testable import MemoTrail

/// Export like Web `lib/export/contracts.ts` and `components/export-settings.tsx`.
final class ExportTests: XCTestCase {
  func testExportSnapshotPreservesCountsAndPortableFilename() throws {
    let json = """
      {"id":"00000000-0000-0000-0000-000000000001","schema_version":1,"captured_at":"2026-09-12T19:00:00.123+00:00","expires_at":"2026-09-13T19:00:00.123+00:00","row_count":1005,"json_bytes":2200000,"datasets":{"entries":1005,"tags":0}}
      """
    let snapshot = try JSONDecoder().decode(ExportSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.rowCount, 1005)
    XCTAssertEqual(snapshot.datasets["tags"], 0)
    XCTAssertEqual(snapshot.filename, "MemoTrail-2026-09-12-00000000.zip")
    let request = try JSONEncoder().encode(ExportInput(action: "download", id: snapshot.id))
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["action", "id"]))
    let id = try XCTUnwrap(UUID(uuidString: "4F8D0FE6-61D0-418A-8713-CF071AEEA450"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let download = try encoder.encode(ExportInput(action: "download", id: id))
    XCTAssertEqual(
      String(decoding: download, as: UTF8.self),
      #"{"action":"download","id":"4f8d0fe6-61d0-418a-8713-cf071aeea450"}"#)
    let list = try encoder.encode(ExportInput(action: "list"))
    XCTAssertEqual(String(decoding: list, as: UTF8.self), #"{"action":"list"}"#)
  }

  func testExportFooterRejectsTruncatedDownloadsAndFalseCompletionText() {
    var tail = Data(repeating: 0, count: ExportAPI.tailSize)
    tail.replaceSubrange(0..<4, with: [0x50, 0x4b, 5, 6])
    tail[20] = UInt8(ExportAPI.completion.utf8.count)
    tail.replaceSubrange(22..<tail.count, with: ExportAPI.completion.utf8)
    XCTAssertTrue(ExportAPI.isComplete(tail))
    for count in 0..<tail.count { XCTAssertFalse(ExportAPI.isComplete(tail.prefix(count))) }
    XCTAssertFalse(ExportAPI.isComplete(tail + Data([0])))
    tail[0] = 0
    XCTAssertFalse(ExportAPI.isComplete(tail))
  }

  func testExportTimesReadLikeWebInTheProfileZoneAndFallBackToUTC() {
    let captured = "2026-09-12T19:05:00.123+00:00"

    XCTAssertEqual(
      ExportSnapshot.timeLabel(captured, timezone: "UTC"), "Sep 12, 2026, 7:05 PM")
    XCTAssertEqual(
      ExportSnapshot.timeLabel(captured, timezone: "Asia/Tokyo"), "Sep 13, 2026, 4:05 AM")
    XCTAssertEqual(
      ExportSnapshot.timeLabel(captured, timezone: "Not/AZone"), "Sep 12, 2026, 7:05 PM")
    XCTAssertEqual(ExportSnapshot.timeLabel("not-a-time", timezone: "UTC"), "not-a-time")
  }

  func testExportKeepsAtMostTwoUnexpiredSnapshotsLikeTheServer() {
    XCTAssertEqual(ExportView.exportLimit, 2)
  }
}
