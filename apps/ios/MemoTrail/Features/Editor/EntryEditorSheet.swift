import PhotosUI
@preconcurrency import Supabase
import SwiftUI

/// What the editor opens with, like Web `NewEntryDialog` and `EntryEditorDialog`.
enum EntryEditorMode: Equatable {
  /// A new Entry that starts with these marks, such as a Chapter added from Timeline.
  case new(EntryMarks)
  /// The current version of a saved Entry, from `EntryAPI.editable(_:)`.
  case edit(EditableEntry)
}

/// What changed when the editor closed after a save or Move to Trash.
enum EntryEditorResult: Equatable {
  case saved(SavedEntry)
  case movedToTrash(UUID)
}

/// Web `EntryEditorDialog`, in Web's order: title, note, tags, photos, the Chapter and First
/// Time marks, the date, the Entry's Location, and camera dates from saved photos. It saves
/// with `save_entry`, then attaches new photos to the same Entry.
struct EntryEditorSheet: View {
  let onSaved: @MainActor (EntryEditorResult) -> Void

  @State private var controller: EntryEditorController
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var removingPhoto: EntryPhotoInfo?
  @State private var isConfirmingTrash = false
  @State private var isConfirmingNoteEdit = false
  @Environment(\.dismiss) private var dismiss

  init(
    client: SupabaseClient, ownerID: UUID, mode: EntryEditorMode,
    onSaved: @escaping @MainActor (EntryEditorResult) -> Void = { _ in }
  ) {
    self.onSaved = onSaved
    _controller = State(
      initialValue: EntryEditorController(client: client, ownerID: ownerID, mode: mode))
  }

  private var draft: EntryEditorDraft { controller.draft }

  var body: some View {
    @Bindable var controller = controller
    MTSheet(
      eyebrow: controller.eyebrow, title: controller.heading,
      closeLabel: "Close Entry editor", closeIdentifier: "editor-close",
      isBusy: controller.isBusy, message: controller.errorMessage
    ) {
      MTTextField(
        label: "Title", text: $controller.draft.title,
        prompt: draft.marks.isChapter ? "Name this Chapter" : "Add a title",
        isRequired: draft.marks.isChapter, maxLength: EntryLimits.title
      )
      .accessibilityIdentifier("editor-title")
      noteField
      MTOrganizationEditor(
        kind: .tag, names: $controller.draft.tagNames, options: controller.tagOptions)
      photoField
      marksField
      OccurrenceEditor(
        value: $controller.draft.occurrence, span: draft.marks.isChapter,
        defaultTimezone: controller.settingsTimezone)
      locationField
      if let photos = controller.savedPhotos, !photos.isEmpty {
        EntryPhotoDatesView(
          client: controller.client, ownerID: controller.ownerID, photos: photos,
          occurrence: $controller.draft.occurrence,
          photoLocation: $controller.draft.photoLocation)
      }
    } footer: {
      footer
    }
    .task { await controller.load() }
    .onChange(of: pickerItems) { _, items in
      guard !items.isEmpty else { return }
      Task {
        await controller.select(items)
        pickerItems = []
      }
    }
    .confirmationDialog(
      "Move this photo to Trash?",
      isPresented: Binding(get: { removingPhoto != nil }, set: { if !$0 { removingPhoto = nil } }),
      titleVisibility: .visible, presenting: removingPhoto
    ) { photo in
      Button("Move photo to Trash", role: .destructive) {
        Task { await controller.moveSavedPhotoToTrash(photo.id) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("The original will be preserved for recovery.")
    }
  }

  // MARK: Note

  @ViewBuilder private var noteField: some View {
    @Bindable var controller = controller
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Note")
      if controller.isNoteEditable {
        MTRichTextEditor(
          text: $controller.note, placeholder: "Write what you want to remember",
          accessibilityIdentifier: "editor-body",
          minimumHeight: MTLayout.RichText.reviewMinHeight)
      } else if let original = draft.original {
        webNote(original)
      }
    }
  }

  /// A note with lists, quotes, links, or code from the web stays as it is, shown read-only,
  /// until the person chooses to edit it here and turn that formatting into paragraphs.
  private func webNote(_ entry: EditableEntry) -> some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.medium)
    return VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTRichTextContent(text: entry.body, richText: entry.richText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("editor-web-note")
      Divider().overlay(MTColor.border)
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
        Text(
          "This note has lists, quotes, links, or code from the web. It stays as it is unless you edit it here."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        Button("Edit note here") { isConfirmingNoteEdit = true }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityIdentifier("editor-edit-web-note")
      }
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
    .confirmationDialog(
      "Edit this note here?", isPresented: $isConfirmingNoteEdit, titleVisibility: .visible
    ) {
      Button("Edit note here") { controller.isEditingWebNote = true }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Lists, quotes, links, and code become plain paragraphs if you change the note. Close without changing it to keep them."
      )
    }
  }

  // MARK: Photos

  @ViewBuilder private var photoField: some View {
    if let saved = controller.savedPhotos {
      MTPhotoField(
        recordLabel: "Entry",
        saved: saved.map {
          MTPhotoField.SavedPhoto(
            id: $0.id, url: $0.displayURL(base: AppConfiguration.apiURL), name: $0.name)
        },
        new: controller.newPhotos.map {
          MTPhotoField.NewPhoto(
            id: $0.id, image: controller.newPhotoImages[$0.id], name: $0.originalFilename)
        },
        limit: PhotoDraft.maximumCount, selection: $pickerItems,
        progress: controller.photoProgress,
        removeSaved: { photo in removingPhoto = saved.first { $0.id == photo.id } },
        removeNew: { photo in controller.removeNewPhoto(photo.id) }
      )
      .disabled(controller.hasMorePhotos)
    } else {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        MTFieldLabel(title: "Photos")
        if controller.photosFailedToLoad {
          HStack(spacing: MTSpacing.s3) {
            Text("Photos could not be loaded.")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.warm)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again") { Task { await controller.loadPhotos() } }
              .mtButtonStyle(.secondary, size: .small)
          }
        } else {
          MTLoadingSkeleton(shape: .fill)
            .frame(height: MTLayout.Grid.photo)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
            .accessibilityLabel("Loading photos")
        }
      }
    }
  }

  // MARK: Marks

  private var marksField: some View {
    VStack(alignment: .leading, spacing: 0) {
      MTCheckbox(
        title: "Chapter",
        detail: "A stretch of your life, like a home, a job, or a school year.",
        isOn: Binding(
          get: { draft.marks.isChapter },
          set: { isOn in
            controller.draft.changeMarks(
              EntryMarks(isChapter: isOn, isFirstTime: draft.marks.isFirstTime))
          })
      )
      .accessibilityIdentifier("editor-chapter")
      MTCheckbox(
        title: "First Time", detail: "The first time you did something.",
        isOn: Binding(
          get: { draft.marks.isFirstTime },
          set: { isOn in
            controller.draft.changeMarks(
              EntryMarks(isChapter: draft.marks.isChapter, isFirstTime: isOn))
          })
      )
      .accessibilityIdentifier("editor-first-time")
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Marks")
  }

  // MARK: Location

  /// Web `LocationPicker` for a saved Location: its preview with Remove. Removing waits for
  /// Save, so Undo brings it back. Address search stays on the web for now.
  @ViewBuilder private var locationField: some View {
    if let opened = draft.original?.primaryLocation {
      MTLocationPanel(
        message:
          "This Entry keeps its own Location. Search for a different address on the web."
      ) {
        if let location = draft.location {
          MTLocationPreview(
            label: location.label, latitude: location.latitude, longitude: location.longitude,
            remove: { controller.draft.location = nil }
          )
          .accessibilityIdentifier("editor-location")
        } else {
          HStack(spacing: MTSpacing.s3) {
            Text("“\(opened.label)” will be removed when you save.")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo") { controller.draft.location = opened }
              .mtButtonStyle(.secondary, size: .small)
              .accessibilityIdentifier("editor-undo-remove-location")
          }
        }
      }
    }
  }

  // MARK: Footer

  private var footer: some View {
    MTSheetFooter {
      if !draft.isNew {
        Button {
          isConfirmingTrash = true
        } label: {
          Label("Move to Trash", icon: .trash)
        }
        .mtButtonStyle(.ghost, isLoading: controller.isTrashing)
        .accessibilityIdentifier("editor-trash")
        .entryTrashConfirmation(trashTitle, isPresented: $isConfirmingTrash) {
          Task { await moveToTrash() }
        }
      }
    } cancel: {
      Button("Cancel") { dismiss() }
        .mtButtonStyle(.secondary)
    } primary: {
      Button(controller.saveTitle) { Task { await save() } }
        .mtButtonStyle(isLoading: controller.isSaving)
        .accessibilityIdentifier("editor-save")
    }
  }

  private var trashTitle: String {
    let title = draft.title.trimmed
    return title.isEmpty ? (draft.original?.displayTitle ?? "this Entry") : title
  }

  private func save() async {
    switch await controller.save() {
    case .saved(let saved):
      onSaved(.saved(saved))
      dismiss()
    case .savedWithUnattachedPhotos(let saved):
      // The Entry changed, so its pages refresh; the editor stays open to retry the photos.
      onSaved(.saved(saved))
    case .failed:
      break
    }
  }

  private func moveToTrash() async {
    guard await controller.moveToTrash() else { return }
    onSaved(.movedToTrash(draft.entryID))
    dismiss()
  }
}

extension View {
  /// Web's recoverable Move to Trash confirmation for one Entry, anchored to its button.
  func entryTrashConfirmation(
    _ title: String, isPresented: Binding<Bool>, confirm: @escaping () -> Void
  ) -> some View {
    confirmationDialog(
      "Move “\(title)” to Trash?", isPresented: isPresented, titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive, action: confirm)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can restore it later from Trash.")
    }
  }
}
