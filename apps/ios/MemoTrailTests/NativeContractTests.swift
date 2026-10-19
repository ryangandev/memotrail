import Foundation
@preconcurrency import Supabase
import UIKit
import XCTest

@testable import MemoTrail

/// Native contracts against the local Supabase stack. `verify-local-contracts.py` signs in a
/// disposable account and passes its session in `MEMOTRAIL_NATIVE_CONTRACT_CONFIG`; without it
/// every test skips.
///
/// This file is the shared harness: the configured client and the helpers below. Each feature
/// adds its own tests in `NativeContractTests+<Area>.swift` as `extension NativeContractTests`,
/// so identifiers stay `MemoTrailTests/NativeContractTests/<test>`.
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

  /// A client signed in as the disposable contract account, sending through `session`.
  func client(session: URLSession = .shared) async throws -> (SupabaseClient, UUID) {
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

  // MARK: P1 contracts

  /// Calls every RPC, table, and Storage path iOS uses through the app's own parameter types,
  /// so a renamed argument (PGRST202), a missing column (PGRST204), or a changed return shape
  /// fails here before any screen meets it. The Web API routes (`/api/media/*`, `/api/export`)
  /// are not part of the schema and are covered by the Web suite.
  func testEveryNativeRPCResolvesAgainstTheCurrentSchema() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let tag = "smoke \(marker)"
    let lisbon = "Europe/Lisbon"

    // save_entry: a closed Chapter, and a formatted First Time dated inside it.
    let chapterID = UUID()
    let chapterStart = try XCTUnwrap(EntryTimestamp.date(from: "2021-03-01T12:00:00Z"))
    let chapterEnd = try XCTUnwrap(EntryTimestamp.date(from: "2021-08-01T12:00:00Z"))
    let chapter = try await api.save(
      SaveEntryParameters(
        entryID: chapterID, expectedRevision: nil, title: "Smoke Chapter \(marker)", body: "",
        richText: nil,
        occurrence: EntryOccurrence(
          precision: .month, start: chapterStart, end: chapterEnd, label: nil, timezone: lisbon),
        tagNames: [], location: nil, marks: .chapter))
    XCTAssertEqual(chapter, SavedEntry(entryID: chapterID, revision: 1))
    let entryID = UUID()
    let body = "Harbor lights"
    let richText = try JSONDecoder().decode(
      EntryRichText.self,
      from: Data(
        #"{"version":1,"text":"Harbor lights","document":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Harbor","marks":[{"type":"bold"}]},{"type":"text","text":" lights"}]}]}}"#
          .utf8))
    let entryDay = try XCTUnwrap(EntryTimestamp.date(from: "2021-05-10T11:00:00Z"))
    _ = try await api.save(
      SaveEntryParameters(
        entryID: entryID, expectedRevision: nil, title: nil, body: body, richText: richText,
        occurrence: EntryOccurrence(
          precision: .day, start: entryDay, end: nil, label: nil, timezone: lisbon),
        tagNames: [tag], location: nil, marks: .firstTime))

    // editable_entry, entry_detail, chapter_entries, chapter_overlaps, and the tag options read.
    let editable = try await api.editable(entryID)
    XCTAssertEqual(editable?.richText, richText)
    XCTAssertEqual(editable?.tagNames, [tag])
    XCTAssertEqual(editable?.marks, .firstTime)
    let missing = try await api.editable(UUID())
    XCTAssertNil(missing)
    let detail = try await api.detail(entryID)
    XCTAssertEqual(detail?.tags.map(\.name), [tag])
    XCTAssertEqual(detail?.displayTitle, "Monday, May 10, 2021")
    let inside = try await api.chapterEntries(id: chapterID, offset: 0)
    XCTAssertEqual(inside.map(\.id), [entryID])
    XCTAssertEqual(inside.first?.totalCount, 1)
    // A Chapter never overlaps itself.
    let overlaps = try await api.chapterOverlaps(id: chapterID)
    XCTAssertFalse(overlaps.contains { $0.id == chapterID })
    let options = try await api.tagOptions()
    XCTAssertTrue(options.contains(tag))

    // The `entries` formatting read and the `entry_locations` read.
    let formatting = await EntryRichTextMap.load(
      [(id: entryID, body: body)], client: client, ownerID: ownerID)
    XCTAssertEqual(formatting, [entryID: richText])
    let locations = try await EntryPrimaryLocations.load(
      client: client, ownerID: ownerID, entryIDs: [entryID])
    XCTAssertEqual(locations, [:])

    // Storage upload and register_entry_attachment, then trash_entry_attachment.
    let photo = try photoDraft()
    let attached = try await api.attachPhoto(photo, entryID: entryID)
    XCTAssertTrue(attached)
    let trashedPhoto = try await api.trashPhoto(photo.id)
    XCTAssertTrue(trashedPhoto)

    // home_workspace and home_resurfaced_memory.
    let home = HomeController(client: client, ownerID: ownerID)
    await home.load()
    XCTAssertNil(home.loadErrorMessage)
    XCTAssertNotNil(home.snapshot)

    // wiki_items_workspace, the Library tags read, and search_wiki_items without semantic
    // arguments.
    let library = LibraryController(client: client, ownerID: ownerID)
    await library.load()
    XCTAssertNil(library.errorMessage)
    XCTAssertNil(library.filtersErrorMessage)
    XCTAssertEqual(library.items.first { $0.id == chapterID }?.subtype, .chapter)
    XCTAssertTrue(library.tagOptions.contains(tag))
    library.tagName = tag
    await library.search()
    XCTAssertNil(library.searchErrorMessage)
    XCTAssertEqual(library.results.map(\.id), [entryID])

    // first_times_workspace and timeline_workspace.
    let firstTimes = FirstTimesController(client: client, ownerID: ownerID)
    await firstTimes.load()
    XCTAssertNil(firstTimes.loadErrorMessage)
    XCTAssertTrue(firstTimes.entries.contains { $0.id == entryID })
    let timeline = TimelineController(client: client, ownerID: ownerID)
    await timeline.load()
    XCTAssertNil(timeline.loadErrorMessage)
    XCTAssertTrue(timeline.chapters.contains { $0.id == chapterID })
    XCTAssertTrue(timeline.firstTimes.contains { $0.id == entryID })

    // The profiles read and write.
    let settings = SettingsController(client: client, ownerID: ownerID)
    await settings.load()
    XCTAssertNil(settings.loadErrorMessage)
    let zoned = await settings.saveTimezone(lisbon)
    XCTAssertTrue(zoned.isSaved, zoned.message)

    // tags_workspace, save_tag, merge_tags, delete_unused_tag, and the tag preview search.
    let tags = OrganizationActions(client: client, ownerID: ownerID)
    let listed = try await tags.load(query: marker)
    XCTAssertEqual(listed.map(\.name), [tag])
    XCTAssertEqual(listed.first?.entryCount, 1)
    for name in ["spare \(marker)", "other \(marker)"] {
      let created = await tags.save(TagSaveRequest(name: name, id: nil, expectedRevision: nil))
      XCTAssertNil(created)
    }
    var named = try await tags.load(query: marker)
    let spare = try XCTUnwrap(named.first { $0.name == "spare \(marker)" })
    let other = try XCTUnwrap(named.first { $0.name == "other \(marker)" })
    let renamed = await tags.save(
      TagSaveRequest(name: "kept \(marker)", id: other.id, expectedRevision: other.revision))
    XCTAssertNil(renamed)
    named = try await tags.load(query: marker)
    let kept = try XCTUnwrap(named.first { $0.name == "kept \(marker)" })
    let merged = await tags.mergeTags(spare, into: kept)
    XCTAssertNil(merged)
    named = try await tags.load(query: marker)
    XCTAssertEqual(Set(named.map(\.name)), [tag, "kept \(marker)"])
    let unused = try XCTUnwrap(named.first { $0.name == "kept \(marker)" })
    let removed = await tags.deleteUnusedTag(unused)
    XCTAssertNil(removed)
    let previews = await tags.tagEntryPreviews(tag)
    XCTAssertEqual(try previews.get().map(\.id), [entryID])

    // The `entries` Move to Trash update, trash_workspace, restore_trash_item,
    // prepare_empty_trash, delete_trash_item_forever, pending_media_purge_paths, and
    // complete_media_purges.
    let current = try await XCTUnwrapAsync(try await api.editable(entryID))
    try await api.moveToTrash(id: entryID, revision: current.revision)
    let trash = TrashController(client: client, ownerID: ownerID)
    await trash.load()
    XCTAssertNil(trash.loadErrorMessage)
    let trashed = try XCTUnwrap(trash.items.first { $0.kind == .entry && $0.itemID == entryID })
    XCTAssertEqual(trashed.title, "Monday, May 10, 2021")
    let restored = await trash.restore(trashed)
    XCTAssertEqual(restored, TrashController.Notice(message: "Item restored.", tone: .success))
    let again = try await XCTUnwrapAsync(try await api.editable(entryID))
    try await api.moveToTrash(id: entryID, revision: again.revision)
    await trash.load()
    let prepared = await trash.prepareEmptyTrash()
    XCTAssertNil(prepared)
    XCTAssertTrue(trash.emptySnapshot?.contains { $0.itemID == entryID } == true)
    trash.cancelEmptyTrash()
    let item = try XCTUnwrap(trash.items.first { $0.kind == .entry && $0.itemID == entryID })
    let deleted = await trash.deleteForever(item)
    XCTAssertEqual(
      deleted, TrashController.Notice(message: "Item permanently deleted.", tone: .success))
    let gone = try await api.detail(entryID)
    XCTAssertNil(gone)

    // The capture insert and its `entries` lookup.
    let (capture, _) = try await isolatedCapture(client: client, ownerID: ownerID)
    let note = "Smoke capture \(marker)"
    let saved = await capture.save(title: "", body: note)
    XCTAssertTrue(saved)
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline, capture.isSyncing || !capture.pendingEntries.isEmpty {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertNil(capture.captureError)
    XCTAssertTrue(capture.pendingEntries.isEmpty)
    let captured: [ExistingRow] =
      try await client.from("entries").select("id").eq("body", value: note).execute().value
    XCTAssertEqual(captured.count, 1)
  }

  /// `save_entry` changes the marks of one Entry in place: the same identity becomes a Chapter
  /// with an end and back, keeping its tags, its Location, and its photo; a Chapter without a
  /// title is refused by the server too.
  func testSaveEntryTurnsAnEntryIntoAChapterAndBackKeepingTagsLocationAndPhotos() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let tags = ["lisbon \(marker)", "moves \(marker)"]
    let id = UUID()
    let lisbon = "Europe/Lisbon"
    let start = try XCTUnwrap(EntryTimestamp.date(from: "2022-02-01T12:00:00Z"))
    let end = try XCTUnwrap(EntryTimestamp.date(from: "2022-11-01T12:00:00Z"))
    let month = EntryOccurrence(precision: .month, start: start, end: nil, label: nil, timezone: lisbon)

    // A First Time with an address typed by hand, which `save_entry` stores as its Location.
    var created = try parameters(
      SaveEntryParameters(
        entryID: id, expectedRevision: nil, title: "Moving to Lisbon",
        body: "Boxes everywhere.", richText: nil, occurrence: month, tagNames: tags,
        location: nil, marks: .firstTime))
    created["p_primary_location"] = .object([
      "kind": .string("manual"), "address": .string("Rua Augusta 1"), "city": .string("Lisbon"),
      "region": .null, "country": .string("Portugal"),
    ])
    let createdRows: [SavedEntry] =
      try await client.rpc("save_entry", params: created).execute().value
    XCTAssertEqual(createdRows, [SavedEntry(entryID: id, revision: 1)])
    let photo = try photoDraft()
    let attached = try await api.attachPhoto(photo, entryID: id)
    XCTAssertTrue(attached)

    let entry = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertEqual(entry.marks, .firstTime)
    XCTAssertEqual(Set(entry.tagNames), Set(tags))
    // Registering a photo never changes the Entry's revision.
    XCTAssertEqual(entry.revision, 1)
    let location = try XCTUnwrap(entry.primaryLocation)
    XCTAssertEqual(location.address, "Rua Augusta 1")
    XCTAssertEqual(location.label, "Rua Augusta 1, Lisbon, Portugal")

    // The same Entry becomes a closed Chapter, resending its Location untouched.
    var chapterSpan = month
    chapterSpan.end = end
    let toChapter = try await api.save(
      SaveEntryParameters(
        entryID: id, expectedRevision: entry.revision, title: entry.title, body: entry.body,
        richText: entry.richText, occurrence: chapterSpan, tagNames: entry.tagNames,
        location: entry.primaryLocation, marks: EntryMarks(isChapter: true, isFirstTime: true)))
    XCTAssertEqual(toChapter, SavedEntry(entryID: id, revision: 2))
    let chapter = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertEqual(chapter.subtype, .chapter)
    XCTAssertTrue(chapter.isFirstTime)
    XCTAssertEqual(chapter.occurredEnd, end)
    XCTAssertEqual(chapter.datePrecision, .month)
    XCTAssertEqual(Set(chapter.tagNames), Set(tags))
    XCTAssertEqual(chapter.primaryLocation?.id, location.id)
    let photosAsChapter = try await livePhotoCount(entryID: id, client: client)
    XCTAssertEqual(photosAsChapter, 1)
    let detail = try await XCTUnwrapAsync(try await api.detail(id))
    XCTAssertEqual(detail.marks.identityLabel, "Chapter · First Time")
    XCTAssertEqual(detail.primaryLocation?.locationID, location.id)
    XCTAssertEqual(detail.chapterDateFacts(now: end).span, "Feb 2022 - Nov 2022")

    // The server refuses a Chapter without a title, which iOS reports in Web's words.
    var untitled = try parameters(
      SaveEntryParameters(
        entryID: id, expectedRevision: chapter.revision, title: "Untitled for now",
        body: chapter.body, richText: nil, occurrence: chapterSpan, tagNames: chapter.tagNames,
        location: chapter.primaryLocation, marks: .chapter))
    untitled["p_title"] = .null
    do {
      let _: [SavedEntry] = try await client.rpc("save_entry", params: untitled).execute().value
      XCTFail("A Chapter without a title must be refused.")
    } catch {
      XCTAssertEqual((error as? PostgrestError)?.message, "chapter_requires_title")
      XCTAssertEqual(SaveEntryError.classify(error), .invalid("Give this Chapter a title."))
    }

    // And back to an Entry: an ordinary Entry dated by month has no end.
    let toEntry = try await api.save(
      SaveEntryParameters(
        entryID: id, expectedRevision: chapter.revision, title: chapter.title,
        body: chapter.body, richText: chapter.richText, occurrence: month,
        tagNames: chapter.tagNames, location: chapter.primaryLocation, marks: .firstTime))
    XCTAssertEqual(toEntry, SavedEntry(entryID: id, revision: 3))
    let back = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertEqual(back.marks, .firstTime)
    XCTAssertNil(back.occurredEnd)
    XCTAssertEqual(Set(back.tagNames), Set(tags))
    XCTAssertEqual(back.primaryLocation?.id, location.id)
    let photosBack = try await livePhotoCount(entryID: id, client: client)
    XCTAssertEqual(photosBack, 1)
  }

  // MARK: Shared helpers

  /// A small PNG photo the contract account can attach.
  func photoDraft(color: UIColor = .systemGreen) throws -> PhotoDraft {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
      .pngData { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
      }
    return try PhotoDraft.validate(
      data: data, mimeType: .png, originalFilename: "kept.png", pixelWidth: 4, pixelHeight: 4)
  }

  /// `save_entry` arguments as JSON values, so a test can send what the app never would.
  func parameters(_ parameters: SaveEntryParameters) throws -> [String: AnyJSON] {
    try JSONDecoder().decode([String: AnyJSON].self, from: JSONEncoder().encode(parameters))
  }

  /// A plain untitled Entry saved through `save_entry`.
  func savedEntry(_ body: String, client: SupabaseClient, ownerID: UUID) async throws
    -> SavedEntry
  {
    try await EntryAPI(client: client, ownerID: ownerID).save(
      SaveEntryParameters(
        entryID: UUID(), expectedRevision: nil, title: nil, body: body, richText: nil,
        occurrence: EntryOccurrence(precision: .unknown, timezone: "UTC"), tagNames: [],
        location: nil, marks: .none))
  }

  /// A synthetic First Time with one photo, moved to Trash. Returns its id and original path.
  func trashedPhotoEntry(_ title: String, client: SupabaseClient, ownerID: UUID) async throws
    -> (UUID, String)
  {
    let api = EntryAPI(client: client, ownerID: ownerID)
    let id = UUID()
    let saved = try await api.save(
      SaveEntryParameters(
        entryID: id, expectedRevision: nil, title: title, body: "", richText: nil,
        occurrence: EntryOccurrence(precision: .unknown, timezone: "UTC"), tagNames: [],
        location: nil, marks: .firstTime))
    let photo = try photoDraft()
    let attached = try await api.attachPhoto(photo, entryID: id)
    XCTAssertTrue(attached)
    try await api.moveToTrash(id: id, revision: saved.revision)
    return (id, photo.objectPath(ownerID: ownerID, entryID: id))
  }

  /// Photos on an Entry that are not in Trash.
  func livePhotoCount(entryID: UUID, client: SupabaseClient) async throws -> Int {
    let rows: [ExistingRow] =
      try await client.from("attachments").select("id")
      .eq("entry_id", value: entryID.uuidString)
      .is("deleted_at", value: nil)
      .execute().value
    return rows.count
  }

  /// Every photo row of these Entries, in Trash or not.
  func attachmentCount(entryIDs: [UUID], client: SupabaseClient) async throws -> Int {
    let rows: [ExistingRow] =
      try await client.from("attachments").select("id")
      .in("entry_id", values: entryIDs.map(\.uuidString))
      .execute().value
    return rows.count
  }

  func storedNames(in folder: String, client: SupabaseClient) async throws -> [String] {
    try await client.storage.from("entry-media").list(path: folder).map(\.name)
  }

  /// Moves an Entry to Trash the way another device does.
  func moveToTrashElsewhere(_ entryID: UUID, client: SupabaseClient) async throws {
    try await client.from("entries")
      .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
      .eq("id", value: entryID.uuidString)
      .execute()
  }

  /// A capture queue with its own storage and photo files, past its first connectivity update
  /// so each save starts its own sync.
  func isolatedCapture(client: SupabaseClient, ownerID: UUID) async throws
    -> (CaptureController, CapturePhotoStore)
  {
    let suiteName = "NativeContractTests.\(UUID().uuidString)"
    let photoRoot = FileManager.default.temporaryDirectory.appending(
      path: "NativeContractTests.\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: photoRoot)
    }
    let queueStore = CaptureQueueStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    let photoStore = CapturePhotoStore(rootURL: photoRoot)
    let capture = CaptureController(
      client: client, ownerID: ownerID, queueStore: queueStore, photoStore: photoStore)
    try await Task.sleep(for: .milliseconds(500))
    return (capture, photoStore)
  }

  /// Waits for the sync a save starts, then returns the toasts shown since `shown`.
  func toasts(after shown: Set<UUID>, from capture: CaptureController) async throws -> [MTToast] {
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline,
      capture.isSyncing || MTToastCenter.shared.toasts.allSatisfy({ shown.contains($0.id) })
    {
      try await Task.sleep(for: .milliseconds(100))
    }
    return MTToastCenter.shared.toasts.filter { !shown.contains($0.id) }
  }

  /// Waits until the server has answered the held call, so it read the data before what follows.
  func waitForHeldResponse() async throws {
    for _ in 0..<1_000 {
      if HeldResponseProtocol.gate.hasHeldResponse { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("The held response never arrived.")
    throw URLError(.timedOut)
  }

  /// `XCTUnwrap` for a value an `async` call returns.
  func XCTUnwrapAsync<T>(
    _ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line
  ) async throws -> T {
    let result = try await value()
    return try XCTUnwrap(result, file: file, line: line)
  }
}

/// Passes each request through to the local stack, but can hold the response to one RPC call
/// until the test releases it, so an earlier load can return after a later one. It can also
/// fail one Storage removal, like a connection lost between two steps, and answer one capture
/// photo upload as `UploadAnswer` describes.
final class HeldResponseProtocol: URLProtocol {
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
    if Self.gate.failsStorageRemoval(forwarded) {
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    let uploadAnswer = Self.gate.claimsUpload(forwarded)
    if case .refuse(let statusCode)? = uploadAnswer, let url = forwarded.url,
      let response = HTTPURLResponse(
        url: url, statusCode: 400, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])
    {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(
        self,
        didLoad: Data(
          #"{"statusCode":"\#(statusCode)","error":"Refused","message":"Refused by the test"}"#
            .utf8))
      client?.urlProtocolDidFinishLoading(self)
      return
    }
    let isHeld = Self.gate.claims(forwarded) || uploadAnswer == .hold
    let losesResponse = uploadAnswer == .loseResponse
    let reference = LoaderReference(loader: self)
    upstreamTask = Self.upstream.dataTask(with: forwarded) { data, response, error in
      let deliver: @Sendable () -> Void = {
        let loader = reference.loader
        if losesResponse {
          loader.client?.urlProtocol(loader, didFailWithError: URLError(.networkConnectionLost))
          return
        }
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

/// A row whose identity is all a check needs.
struct ExistingRow: Decodable {
  let id: UUID
}

/// How the next capture photo upload is answered.
enum UploadAnswer: Equatable, Sendable {
  /// Storage refuses it with this status in its error body, beside HTTP 400 like the real one.
  case refuse(statusCode: String)
  /// It reaches Storage, but the answer is lost on the way back.
  case loseResponse
  /// It reaches Storage, and the answer waits until the test releases it.
  case hold
}

/// URLSession calls back on its own queue; this carries the loading protocol into those calls.
private struct LoaderReference: @unchecked Sendable {
  let loader: HeldResponseProtocol
}

/// The RPC whose next response waits, and that response once the server has answered.
final class ResponseGate: @unchecked Sendable {
  private let lock = NSLock()
  private var rpc: String?
  private var heldDelivery: (@Sendable () -> Void)?
  private var failsNextStorageRemoval = false
  private var uploadAnswer: UploadAnswer?

  /// Answers the next capture photo upload this way, or stops doing so with nil.
  func answerNextUpload(_ answer: UploadAnswer?) {
    lock.withLock { uploadAnswer = answer }
  }

  fileprivate func claimsUpload(_ request: URLRequest) -> UploadAnswer? {
    lock.withLock {
      guard let answer = uploadAnswer, request.httpMethod == "POST",
        request.url?.path.contains("/storage/v1/object/entry-media/") == true
      else { return nil }
      uploadAnswer = nil
      return answer
    }
  }

  /// Fails the next Storage object removal as a lost connection, without sending it.
  func failNextStorageRemoval(_ enabled: Bool = true) {
    lock.withLock { failsNextStorageRemoval = enabled }
  }

  fileprivate func failsStorageRemoval(_ request: URLRequest) -> Bool {
    lock.withLock {
      guard failsNextStorageRemoval, request.httpMethod == "DELETE",
        request.url?.path.contains("/storage/v1/object/") == true
      else { return false }
      failsNextStorageRemoval = false
      return true
    }
  }

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
