import PhotosUI
import SwiftUI
import UIKit

/// Web `FirstTimeEditor` as a form sheet: the title, when it happened, its Location, the
/// reflection, organization, and photos, with Move to Trash beside Cancel and Save.
struct FirstTimeEditorSheet: View {
  let controller: FirstTimesController
  let entry: FirstTimeEntry?
  let defaultTimezone: String?
  let onTrashed: (@MainActor () -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var title: String
  @State private var note: String
  @State private var occurrence: OccurrenceDraft
  /// Native iOS keeps or removes a saved Location; address search stays on Web for now.
  @State private var location: EntryLocation?
  @State private var isRemovingLocation = false
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var attachments: [FirstTimeAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var uploadProgress: (completed: Int, total: Int)?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: FirstTimeAttachment?

  init(
    controller: FirstTimesController,
    entry: FirstTimeEntry?,
    defaultTimezone: String? = nil,
    onTrashed: (@MainActor () -> Void)? = nil
  ) {
    self.controller = controller
    self.entry = entry
    self.defaultTimezone = defaultTimezone
    self.onTrashed = onTrashed
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? "")
    _note = State(initialValue: entry?.body ?? "")
    let timezone = defaultTimezone ?? TimeZone.current.identifier
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone),
        undatedTimezone: timezone))
    _location = State(initialValue: entry?.location)
    _collectionNames = State(initialValue: entry?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? [])
    _attachments = State(initialValue: entry?.originalAttachments ?? [])
  }

  var body: some View {
    MTSheet(
      eyebrow: currentEntryID == nil ? "New First Time" : "Edit First Time",
      title: currentEntryID == nil ? "Keep a beginning" : title.trimmed.nonEmpty ?? "First Time",
      closeLabel: "Close First Time editor", closeIdentifier: "close-first-time-editor",
      isBusy: isWorking, message: errorMessage
    ) {
      MTTextField(
        label: "Title", text: $title, prompt: "First time skiing", isRequired: true,
        maxLength: FirstTimeEntryInput.titleLimit
      )
      .textInputAutocapitalization(.sentences)
      .accessibilityIdentifier("first-time-title")
      OccurrenceEditor(value: $occurrence, defaultTimezone: defaultTimezone)
      MTLocationPanel(
        message:
          "This First Time keeps its own Location. To find a new address, use MemoTrail on the web."
      ) {
        if let location {
          MTLocationPreview(
            label: location.label, latitude: location.latitude, longitude: location.longitude
          ) {
            self.location = nil
            isRemovingLocation = true
          }
        }
      }
      MTTextField(
        label: "Reflection", text: $note,
        prompt: "What happened, and what do you want to remember?",
        maxLength: FirstTimeEntryInput.bodyLimit, axis: .vertical, lines: 5...12
      )
      .accessibilityIdentifier("first-time-reflection")
      MTOrganizationEditor(
        kind: .collection, names: $collectionNames, options: controller.collectionOptions)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: controller.tagOptions)
      MTPhotoField(
        recordLabel: "First Time", saved: savedPhotos, new: newPhotos,
        limit: FirstTimePhotoDraft.maximumCount, selection: $pickerItems,
        progress: uploadProgress,
        removeSaved: { photo in attachmentToRemove = attachments.first { $0.id == photo.id } },
        removeNew: { photo in photoDrafts.removeAll { $0.id == photo.id } })
    } footer: {
      MTSheetFooter {
        trashButton
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(currentEntryID == nil ? "Add First Time" : "Save changes") {
          Task { await save() }
        }
        .mtButtonStyle(isLoading: isWorking)
        .accessibilityIdentifier("save-first-time")
      }
    }
    .onChange(of: pickerItems) { _, items in Task { await loadPhotos(from: items) } }
    .confirmationDialog(
      "Move this photo to Trash?",
      isPresented: Binding(
        get: { attachmentToRemove != nil }, set: { if !$0 { attachmentToRemove = nil } }),
      titleVisibility: .visible, presenting: attachmentToRemove
    ) { attachment in
      Button("Move photo to Trash", role: .destructive) {
        Task { await removeAttachment(attachment) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("The original will be preserved for recovery.")
    }
  }

  @ViewBuilder private var trashButton: some View {
    if currentEntryID != nil {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("trash-first-time")
        .confirmationDialog(
          "Move “\(title.trimmed.nonEmpty ?? "this First Time")” to Trash?",
          isPresented: $isConfirmingTrash, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Its history and private photos will be preserved.")
        }
    }
  }

  private var savedPhotos: [MTPhotoField.SavedPhoto] {
    attachments.map {
      MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
    }
  }

  private var newPhotos: [MTPhotoField.NewPhoto] {
    photoDrafts.map {
      MTPhotoField.NewPhoto(id: $0.id, image: UIImage(data: $0.data), name: $0.originalFilename)
    }
  }

  private func loadPhotos(from items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    let available = max(
      0, FirstTimePhotoDraft.maximumCount - attachments.count - photoDrafts.count)
    var failure: String?
    for item in items.prefix(available) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else { continue }
        guard
          let mimeType = FirstTimeImageType.detect(
            data: data, typeIdentifiers: item.supportedContentTypes.map(\.identifier))
        else { throw FirstTimeEntryError.unsupportedPhotoType }
        let image = UIImage(data: data)
        photoDrafts.append(
          try FirstTimePhotoDraft.validate(
            data: data, mimeType: mimeType, originalFilename: nil,
            pixelWidth: image.map { Int($0.size.width * $0.scale) },
            pixelHeight: image.map { Int($0.size.height * $0.scale) }))
      } catch {
        failure = error.localizedDescription
      }
    }
    if items.count > available {
      failure = "Keep up to \(FirstTimePhotoDraft.maximumCount) photos on a First Time."
    }
    errorMessage = failure
    pickerItems = []
  }

  private func save() async {
    let resolved: EntryOccurrence
    do {
      resolved = try occurrence.resolve(original: entry?.occurrence)
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    isWorking = true
    errorMessage = nil
    defer {
      isWorking = false
      uploadProgress = nil
    }
    let result = await controller.save(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      title: title,
      body: note,
      occurredStart: resolved.start,
      datePrecision: FirstTimeDatePrecision(rawValue: resolved.precision.rawValue) ?? .unknown,
      occurredLabel: resolved.label ?? "",
      // Like Web, only a dated First Time stores its time zone.
      occurredTimezone: resolved.start == nil ? nil : resolved.timezone,
      collectionNames: collectionNames,
      tagNames: tagNames,
      occurredEnd: resolved.end,
      original: entry,
      removingLocation: isRemovingLocation
    )

    guard result.succeeded, let identity = result.identity else {
      errorMessage = result.message
      return
    }

    let created = currentEntryID == nil
    currentEntryID = identity.id
    currentRevision = identity.revision
    isRemovingLocation = false

    var failedCount = 0
    let drafts = photoDrafts
    for (index, draft) in drafts.enumerated() {
      uploadProgress = (completed: index, total: drafts.count)
      let upload = await controller.upload(draft, entryID: identity.id)
      if upload.succeeded {
        photoDrafts.removeAll { $0.id == draft.id }
      } else {
        failedCount += 1
      }
    }
    await controller.reloadAfterMutation()
    // Photo changes commute with writing, so only the photos are adopted from the reload.
    if let saved = controller.entry(id: identity.id) { attachments = saved.originalAttachments }

    guard failedCount == 0 else {
      errorMessage =
        "The First Time was saved, but \(countLabel(failedCount, "photo")) could not be attached. Select Save again to retry."
      return
    }

    MTToastCenter.shared.success(created ? "First Time created." : "First Time saved.")
    dismiss()
  }

  private func removeAttachment(_ attachment: FirstTimeAttachment) async {
    isWorking = true
    errorMessage = nil
    let result = await controller.removeAttachment(attachment)
    if result.succeeded {
      attachments.removeAll { $0.id == attachment.id }
      MTToastCenter.shared.info(result.message)
      await controller.reloadAfterMutation()
    } else {
      errorMessage = result.message
    }
    isWorking = false
  }

  private func moveToTrash() async {
    guard let currentEntryID, let currentRevision else { return }
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(
      entryID: currentEntryID, expectedRevision: currentRevision)
    isWorking = false
    guard result.succeeded else {
      errorMessage = result.message
      return
    }
    MTToastCenter.shared.info(result.message)
    dismiss()
    onTrashed?()
  }
}
