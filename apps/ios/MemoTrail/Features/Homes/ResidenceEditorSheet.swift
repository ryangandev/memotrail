import PhotosUI
import SwiftUI
import UIKit

/// Web `HomeEditor` as a form sheet: Home details, its Location, memories and organization,
/// and photos, with Move to Trash beside Cancel and Save.
struct ResidenceEditorSheet: View {
  let controller: ResidenceController
  let entry: ResidenceEntry?
  let sourceCapture: CaptureExtractionSource?
  let defaultTimezone: String?
  let onSaved: (@MainActor () async -> Void)?
  let onTrashed: (@MainActor () -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var currentPlaceID: UUID?
  @State private var title: String
  @State private var note: String
  @State private var occurrence: OccurrenceDraft
  @State private var address: String
  @State private var city: String
  @State private var region: String
  @State private var country: String
  @State private var latitude: Double?
  @State private var longitude: Double?
  /// Web keeps the saved Location's preview until the address is edited by hand or removed.
  @State private var showsLocationPreview: Bool
  @State private var moveInReason: String
  @State private var moveOutReason: String
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var attachments: [ResidenceAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var uploadProgress: (completed: Int, total: Int)?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: ResidenceAttachment?

  init(
    controller: ResidenceController,
    entry: ResidenceEntry?,
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
    _currentPlaceID = State(initialValue: entry?.placeID)
    _title = State(initialValue: entry?.title ?? sourceCapture?.title ?? "")
    _note = State(initialValue: entry?.body ?? sourceCapture?.body ?? "")
    let timezone = defaultTimezone ?? TimeZone.current.identifier
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence ?? sourceCapture?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone),
        undatedTimezone: timezone))
    _address = State(initialValue: entry?.address ?? "")
    _city = State(initialValue: entry?.city ?? "")
    _region = State(initialValue: entry?.region ?? "")
    _country = State(initialValue: entry?.country ?? "")
    _latitude = State(initialValue: entry?.latitude)
    _longitude = State(initialValue: entry?.longitude)
    _showsLocationPreview = State(initialValue: entry?.placeID != nil)
    _moveInReason = State(initialValue: entry?.moveInReason ?? "")
    _moveOutReason = State(initialValue: entry?.moveOutReason ?? "")
    _collectionNames = State(
      initialValue: entry?.collectionNames ?? sourceCapture?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? sourceCapture?.tagNames ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  private var sheetTitle: String {
    if currentEntryID != nil { return title.trimmed.nonEmpty ?? "Home" }
    return sourceCapture == nil
      ? "Keep a Home in your Life Wiki" : "Create a Home from this Capture"
  }

  var body: some View {
    MTSheet(
      eyebrow: currentEntryID == nil ? "New Home" : "Edit Home", title: sheetTitle,
      closeLabel: "Close Home editor", closeIdentifier: "close-home-editor", isBusy: isWorking,
      message: errorMessage
    ) {
      if sourceCapture != nil {
        MTFeedback(
          title: "Starting from an Inbox Capture",
          message:
            "Saving creates a separate Home and links it to the preserved source Capture.",
          tone: .accent, systemImage: MTIcon.inbox.systemName)
      }
      detailsSection
      locationSection
      memoriesSection
      MTPhotoField(
        recordLabel: "Home", saved: savedPhotos, new: newPhotos,
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
        Button(currentEntryID == nil ? "Add Home" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .accessibilityIdentifier("save-home")
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
    MTFormSection("Home details") {
      MTTextField(
        label: "Home name", text: $title, prompt: "Philadelphia rowhome", isRequired: true,
        maxLength: ResidenceEntryInput.titleLimit
      )
      .textInputAutocapitalization(.words)
      .accessibilityIdentifier("home-title")
      OccurrenceEditor(value: $occurrence, span: true, defaultTimezone: defaultTimezone)
      MTTextField(
        label: "Why you moved in", text: $moveInReason,
        maxLength: ResidenceEntryInput.detailLimit)
      MTTextField(
        label: "Why you left", text: $moveOutReason, maxLength: ResidenceEntryInput.detailLimit)
    }
  }

  private var locationSection: some View {
    MTFormSection("Location") {
      if showsLocationPreview {
        MTLocationPreview(label: locationLabel, latitude: latitude, longitude: longitude) {
          removeLocation()
        }
      }
      MTFormNote(
        "Save an address or position for this Home. It can appear on a future map alongside memories and events from the same area."
      )
      locationField("City", text: $city, limit: ResidenceEntryInput.locationLimit)
      locationField("Region", text: $region, limit: ResidenceEntryInput.locationLimit)
      locationField("Country", text: $country, limit: ResidenceEntryInput.locationLimit)
      MTTextField(
        label: "Exact address",
        text: manualLocation($address), note: "Private",
        maxLength: ResidenceEntryInput.addressLimit
      )
      .textContentType(.fullStreetAddress)
    }
  }

  private func locationField(_ label: String, text: Binding<String>, limit: Int) -> some View {
    MTTextField(label: label, text: manualLocation(text), maxLength: limit)
      .textInputAutocapitalization(.words)
  }

  private var memoriesSection: some View {
    MTFormSection("Memories and organization") {
      MTTextField(
        label: "Memories", text: $note,
        prompt: "What was life like here? What do you want to remember?",
        maxLength: ResidenceEntryInput.bodyLimit, axis: .vertical, lines: 5...12
      )
      .accessibilityIdentifier("home-memories")
      MTOrganizationEditor(
        kind: .collection, names: $collectionNames, options: controller.collectionOptions)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: controller.tagOptions)
    }
  }

  @ViewBuilder private var trashButton: some View {
    if currentEntryID != nil {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("trash-home")
        .confirmationDialog(
          "Move “\(title.trimmed.nonEmpty ?? "this Home")” to Trash?",
          isPresented: $isConfirmingTrash, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Its history, Location, and private photos will be preserved.")
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

  /// Web `locationDisplayLabel` for the saved Location.
  private var locationLabel: String {
    [address, city, region, country].compactMap(\.trimmed.nonEmpty).joined(separator: ", ")
      .nonEmpty ?? "Location not set"
  }

  /// Editing the address by hand discards the saved position, like Web.
  private func manualLocation(_ text: Binding<String>) -> Binding<String> {
    Binding {
      text.wrappedValue
    } set: { value in
      guard value != text.wrappedValue else { return }
      text.wrappedValue = value
      showsLocationPreview = false
      currentPlaceID = nil
      latitude = nil
      longitude = nil
    }
  }

  private func removeLocation() {
    showsLocationPreview = false
    currentPlaceID = nil
    address = ""
    city = ""
    region = ""
    country = ""
    latitude = nil
    longitude = nil
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
      failure = "Keep up to \(FirstTimePhotoDraft.maximumCount) photos on a Home."
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
      placeID: currentPlaceID,
      placeName: String(locationLabel.prefix(ResidenceEntryInput.placeNameLimit)),
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: latitude,
      longitude: longitude,
      placeNotes: entry?.placeNotes ?? "",
      moveInReason: moveInReason,
      moveOutReason: moveOutReason,
      collectionNames: collectionNames,
      tagNames: tagNames,
      originalEntry: entry,
      sourceCapture: currentEntryID == nil ? sourceCapture : nil
    )

    guard result.succeeded, let identity = result.identity else {
      errorMessage = result.message
      return
    }

    let created = currentEntryID == nil
    currentEntryID = identity.id
    currentRevision = identity.revision
    currentPlaceID = identity.placeID

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
        "The Home was saved, but \(failedCount) \(failedCount == 1 ? "photo" : "photos") could not be attached. Select Save again to retry."
      return
    }

    MTToastCenter.shared.success(created ? "Home created." : "Home saved.")
    if let onSaved {
      await onSaved()
    } else {
      dismiss()
    }
  }

  private func removeAttachment(_ attachment: ResidenceAttachment) async {
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
