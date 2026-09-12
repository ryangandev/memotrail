import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

struct GoalsView: View {
  @State private var controller: GoalController
  @State private var editorSelection: GoalEditorSelection?
  private let embedded: Bool

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false) {
    self.embedded = embedded
    _controller = State(initialValue: GoalController(client: client, ownerID: ownerID))
  }

  @ViewBuilder
  var body: some View {
    if embedded { archiveView } else { NavigationStack { archiveView } }
  }

  private var archiveView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s6) {
        header
        summary
        content
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle("Goals")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          editorSelection = GoalEditorSelection(entry: nil)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add Goal")
        .accessibilityIdentifier("add-goal")
      }
    }
    .refreshable { await controller.load() }
    .sheet(item: $editorSelection) { selection in
      GoalEditorSheet(controller: controller, entry: selection.entry)
    }
    .task { if !controller.hasLoaded { await controller.load() } }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("INTENTIONS WITHOUT THE PRESSURE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)
      Text("Goals").font(MTTypography.display).foregroundStyle(MTColor.ink)
      Text("Keep what you are moving toward, considering, or ready to leave behind.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text("\(controller.entries.count) \(controller.entries.count == 1 ? "goal" : "goals")")
      Text("·")
      Text("\(controller.activeEntries.count) in motion")
      Text("·")
      Label("\(controller.photoCount)", systemImage: "photo")
      Spacer()
      if controller.isLoading, controller.hasLoaded { ProgressView().controlSize(.small) }
    }
    .font(MTTypography.caption)
    .foregroundStyle(MTColor.inkFaint)
  }

  @ViewBuilder
  private var content: some View {
    if controller.isLoading, !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView()
        Text("Loading your Goals...").foregroundStyle(MTColor.inkMuted)
      }
      .font(MTTypography.body)
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "Goals unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.entries.isEmpty {
      archiveMessage(
        title: "Begin with something worth moving toward",
        message: "Give it a title and a horizon. A target date is always optional.",
        systemImage: "target"
      )
    } else {
      if !controller.activeEntries.isEmpty {
        goalSection(title: "IN MOTION", entries: controller.activeEntries)
      }
      if !controller.consideringEntries.isEmpty {
        goalSection(title: "CONSIDERING", entries: controller.consideringEntries)
      }
      if !controller.pausedEntries.isEmpty {
        goalSection(title: "PAUSED", entries: controller.pausedEntries)
      }
      if !controller.closedEntries.isEmpty {
        goalSection(title: "CLOSED CHAPTERS", entries: controller.closedEntries)
      }
    }
  }

  private func goalSection(title: String, entries: [GoalEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)
      ForEach(entries) { entry in
        Button {
          editorSelection = GoalEditorSelection(entry: entry)
        } label: {
          GoalArchiveCard(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(entry.title)")
      }
    }
  }

  private func archiveMessage(title: String, message: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(MTColor.accent)
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(title).font(MTTypography.titleSmall).foregroundStyle(MTColor.ink)
        Text(message).font(MTTypography.body).foregroundStyle(MTColor.inkMuted).lineSpacing(2)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(MTColor.surfaceSubtle.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
  }
}

private struct GoalArchiveCard: View {
  let entry: GoalEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment = entry.attachments.first {
        GoalRemoteImage(attachment: attachment).frame(height: 180).clipped()
      }
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: MTSpacing.s2) {
              Text(entry.horizon.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(MTColor.warm)
              Text(entry.status.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MTColor.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MTColor.accentSubtle, in: Capsule())
            }
            Text(entry.title)
              .font(MTTypography.titleSmall)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)
            Label(entry.targetLabel, systemImage: "calendar")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkMuted)
          }
          Spacer(minLength: MTSpacing.s2)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }
        if !entry.body.isEmpty {
          Text(entry.body)
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
        }
        if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MTSpacing.s2) {
              ForEach(entry.collectionNames, id: \.self) { name in
                GoalPill(label: name, systemImage: "archivebox")
              }
              ForEach(entry.tagNames, id: \.self) { name in
                GoalPill(label: name, systemImage: "number")
              }
            }
          }
        }
        if !entry.relatedEntries.isEmpty {
          Label(
            "\(entry.relatedEntries.count) linked \(entry.relatedEntries.count == 1 ? "Entry" : "Entries")",
            systemImage: "link"
          )
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
        }
      }
      .padding(MTSpacing.s4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
  }
}

private struct GoalRemoteImage: View {
  let attachment: GoalAttachment

  var body: some View {
    AsyncImage(url: attachment.signedURL) { phase in
      switch phase {
      case .success(let image): image.resizable().scaledToFill()
      case .failure: placeholder(systemImage: "exclamationmark.triangle")
      case .empty:
        ZStack {
          MTColor.surfaceSubtle
          ProgressView()
        }
      @unknown default: placeholder(systemImage: "photo")
      }
    }
    .accessibilityLabel(attachment.originalFilename ?? "Goal photo")
  }

  private func placeholder(systemImage: String) -> some View {
    ZStack {
      MTColor.surfaceSubtle
      Image(systemName: systemImage).font(.system(size: 24)).foregroundStyle(MTColor.inkFaint)
    }
  }
}

private struct GoalPill: View {
  let label: String
  let systemImage: String

  var body: some View {
    Label(label, systemImage: systemImage)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(MTColor.surfaceSubtle, in: Capsule())
  }
}

struct GoalEditorSelection: Identifiable {
  let id = UUID()
  let entry: GoalEntry?
}

struct GoalEditorSheet: View {
  let controller: GoalController
  let entry: GoalEntry?

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var title: String
  @State private var reflection: String
  @State private var horizon: GoalHorizon
  @State private var status: GoalStatus
  @State private var usesTargetDate: Bool
  @State private var targetDate: Date
  @State private var collectionNames: [String]
  @State private var collectionInput = ""
  @State private var tagNames: [String]
  @State private var tagInput = ""
  @State private var relatedEntryIDs: [UUID]
  @State private var attachments: [GoalAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var achievementOccurrence = OccurrenceDraft(
    EntryOccurrence(
      precision: .unknown, start: nil, end: nil, label: nil, timezone: TimeZone.current.identifier))
  @State private var isWorking = false
  @State private var progressMessage: String?
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: GoalAttachment?

  init(controller: GoalController, entry: GoalEntry?) {
    self.controller = controller
    self.entry = entry
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? "")
    _reflection = State(initialValue: entry?.body ?? "")
    _horizon = State(initialValue: entry?.horizon ?? .shortTerm)
    _status = State(initialValue: entry?.status ?? .considering)
    _usesTargetDate = State(initialValue: entry?.targetDate != nil)
    _targetDate = State(
      initialValue: entry?.targetDate.flatMap(GoalCalendarDate.date) ?? Date()
    )
    _collectionNames = State(initialValue: entry?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? [])
    _relatedEntryIDs = State(initialValue: entry?.editableRelatedEntries.map(\.id) ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        intentionSection
        organizationSections
        relatedEntriesSection
        photosSection
        achievementSection
        statusSections
      }
      .navigationTitle(entry == nil ? "New Goal" : "Edit Goal")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: title) { trim(&title, to: GoalEntryInput.titleLimit) }
      .onChange(of: reflection) { trim(&reflection, to: GoalEntryInput.bodyLimit) }
      .onChange(of: pickerItems) { _, items in Task { await loadPhotos(from: items) } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(entry == nil ? "Add" : "Save") { Task { await save() } }
            .fontWeight(.semibold)
            .disabled(isWorking)
            .accessibilityIdentifier("save-goal")
        }
      }
      .overlay {
        if isWorking {
          VStack(spacing: MTSpacing.s2) {
            ProgressView()
            if let progressMessage {
              Text(progressMessage).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            }
          }
          .padding(MTSpacing.s4)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
      .confirmationDialog(
        "Move this Goal to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its photos, relationships, and edit history will be preserved.")
      }
      .confirmationDialog(
        "Remove this photo?",
        isPresented: Binding(
          get: { attachmentToRemove != nil },
          set: { if !$0 { attachmentToRemove = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove Photo", role: .destructive) {
          if let attachmentToRemove { Task { await removeAttachment(attachmentToRemove) } }
        }
        Button("Cancel", role: .cancel) { attachmentToRemove = nil }
      } message: {
        Text("The original file will be preserved for future restoration.")
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  private var intentionSection: some View {
    Section {
      TextField("What are you moving toward?", text: $title, axis: .vertical)
        .textInputAutocapitalization(.sentences)
        .accessibilityIdentifier("goal-title")
      TextEditor(text: $reflection)
        .frame(minHeight: 130)
        .accessibilityLabel("Reflection")
        .accessibilityIdentifier("goal-reflection")
      Picker("Horizon", selection: $horizon) {
        ForEach(GoalHorizon.allCases, id: \.self) { value in
          Text(value.displayName).tag(value)
        }
      }
      Picker("Status", selection: $status) {
        ForEach(GoalStatus.allCases, id: \.self) { value in
          Text(value.displayName).tag(value)
        }
      }
      Toggle("Add a target date", isOn: $usesTargetDate)
      if usesTargetDate {
        DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
      }
    } header: {
      Text("Intention")
    } footer: {
      Text("The target date is context, not a deadline. MemoTrail will not mark it overdue.")
    }
  }

  @ViewBuilder
  private var organizationSections: some View {
    Section("Collections") {
      GoalNameEditor(
        names: $collectionNames,
        input: $collectionInput,
        options: controller.collectionOptions,
        placeholder: "Add a Collection",
        maximumCount: GoalEntryInput.collectionLimit,
        maximumNameLength: GoalEntryInput.collectionNameLimit
      )
    }
    Section("Tags") {
      GoalNameEditor(
        names: $tagNames,
        input: $tagInput,
        options: controller.tagOptions,
        placeholder: "Add a tag",
        maximumCount: GoalEntryInput.tagLimit,
        maximumNameLength: GoalEntryInput.tagNameLimit
      )
    }
  }

  private var relatedEntriesSection: some View {
    Section {
      if relatedEntryIDs.isEmpty {
        Text("No related Entries yet")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkFaint)
      } else {
        ForEach(relatedEntryIDs, id: \.self) { id in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(relatedTitle(id))
                .font(MTTypography.body)
                .foregroundStyle(MTColor.ink)
                .lineLimit(2)
              if let type = relatedType(id) {
                Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                  .font(MTTypography.caption)
                  .foregroundStyle(MTColor.inkFaint)
              }
            }
            Spacer()
            Button {
              relatedEntryIDs.removeAll { $0 == id }
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(MTColor.inkFaint)
            .accessibilityLabel("Remove \(relatedTitle(id))")
          }
        }
      }
      if !availableLinkOptions.isEmpty, relatedEntryIDs.count < GoalEntryInput.relatedEntryLimit {
        Menu("Link an Entry", systemImage: "link.badge.plus") {
          ForEach(availableLinkOptions) { option in
            Button {
              relatedEntryIDs.append(option.id)
            } label: {
              Text(
                "\(option.displayTitle) · \(option.entryType.replacingOccurrences(of: "_", with: " ").capitalized)"
              )
            }
          }
        }
      }
      if let entry, !entry.achievementEntries.isEmpty {
        ForEach(entry.achievementEntries) { achieved in
          Label("First Time: \(achieved.displayTitle)", systemImage: "star.fill")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.accent)
        }
      }
    } header: {
      Text("Related Entries")
    } footer: {
      Text("Links add context without copying or changing the original Entry.")
    }
  }

  private var photosSection: some View {
    Section {
      if attachments.isEmpty, photoDrafts.isEmpty {
        Text("No photos yet").font(MTTypography.body).foregroundStyle(MTColor.inkFaint)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s3) {
            ForEach(attachments) { attachment in
              ZStack(alignment: .topTrailing) {
                GoalRemoteImage(attachment: attachment)
                  .frame(width: 132, height: 112)
                  .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                removeButton(label: "Remove photo") { attachmentToRemove = attachment }
              }
            }
            ForEach(photoDrafts) { draft in
              ZStack(alignment: .topTrailing) {
                if let image = UIImage(data: draft.data) {
                  Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                }
                removeButton(label: "Remove selected photo") {
                  photoDrafts.removeAll { $0.id == draft.id }
                }
              }
            }
          }
        }
      }
      PhotosPicker(
        selection: $pickerItems,
        maxSelectionCount: max(1, remainingPhotoCount),
        matching: .images
      ) {
        Label("Add photos", systemImage: "photo.badge.plus")
      }
      .disabled(remainingPhotoCount == 0)
      .accessibilityIdentifier("add-goal-photos")
    } header: {
      Text("Photos")
    } footer: {
      Text(
        "\(attachments.count + photoDrafts.count) of \(FirstTimePhotoDraft.maximumCount). Each photo can be up to 50 MB."
      )
    }
  }

  @ViewBuilder
  private var achievementSection: some View {
    if let entry, entry.isBucketList, status != .achieved {
      Section {
        Label("Turn this achievement into a First Time", systemImage: "star")
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
        Text(
          "MemoTrail will mark this Goal Achieved and create a linked First Time with the same title. Your reflection stays here."
        )
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkMuted)
      } header: {
        Text("Bucket List Milestone")
      }
      OccurrenceEditor(value: $achievementOccurrence)
      Section {
        if hasUnsavedChanges {
          Label(
            "Save your other Goal changes before recording this milestone.",
            systemImage: "info.circle"
          )
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkMuted)
        }
        Button("Mark achieved and create First Time", systemImage: "checkmark") {
          Task { await markAchieved() }
        }
        .disabled(hasUnsavedChanges)
        .accessibilityIdentifier("achieve-bucket-list-goal")
      }
    }
  }

  @ViewBuilder
  private var statusSections: some View {
    if let errorMessage {
      Section {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
          .accessibilityIdentifier("goal-editor-error")
      }
    }
    if currentEntryID != nil {
      Section {
        Button("Move to Trash", role: .destructive) { isConfirmingTrash = true }
      } footer: {
        Text("The Goal, photos, relationships, and edit history remain available for restoration.")
      }
    }
  }

  private var availableLinkOptions: [GoalLinkOption] {
    controller.linkOptions.filter { option in
      option.id != currentEntryID && !relatedEntryIDs.contains(option.id)
    }
  }

  private var hasUnsavedChanges: Bool {
    guard let entry else { return true }
    return title != entry.title || reflection != entry.body || horizon != entry.horizon
      || status != entry.status || selectedTargetDate != entry.targetDate
      || collectionNames != entry.collectionNames || tagNames != entry.tagNames
      || relatedEntryIDs != entry.editableRelatedEntries.map(\.id)
      || !collectionInput.trimmed.isEmpty || !tagInput.trimmed.isEmpty || !photoDrafts.isEmpty
  }

  private var selectedTargetDate: String? {
    usesTargetDate ? GoalCalendarDate.string(from: targetDate) : nil
  }

  private var remainingPhotoCount: Int {
    max(0, FirstTimePhotoDraft.maximumCount - attachments.count - photoDrafts.count)
  }

  private func relatedTitle(_ id: UUID) -> String {
    controller.linkOptions.first { $0.id == id }?.displayTitle
      ?? entry?.editableRelatedEntries.first { $0.id == id }?.displayTitle
      ?? "Related Entry"
  }

  private func relatedType(_ id: UUID) -> String? {
    controller.linkOptions.first { $0.id == id }?.entryType
      ?? entry?.editableRelatedEntries.first { $0.id == id }?.entryType
  }

  private func removeButton(label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: 26, height: 26)
        .background(Color.black.opacity(0.65), in: Circle())
    }
    .buttonStyle(.plain)
    .padding(6)
    .accessibilityLabel(label)
  }

  private func trim(_ value: inout String, to limit: Int) {
    if value.count > limit { value = String(value.prefix(limit)) }
  }

  @MainActor
  private func loadPhotos(from items: [PhotosPickerItem]) async {
    errorMessage = nil
    for item in items.prefix(remainingPhotoCount) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else { continue }
        guard
          let mimeType = FirstTimeImageType.detect(
            data: data,
            typeIdentifiers: item.supportedContentTypes.map(\.identifier)
          )
        else { throw FirstTimeEntryError.unsupportedPhotoType }
        let image = UIImage(data: data)
        photoDrafts.append(
          try FirstTimePhotoDraft.validate(
            data: data,
            mimeType: mimeType,
            originalFilename: nil,
            pixelWidth: image.map { Int($0.size.width * $0.scale) },
            pixelHeight: image.map { Int($0.size.height * $0.scale) }
          ))
      } catch {
        errorMessage = error.localizedDescription
      }
    }
    pickerItems = []
  }

  @MainActor
  private func save() async {
    errorMessage = nil
    isWorking = true
    progressMessage = "Saving Goal..."
    let result = await controller.save(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      title: title,
      body: reflection,
      horizon: horizon,
      status: status,
      targetDate: selectedTargetDate,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      tagNames: namesIncludingDraft(tagNames, tagInput),
      relatedEntryIDs: relatedEntryIDs
    )
    guard result.status == .saved, let identity = result.identity else {
      isWorking = false
      progressMessage = nil
      errorMessage = result.message
      return
    }

    currentEntryID = identity.id
    currentRevision = identity.revision
    var uploadedIDs: Set<UUID> = []
    var failedMessage: String?
    for (index, draft) in photoDrafts.enumerated() {
      progressMessage = "Uploading photo \(index + 1) of \(photoDrafts.count)..."
      let uploadResult = await controller.upload(draft, entryID: identity.id)
      if uploadResult.status == .saved {
        uploadedIDs.insert(draft.id)
      } else {
        failedMessage = uploadResult.message
      }
    }
    photoDrafts.removeAll { uploadedIDs.contains($0.id) }
    await controller.reloadAfterMutation()
    isWorking = false
    progressMessage = nil
    if let failedMessage {
      errorMessage = "Your Goal was saved. \(failedMessage)"
    } else {
      dismiss()
    }
  }

  @MainActor
  private func markAchieved() async {
    guard let currentEntryID, let currentRevision, !hasUnsavedChanges else { return }
    isWorking = true
    errorMessage = nil
    progressMessage = "Recording milestone..."
    let occurrence: EntryOccurrence
    do { occurrence = try achievementOccurrence.resolve() } catch {
      isWorking = false
      progressMessage = nil
      errorMessage = error.localizedDescription
      return
    }
    let result = await controller.markAchieved(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      occurredStart: occurrence.start,
      datePrecision: occurrence.precision,
      occurredLabel: occurrence.label ?? "",
      occurredTimezone: occurrence.timezone,
      occurredEnd: occurrence.end
    )
    if result.status == .achieved {
      await controller.reloadAfterMutation()
      isWorking = false
      progressMessage = nil
      dismiss()
    } else {
      isWorking = false
      progressMessage = nil
      errorMessage = result.message
    }
  }

  @MainActor
  private func removeAttachment(_ attachment: GoalAttachment) async {
    isWorking = true
    errorMessage = nil
    progressMessage = "Removing photo..."
    let result = await controller.removeAttachment(attachment)
    if result.status == .trashed {
      attachments.removeAll { $0.id == attachment.id }
      attachmentToRemove = nil
      await controller.reloadAfterMutation()
    } else {
      errorMessage = result.message
    }
    isWorking = false
    progressMessage = nil
  }

  @MainActor
  private func moveToTrash() async {
    guard let currentEntryID, let currentRevision else { return }
    isWorking = true
    errorMessage = nil
    progressMessage = "Moving to Trash..."
    let result = await controller.moveToTrash(
      entryID: currentEntryID,
      expectedRevision: currentRevision
    )
    isWorking = false
    progressMessage = nil
    if result.status == .trashed { dismiss() } else { errorMessage = result.message }
  }

  private func namesIncludingDraft(_ names: [String], _ draft: String) -> [String] {
    let name = draft.trimmed
    return name.isEmpty ? names : names + [name]
  }
}

private struct GoalNameEditor: View {
  @Binding var names: [String]
  @Binding var input: String
  let options: [String]
  let placeholder: String
  let maximumCount: Int
  let maximumNameLength: Int

  private var selectedNames: Set<String> { Set(names.map { $0.lowercased() }) }
  private var suggestions: [String] {
    options.filter { !selectedNames.contains($0.lowercased()) }
  }

  var body: some View {
    if !names.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MTSpacing.s2) {
          ForEach(names, id: \.self) { name in
            Button {
              names.removeAll { $0 == name }
            } label: {
              Label(name, systemImage: "xmark").font(MTTypography.caption)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Remove \(name)")
          }
        }
      }
    }
    HStack {
      TextField(placeholder, text: $input)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .onSubmit(addInput)
        .onChange(of: input) {
          if input.count > maximumNameLength { input = String(input.prefix(maximumNameLength)) }
        }
      Button("Add", systemImage: "plus") { addInput() }
        .labelStyle(.iconOnly)
        .disabled(input.trimmed.isEmpty || names.count >= maximumCount)
    }
    if !suggestions.isEmpty, names.count < maximumCount {
      Menu("Add existing", systemImage: "tag") {
        ForEach(suggestions, id: \.self) { suggestion in
          Button(suggestion) { add(suggestion) }
        }
      }
      .font(MTTypography.caption)
    }
  }

  private func addInput() {
    add(input)
    input = ""
  }

  private func add(_ value: String) {
    let name = value.trimmed
    guard !name.isEmpty, name.count <= maximumNameLength, names.count < maximumCount,
      !selectedNames.contains(name.lowercased())
    else { return }
    names.append(name)
  }
}
