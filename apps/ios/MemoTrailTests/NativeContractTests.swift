import Foundation
@preconcurrency import Supabase
import UIKit
import XCTest

@testable import MemoTrail

@MainActor
final class NativeContractTests: XCTestCase {
  // Keep synthetic sessions out of the device Keychain, including unsigned test hosts.
  private final class SessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
      lock.lock()
      defer { lock.unlock() }
      values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
      lock.lock()
      defer { lock.unlock() }
      return values[key]
    }

    func remove(key: String) throws {
      lock.lock()
      defer { lock.unlock() }
      values.removeValue(forKey: key)
    }
  }

  private struct Configuration: Decodable {
    let supabaseURL: URL
    let publishableKey: String
    let accessToken: String
    let refreshToken: String
    let ownerID: UUID
  }

  private func client() async throws -> (SupabaseClient, UUID) {
    let path = ProcessInfo.processInfo.environment["MEMOTRAIL_NATIVE_CONTRACT_CONFIG"] ?? ""
    guard !path.isEmpty, !path.contains("$(") else {
      throw XCTSkip("Run apps/ios/scripts/verify-local-contracts.py with the local Supabase stack.")
    }
    let config = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    XCTAssertEqual(config.supabaseURL.host, "127.0.0.1")
    guard config.supabaseURL.host == "127.0.0.1" else { throw URLError(.badURL) }
    let client = SupabaseClient(
      supabaseURL: config.supabaseURL, supabaseKey: config.publishableKey,
      options: .init(
        auth: .init(
          storage: SessionStorage(), storageKey: "native-contract-\(config.ownerID)",
          autoRefreshToken: false, emitLocalSessionAsInitialSession: true)))
    let session = try await client.auth.setSession(
      accessToken: config.accessToken, refreshToken: config.refreshToken)
    XCTAssertEqual(session.user.id, config.ownerID)
    let stored = try await client.auth.session
    XCTAssertEqual(stored.user.id, config.ownerID)
    return (client, config.ownerID)
  }

  func testCaptureReviewLibraryAndSearchUseTheSameEntryIdentity() async throws {
    let (client, ownerID) = try await client()
    let id = UUID()
    let title = "Native contract \(id.uuidString)"
    let payload = InboxEntryInsert(
      id: id, ownerID: ownerID, title: title, body: "A private synthetic Entry.",
      occurredStart: nil, occurredTimezone: "UTC", datePrecision: "unknown",
      clientID: "native-contract:\(id)")
    try await client.from("entries").insert(payload).execute()

    let inbox = InboxController(client: client, ownerID: ownerID)
    await inbox.load()
    XCTAssertNil(inbox.loadErrorMessage)
    let entry = try XCTUnwrap(inbox.entries.first { $0.id == id })
    XCTAssertEqual(entry.itemKind, .entry)
    XCTAssertEqual(entry.itemSubtype, "entry")

    // Browsing lists organized records only, while search also finds Inbox captures.
    let library = LibraryController(client: client, ownerID: ownerID)
    await library.load()
    XCTAssertNil(library.errorMessage)
    XCTAssertFalse(library.items.contains { $0.id == id })
    library.query = title
    await library.search()
    XCTAssertNil(library.searchErrorMessage)
    XCTAssertTrue(try XCTUnwrap(library.results.first { $0.id == id }).isInInbox)

    let result = await inbox.review(
      entry: entry,
      draft: EntryReviewDraft(
        title: title, body: entry.body, collectionNames: ["Native contract"],
        tagNames: ["native-contract"], occurrence: entry.occurrence),
      intent: .done)
    XCTAssertEqual(result.status, .done, result.message)

    library.clearAll()
    await library.load()
    let organized = try XCTUnwrap(library.items.first { $0.id == id })
    XCTAssertEqual(organized.itemKind, .entry)
    XCTAssertFalse(organized.isInInbox)

    library.query = title
    library.classification = .entry
    library.tagName = "native-contract"
    await library.search()
    XCTAssertNil(library.searchErrorMessage)
    let found = try XCTUnwrap(library.results.first { $0.id == id })
    XCTAssertFalse(found.isInInbox)
    XCTAssertEqual(found.tagNames, ["native-contract"])
    XCTAssertEqual(found.collectionNames, ["Native contract"])
    XCTAssertTrue(library.collectionOptions.contains("Native contract"))
    XCTAssertTrue(library.tagOptions.contains("native-contract"))
    library.classification = .goal
    await library.search()
    XCTAssertFalse(library.results.contains { $0.id == id })

    let stale = await inbox.review(
      entry: entry,
      draft: EntryReviewDraft(
        title: title, body: "A stale edit", collectionNames: [], tagNames: [],
        occurrence: entry.occurrence),
      intent: .done)
    XCTAssertEqual(stale.status, .conflict)
  }

  func testInboxReviewKeepsFormattingAndTrashUsesTheCurrentRevision() async throws {
    let (client, ownerID) = try await client()
    let id = UUID()
    try await client.from("entries").insert(
      InboxEntryInsert(
        id: id, ownerID: ownerID, title: nil, body: "Harbor lights", occurredStart: nil,
        occurredTimezone: "UTC", datePrecision: "unknown", clientID: "native-contract:\(id)")
    ).execute()
    let inbox = InboxController(client: client, ownerID: ownerID)
    await inbox.load()
    let capture = try XCTUnwrap(inbox.entries.first { $0.id == id })
    XCTAssertNil(capture.bodyRich)

    let note = NSMutableAttributedString(
      string: "Harbor", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
    note.append(
      NSAttributedString(string: " lights", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
    let rich = try XCTUnwrap(EntryRichText(EntryEmphasisContent(attributedText: note)))
    let saved = await inbox.review(
      entry: capture,
      draft: EntryReviewDraft(
        title: "", body: "Harbor lights", bodyRich: rich, collectionNames: [], tagNames: [],
        occurrence: capture.occurrence),
      intent: .save)
    XCTAssertEqual(saved.status, .saved, saved.message)
    await inbox.load()
    let formatted = try XCTUnwrap(inbox.entries.first { $0.id == id })
    XCTAssertEqual(formatted.bodyRich, rich)
    XCTAssertGreaterThan(formatted.revision, capture.revision)

    // Library search results show the same formatting, like Web `loadEntryRichTextMap`.
    let library = LibraryController(client: client, ownerID: ownerID)
    library.query = "Harbor lights"
    await library.search()
    XCTAssertNil(library.searchErrorMessage)
    XCTAssertEqual(library.results.first { $0.id == id }?.bodyRich, rich)

    // Like Web, a capture moves to Trash only at the revision the person reviewed.
    let stale = await inbox.moveToTrash(capture)
    XCTAssertNotNil(stale)
    XCTAssertTrue(inbox.entries.contains { $0.id == id })
    let trashed = await inbox.moveToTrash(formatted)
    XCTAssertNil(trashed)
    XCTAssertFalse(inbox.entries.contains { $0.id == id })
    await inbox.load()
    XCTAssertNil(inbox.loadErrorMessage)
    XCTAssertFalse(inbox.entries.contains { $0.id == id })
  }

  func testTimelineCreatesMomentAndPeriodWithoutLegacyKinds() async throws {
    let (client, ownerID) = try await client()
    let timeline = TimelineController(client: client, ownerID: ownerID)
    await timeline.load()
    XCTAssertNil(timeline.loadErrorMessage)
    let track = try XCTUnwrap(timeline.tracks.first { $0.systemKey == "other_events" })
    let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
    for (kind, subtype) in [(TimelineKind.event, "moment"), (.stage, "period")] {
      let title = "Native \(subtype) \(UUID().uuidString)"
      let result = await timeline.save(
        entry: nil, trackID: track.id, kind: kind, title: title, body: "Synthetic Timeline record.",
        occurredStart: start, occurredEnd: kind == .stage ? start.addingTimeInterval(86_400) : nil,
        datePrecision: .day, occurredLabel: "", occurredTimezone: "UTC")
      XCTAssertEqual(result.status, .saved, result.message)
      let entry = try XCTUnwrap(timeline.tracks.flatMap(\.entries).first { $0.title == title })
      XCTAssertEqual(entry.itemKind, .entry)
      XCTAssertEqual(entry.itemSubtype, subtype)
    }
  }

  func testHomeWithoutLocationCanBeSavedAndLoaded() async throws {
    let (client, ownerID) = try await client()
    let homes = ResidenceController(client: client, ownerID: ownerID)
    let result = await homes.save(
      entryID: nil, expectedRevision: nil, title: "Native Home \(UUID().uuidString)", body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", placeID: nil, placeName: "", address: "", city: "", region: "",
      country: "", latitude: nil, longitude: nil, placeNotes: "", moveInReason: "",
      moveOutReason: "", collectionNames: [], tagNames: [])
    XCTAssertEqual(result.status, .saved, result.message)
    let identity = try XCTUnwrap(result.identity)
    XCTAssertNil(identity.placeID)
    await homes.load()
    XCTAssertNil(homes.loadErrorMessage)
    let home = try XCTUnwrap(homes.entries.first { $0.id == identity.id })
    XCTAssertNil(home.placeID)
    XCTAssertEqual(home.displayLocation, "Location not added")
  }

  func testMapReadsCurrentOwnedLocationsAndExcludesTrashedRecords() async throws {
    let (client, ownerID) = try await client()
    let homes = ResidenceController(client: client, ownerID: ownerID)
    let result = await homes.save(
      entryID: nil, expectedRevision: nil, title: "Native Map \(UUID().uuidString)", body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", placeID: nil, placeName: "Austin", address: "Austin, Texas",
      city: "Austin", region: "Texas", country: "US", latitude: 30.2672, longitude: -97.7431,
      placeNotes: "", moveInReason: "", moveOutReason: "", collectionNames: [], tagNames: [])
    XCTAssertEqual(result.status, .saved, result.message)
    let identity = try XCTUnwrap(result.identity)
    let snapshot = try await LocationMapRepository(client: client, ownerID: ownerID).load()
    let item = try XCTUnwrap(snapshot.items.first { $0.entryID == identity.id })
    XCTAssertEqual(item.kind, .entity)
    XCTAssertEqual(item.subtype, "home")
    XCTAssertEqual(item.latitude, 30.2672, accuracy: 0.000001)
    XCTAssertEqual(item.city, "Austin")
    XCTAssertFalse(snapshot.truncated)
    await homes.load()
    let home = try XCTUnwrap(homes.entries.first { $0.id == identity.id })
    let removed = await homes.moveToTrash(entryID: home.id, expectedRevision: home.revision)
    XCTAssertEqual(removed.status, .trashed, removed.message)
    let afterTrash = try await LocationMapRepository(client: client, ownerID: ownerID).load()
    XCTAssertFalse(afterTrash.items.contains { $0.entryID == home.id })
  }

  func testFocusedRecordsDecodeInLibraryCollectionsAndHome() async throws {
    let (client, ownerID) = try await client()
    let collectionName = "Native focused \(UUID().uuidString)"
    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    let first = await firstTimes.save(
      entryID: nil, expectedRevision: nil, title: "Native First Time", body: "Synthetic record.",
      occurredStart: nil, datePrecision: .unknown, occurredLabel: "", occurredTimezone: nil,
      collectionNames: [collectionName], tagNames: [])
    XCTAssertEqual(first.status, .saved, first.message)
    let firstID = try XCTUnwrap(first.identity?.id)
    await firstTimes.load()
    XCTAssertNil(firstTimes.loadErrorMessage)
    XCTAssertTrue(firstTimes.entries.contains { $0.id == firstID })

    let vehicles = VehicleController(client: client, ownerID: ownerID)
    let vehicle = await vehicles.save(
      entryID: nil, expectedRevision: nil, title: "Native Vehicle", body: "Synthetic record.",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", make: "Native", model: "Fixture", modelYear: nil, color: "",
      collectionNames: [collectionName], tagNames: [])
    XCTAssertEqual(vehicle.status, .saved, vehicle.message)
    let vehicleID = try XCTUnwrap(vehicle.identity?.id)
    await vehicles.load()
    XCTAssertNil(vehicles.loadErrorMessage)
    XCTAssertTrue(vehicles.entries.contains { $0.id == vehicleID })

    let goals = GoalController(client: client, ownerID: ownerID)
    let goal = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Goal", body: "Synthetic record.",
      horizon: .someday, status: .considering, targetDate: nil, collectionNames: [collectionName],
      tagNames: [], relatedEntryIDs: [firstID])
    XCTAssertEqual(goal.status, .saved, goal.message)
    let goalID = try XCTUnwrap(goal.identity?.id)
    await goals.load()
    XCTAssertNil(goals.loadErrorMessage)
    XCTAssertTrue(goals.entries.contains { $0.id == goalID })

    let library = LibraryController(client: client, ownerID: ownerID)
    await library.load()
    XCTAssertNil(library.errorMessage)
    XCTAssertEqual(library.items.first { $0.id == firstID }?.itemKind, .entry)
    XCTAssertEqual(library.items.first { $0.id == vehicleID }?.itemKind, .entity)
    XCTAssertEqual(library.items.first { $0.id == goalID }?.itemKind, .goal)

    let collections = CollectionsController(client: client, ownerID: ownerID)
    await collections.load()
    XCTAssertNil(collections.loadErrorMessage)
    let collection = try XCTUnwrap(collections.collections.first { $0.name == collectionName })
    let detail = CollectionDetailController(
      client: client, ownerID: ownerID, collectionID: collection.id)
    await detail.load()
    XCTAssertNil(detail.loadErrorMessage)
    XCTAssertEqual(Set(detail.entries.map(\.id)), Set([firstID, vehicleID, goalID]))

    let home = HomeController(client: client, ownerID: ownerID)
    await home.load()
    XCTAssertNil(home.loadErrorMessage)
    XCTAssertNotNil(home.snapshot)
  }
}
