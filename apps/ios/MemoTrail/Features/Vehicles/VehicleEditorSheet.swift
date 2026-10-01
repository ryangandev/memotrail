import PhotosUI
import SwiftUI
import UIKit

/// Web `VehicleEditor` as a form sheet: Vehicle details with its Location, Vehicle facts,
/// memories and organization, and photos, with Move to Trash beside Cancel and Save.
struct VehicleEditorSheet: View {
  let controller: VehicleController
  let entry: VehicleEntry?
  let sourceCapture: CaptureExtractionSource?
  let defaultTimezone: String?
  let onSaved: (@MainActor () async -> Void)?
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
  @State private var make: String
  @State private var model: String
  @State private var modelYear: String
  @State private var color: String
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var attachments: [VehicleAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var uploadProgress: (completed: Int, total: Int)?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: VehicleAttachment?

  init(
    controller: VehicleController,
    entry: VehicleEntry?,
    sourceCapture: CaptureExtractionSource? = nil,
    defaultTimezone: String? = nil,
    onSaved: (@MainActor () async -> Void)? = nil,
    onTrashed: (@MainActor () -> Void)? = nil
  ) {
    self.controller = controller
    self.entry = entry
    self.sourceCapture = sourceCapture
    self.defaultTimezone = defaultTimezone
    self.onSaved = onSaved
    self.onTrashed = onTrashed
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? sourceCapture?.title ?? "")
    _note = State(initialValue: entry?.body ?? sourceCapture?.body ?? "")
    let timezone = defaultTimezone ?? TimeZone.current.identifier
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence ?? sourceCapture?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone),
        undatedTimezone: timezone))
    _location = State(initialValue: entry?.location)
    _make = State(initialValue: entry?.make ?? "")
    _model = State(initialValue: entry?.model ?? "")
    _modelYear = State(initialValue: entry?.modelYear.map(String.init) ?? "")
    _color = State(initialValue: entry?.color ?? "")
    _collectionNames = State(
      initialValue: entry?.collectionNames ?? sourceCapture?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? sourceCapture?.tagNames ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  private var sheetTitle: String {
    if currentEntryID != nil { return title.trimmed.nonEmpty ?? "Vehicle" }
    return sourceCapture == nil
      ? "Keep a Vehicle in your Life Wiki" : "Create a Vehicle from this Capture"
  }

  var body: some View {
    MTSheet(
      eyebrow: currentEntryID == nil ? "New Vehicle" : "Edit Vehicle", title: sheetTitle,
      closeLabel: "Close Vehicle editor", closeIdentifier: "close-vehicle-editor",
      isBusy: isWorking, message: errorMessage
    ) {
      if sourceCapture != nil {
        MTFeedback(
          title: "Starting from an Inbox Capture",
          message:
            "Saving creates a separate Vehicle and links it to the preserved source Capture.",
          tone: .accent, systemImage: MTIcon.inbox.systemName)
      }
      detailsSection
      factsSection
      memoriesSection
      MTPhotoField(
        recordLabel: "Vehicle", saved: savedPhotos, new: newPhotos,
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
        Button(currentEntryID == nil ? "Add Vehicle" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .accessibilityIdentifier("save-vehicle")
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

  private var detailsSection: some View {
    MTFormSection("Vehicle details") {
      MTTextField(
        label: "Name or nickname", text: $title, prompt: "Blue Civic", isRequired: true,
        maxLength: VehicleEntryInput.titleLimit
      )
      .textInputAutocapitalization(.words)
      .accessibilityIdentifier("vehicle-title")
      OccurrenceEditor(value: $occurrence, span: true, defaultTimezone: defaultTimezone)
      MTLocationPanel(
        message:
          "This Vehicle keeps its own Location. To find a new address, use MemoTrail on the web."
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
    }
  }

  private var factsSection: some View {
    MTFormSection("Vehicle facts") {
      MTTextField(
        label: "Make", text: $make, prompt: "Honda", maxLength: VehicleEntryInput.makeLimit
      )
      .textInputAutocapitalization(.words)
      MTTextField(
        label: "Model", text: $model, prompt: "Civic", maxLength: VehicleEntryInput.modelLimit
      )
      .textInputAutocapitalization(.words)
      MTTextField(label: "Model year", text: $modelYear, prompt: "2018", maxLength: 4)
        .keyboardType(.numberPad)
      MTTextField(
        label: "Color", text: $color, prompt: "Midnight blue",
        maxLength: VehicleEntryInput.colorLimit
      )
      .textInputAutocapitalization(.words)
    }
  }

  private var memoriesSection: some View {
    MTFormSection("Memories and organization") {
      MTTextField(
        label: "Memories", text: $note,
        prompt: "Where did it take you? What do you want to remember?",
        maxLength: VehicleEntryInput.bodyLimit, axis: .vertical, lines: 5...12
      )
      .accessibilityIdentifier("vehicle-memories")
      MTOrganizationEditor(
        kind: .collection, names: $collectionNames, options: controller.collectionOptions)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: controller.tagOptions)
    }
  }

  @ViewBuilder private var trashButton: some View {
    if currentEntryID != nil {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("trash-vehicle")
        .confirmationDialog(
          "Move “\(title.trimmed.nonEmpty ?? "this Vehicle")” to Trash?",
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
      failure = "Keep up to \(FirstTimePhotoDraft.maximumCount) photos on a Vehicle."
    }
    errorMessage = failure
    pickerItems = []
  }

  private func save() async {
    let resolved: EntryOccurrence
    do {
      resolved = try occurrence.resolve(original: entry?.occurrence, span: true)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    let parsedModelYear: Int?
    if let text = modelYear.trimmed.nonEmpty {
      guard let value = Int(text) else {
        errorMessage = VehicleEntryError.invalidModelYear.localizedDescription
        return
      }
      parsedModelYear = value
    } else {
      parsedModelYear = nil
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
      occurredEnd: resolved.end,
      datePrecision: resolved.precision,
      occurredLabel: resolved.label ?? "",
      occurredTimezone: resolved.timezone,
      make: make,
      model: model,
      modelYear: parsedModelYear,
      color: color,
      collectionNames: collectionNames,
      tagNames: tagNames,
      originalEntry: entry,
      sourceCapture: currentEntryID == nil ? sourceCapture : nil,
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
    if let saved = controller.entry(id: identity.id) { attachments = saved.attachments }

    guard failedCount == 0 else {
      errorMessage =
        "The Vehicle was saved, but \(countLabel(failedCount, "photo")) could not be attached. Select Save again to retry."
      return
    }

    MTToastCenter.shared.success(created ? "Vehicle created." : "Vehicle saved.")
    if let onSaved {
      await onSaved()
    } else {
      dismiss()
    }
  }

  private func removeAttachment(_ attachment: VehicleAttachment) async {
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
