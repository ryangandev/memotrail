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

  private func client(session: URLSession = .shared) async throws -> (SupabaseClient, UUID) {
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
          autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
        global: .init(session: session)))
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

  #if DEBUG
    func testOfflineCaptureIsConfirmedOnceAndAnnouncedAgainOnlyWhenItSyncs() async throws {
      let (client, ownerID) = try await client(session: NativeReviewNetwork.session())
      defer { NativeReviewNetwork.isOffline = false }
      let suiteName = "NativeContractTests.\(UUID().uuidString)"
      addTeardownBlock {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
      }
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
      let inbox = InboxController(
        client: client, ownerID: ownerID, queueStore: InboxQueueStore(defaults: defaults))
      // Let the connectivity monitor's first update pass, so each save starts its own sync.
      try await Task.sleep(for: .milliseconds(500))
      let center = MTToastCenter.shared

      // Without a connection the capture stays on this iPhone, confirmed by one toast rather
      // than a problem in the composer.
      NativeReviewNetwork.isOffline = true
      let note = "Offline capture \(UUID().uuidString)"
      var shown = Set(center.toasts.map(\.id))
      let didSave = await inbox.save(title: "", body: note)
      XCTAssertTrue(didSave)
      var announced = try await toasts(after: shown, from: inbox)
      XCTAssertEqual(
        announced.map(\.message),
        ["Saved on this iPhone. MemoTrail will sync when you are online."])
      XCTAssertEqual(announced.map(\.tone), [.info])
      XCTAssertNil(inbox.captureError)
      XCTAssertEqual(inbox.pendingEntries.map(\.body), [note])

      // Retrying while still offline announces it nowhere again.
      shown = Set(center.toasts.map(\.id))
      let retried = await inbox.synchronizePendingEntries()
      XCTAssertFalse(retried)
      XCTAssertTrue(center.toasts.allSatisfy { shown.contains($0.id) })
      XCTAssertNil(inbox.captureError)
      XCTAssertEqual(inbox.pendingEntries.map(\.body), [note])

      // Back online, the waiting capture syncs and is announced as saved.
      NativeReviewNetwork.isOffline = false
      shown = Set(center.toasts.map(\.id))
      let synced = await inbox.synchronizePendingEntries()
      XCTAssertTrue(synced)
      announced = center.toasts.filter { !shown.contains($0.id) }
      XCTAssertEqual(announced.map(\.message), ["Saved to Inbox."])
      XCTAssertTrue(inbox.pendingEntries.isEmpty)
      await inbox.load()
      XCTAssertTrue(inbox.entries.contains { $0.body == note })

      // An online save is announced once, after it syncs, without an offline confirmation.
      let onlineNote = "Online capture \(UUID().uuidString)"
      shown = Set(center.toasts.map(\.id))
      let didSaveOnline = await inbox.save(title: "", body: onlineNote)
      XCTAssertTrue(didSaveOnline)
      announced = try await toasts(after: shown, from: inbox)
      XCTAssertEqual(announced.map(\.message), ["Saved to Inbox."])
      XCTAssertNil(inbox.captureError)
      XCTAssertTrue(inbox.pendingEntries.isEmpty)
    }

    /// Waits for the sync a save starts, then returns the toasts shown since `shown`.
    private func toasts(after shown: Set<UUID>, from inbox: InboxController) async throws
      -> [MTToast]
    {
      let deadline = Date().addingTimeInterval(15)
      while Date() < deadline,
        inbox.isSyncing || MTToastCenter.shared.toasts.allSatisfy({ shown.contains($0.id) })
      {
        try await Task.sleep(for: .milliseconds(100))
      }
      return MTToastCenter.shared.toasts.filter { !shown.contains($0.id) }
    }
  #endif

  func testSettingsSaveAndClearTheProfileLikeWeb() async throws {
    let (client, ownerID) = try await client()
    let settings = SettingsController(client: client, ownerID: ownerID)
    await settings.load()
    XCTAssertNil(settings.loadErrorMessage)
    XCTAssertNotNil(settings.profile)

    let named = await settings.savePreferredName("  River  Gan ")
    XCTAssertEqual(named, .init(isSaved: true, message: "Preferred name saved."))
    let born = await settings.saveBirthDate("1994-04-18")
    XCTAssertEqual(born, .init(isSaved: true, message: "Birth date saved."))
    let zoned = await settings.saveTimezone("Asia/Tokyo")
    XCTAssertEqual(zoned, .init(isSaved: true, message: "Default time zone saved."))
    let future = await settings.saveBirthDate("2999-01-01")
    XCTAssertFalse(future.isSaved)

    let reloaded = SettingsController(client: client, ownerID: ownerID)
    await reloaded.load()
    XCTAssertEqual(
      reloaded.profile,
      ProfileSettings(preferredName: "River Gan", birthDate: "1994-04-18", timezone: "Asia/Tokyo"))

    let cleared = await reloaded.savePreferredName("")
    XCTAssertEqual(cleared, .init(isSaved: true, message: "Preferred name cleared."))
    let removed = await reloaded.saveBirthDate("")
    XCTAssertEqual(removed, .init(isSaved: true, message: "Birth date removed."))
    await settings.load()
    XCTAssertNil(settings.profile?.preferredName)
    XCTAssertNil(settings.profile?.birthDate)
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
      let occurrence = EntryOccurrence(
        precision: .day, start: start,
        end: kind == .stage ? start.addingTimeInterval(86_400) : nil, label: nil, timezone: "UTC")
      let result = await timeline.save(
        entry: nil, trackID: track.id, kind: kind, title: title, body: "Synthetic Timeline record.",
        occurrence: occurrence, collectionNames: ["Native trips"], tagNames: ["native"])
      XCTAssertEqual(result, .init(message: "Moment created.", status: .created))
      let entry = try XCTUnwrap(timeline.entries.first { $0.title == title })
      XCTAssertEqual(entry.itemKind, .entry)
      XCTAssertEqual(entry.itemSubtype, subtype)
      XCTAssertEqual(entry.collectionNames, ["Native trips"])
      XCTAssertEqual(entry.tagNames, ["native"])
    }
    XCTAssertTrue(timeline.collectionOptions.contains("Native trips"))

    // Editing replaces the organization, and Move to Trash removes the moment.
    let moment = try XCTUnwrap(timeline.entries.first { $0.itemSubtype == "moment" })
    let saved = await timeline.save(
      entry: moment, trackID: moment.trackID, kind: .event, title: moment.title,
      body: moment.body, occurrence: moment.occurrence, collectionNames: [], tagNames: ["edited"])
    XCTAssertEqual(saved, .init(message: "Moment saved.", status: .saved))
    let edited = try XCTUnwrap(timeline.entries.first { $0.id == moment.id })
    XCTAssertEqual(edited.collectionNames, [])
    XCTAssertEqual(edited.tagNames, ["edited"])
    let trashed = await timeline.moveToTrash(edited)
    XCTAssertEqual(trashed, .init(message: "Moment moved to Trash.", status: .trashed))
    XCTAssertFalse(timeline.entries.contains { $0.id == moment.id })
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
    XCTAssertEqual(result.status, .created, result.message)
    XCTAssertEqual(result.message, "Home created.")
    let identity = try XCTUnwrap(result.identity)
    XCTAssertNil(identity.placeID)
    await homes.load()
    XCTAssertNil(homes.loadErrorMessage)
    let home = try XCTUnwrap(homes.entries.first { $0.id == identity.id })
    XCTAssertNil(home.placeID)
    XCTAssertEqual(home.displayLocation, "Location not added")

    // Saving again reports Web's saved message and keeps the Home without a Location.
    let edited = await homes.save(
      entryID: home.id, expectedRevision: home.revision, title: home.title, body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "America/Los_Angeles", placeID: nil, placeName: "", address: "",
      city: "", region: "", country: "", latitude: nil, longitude: nil, placeNotes: "",
      moveInReason: "Closer to the water", moveOutReason: "", collectionNames: [], tagNames: [],
      originalEntry: home)
    XCTAssertEqual(edited.status, .saved, edited.message)
    XCTAssertEqual(edited.message, "Home saved.")
    await homes.load()
    XCTAssertEqual(homes.entry(id: home.id)?.moveInReason, "Closer to the water")
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
    XCTAssertEqual(result.status, .created, result.message)
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
    XCTAssertEqual(removed.message, "Home moved to Trash.")
    let afterTrash = try await LocationMapRepository(client: client, ownerID: ownerID).load()
    XCTAssertFalse(afterTrash.items.contains { $0.entryID == home.id })
  }

  func testVehicleLoadsItsLocationAndRemovesItWithTheSave() async throws {
    let (client, ownerID) = try await client()
    let vehicles = VehicleController(client: client, ownerID: ownerID)
    let created = await vehicles.save(
      entryID: nil, expectedRevision: nil, title: "Native Location Vehicle", body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", make: "Honda", model: "Civic", modelYear: 2018, color: "",
      collectionNames: [], tagNames: [])
    XCTAssertEqual(created.status, .created, created.message)
    let identity = try XCTUnwrap(created.identity)

    // Web's address search saves a provider Location through the same RPC.
    let located: [SavedVehicleEntry] =
      try await client.rpc(
        "save_vehicle_with_location",
        params: SyntheticVehicleLocation(entryID: identity.id, revision: identity.revision)
      )
      .execute().value
    XCTAssertEqual(located.first?.entryID, identity.id)
    await vehicles.load()
    XCTAssertNil(vehicles.loadErrorMessage)
    let vehicle = try XCTUnwrap(vehicles.entry(id: identity.id))
    let location = try XCTUnwrap(vehicle.location)
    XCTAssertEqual(location.label, "Pier 39, San Francisco, CA 94133, United States")
    XCTAssertEqual(try XCTUnwrap(location.latitude), 37.8087, accuracy: 0.000001)

    let removed = await vehicles.save(
      entryID: vehicle.id, expectedRevision: vehicle.revision, title: vehicle.title,
      body: "Kept without a Location.", occurredStart: nil, occurredEnd: nil,
      datePrecision: .unknown, occurredLabel: "", occurredTimezone: "UTC", make: "Honda",
      model: "Civic", modelYear: 2018, color: "", collectionNames: [], tagNames: [],
      originalEntry: vehicle, removingLocation: true)
    XCTAssertEqual(removed.status, .saved, removed.message)
    XCTAssertEqual(removed.message, "Vehicle saved.")
    await vehicles.load()
    let saved = try XCTUnwrap(vehicles.entry(id: identity.id))
    XCTAssertNil(saved.location)
    XCTAssertEqual(saved.body, "Kept without a Location.")

    let trashed = await vehicles.moveToTrash(entryID: saved.id, expectedRevision: saved.revision)
    XCTAssertEqual(trashed.status, .trashed, trashed.message)
    XCTAssertEqual(trashed.message, "Vehicle moved to Trash.")
    XCTAssertNil(vehicles.entry(id: identity.id))
  }

  func testFirstTimeLoadsItsLocationAndRemovesItWithTheSave() async throws {
    let (client, ownerID) = try await client()
    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    let created = await firstTimes.save(
      entryID: nil, expectedRevision: nil, title: "Native Location First Time", body: "",
      occurredStart: nil, datePrecision: .unknown, occurredLabel: "", occurredTimezone: nil,
      collectionNames: [], tagNames: [])
    XCTAssertEqual(created.status, .created, created.message)
    XCTAssertEqual(created.message, "First Time added.")
    let identity = try XCTUnwrap(created.identity)

    // Web's address search saves a provider Location through the same RPC.
    let located: [SavedFirstTimeEntry] =
      try await client.rpc(
        "save_first_time_with_location",
        params: SyntheticFirstTimeLocation(entryID: identity.id, revision: identity.revision)
      )
      .execute().value
    XCTAssertEqual(located.first?.entryID, identity.id)
    await firstTimes.load()
    XCTAssertNil(firstTimes.loadErrorMessage)
    let firstTime = try XCTUnwrap(firstTimes.entry(id: identity.id))
    let location = try XCTUnwrap(firstTime.location)
    XCTAssertEqual(location.label, "Ferry Building, San Francisco, CA 94111, United States")
    XCTAssertEqual(try XCTUnwrap(location.longitude), -122.3937, accuracy: 0.000001)

    let removed = await firstTimes.save(
      entryID: firstTime.id, expectedRevision: firstTime.revision, title: firstTime.title,
      body: "Kept without a Location.", occurredStart: nil, datePrecision: .unknown,
      occurredLabel: "", occurredTimezone: nil, collectionNames: [], tagNames: [],
      original: firstTime, removingLocation: true)
    XCTAssertEqual(removed.status, .saved, removed.message)
    XCTAssertEqual(removed.message, "First Time saved.")
    await firstTimes.load()
    let saved = try XCTUnwrap(firstTimes.entry(id: identity.id))
    XCTAssertNil(saved.location)
    XCTAssertEqual(saved.body, "Kept without a Location.")

    let trashed = await firstTimes.moveToTrash(
      entryID: saved.id, expectedRevision: saved.revision)
    XCTAssertEqual(trashed.status, .trashed, trashed.message)
    XCTAssertEqual(trashed.message, "First Time moved to Trash.")
    XCTAssertNil(firstTimes.entry(id: identity.id))
  }

  func testBucketListGoalAchievementCreatesALinkedFirstTime() async throws {
    let (client, ownerID) = try await client()
    let goals = GoalController(client: client, ownerID: ownerID)
    let created = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Bucket List Goal",
      body: "A private reflection.", horizon: .someday, status: .considering,
      targetDate: "2027-05-01", collectionNames: ["Bucket List"], tagNames: [],
      relatedEntryIDs: [])
    XCTAssertEqual(created.status, .created, created.message)
    XCTAssertEqual(created.message, "Goal added.")
    let identity = try XCTUnwrap(created.identity)
    await goals.load(including: identity.id)
    XCTAssertNil(goals.loadErrorMessage)
    let goal = try XCTUnwrap(goals.entry(id: identity.id))
    XCTAssertTrue(goal.isBucketList)
    XCTAssertEqual(goal.targetLabel, "Target May 1, 2027")

    let achieved = await goals.markAchieved(
      entryID: goal.id, expectedRevision: goal.revision, occurredStart: nil,
      datePrecision: .unknown, occurredLabel: "", occurredTimezone: "UTC")
    XCTAssertEqual(achieved.status, .achieved, achieved.message)
    XCTAssertEqual(achieved.message, "Achievement saved, with a linked First Time.")
    let firstTimeID = try XCTUnwrap(achieved.identity?.relatedID)
    await goals.load()
    let saved = try XCTUnwrap(goals.entry(id: identity.id))
    XCTAssertEqual(saved.status, .achieved)
    XCTAssertEqual(saved.achievementEntries.map(\.id), [firstTimeID])
    XCTAssertEqual(saved.achievementEntries.first?.itemSubtype, "first_time")
    XCTAssertTrue(saved.editableRelatedEntries.isEmpty)

    // A stale revision cannot record the achievement twice.
    let repeated = await goals.markAchieved(
      entryID: goal.id, expectedRevision: goal.revision, occurredStart: nil,
      datePrecision: .unknown, occurredLabel: "", occurredTimezone: "UTC")
    XCTAssertEqual(repeated.status, .conflict, repeated.message)

    let trashed = await goals.moveToTrash(entryID: saved.id, expectedRevision: saved.revision)
    XCTAssertEqual(trashed.status, .trashed, trashed.message)
    XCTAssertEqual(trashed.message, "Goal moved to Trash.")
    XCTAssertNil(goals.entry(id: identity.id))
  }

  // Each editor keeps the revision it opened with, while removing a photo creates a revision.
  func testFocusedEditorsMoveToTrashAfterRemovingAPhotoAtTheOpenedRevision() async throws {
    let (client, ownerID) = try await client()

    let goals = GoalController(client: client, ownerID: ownerID)
    let createdGoal = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo Goal", body: "",
      horizon: .someday, status: .considering, targetDate: nil, collectionNames: [],
      tagNames: [], relatedEntryIDs: [])
    let goalID = try XCTUnwrap(createdGoal.identity?.id, createdGoal.message)
    let goalUpload = try await goals.upload(photoDraft(), entryID: goalID)
    XCTAssertEqual(goalUpload.status, .saved, goalUpload.message)
    await goals.load(including: goalID)
    let goal = try XCTUnwrap(goals.entry(id: goalID))
    let goalPhoto = try await goals.removeAttachment(XCTUnwrap(goal.attachments.first))
    XCTAssertEqual(goalPhoto.status, .trashed, goalPhoto.message)
    await goals.reloadAfterMutation()
    XCTAssertEqual(goals.entry(id: goalID)?.revision, goal.revision + 1)
    let trashedGoal = await goals.moveToTrash(entryID: goal.id, expectedRevision: goal.revision)
    XCTAssertEqual(trashedGoal.status, .trashed, trashedGoal.message)

    let homes = ResidenceController(client: client, ownerID: ownerID)
    let createdHome = await homes.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo Home", body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", placeID: nil, placeName: "", address: "", city: "", region: "",
      country: "", latitude: nil, longitude: nil, placeNotes: "", moveInReason: "",
      moveOutReason: "", collectionNames: [], tagNames: [])
    let homeID = try XCTUnwrap(createdHome.identity?.id, createdHome.message)
    let homeUpload = try await homes.upload(photoDraft(), entryID: homeID)
    XCTAssertEqual(homeUpload.status, .saved, homeUpload.message)
    await homes.load()
    let home = try XCTUnwrap(homes.entry(id: homeID))
    let homePhoto = try await homes.removeAttachment(XCTUnwrap(home.attachments.first))
    XCTAssertEqual(homePhoto.status, .trashed, homePhoto.message)
    let trashedHome = await homes.moveToTrash(entryID: home.id, expectedRevision: home.revision)
    XCTAssertEqual(trashedHome.status, .trashed, trashedHome.message)

    let vehicles = VehicleController(client: client, ownerID: ownerID)
    let createdVehicle = await vehicles.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo Vehicle", body: "",
      occurredStart: nil, occurredEnd: nil, datePrecision: .unknown, occurredLabel: "",
      occurredTimezone: "UTC", make: "Honda", model: "Civic", modelYear: 2018, color: "",
      collectionNames: [], tagNames: [])
    let vehicleID = try XCTUnwrap(createdVehicle.identity?.id, createdVehicle.message)
    let vehicleUpload = try await vehicles.upload(photoDraft(), entryID: vehicleID)
    XCTAssertEqual(vehicleUpload.status, .saved, vehicleUpload.message)
    await vehicles.load()
    let vehicle = try XCTUnwrap(vehicles.entry(id: vehicleID))
    let vehiclePhoto = try await vehicles.removeAttachment(XCTUnwrap(vehicle.attachments.first))
    XCTAssertEqual(vehiclePhoto.status, .trashed, vehiclePhoto.message)
    let trashedVehicle = await vehicles.moveToTrash(
      entryID: vehicle.id, expectedRevision: vehicle.revision)
    XCTAssertEqual(trashedVehicle.status, .trashed, trashedVehicle.message)

    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    let createdFirstTime = await firstTimes.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo First Time", body: "",
      occurredStart: nil, datePrecision: .unknown, occurredLabel: "", occurredTimezone: nil,
      collectionNames: [], tagNames: [])
    let firstTimeID = try XCTUnwrap(createdFirstTime.identity?.id, createdFirstTime.message)
    let firstTimeUpload = try await firstTimes.upload(photoDraft(), entryID: firstTimeID)
    XCTAssertEqual(firstTimeUpload.status, .saved, firstTimeUpload.message)
    await firstTimes.load()
    let firstTime = try XCTUnwrap(firstTimes.entry(id: firstTimeID))
    let firstTimePhoto = try await firstTimes.removeAttachment(
      XCTUnwrap(firstTime.attachments.first))
    XCTAssertEqual(firstTimePhoto.status, .trashed, firstTimePhoto.message)
    let trashedFirstTime = await firstTimes.moveToTrash(
      entryID: firstTime.id, expectedRevision: firstTime.revision)
    XCTAssertEqual(trashedFirstTime.status, .trashed, trashedFirstTime.message)

    // Writing from another device is still never adopted.
    let createdConflict = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo Conflict", body: "",
      horizon: .someday, status: .considering, targetDate: nil, collectionNames: [],
      tagNames: [], relatedEntryIDs: [])
    let conflictID = try XCTUnwrap(createdConflict.identity?.id, createdConflict.message)
    let conflictUpload = try await goals.upload(photoDraft(), entryID: conflictID)
    XCTAssertEqual(conflictUpload.status, .saved, conflictUpload.message)
    await goals.load(including: conflictID)
    let conflict = try XCTUnwrap(goals.entry(id: conflictID))
    let conflictPhoto = try await goals.removeAttachment(XCTUnwrap(conflict.attachments.first))
    XCTAssertEqual(conflictPhoto.status, .trashed, conflictPhoto.message)
    try await client.from("entries").update(["body": "Other device writing"])
      .eq("id", value: conflictID.uuidString).execute()
    let refused = await goals.moveToTrash(entryID: conflict.id, expectedRevision: conflict.revision)
    XCTAssertEqual(refused.status, .conflict, refused.message)
    XCTAssertEqual(
      refused.message, "This Goal changed on another device. Close it, refresh, and try again.")
    await goals.load(including: conflictID)
    XCTAssertEqual(goals.entry(id: conflictID)?.body, "Other device writing")
  }

  func testBucketListGoalIsAchievedAfterRemovingAPhotoAtTheOpenedRevision() async throws {
    let (client, ownerID) = try await client()
    let goals = GoalController(client: client, ownerID: ownerID)
    let created = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Photo Bucket List Goal", body: "",
      horizon: .someday, status: .considering, targetDate: nil,
      collectionNames: ["Bucket List"], tagNames: [], relatedEntryIDs: [])
    let goalID = try XCTUnwrap(created.identity?.id, created.message)
    let upload = try await goals.upload(photoDraft(), entryID: goalID)
    XCTAssertEqual(upload.status, .saved, upload.message)
    await goals.load(including: goalID)
    let goal = try XCTUnwrap(goals.entry(id: goalID))
    XCTAssertTrue(goal.isBucketList)
    let removed = try await goals.removeAttachment(XCTUnwrap(goal.attachments.first))
    XCTAssertEqual(removed.status, .trashed, removed.message)

    let achieved = await goals.markAchieved(
      entryID: goal.id, expectedRevision: goal.revision, occurredStart: nil,
      datePrecision: .unknown, occurredLabel: "", occurredTimezone: "UTC")
    XCTAssertEqual(achieved.status, .achieved, achieved.message)
    let firstTimeID = try XCTUnwrap(achieved.identity?.relatedID)
    await goals.load(including: goalID)
    let saved = try XCTUnwrap(goals.entry(id: goalID))
    XCTAssertEqual(saved.status, .achieved)
    XCTAssertEqual(saved.achievementEntries.map(\.id), [firstTimeID])
    XCTAssertTrue(saved.attachments.isEmpty)
  }

  private func photoDraft() throws -> FirstTimePhotoDraft {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
      .pngData { context in
        UIColor.systemGreen.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
      }
    return try FirstTimePhotoDraft.validate(
      data: data, mimeType: .png, originalFilename: "kept.png", pixelWidth: 4, pixelHeight: 4)
  }

  func testPersonLinksItemsAndMovesToTrashOnlyOnceUnlinked() async throws {
    let (client, ownerID) = try await client()
    let goals = GoalController(client: client, ownerID: ownerID)
    let goal = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Person link", body: "",
      horizon: .someday, status: .considering, targetDate: nil, collectionNames: [],
      tagNames: [], relatedEntryIDs: [])
    let goalID = try XCTUnwrap(goal.identity?.id)

    let people = PeopleController(client: client, ownerID: ownerID)
    await people.load()
    XCTAssertNil(people.loadErrorMessage)
    XCTAssertTrue(people.linkOptions.contains { $0.id == goalID })
    let created = await people.save(
      PersonSaveInput(
        personID: nil, expectedRevision: nil, name: "Native Friend", relationshipLabel: "Mentor",
        notes: "Met on a synthetic trail.", relatedEntryIDs: [goalID]))
    XCTAssertEqual(created.status, .created, created.message)
    XCTAssertEqual(created.message, "Person created.")
    let personID = try XCTUnwrap(created.personID)
    let person = try XCTUnwrap(people.person(id: personID))
    XCTAssertEqual(person.linkedEntries.map(\.id), [goalID])
    XCTAssertEqual(person.linkedEntries.first?.itemKind, .goal)
    XCTAssertEqual(people.people.first?.id, personID)

    // Like Web, a Person keeps out of Trash while Items are linked.
    let blocked = await people.moveToTrash(person)
    XCTAssertEqual(blocked.status, .conflict, blocked.message)

    // A Person's own page loads them by ID, whatever pages have loaded.
    let focused = PeopleController(client: client, ownerID: ownerID)
    let opened = await focused.loadPerson(id: personID)
    XCTAssertEqual(opened, .loaded)
    XCTAssertEqual(focused.person(id: personID)?.relationshipLabel, "Mentor")

    let unlinked = await people.save(
      PersonSaveInput(
        personID: personID, expectedRevision: person.revision, name: "Native Friend",
        relationshipLabel: " ", notes: "", relatedEntryIDs: []))
    XCTAssertEqual(unlinked.status, .saved, unlinked.message)
    XCTAssertEqual(unlinked.message, "Person saved.")
    let saved = try XCTUnwrap(people.person(id: personID))
    XCTAssertTrue(saved.linkedEntries.isEmpty)
    XCTAssertNil(saved.relationshipLabel)

    // A stale revision cannot overwrite the newer save.
    let stale = await people.save(
      PersonSaveInput(
        personID: personID, expectedRevision: person.revision, name: "Stale Friend",
        relationshipLabel: "", notes: "", relatedEntryIDs: []))
    XCTAssertEqual(stale.status, .conflict, stale.message)

    let trashed = await people.moveToTrash(saved)
    XCTAssertEqual(trashed.status, .trashed, trashed.message)
    XCTAssertEqual(trashed.message, "Person moved to Trash.")
    XCTAssertNil(people.person(id: personID))
    XCTAssertFalse(people.people.contains { $0.id == personID })
    let reopened = await focused.loadPerson(id: personID)
    XCTAssertEqual(reopened, .unavailable)
  }

  func testItemHistoryRestoresLinksCreatesALinkedGoalAndMovesToTrash() async throws {
    let (client, ownerID) = try await client()
    let inbox = InboxController(client: client, ownerID: ownerID)
    var ids: [UUID] = []
    for body in ["Native item source", "Native item target"] {
      let id = UUID()
      try await client.from("entries").insert(
        InboxEntryInsert(
          id: id, ownerID: ownerID, title: nil, body: body, occurredStart: nil,
          occurredTimezone: "UTC", datePrecision: "unknown", clientID: "native-contract:\(id)")
      ).execute()
      await inbox.load()
      let capture = try XCTUnwrap(inbox.entries.first { $0.id == id })
      let saved = await inbox.review(
        entry: capture,
        draft: EntryReviewDraft(
          title: "", body: body, bodyRich: nil, collectionNames: [], tagNames: [],
          occurrence: capture.occurrence),
        intent: .done)
      XCTAssertEqual(saved.status, .done, saved.message)
      ids.append(id)
    }
    let (sourceID, targetID) = (ids[0], ids[1])

    // The Item page loads the current snapshot and the version from before its review.
    let item = EntryHistoryController(client: client, ownerID: ownerID, entryID: sourceID)
    await item.load()
    XCTAssertFalse(item.loadFailed)
    let loaded = try XCTUnwrap(item.record)
    XCTAssertEqual(loaded.title, "Native item source")
    XCTAssertEqual(loaded.identityLabel, "Entry")
    XCTAssertFalse(loaded.isDeleted)
    XCTAssertFalse(loaded.versions.isEmpty)
    let editable = await item.editableEntry()
    XCTAssertEqual(editable?.id, sourceID)

    // Linking another Item saves a revision whose earlier version lacks the link.
    let linked: Int? = try await client.rpc(
      "set_entry_relation",
      params: EntryRelationChange(
        entryID: sourceID, targetID: targetID, expectedRevision: loaded.revision, linked: true)
    ).execute().value
    XCTAssertEqual(linked, loaded.revision + 1)
    await item.reload()
    let withLink = try XCTUnwrap(item.record)
    XCTAssertEqual(withLink.current["links"]?.array?.count, 1)
    let beforeLink = try XCTUnwrap(withLink.versions.first)
    // The server still archives the schema this client restores.
    XCTAssertTrue(HistoryPresentation.canRestore(beforeLink.snapshot))
    XCTAssertEqual(
      HistoryPresentation.differences(current: withLink.current, previous: beforeLink.snapshot),
      ["Entry links"])

    // Restoring that version removes the link; a page still showing the old revision cannot.
    let stale = EntryHistoryController(client: client, ownerID: ownerID, entryID: sourceID)
    await stale.load()
    let restored = await item.restore(version: beforeLink.version)
    XCTAssertNil(restored)
    XCTAssertEqual(item.record?.current["links"]?.array?.count, 0)
    let conflict = await stale.restore(version: beforeLink.version)
    XCTAssertEqual(
      conflict,
      "This Entry changed on another device or is in Trash. Refresh or restore it from Trash first."
    )

    // A linked Goal starts from a valid title and links both ways.
    let invalid = await item.extractGoal(
      goalID: UUID(), title: " ", horizon: .someday, status: .considering, targetDate: nil)
    XCTAssertEqual(
      invalid,
      .failure(
        GoalExtractionFailure(
          message: "Add a Goal title up to 200 characters and a valid optional target date.")))
    let goalID = UUID()
    let extracted = await item.extractGoal(
      goalID: goalID, title: "Native linked Goal", horizon: .shortTerm, status: .active,
      targetDate: nil)
    XCTAssertEqual(extracted, .success(goalID))
    await item.reload()
    XCTAssertTrue(
      item.record?.provenanceLinks.contains {
        $0.targetID == goalID && $0.title == "Open extracted item"
      } == true)
    let goal = EntryHistoryController(client: client, ownerID: ownerID, entryID: goalID)
    await goal.load()
    XCTAssertEqual(goal.record?.itemKind, .goal)
    XCTAssertTrue(
      goal.record?.provenanceLinks.contains {
        $0.targetID == sourceID && $0.title == "Open source item"
      } == true)

    // Like Web `trashWikiItem`, Move to Trash applies only at the revision shown.
    let staleTrash = await stale.moveToTrash()
    XCTAssertEqual(
      staleTrash,
      "This item changed on another device or is already in Trash. Refresh and try again.")
    let trashed = await item.moveToTrash()
    XCTAssertNil(trashed)
    await item.reload()
    XCTAssertEqual(item.record?.isDeleted, true)
  }

  func testItemHistoryKeepsARestoreWhenAnEarlierRefreshReturnsLast() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let sourceID = try await reviewedEntry(
      "Native refresh source", client: client, ownerID: ownerID)
    let targetID = try await reviewedEntry(
      "Native refresh target", client: client, ownerID: ownerID)
    let item = EntryHistoryController(client: client, ownerID: ownerID, entryID: sourceID)
    await item.load()
    let loaded = try XCTUnwrap(item.record)
    let linked: Int? = try await client.rpc(
      "set_entry_relation",
      params: EntryRelationChange(
        entryID: sourceID, targetID: targetID, expectedRevision: loaded.revision, linked: true)
    ).execute().value
    XCTAssertEqual(linked, loaded.revision + 1)
    await item.reload()
    let withLink = try XCTUnwrap(item.record)
    XCTAssertEqual(withLink.current["links"]?.array?.count, 1)
    let beforeLink = try XCTUnwrap(withLink.versions.first)

    // Pull to refresh reads the linked revision, but its response arrives last.
    HeldResponseProtocol.gate.holdNextResponse(toRPC: "entry_history")
    defer { HeldResponseProtocol.gate.releaseHeldResponse() }
    let refresh = Task { await item.load(page: item.page) }
    try await waitForHeldResponse()

    // The restore reloads first, and the slower refresh must not bring the link back.
    let restored = await item.restore(version: beforeLink.version)
    XCTAssertNil(restored)
    XCTAssertEqual(item.record?.current["links"]?.array?.count, 0)
    HeldResponseProtocol.gate.releaseHeldResponse()
    await refresh.value
    XCTAssertEqual(item.record?.current["links"]?.array?.count, 0)
    XCTAssertGreaterThan(item.record?.revision ?? 0, withLink.revision)
    XCTAssertFalse(item.isLoading)
    XCTAssertFalse(item.loadFailed)
  }

  func testTimelineKeepsASavedMomentWhenAnEarlierRefreshReturnsLast() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let timeline = TimelineController(client: client, ownerID: ownerID)
    await timeline.load()
    XCTAssertNil(timeline.loadErrorMessage)
    let track = try XCTUnwrap(timeline.tracks.first { $0.systemKey == "other_events" })

    // Pull to refresh reads the Timeline before the save, but its response arrives last.
    HeldResponseProtocol.gate.holdNextResponse(toRPC: "timeline_workspace_with_organization")
    defer { HeldResponseProtocol.gate.releaseHeldResponse() }
    let refresh = Task { await timeline.load() }
    try await waitForHeldResponse()

    let title = "Native refresh moment \(UUID().uuidString)"
    let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-01T12:00:00Z"))
    let created = await timeline.save(
      entry: nil, trackID: track.id, kind: .event, title: title, body: "Synthetic Timeline record.",
      occurrence: EntryOccurrence(
        precision: .day, start: start, end: nil, label: nil, timezone: "UTC"),
      collectionNames: [], tagNames: [])
    XCTAssertEqual(created, .init(message: "Moment created.", status: .created))
    XCTAssertTrue(timeline.entries.contains { $0.title == title })
    HeldResponseProtocol.gate.releaseHeldResponse()
    await refresh.value
    XCTAssertTrue(timeline.entries.contains { $0.title == title })
    XCTAssertFalse(timeline.isLoading)
    XCTAssertNil(timeline.loadErrorMessage)
  }

  func testPeopleListIncludesAPersonSavedWhileTheFirstLoadRuns() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let people = PeopleController(client: client, ownerID: ownerID)

    // The first load reads People before the save, but its response arrives last.
    HeldResponseProtocol.gate.holdNextResponse(toRPC: "people_workspace")
    defer { HeldResponseProtocol.gate.releaseHeldResponse() }
    let firstLoad = Task { await people.load() }
    try await waitForHeldResponse()

    let created = await people.save(
      PersonSaveInput(
        personID: nil, expectedRevision: nil, name: "Native Refresh Friend",
        relationshipLabel: "", notes: "", relatedEntryIDs: []))
    XCTAssertEqual(created.status, .created, created.message)
    let personID = try XCTUnwrap(created.personID)
    XCTAssertTrue(people.people.contains { $0.id == personID })
    HeldResponseProtocol.gate.releaseHeldResponse()
    await firstLoad.value
    XCTAssertTrue(people.people.contains { $0.id == personID })
    XCTAssertTrue(people.hasLoaded)
    XCTAssertFalse(people.isLoading)
    XCTAssertNil(people.loadErrorMessage)
  }

  func testTrashKeepsARestoreWhenAnEarlierRefreshReturnsLast() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    let entryID = try await reviewedEntry("Native refresh Trash", client: client, ownerID: ownerID)
    let item = EntryHistoryController(client: client, ownerID: ownerID, entryID: entryID)
    await item.load()
    let movedToTrash = await item.moveToTrash()
    XCTAssertNil(movedToTrash)
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    let trashed = try XCTUnwrap(trash.items.first { $0.itemID == entryID })

    // Pull to refresh reads Trash before the restore, but its response arrives last.
    HeldResponseProtocol.gate.holdNextResponse(toRPC: "trash_workspace")
    defer { HeldResponseProtocol.gate.releaseHeldResponse() }
    let refresh = Task { await trash.load() }
    try await waitForHeldResponse()

    let restored = await trash.restore(trashed)
    XCTAssertEqual(restored, .init(message: "Item restored.", tone: .success))
    XCTAssertFalse(trash.items.contains { $0.itemID == entryID })
    HeldResponseProtocol.gate.releaseHeldResponse()
    await refresh.value
    XCTAssertFalse(trash.items.contains { $0.itemID == entryID })
    XCTAssertFalse(trash.isLoading)
    XCTAssertNil(trash.loadErrorMessage)
  }

  /// A synthetic capture saved to the Library through Inbox review.
  private func reviewedEntry(
    _ body: String, client: SupabaseClient, ownerID: UUID
  ) async throws -> UUID {
    let id = UUID()
    try await client.from("entries").insert(
      InboxEntryInsert(
        id: id, ownerID: ownerID, title: nil, body: body, occurredStart: nil,
        occurredTimezone: "UTC", datePrecision: "unknown", clientID: "native-contract:\(id)")
    ).execute()
    let inbox = InboxController(client: client, ownerID: ownerID)
    await inbox.load()
    let capture = try XCTUnwrap(inbox.entries.first { $0.id == id })
    let saved = await inbox.review(
      entry: capture,
      draft: EntryReviewDraft(
        title: "", body: body, bodyRich: nil, collectionNames: [], tagNames: [],
        occurrence: capture.occurrence),
      intent: .done)
    XCTAssertEqual(saved.status, .done, saved.message)
    return id
  }

  /// Waits until the server has answered the held call, so it read the data before what follows.
  private func waitForHeldResponse() async throws {
    for _ in 0..<1_000 {
      if HeldResponseProtocol.gate.hasHeldResponse { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("The held response never arrived.")
    throw URLError(.timedOut)
  }

  func testFocusedRecordsDecodeInLibraryCollectionsAndHome() async throws {
    let (client, ownerID) = try await client()
    let collectionName = "Native focused \(UUID().uuidString)"
    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    let first = await firstTimes.save(
      entryID: nil, expectedRevision: nil, title: "Native First Time", body: "Synthetic record.",
      occurredStart: nil, datePrecision: .unknown, occurredLabel: "", occurredTimezone: nil,
      collectionNames: [collectionName], tagNames: [])
    XCTAssertEqual(first.status, .created, first.message)
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
    XCTAssertEqual(vehicle.status, .created, vehicle.message)
    let vehicleID = try XCTUnwrap(vehicle.identity?.id)
    await vehicles.load()
    XCTAssertNil(vehicles.loadErrorMessage)
    XCTAssertTrue(vehicles.entries.contains { $0.id == vehicleID })

    let goals = GoalController(client: client, ownerID: ownerID)
    let goal = await goals.save(
      entryID: nil, expectedRevision: nil, title: "Native Goal", body: "Synthetic record.",
      horizon: .someday, status: .considering, targetDate: nil, collectionNames: [collectionName],
      tagNames: [], relatedEntryIDs: [firstID])
    XCTAssertEqual(goal.status, .created, goal.message)
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

/// A provider Location as Web address search submits it, for a synthetic local Vehicle.
private struct SyntheticVehicleLocation: Encodable {
  let entryID: UUID
  let revision: Int

  private enum CodingKeys: String, CodingKey {
    case input = "p_input"
    case source = "p_source"
    case location = "p_location"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(
      [
        "id": AnyJSON.string(entryID.uuidString), "revision": .integer(revision),
        "title": "Native Location Vehicle", "body": "", "datePrecision": "unknown",
        "occurredTimezone": "UTC", "make": "Honda", "model": "Civic", "modelYear": .integer(2018),
        "collectionNames": [], "tagNames": [],
      ] as [String: AnyJSON], forKey: .input)
    try values.encodeNil(forKey: .source)
    try values.encode(
      [
        "kind": "provider", "provider": "geoapify",
        "providerLocationId": "native-contract-pier-39",
        "formattedAddress": "Pier 39, San Francisco, CA 94133, United States",
        "address": "Beach Street", "city": "San Francisco", "region": "CA",
        "country": "United States", "countryCode": "us",
        "latitude": .double(37.8087), "longitude": .double(-122.4098),
      ] as [String: AnyJSON], forKey: .location)
  }
}

/// A provider Location as Web address search submits it, for a synthetic local First Time.
private struct SyntheticFirstTimeLocation: Encodable {
  let entryID: UUID
  let revision: Int

  private enum CodingKeys: String, CodingKey {
    case input = "p_input"
    case location = "p_location"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(
      [
        "id": AnyJSON.string(entryID.uuidString), "revision": .integer(revision),
        "title": "Native Location First Time", "body": "", "datePrecision": "unknown",
        "collectionNames": [], "tagNames": [],
      ] as [String: AnyJSON], forKey: .input)
    try values.encode(
      [
        "kind": "provider", "provider": "geoapify",
        "providerLocationId": "native-contract-ferry-building",
        "formattedAddress": "Ferry Building, San Francisco, CA 94111, United States",
        "city": "San Francisco", "region": "CA", "country": "United States",
        "countryCode": "us", "latitude": .double(37.7955), "longitude": .double(-122.3937),
      ] as [String: AnyJSON], forKey: .location)
  }
}

/// Passes each request through to the local stack, but can hold the response to one RPC call
/// until the test releases it, so an earlier load can return after a later one.
private final class HeldResponseProtocol: URLProtocol {
  static let gate = ResponseGate()
  /// A session whose requests pass through this protocol.
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HeldResponseProtocol.self]
    return URLSession(configuration: configuration)
  }()
  private static let upstream = URLSession(configuration: .ephemeral)
  private var upstreamTask: URLSessionDataTask?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var forwarded = request
    // URLSession hands a protocol the request body as a stream.
    if forwarded.httpBody == nil, let stream = forwarded.httpBodyStream {
      forwarded.httpBodyStream = nil
      forwarded.httpBody = stream.readAll()
    }
    let isHeld = Self.gate.claims(forwarded)
    let reference = LoaderReference(loader: self)
    upstreamTask = Self.upstream.dataTask(with: forwarded) { data, response, error in
      let deliver: @Sendable () -> Void = {
        let loader = reference.loader
        if let response {
          loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data { loader.client?.urlProtocol(loader, didLoad: data) }
        if let error {
          loader.client?.urlProtocol(loader, didFailWithError: error)
        } else {
          loader.client?.urlProtocolDidFinishLoading(loader)
        }
      }
      if isHeld {
        HeldResponseProtocol.gate.hold(deliver)
      } else {
        DispatchQueue.global().async(execute: deliver)
      }
    }
    upstreamTask?.resume()
  }

  override func stopLoading() { upstreamTask?.cancel() }
}

/// URLSession calls back on its own queue; this carries the loading protocol into those calls.
private struct LoaderReference: @unchecked Sendable {
  let loader: HeldResponseProtocol
}

/// The RPC whose next response waits, and that response once the server has answered.
private final class ResponseGate: @unchecked Sendable {
  private let lock = NSLock()
  private var rpc: String?
  private var heldDelivery: (@Sendable () -> Void)?

  /// Holds the response to the next call of `rpc`, once the server has answered it.
  func holdNextResponse(toRPC rpc: String) {
    lock.withLock {
      self.rpc = rpc
      heldDelivery = nil
    }
  }

  /// Whether the held call has been answered, so it read the data before anything that follows.
  var hasHeldResponse: Bool { lock.withLock { heldDelivery != nil } }

  /// Delivers the held response, and stops holding a call that has not started yet.
  func releaseHeldResponse() {
    let delivery = lock.withLock {
      defer {
        rpc = nil
        heldDelivery = nil
      }
      return heldDelivery
    }
    if let delivery { DispatchQueue.global().async(execute: delivery) }
  }

  fileprivate func claims(_ request: URLRequest) -> Bool {
    lock.withLock {
      guard let rpc, request.url?.path.hasSuffix("/rpc/\(rpc)") == true else { return false }
      self.rpc = nil
      return true
    }
  }

  fileprivate func hold(_ delivery: @escaping @Sendable () -> Void) {
    lock.withLock { heldDelivery = delivery }
  }
}

extension InputStream {
  fileprivate func readAll() -> Data {
    open()
    defer { close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while hasBytesAvailable {
      let count = read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
