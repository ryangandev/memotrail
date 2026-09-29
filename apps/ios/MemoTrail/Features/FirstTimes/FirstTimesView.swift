import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

struct FirstTimesView: View {
  @State private var controller: FirstTimesController
  @State private var editorSelection: FirstTimeEditorSelection?

  private let embedded: Bool
  private let focusedEntryID: UUID?

  init(
    client: SupabaseClient,
    ownerID: UUID,
    embedded: Bool = false,
    focusedEntryID: UUID? = nil
  ) {
    self.embedded = embedded
    self.focusedEntryID = focusedEntryID
    _controller = State(
      initialValue: FirstTimesController(client: client, ownerID: ownerID)
    )
  }

  @ViewBuilder
  var body: some View {
    if embedded {
      archiveView
    } else {
      NavigationStack {
        archiveView
      }
    }
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
    .navigationTitle("First Times")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          editorSelection = FirstTimeEditorSelection(entry: nil)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add First Time")
        .accessibilityIdentifier("add-first-time")
      }
    }
    .refreshable {
      await controller.load()
    }
    .sheet(item: $editorSelection) { selection in
      FirstTimeEditorSheet(
        controller: controller,
        entry: selection.entry,
        collectionOptions: controller.collectionOptions,
        tagOptions: controller.tagOptions
      )
    }
    .task {
      if !controller.hasLoaded {
        await controller.load()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("A PERSONAL ARCHIVE OF BEGINNINGS")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.inkFaint)

      Text("First Times")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Keep the date, story, and photos from every new experience.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text(entryCountLabel)
      Text("·")
      Label(photoCountLabel, systemImage: "photo")

      Spacer()

      if controller.isLoading, controller.hasLoaded {
        ProgressView()
          .controlSize(.small)
      }
    }
    .font(MTTypography.caption)
    .foregroundStyle(MTColor.inkFaint)
  }

  @ViewBuilder
  private var content: some View {
    if controller.isLoading, !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView()
        Text("Loading your First Times...")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "First Times unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if let focusedEntryID {
      if let entry = controller.entries.first(where: { $0.id == focusedEntryID }) {
        firstTimeSection(title: "FIRST TIME", entries: [entry])
      } else {
        archiveMessage(
          title: "First Time unavailable",
          message: "This First Time is no longer available in the loaded workspace.",
          systemImage: "star"
        )
      }
    } else if controller.entries.isEmpty {
      archiveMessage(
        title: "Your archive starts here",
        message:
          "Add a title now. A date, reflection, Collections, tags, and photos can come later.",
        systemImage: "sparkles"
      )
    } else {
      LazyVStack(spacing: MTSpacing.s4) {
        ForEach(controller.entries) { entry in
          Button {
            editorSelection = FirstTimeEditorSelection(entry: entry)
          } label: {
            FirstTimeArchiveCard(entry: entry)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Edit \(entry.title)")
        }
      }
    }
  }

  private func firstTimeSection(title: String, entries: [FirstTimeEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)

      ForEach(entries) { entry in
        Button {
          editorSelection = FirstTimeEditorSelection(entry: entry)
        } label: {
          FirstTimeArchiveCard(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(entry.title)")
      }
    }
  }

  private func archiveMessage(
    title: String,
    message: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(MTColor.accent)

      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)

        Text(message)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(MTColor.surfaceSubtle.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var entryCountLabel: String {
    "\(controller.entries.count) \(controller.entries.count == 1 ? "first" : "firsts")"
  }

  private var photoCountLabel: String {
    "\(controller.photoCount) \(controller.photoCount == 1 ? "photo" : "photos")"
  }
}

private struct FirstTimeArchiveCard: View {
  let entry: FirstTimeEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment = entry.attachments.first {
        FirstTimeRemoteImage(attachment: attachment)
          .frame(height: 190)
          .clipped()
      }

      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayDate.uppercased())
              .font(.system(size: 10, weight: .semibold))
              .tracking(0.8)
              .foregroundStyle(MTColor.warm)

            Text(entry.title)
              .font(MTTypography.titleSmall)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)
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
                FirstTimePill(label: name, systemImage: "archivebox")
              }
              ForEach(entry.tagNames, id: \.self) { name in
                FirstTimePill(label: name, systemImage: "number")
              }
            }
          }
        }

        if entry.attachments.count > 1 {
          Label("\(entry.attachments.count) photos", systemImage: "photo.on.rectangle.angled")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      .padding(MTSpacing.s4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}

private struct FirstTimeRemoteImage: View {
  let attachment: FirstTimeAttachment

  var body: some View {
    AsyncImage(url: attachment.signedURL) { phase in
      switch phase {
      case .success(let image):
        image
          .resizable()
          .scaledToFill()
      case .failure:
        placeholder(systemImage: "exclamationmark.triangle")
      case .empty:
        ZStack {
          MTColor.surfaceSubtle
          ProgressView()
        }
      @unknown default:
        placeholder(systemImage: "photo")
      }
    }
    .accessibilityLabel(attachment.originalFilename ?? "First Time photo")
  }

  private func placeholder(systemImage: String) -> some View {
    ZStack {
      MTColor.surfaceSubtle
      Image(systemName: systemImage)
        .font(.system(size: 24))
        .foregroundStyle(MTColor.inkFaint)
    }
  }
}

private struct FirstTimePill: View {
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

private struct FirstTimeEditorSelection: Identifiable {
  let id = UUID()
  let entry: FirstTimeEntry?
}

private struct FirstTimeEditorSheet: View {
  let controller: FirstTimesController
  let entry: FirstTimeEntry?
  let collectionOptions: [String]
  let tagOptions: [String]

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var title: String
  @State private var note: String
  @State private var occurrence: OccurrenceDraft
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var attachments: [FirstTimeAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isWorking = false
  @State private var progressMessage: String?
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: FirstTimeAttachment?

  init(
    controller: FirstTimesController,
    entry: FirstTimeEntry?,
    collectionOptions: [String],
    tagOptions: [String]
  ) {
    self.controller = controller
    self.entry = entry
    self.collectionOptions = collectionOptions
    self.tagOptions = tagOptions
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? "")
    _note = State(initialValue: entry?.body ?? "")
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil,
            timezone: TimeZone.current.identifier)))
    _collectionNames = State(initialValue: entry?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("What happened") {
          TextField("Title", text: $title, axis: .vertical)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("first-time-title")

          TextEditor(text: $note)
            .frame(minHeight: 150)
            .accessibilityLabel("Reflection")
            .accessibilityIdentifier("first-time-notes")
        }

        Section {
          OccurrenceEditor(value: $occurrence)
        } header: {
          Text("When it happened")
        }

        Section {
          MTOrganizationEditor(
            kind: .collection, names: $collectionNames,
            options: collectionOptions)
          MTOrganizationEditor(
            kind: .tag, names: $tagNames, options: tagOptions)
        }

        photosSection

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
              .accessibilityIdentifier("first-time-editor-error")
          }
        }

        if currentEntryID != nil {
          Section {
            Button("Move to Trash", role: .destructive) {
              isConfirmingTrash = true
            }
            .disabled(isWorking)
          } footer: {
            Text(
              "The First Time, photos, and edit history remain available for future restoration.")
          }
        }
      }
      .navigationTitle(entry == nil ? "New First Time" : "Edit First Time")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: title) {
        if title.count > FirstTimeEntryInput.titleLimit {
          title = String(title.prefix(FirstTimeEntryInput.titleLimit))
        }
      }
      .onChange(of: note) {
        if note.count > FirstTimeEntryInput.bodyLimit {
          note = String(note.prefix(FirstTimeEntryInput.bodyLimit))
        }
      }
      .onChange(of: pickerItems) { _, items in
        Task { await loadPhotos(from: items) }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isWorking)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(entry == nil ? "Add" : "Save") {
            Task { await save() }
          }
          .fontWeight(.semibold)
          .disabled(isWorking)
          .accessibilityIdentifier("save-first-time")
        }
      }
      .overlay {
        if isWorking {
          VStack(spacing: MTSpacing.s2) {
            ProgressView()
            if let progressMessage {
              Text(progressMessage)
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkMuted)
            }
          }
          .padding(MTSpacing.s4)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
      .confirmationDialog(
        "Move this First Time to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) {
          Task { await moveToTrash() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its photos and edit history will be preserved.")
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
          if let attachmentToRemove {
            Task { await removeAttachment(attachmentToRemove) }
          }
        }
        Button("Cancel", role: .cancel) {
          attachmentToRemove = nil
        }
      } message: {
        Text("The original file will be preserved for future restoration.")
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  private var remainingPhotoCount: Int {
    max(0, FirstTimePhotoDraft.maximumCount - attachments.count - photoDrafts.count)
  }

  private var photosSection: some View {
    Section {
      if attachments.isEmpty, photoDrafts.isEmpty {
        Text("No photos yet")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkFaint)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s3) {
            ForEach(attachments) { attachment in
              ZStack(alignment: .topTrailing) {
                FirstTimeRemoteImage(attachment: attachment)
                  .frame(width: 132, height: 112)
                  .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))

                Button {
                  attachmentToRemove = attachment
                } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Remove photo")
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

                Button {
                  photoDrafts.removeAll { $0.id == draft.id }
                } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Remove selected photo")
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
      .accessibilityIdentifier("add-first-time-photos")
    } header: {
      Text("Photos")
    } footer: {
      Text(
        "\(attachments.count + photoDrafts.count) of \(FirstTimePhotoDraft.maximumCount). Each photo can be up to 50 MB."
      )
    }
  }

  @MainActor
  private func loadPhotos(from items: [PhotosPickerItem]) async {
    errorMessage = nil

    for item in items.prefix(remainingPhotoCount) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          continue
        }
        guard
          let mimeType = FirstTimeImageType.detect(
            data: data,
            typeIdentifiers: item.supportedContentTypes.map(\.identifier)
          )
        else {
          throw FirstTimeEntryError.unsupportedPhotoType
        }

        let image = UIImage(data: data)
        let draft = try FirstTimePhotoDraft.validate(
          data: data,
          mimeType: mimeType,
          originalFilename: nil,
          pixelWidth: image.map { Int($0.size.width * $0.scale) },
          pixelHeight: image.map { Int($0.size.height * $0.scale) }
        )
        photoDrafts.append(draft)
      } catch {
        errorMessage = error.localizedDescription
      }
    }

    pickerItems = []
  }

  @MainActor
  private func save() async {
    isWorking = true
    errorMessage = nil
    progressMessage = "Saving First Time..."

    let resolved: EntryOccurrence
    do { resolved = try occurrence.resolve(original: entry?.occurrence) } catch {
      isWorking = false
      progressMessage = nil
      errorMessage = error.localizedDescription
      return
    }
    let result = await controller.save(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      title: title,
      body: note,
      occurredStart: resolved.start,
      datePrecision: FirstTimeDatePrecision(rawValue: resolved.precision.rawValue) ?? .unknown,
      occurredLabel: resolved.label ?? "",
      occurredTimezone: resolved.start == nil ? nil : resolved.timezone,
      collectionNames: collectionNames,
      tagNames: tagNames,
      occurredEnd: resolved.end,
      original: entry
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
      errorMessage = "Your First Time was saved. \(failedMessage)"
    } else {
      dismiss()
    }
  }

  @MainActor
  private func removeAttachment(_ attachment: FirstTimeAttachment) async {
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

    if result.status == .trashed {
      dismiss()
    } else {
      errorMessage = result.message
    }
  }
}
