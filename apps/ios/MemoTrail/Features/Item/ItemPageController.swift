import Foundation
import Observation
@preconcurrency import Supabase

/// Web `/items/<entry>`: loads one Entry through `entry_detail`, then its current photos and, for
/// a dated Chapter, the Entries inside it, the Chapters beside it, and its saved review. The
/// Entry shows as soon as it arrives; the rest fills in beside it. Only the newest load applies.
@MainActor
@Observable
final class ItemPageController {
  private(set) var entry: EntryDetail?
  private(set) var hasLoaded = false
  private(set) var loadFailed = false

  // Photos (Web `loadEntryPhotos`).
  private(set) var photos: [EntryPhotoInfo] = []
  private(set) var photosHaveMore = false
  /// Whether the photos could not load, so the page says so instead of showing none.
  private(set) var photosFailed = false

  // A Chapter's Entries, oldest first, one page at a time (Web `loadChapterContents`).
  private(set) var chapterEntries: [ChapterEntry] = []
  private(set) var chapterEntryCount = 0
  private(set) var chapterOverlaps: [ChapterOverlap] = []
  private(set) var chapterErrorMessage: String?
  private(set) var isLoadingMoreEntries = false
  private(set) var moreEntriesErrorMessage: String?
  /// Display addresses for the Entries' cover photos.
  private(set) var coverURLs: [UUID: URL] = [:]

  // A Chapter's saved review, read-only. Nil when it has none or could not be read.
  private(set) var review: StoredReview?
  private(set) var reviewFacts: ReviewFacts?

  let entryID: UUID
  private let api: EntryAPI
  private let reviews: ChapterReviewAPI
  private let client: SupabaseClient
  private let ownerID: UUID
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.entryID = entryID
    self.client = client
    self.ownerID = ownerID
    api = EntryAPI(client: client, ownerID: ownerID)
    reviews = ChapterReviewAPI(client: client, ownerID: ownerID)
  }

  /// Whether more of a Chapter's Entries wait beyond the pages shown.
  var hasMoreEntries: Bool { chapterEntries.count < chapterEntryCount }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    let detail: EntryDetail?
    do {
      detail = try await api.detail(entryID)
    } catch {
      guard loadGeneration == generation, !(error is CancellationError) else { return }
      loadFailed = true
      hasLoaded = true
      return
    }
    guard loadGeneration == generation else { return }
    entry = detail
    loadFailed = false
    hasLoaded = true

    // Photos of an Entry in Trash show from Trash, where it can be restored.
    guard let detail, !detail.isInTrash else {
      clearSections()
      return
    }
    // Like Web, a Chapter lists the Entries dated inside it; one with no calendar date has no
    // days to hold any.
    let listsEntries = detail.subtype == .chapter && detail.occurredStart != nil
    async let photoResult = loadPhotos()
    async let contentsResult = loadContents(if: listsEntries)
    async let reviewResult = loadReview(if: detail.subtype == .chapter)
    let (photoOutcome, contents, loadedReview) = await (
      photoResult, contentsResult, reviewResult
    )
    guard loadGeneration == generation, !Task.isCancelled else { return }

    switch photoOutcome {
    case .loaded(let response):
      self.photos = response.photos
      photosHaveMore = response.hasMore
      photosFailed = false
    case .failed:
      photosFailed = true
    case .unavailable:
      self.photos = []
      photosHaveMore = false
      photosFailed = false
    }
    if let contents {
      chapterEntries = contents.entries
      chapterEntryCount = contents.entries.first?.totalCount ?? 0
      chapterOverlaps = contents.overlaps
      chapterErrorMessage = contents.failed ? Self.chapterFailure : nil
      moreEntriesErrorMessage = nil
      coverURLs = contents.coverURLs
    } else {
      clearChapterContents()
    }
    review = loadedReview?.shown
    reviewFacts = loadedReview?.facts
  }

  /// The next page of a Chapter's Entries, appended below the ones shown.
  func loadMoreEntries() async {
    guard hasMoreEntries, !isLoadingMoreEntries else { return }
    let generation = loadGeneration
    isLoadingMoreEntries = true
    moreEntriesErrorMessage = nil
    defer { isLoadingMoreEntries = false }
    do {
      let page = try await api.chapterEntries(id: entryID, offset: chapterEntries.count)
      let covers = await coverURLMap(for: page)
      guard loadGeneration == generation, !Task.isCancelled else { return }
      // A page that arrives empty ends the list, so the trigger cannot repeat for ever.
      guard !page.isEmpty else {
        chapterEntryCount = chapterEntries.count
        return
      }
      chapterEntries = Self.appending(page, to: chapterEntries)
      chapterEntryCount = page.first?.totalCount ?? chapterEntryCount
      coverURLs.merge(covers) { _, new in new }
    } catch {
      guard loadGeneration == generation, !(error is CancellationError) else { return }
      moreEntriesErrorMessage = "More Entries could not load."
    }
  }

  /// Web `loadEditableEntry`: the Entry as the editor opens it, or nil when it cannot.
  func editableEntry() async -> EditableEntry? {
    try? await api.editable(entryID)
  }

  /// Web `trashWikiItem`: nil when the Entry moved to Trash, otherwise why it did not.
  func moveToTrash() async -> String? {
    guard let entry else { return EntryTrashError.invalid.errorDescription }
    do {
      try await api.moveToTrash(id: entry.id, revision: entry.revision)
      return nil
    } catch let error as EntryTrashError {
      return error.errorDescription
    } catch {
      return "Could not confirm the move to Trash. Refresh before trying again."
    }
  }

  static let chapterFailure =
    "The Entries in this Chapter could not load. Refresh to try again."

  /// A page of Entries added below the ones shown, leaving out any already listed, since the
  /// list can shift between pages when an Entry is added or dated elsewhere.
  static func appending(_ page: [ChapterEntry], to entries: [ChapterEntry]) -> [ChapterEntry] {
    let known = Set(entries.map(\.id))
    return entries + page.filter { !known.contains($0.id) }
  }

  // MARK: Loading the parts

  private enum PhotosResult {
    case loaded(EntryPhotosResponse)
    case failed
    /// There is no media service to ask, such as a build with no API address.
    case unavailable
  }

  private struct Contents {
    var entries: [ChapterEntry] = []
    var overlaps: [ChapterOverlap] = []
    var coverURLs: [UUID: URL] = [:]
    var failed = false
  }

  private func loadPhotos() async -> PhotosResult {
    guard AppConfiguration.apiURL != nil else { return .unavailable }
    do {
      return .loaded(try await api.photos(entryID: entryID))
    } catch {
      return .failed
    }
  }

  private func loadContents(if applies: Bool) async -> Contents? {
    guard applies else { return nil }
    do {
      async let entries = api.chapterEntries(id: entryID, offset: 0)
      async let overlaps = api.chapterOverlaps(id: entryID)
      let page = try await entries
      return Contents(
        entries: page, overlaps: try await overlaps, coverURLs: await coverURLMap(for: page))
    } catch {
      return Contents(failed: true)
    }
  }

  /// Web reads the review only to show it: if it cannot be read, the Chapter shows without one.
  private func loadReview(if applies: Bool) async -> ChapterReview? {
    guard applies else { return nil }
    return try? await reviews.review(chapterID: entryID)
  }

  private func coverURLMap(for entries: [ChapterEntry]) async -> [UUID: URL] {
    let covers = entries.compactMap { entry in entry.coverPhoto.map { (entry.id, $0.objectPath) } }
    guard !covers.isEmpty else { return [:] }
    let urls = await MediaDelivery.displayURLs(
      paths: covers.map(\.1), client: client, ownerID: ownerID)
    return Dictionary(
      covers.compactMap { id, path in urls[path].map { (id, $0) } }, uniquingKeysWith: { $1 })
  }

  private func clearSections() {
    photos = []
    photosHaveMore = false
    photosFailed = false
    clearChapterContents()
    review = nil
    reviewFacts = nil
  }

  private func clearChapterContents() {
    chapterEntries = []
    chapterEntryCount = 0
    chapterOverlaps = []
    chapterErrorMessage = nil
    moreEntriesErrorMessage = nil
    coverURLs = [:]
  }
}
