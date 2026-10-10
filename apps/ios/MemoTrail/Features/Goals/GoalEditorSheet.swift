import PhotosUI
import SwiftUI
import UIKit

/// Web `GoalEditor` as a form sheet: the intention, organization, related Items, and photos,
/// with Move to Trash beside Cancel and Save. A saved Bucket List Goal can also be marked
/// achieved, which creates a linked First Time and keeps the editor open, like Web.
struct GoalEditorSheet: View {
  let controller: GoalController
  let entry: GoalEntry?
  let sourceCapture: CaptureExtractionSource?
  let onTrashed: (@MainActor () -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var title: String
  @State private var reflection: String
  @State private var horizon: GoalHorizon
  @State private var status: GoalStatus
  @State private var targetDate: String
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var relatedEntryIDs: [UUID]
  @State private var relatedSelection: UUID?
  @State private var attachments: [GoalAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var uploadProgress: (completed: Int, total: Int)?
  /// Like Web, the achievement is dated in the device's time zone.
  @State private var achievementOccurrence = OccurrenceDraft(
    EntryOccurrence(
      precision: .unknown, start: nil, end: nil, label: nil, timezone: TimeZone.current.identifier)
  )
  @State private var achievementError: String?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: GoalAttachment?

  init(
    controller: GoalController,
    entry: GoalEntry?,
    sourceCapture: CaptureExtractionSource? = nil,
    onTrashed: (@MainActor () -> Void)? = nil
  ) {
    self.controller = controller
    self.entry = entry
    self.sourceCapture = sourceCapture
    self.onTrashed = onTrashed
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? sourceCapture?.title ?? "")
    _reflection = State(initialValue: entry?.body ?? sourceCapture?.body ?? "")
    _horizon = State(initialValue: entry?.horizon ?? .shortTerm)
    _status = State(initialValue: entry?.status ?? .considering)
    _targetDate = State(initialValue: entry?.targetDate ?? "")
    _collectionNames = State(
      initialValue: entry?.collectionNames ?? sourceCapture?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? sourceCapture?.tagNames ?? [])
    _relatedEntryIDs = State(initialValue: entry?.editableRelatedEntries.map(\.id) ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  private var sheetTitle: String {
    if currentEntryID != nil { return title.trimmed.nonEmpty ?? "Goal" }
    return sourceCapture == nil ? "Keep an intention close" : "Create a Goal from this Capture"
  }

  var body: some View {
    MTSheet(
      eyebrow: currentEntryID == nil ? "New Goal" : "Edit Goal", title: sheetTitle,
      closeLabel: "Close Goal editor", closeIdentifier: "close-goal-editor",
      isBusy: isWorking, message: errorMessage
    ) {
      if sourceCapture != nil {
        MTFeedback(
          title: "Starting from an Inbox Capture",
          message: "Saving creates a separate Goal and links it to the preserved source Capture.",
          tone: .accent, systemImage: MTIcon.inbox.systemName)
      }
      intentionSection
      MTFormSection("Organization") {
        MTOrganizationEditor(
          kind: .collection, names: $collectionNames, options: controller.collectionOptions)
        MTOrganizationEditor(kind: .tag, names: $tagNames, options: controller.tagOptions)
      }
      relatedSection
      MTPhotoField(
        recordLabel: "Goal", saved: savedPhotos, new: newPhotos,
        limit: FirstTimePhotoDraft.maximumCount, selection: $pickerItems,
        progress: uploadProgress,
        removeSaved: { photo in attachmentToRemove = attachments.first { $0.id == photo.id } },
        removeNew: { photo in photoDrafts.removeAll { $0.id == photo.id } })
      achievementSection
    } footer: {
      MTSheetFooter {
        trashButton
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(currentEntryID == nil ? "Add Goal" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .accessibilityIdentifier("save-goal")
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

  private var intentionSection: some View {
    MTFormSection("The intention") {
      MTTextField(
        label: "Title", text: $title, prompt: "Learn to sail", isRequired: true,
        maxLength: GoalEntryInput.titleLimit
      )
      .textInputAutocapitalization(.sentences)
      .accessibilityIdentifier("goal-title")
      MTSelectField(
        label: "Horizon", selection: $horizon, options: GoalHorizon.allCases,
        title: \.displayName)
      MTSelectField(
        label: "Reflective state", selection: $status, options: GoalStatus.allCases,
        title: \.displayName)
      MTDateField(label: "Target date", value: $targetDate)
      MTTextField(
        label: "Reflection", text: $reflection,
        prompt: "Why does this matter? What would you like to remember about wanting it?",
        maxLength: GoalEntryInput.bodyLimit, axis: .vertical, lines: 6...12
      )
      .accessibilityIdentifier("goal-reflection")
    }
  }

  private var relatedSection: some View {
    MTFormSection("Related Items") {
      MTFormNote(
        "Link memories, ideas, or learning that give this Goal context.", color: MTColor.inkFaint)
      if !relatedEntryIDs.isEmpty {
        MTFlowLayout(spacing: MTSpacing.chipGap) {
          ForEach(relatedEntryIDs, id: \.self) { id in
            Button {
              relatedEntryIDs.removeAll { $0 == id }
            } label: {
              HStack(spacing: MTSpacing.s2) {
                Text(relatedTitle(id))
                Text("×")
                  .font(.mtIcon(MTSize.Icon.s16))
                  .foregroundStyle(MTColor.inkFaint)
                  .accessibilityHidden(true)
              }
            }
            .mtButtonStyle(.secondary)
            .accessibilityLabel("Remove related Item \(relatedTitle(id))")
          }
        }
      }
      // Web sets the picker beside Add link, and stacks them on phones.
      if horizontalSizeClass == .regular {
        HStack(alignment: .bottom, spacing: MTSpacing.s2) {
          relatedPicker
          addLinkButton
        }
      } else {
        relatedPicker
        addLinkButton
      }
    }
  }

  private var relatedPicker: some View {
    let options = availableLinkOptions
    return MTSelectField(
      label: "Choose a related Item", selection: $relatedSelection,
      options: [nil] + options.map { Optional($0.id) },
      title: { id in
        guard let id, let option = options.first(where: { $0.id == id }) else {
          return options.isEmpty ? "No more Items available" : "Choose an Item"
        }
        return "\(option.displayTitle) · \(option.displayType)"
      },
      hidesLabel: true
    )
    .disabled(options.isEmpty)
    .accessibilityIdentifier("goal-related-item")
  }

  private var addLinkButton: some View {
    Button("Add link") {
      guard let relatedSelection else { return }
      relatedEntryIDs.append(relatedSelection)
      self.relatedSelection = nil
    }
    .mtButtonStyle(.secondary, fillsWidth: horizontalSizeClass != .regular)
    .disabled(relatedSelection == nil)
    .accessibilityIdentifier("add-goal-related-item")
  }

  /// Web `AchievementPanel`, shown while a saved Bucket List Goal is not yet achieved.
  @ViewBuilder private var achievementSection: some View {
    if currentEntryID != nil, let saved = savedEntry, saved.isBucketList, status != .achieved {
      MTFormSection("Bucket List milestone", tone: .accent) {
        HStack(alignment: .top, spacing: MTSpacing.s3) {
          Image(.star)
            .font(.mtIcon(MTSize.Icon.s17, weight: .medium))
            .foregroundStyle(MTColor.accent)
            .frame(width: MTLayout.IconTile.small, height: MTLayout.IconTile.small)
            .background(MTColor.surfaceRaised, in: Circle())
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: MTSpacing.headingGap) {
            Text("Turn this achievement into a First Time")
              .font(MTFont.itemTitle)
              .foregroundStyle(MTColor.ink)
            Text(
              "MemoTrail will mark the Goal Achieved and create a linked First Time with the same title. Your private reflection stays here."
            )
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
          }
          .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        OccurrenceEditor(value: $achievementOccurrence)
        if let achievementError {
          Text(achievementError)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.warm)
            .accessibilityAddTraits(.updatesFrequently)
        }
        if hasUnsavedChanges {
          Text("Save your other Goal changes before recording this milestone.")
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
        }
        Button {
          Task { await markAchieved() }
        } label: {
          Label("Mark achieved and create First Time", icon: .check)
        }
        .mtButtonStyle()
        .disabled(hasUnsavedChanges)
        .accessibilityIdentifier("achieve-bucket-list-goal")
      }
    }
  }

  @ViewBuilder private var trashButton: some View {
    if currentEntryID != nil {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("trash-goal")
        .confirmationDialog(
          "Move “\(title.trimmed.nonEmpty ?? "this Goal")” to Trash?",
          isPresented: $isConfirmingTrash, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Its history and private photos will be preserved.")
        }
    }
  }

  /// The Goal as last saved, which Web's editor reads again after each refresh.
  private var savedEntry: GoalEntry? {
    currentEntryID.flatMap { controller.entry(id: $0) } ?? entry
  }

  private var hasUnsavedChanges: Bool {
    guard let saved = savedEntry else { return false }
    return title != saved.title || reflection != saved.body || horizon != saved.horizon
      || status != saved.status || targetDate.trimmed.nonEmpty != saved.targetDate
      || collectionNames != saved.collectionNames || tagNames != saved.tagNames
      || relatedEntryIDs != saved.editableRelatedEntries.map(\.id) || !photoDrafts.isEmpty
  }

  private var availableLinkOptions: [GoalLinkOption] {
    controller.linkOptions.filter { $0.id != currentEntryID && !relatedEntryIDs.contains($0.id) }
  }

  private func relatedTitle(_ id: UUID) -> String {
    controller.linkOptions.first { $0.id == id }?.displayTitle
      ?? entry?.editableRelatedEntries.first { $0.id == id }?.displayTitle
      ?? "Related Item"
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
      failure = "Keep up to \(FirstTimePhotoDraft.maximumCount) photos on a Goal."
    }
    errorMessage = failure
    pickerItems = []
  }

  private func save() async {
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
      body: reflection,
      horizon: horizon,
      status: status,
      targetDate: targetDate.trimmed.nonEmpty,
      collectionNames: collectionNames,
      tagNames: tagNames,
      relatedEntryIDs: relatedEntryIDs,
      sourceCapture: currentEntryID == nil ? sourceCapture : nil
    )
    guard result.succeeded, let identity = result.identity else {
      errorMessage = result.message
      return
    }

    let created = currentEntryID == nil
    currentEntryID = identity.id
    currentRevision = identity.revision

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
        "The Goal was saved, but \(countLabel(failedCount, "photo")) could not be attached. Select Save again to retry."
      return
    }

    MTToastCenter.shared.success(created ? "Goal created." : "Goal saved.")
    dismiss()
  }

  private func markAchieved() async {
    guard let currentEntryID, let currentRevision, !hasUnsavedChanges else { return }
    let occurrence: EntryOccurrence
    do {
      occurrence = try achievementOccurrence.resolve()
    } catch {
      achievementError = error.localizedDescription
      return
    }

    isWorking = true
    achievementError = nil
    defer { isWorking = false }
    let result = await controller.markAchieved(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      occurredStart: occurrence.start,
      datePrecision: occurrence.precision,
      occurredLabel: occurrence.label ?? "",
      occurredTimezone: occurrence.timezone,
      occurredEnd: occurrence.end
    )
    guard result.succeeded, let identity = result.identity else {
      achievementError = result.message
      return
    }
    // Like Web, the editor stays open on the now achieved Goal.
    self.currentRevision = identity.revision
    status = .achieved
    errorMessage = nil
    await controller.reloadAfterMutation()
    MTToastCenter.shared.success(result.message)
  }

  private func removeAttachment(_ attachment: GoalAttachment) async {
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
