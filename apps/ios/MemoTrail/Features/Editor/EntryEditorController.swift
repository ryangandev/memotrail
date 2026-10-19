import Foundation
import Observation
import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

/// The Entry editor's state and actions, like Web `EntryEditorDialog`: it loads the tag
/// choices, the Settings time zone, and the saved photos, saves with `save_entry`, attaches new
/// photos after the save, and keeps the editor open with the same Entry when some photos could
/// not be attached, so Save again retries them.
@MainActor
@Observable
final class EntryEditorController {
  /// What a save did.
  enum SaveOutcome: Equatable {
    /// Everything was saved; the editor closes.
    case saved(SavedEntry)
    /// The Entry was saved but some photos were not attached; the editor stays open.
    case savedWithUnattachedPhotos(SavedEntry)
    /// Nothing was saved; `errorMessage` says why.
    case failed
  }

  var draft: EntryEditorDraft
  var note: NSAttributedString
  /// The note as it opened, to tell an untouched note from an edited one.
  let openingNote: NSAttributedString
  /// Web writing with lists, quotes, links, or code that the native editor cannot keep.
  let hasWebOnlyFormatting: Bool
  /// Whether the person chose to edit a note with Web-only formatting here anyway.
  var isEditingWebNote = false
  private(set) var tagOptions: [String] = []
  /// The time zone from Settings, once it has loaded.
  private(set) var settingsTimezone: String?
  /// The Entry's saved photos: empty for a new Entry, nil while they load or after a failure.
  private(set) var savedPhotos: [EntryPhotoInfo]?
  private(set) var hasMorePhotos = false
  private(set) var photosFailedToLoad = false
  /// Photos chosen here, attached after the next save.
  private(set) var newPhotos: [PhotoDraft] = []
  /// Thumbnails of the new photos, decoded once.
  private(set) var newPhotoImages: [UUID: UIImage] = [:]
  private(set) var photoProgress: (completed: Int, total: Int)?
  private(set) var isSaving = false
  private(set) var isTrashing = false
  private(set) var isChangingPhotos = false
  var errorMessage: String?

  let mode: EntryEditorMode
  let client: SupabaseClient
  let ownerID: UUID

  init(
    client: SupabaseClient, ownerID: UUID, mode: EntryEditorMode,
    timezone: String = TimeZone.current.identifier
  ) {
    self.mode = mode
    self.client = client
    self.ownerID = ownerID
    draft = EntryEditorDraft(mode: mode, timezone: timezone)
    let opening = EntryEditorNote.opening(draft.original)
    openingNote = opening.note
    hasWebOnlyFormatting = opening.hasWebOnlyFormatting
    note = opening.note
    if draft.isNew { savedPhotos = [] }
  }

  private var api: EntryAPI { EntryAPI(client: client, ownerID: ownerID) }

  var isBusy: Bool { isSaving || isTrashing || isChangingPhotos }

  /// Whether the native editor shows the note; a note with Web-only formatting stays read-only
  /// until the person chooses to edit it here.
  var isNoteEditable: Bool { !hasWebOnlyFormatting || isEditingWebNote }

  var eyebrow: String { draft.isNew ? "New Entry" : "Entry" }

  /// Web's dialog title, which names what a new Entry started as.
  var heading: String {
    switch mode {
    case .edit: "Edit Entry"
    case .new(let marks):
      marks.isChapter ? "Add a Chapter" : marks.isFirstTime ? "Add a First Time" : "Add an Entry"
    }
  }

  var saveTitle: String { isSaving ? "Saving…" : draft.isNew ? "Add" : "Save changes" }

  /// Room for more photos, Web's `entryPhotoLimit`.
  var photoRoom: Int {
    max(0, PhotoDraft.maximumCount - (savedPhotos?.count ?? 0) - newPhotos.count)
  }

  // MARK: Loading

  /// Loads what the editor offers: tags most used first, the Settings time zone, and the
  /// Entry's saved photos. Each part fails on its own.
  func load() async {
    async let tags: Void = loadTagOptions()
    async let timezone: Void = loadSettingsTimezone()
    async let photos: Void = loadPhotos()
    _ = await (tags, timezone, photos)
  }

  func loadTagOptions() async {
    if let options = try? await api.tagOptions() { tagOptions = options }
  }

  private func loadSettingsTimezone() async {
    struct Row: Decodable { let timezone: String? }
    do {
      let row: Row = try await client.from("profiles").select("timezone")
        .eq("user_id", value: ownerID.uuidString).single().execute().value
      guard try await client.auth.session.user.id == ownerID,
        let timezone = row.timezone, OccurrenceRules.validTimezone(timezone)
      else { return }
      settingsTimezone = timezone
      draft.useDefaultTimezone(timezone)
    } catch {
      // The device zone stays, as when Settings has none.
    }
  }

  /// The saved photos of an Entry being edited.
  func loadPhotos() async {
    guard !draft.isNew || draft.revision != nil else { return }
    do {
      let result = try await api.photos(entryID: draft.entryID)
      savedPhotos = result.photos
      hasMorePhotos = result.hasMore
      photosFailedToLoad = false
    } catch {
      guard !(error is CancellationError) else { return }
      if savedPhotos == nil { photosFailedToLoad = true }
    }
  }

  // MARK: Photos

  /// Adds chosen photos to attach on save, as many as there is room for.
  func add(_ drafts: [PhotoDraft], refused: String? = nil) {
    let room = photoRoom
    let accepted = drafts.prefix(room)
    newPhotos += accepted
    for photo in accepted { newPhotoImages[photo.id] = UIImage(data: photo.data) }
    errorMessage = drafts.count > room ? PhotoDraft.tooManyMessage : refused
  }

  /// Reads the photos chosen in the system picker, like Web `validateInboxPhotoFiles`.
  func select(_ items: [PhotosPickerItem]) async {
    var drafts: [PhotoDraft] = []
    var refused: String?
    for item in items {
      do {
        drafts.append(try await PhotoDraft.load(item))
      } catch {
        refused = error.localizedDescription
      }
    }
    add(drafts, refused: refused)
  }

  func removeNewPhoto(_ id: UUID) {
    newPhotos.removeAll { $0.id == id }
    newPhotoImages[id] = nil
  }

  /// Web `removePhoto`: moves a saved photo to Trash at once, after the person confirms.
  func moveSavedPhotoToTrash(_ id: UUID) async {
    guard !isBusy else { return }
    isChangingPhotos = true
    errorMessage = nil
    defer { isChangingPhotos = false }
    do {
      guard try await api.trashPhoto(id) else { throw URLError(.badServerResponse) }
      savedPhotos?.removeAll { $0.id == id }
      if draft.photoLocation?.attachmentId == id { draft.photoLocation = nil }
      MTToastCenter.shared.info("Photo moved to Trash.")
    } catch {
      errorMessage = "MemoTrail could not remove this photo. Try again."
    }
  }

  // MARK: Saving

  /// Saves the draft, then attaches the new photos to the same Entry.
  func save() async -> SaveOutcome {
    guard !isBusy else { return .failed }
    let note =
      isNoteEditable
      ? EntryEditorNote.toSave(current: note, opening: openingNote, original: draft.original)
      : (draft.original?.body ?? "", draft.original?.richText)
    let parameters: SaveEntryParameters
    do {
      parameters = try draft.parameters(
        body: note.body, richText: note.richText, tagOptions: tagOptions)
    } catch {
      errorMessage = error.localizedDescription
      return .failed
    }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    let saved: SavedEntry
    do {
      saved = try await api.save(parameters)
    } catch {
      errorMessage = error.localizedDescription
      return .failed
    }
    draft.revision = saved.revision
    if parameters.photoLocation != nil {
      // The photo's position is now the saved Location, so a retry keeps it as it is.
      draft.photoLocation = nil
      if let current = try? await api.editable(saved.entryID) {
        draft.location = current.primaryLocation
      }
    }
    let unattached = await attachNewPhotos(to: saved.entryID)
    if unattached > 0 {
      errorMessage =
        "The Entry was saved, but \(unattached == 1 ? "1 photo" : "\(unattached) photos") could not be attached. Select Save again to retry."
      return .savedWithUnattachedPhotos(saved)
    }
    MTToastCenter.shared.success(
      !draft.isNew
        ? "Entry saved."
        : draft.marks.isChapter
          ? "Chapter added." : draft.marks.isFirstTime ? "First Time added." : "Entry added.")
    return .saved(saved)
  }

  /// Attaches each new photo in order and keeps the ones that were not confirmed.
  /// Returns how many remain.
  private func attachNewPhotos(to entryID: UUID) async -> Int {
    guard !newPhotos.isEmpty else { return 0 }
    let drafts = newPhotos
    var failed: [PhotoDraft] = []
    for (index, photo) in drafts.enumerated() {
      photoProgress = (completed: index, total: drafts.count)
      do {
        if try await !api.attachPhoto(photo, entryID: entryID) { failed.append(photo) }
      } catch {
        failed.append(photo)
      }
    }
    photoProgress = nil
    newPhotos = failed
    newPhotoImages = newPhotoImages.filter { id, _ in failed.contains { $0.id == id } }
    if failed.count < drafts.count { await loadPhotos() }
    return failed.count
  }

  /// Web `trashWikiItem` for the version this editor last saved or opened.
  func moveToTrash() async -> Bool {
    guard let revision = draft.revision, !draft.isNew, !isBusy else { return false }
    isTrashing = true
    errorMessage = nil
    defer { isTrashing = false }
    do {
      try await api.moveToTrash(id: draft.entryID, revision: revision)
      MTToastCenter.shared.info("Entry moved to Trash.")
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}

extension PhotoDraft {
  /// A photo chosen in the system picker, checked like Web `validateInboxPhotoFiles`.
  @MainActor
  static func load(_ item: PhotosPickerItem) async throws -> PhotoDraft {
    guard let data = try await item.loadTransferable(type: Data.self),
      let mime = PhotoImageType.detect(
        data: data, typeIdentifiers: item.supportedContentTypes.map(\.identifier))
    else { throw PhotoDraftError.unsupportedType }
    let image = UIImage(data: data)
    return try validate(
      data: data, mimeType: mime, originalFilename: nil,
      pixelWidth: image.map { Int($0.size.width * $0.scale) },
      pixelHeight: image.map { Int($0.size.height * $0.scale) })
  }
}
