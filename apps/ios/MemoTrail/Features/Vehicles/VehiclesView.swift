import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

struct VehiclesView: View {
  @State private var controller: VehicleController
  @State private var editorSelection: VehicleEditorSelection?
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
    _controller = State(initialValue: VehicleController(client: client, ownerID: ownerID))
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
    .navigationTitle("Vehicles")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          editorSelection = VehicleEditorSelection(entry: nil)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add Vehicle")
        .accessibilityIdentifier("add-vehicle")
      }
    }
    .refreshable { await controller.load() }
    .sheet(item: $editorSelection) { selection in
      VehicleEditorSheet(controller: controller, entry: selection.entry)
    }
    .task { if !controller.hasLoaded { await controller.load() } }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("THE MACHINES THAT CARRIED YOUR STORY")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)
      Text("Vehicles").font(MTTypography.display).foregroundStyle(MTColor.ink)
      Text("Keep every car, bike, or other vehicle with its dates, notes, and photos.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text("\(controller.entries.count) \(controller.entries.count == 1 ? "vehicle" : "vehicles")")
      Text("·")
      Text("\(controller.currentEntries.count) current")
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
        Text("Loading your Vehicles...").foregroundStyle(MTColor.inkMuted)
      }
      .font(MTTypography.body)
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "Vehicles unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if let focusedEntryID {
      if let entry = controller.entries.first(where: { $0.id == focusedEntryID }) {
        vehicleSection(title: "VEHICLE", entries: [entry])
      } else {
        archiveMessage(
          title: "Vehicle unavailable",
          message: "This Vehicle is no longer available in the loaded workspace.",
          systemImage: "car"
        )
      }
    } else if controller.entries.isEmpty {
      archiveMessage(
        title: "Begin with a vehicle that carried you",
        message: "Add its name and best-known start date. Details can come later.",
        systemImage: "car"
      )
    } else {
      if !controller.currentEntries.isEmpty {
        vehicleSection(title: "CURRENT", entries: controller.currentEntries)
      }
      if !controller.earlierEntries.isEmpty {
        vehicleSection(title: "EARLIER", entries: controller.earlierEntries)
      }
    }
  }

  private func vehicleSection(title: String, entries: [VehicleEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)
      ForEach(entries) { entry in
        Button {
          editorSelection = VehicleEditorSelection(entry: entry)
        } label: {
          VehicleArchiveCard(entry: entry)
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

private struct VehicleArchiveCard: View {
  let entry: VehicleEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment = entry.attachments.first {
        VehicleRemoteImage(attachment: attachment).frame(height: 190).clipped()
      }
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MTSpacing.s2) {
              Text(entry.displayRange.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(MTColor.warm)
              if entry.isCurrent {
                Text("CURRENT")
                  .font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(MTColor.accent)
                  .padding(.horizontal, 6).padding(.vertical, 3)
                  .background(MTColor.accentSubtle, in: Capsule())
              }
            }
            Text(entry.title)
              .font(MTTypography.titleSmall)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)
            Label(entry.factsLabel, systemImage: "car")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkMuted)
          }
          Spacer(minLength: MTSpacing.s2)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }
        Text(entry.durationLabel()).font(MTTypography.caption).foregroundStyle(MTColor.inkFaint)
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
                VehiclePill(label: name, systemImage: "archivebox")
              }
              ForEach(entry.tagNames, id: \.self) { name in
                VehiclePill(label: name, systemImage: "number")
              }
            }
          }
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

private struct VehicleRemoteImage: View {
  let attachment: VehicleAttachment

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
    .accessibilityLabel(attachment.originalFilename ?? "Vehicle photo")
  }

  private func placeholder(systemImage: String) -> some View {
    ZStack {
      MTColor.surfaceSubtle
      Image(systemName: systemImage).font(.system(size: 24)).foregroundStyle(MTColor.inkFaint)
    }
  }
}

private struct VehiclePill: View {
  let label: String
  let systemImage: String

  var body: some View {
    Label(label, systemImage: systemImage)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, 9).padding(.vertical, 5)
      .background(MTColor.surfaceSubtle, in: Capsule())
  }
}

struct VehicleEditorSelection: Identifiable {
  let id = UUID()
  let entry: VehicleEntry?
}

struct VehicleEditorSheet: View {
  let controller: VehicleController
  let entry: VehicleEntry?
  let sourceCapture: CaptureExtractionSource?
  let onSaved: (@MainActor () async -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var title: String
  @State private var note: String
  @State private var occurrence: OccurrenceDraft
  @State private var make: String
  @State private var model: String
  @State private var modelYear: String
  @State private var color: String
  @State private var collectionNames: [String]
  @State private var collectionInput = ""
  @State private var tagNames: [String]
  @State private var tagInput = ""
  @State private var attachments: [VehicleAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isWorking = false
  @State private var progressMessage: String?
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: VehicleAttachment?

  init(
    controller: VehicleController,
    entry: VehicleEntry?,
    sourceCapture: CaptureExtractionSource? = nil,
    onSaved: (@MainActor () async -> Void)? = nil
  ) {
    self.controller = controller
    self.entry = entry
    self.sourceCapture = sourceCapture
    self.onSaved = onSaved
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _title = State(initialValue: entry?.title ?? sourceCapture?.title ?? "")
    _note = State(initialValue: entry?.body ?? sourceCapture?.body ?? "")
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence ?? sourceCapture?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil,
            timezone: TimeZone.current.identifier)))
    _make = State(initialValue: entry?.make ?? "")
    _model = State(initialValue: entry?.model ?? "")
    _modelYear = State(initialValue: entry?.modelYear.map(String.init) ?? "")
    _color = State(initialValue: entry?.color ?? "")
    _collectionNames = State(
      initialValue: entry?.collectionNames ?? sourceCapture?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? sourceCapture?.tagNames ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        if sourceCapture != nil {
          Section {
            Label("Creating a Vehicle from this Capture", systemImage: "arrow.triangle.branch")
          } footer: {
            Text("The original Capture stays linked as provenance after this Vehicle is created.")
          }
        }
        identitySection
        datesSection
        factsSection
        organizationSections
        photosSection
        statusSections
      }
      .navigationTitle(
        sourceCapture == nil ? (entry == nil ? "New Vehicle" : "Edit Vehicle") : "Create Vehicle"
      )
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: title) { trim(&title, to: VehicleEntryInput.titleLimit) }
      .onChange(of: note) { trim(&note, to: VehicleEntryInput.bodyLimit) }
      .onChange(of: make) { trim(&make, to: VehicleEntryInput.makeLimit) }
      .onChange(of: model) { trim(&model, to: VehicleEntryInput.modelLimit) }
      .onChange(of: color) { trim(&color, to: VehicleEntryInput.colorLimit) }
      .onChange(of: pickerItems) { _, items in Task { await loadPhotos(from: items) } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(currentEntryID == nil ? "Add" : "Save") { Task { await save() } }
            .fontWeight(.semibold)
            .disabled(isWorking)
            .accessibilityIdentifier("save-vehicle")
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
        "Move this Vehicle to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
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

  private var identitySection: some View {
    Section("Vehicle details") {
      TextField("Name or nickname", text: $title, axis: .vertical)
        .textInputAutocapitalization(.words)
        .accessibilityIdentifier("vehicle-title")
      TextEditor(text: $note)
        .frame(minHeight: 130)
        .accessibilityLabel("Notes")
        .accessibilityIdentifier("vehicle-memories")
    }
  }

  private var datesSection: some View {
    OccurrenceEditor(
      value: $occurrence, span: true,
      chapterGuidance: "Leave the end date empty while this Vehicle is still in your life.")
  }

  private var factsSection: some View {
    Section("Vehicle facts") {
      TextField("Make (optional)", text: $make).textInputAutocapitalization(.words)
      TextField("Model (optional)", text: $model).textInputAutocapitalization(.words)
      TextField("Model year (optional)", text: $modelYear)
        .keyboardType(.numberPad)
      TextField("Color (optional)", text: $color).textInputAutocapitalization(.words)
    }
  }

  @ViewBuilder
  private var organizationSections: some View {
    Section("Collections") {
      VehicleNameEditor(
        names: $collectionNames,
        input: $collectionInput,
        options: controller.collectionOptions,
        placeholder: "Add a Collection",
        maximumCount: VehicleEntryInput.collectionLimit,
        maximumNameLength: VehicleEntryInput.collectionNameLimit
      )
    }
    Section("Tags") {
      VehicleNameEditor(
        names: $tagNames,
        input: $tagInput,
        options: controller.tagOptions,
        placeholder: "Add a tag",
        maximumCount: VehicleEntryInput.tagLimit,
        maximumNameLength: VehicleEntryInput.tagNameLimit
      )
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
                VehicleRemoteImage(attachment: attachment)
                  .frame(width: 132, height: 112)
                  .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                removeButton(label: "Remove photo") { attachmentToRemove = attachment }
              }
            }
            ForEach(photoDrafts) { draft in
              ZStack(alignment: .topTrailing) {
                if let image = UIImage(data: draft.data) {
                  Image(uiImage: image)
                    .resizable().scaledToFill()
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
      .accessibilityIdentifier("add-vehicle-photos")
    } header: {
      Text("Photos")
    } footer: {
      Text(
        "\(attachments.count + photoDrafts.count) of \(FirstTimePhotoDraft.maximumCount). Each photo can be up to 50 MB."
      )
    }
  }

  @ViewBuilder
  private var statusSections: some View {
    if let errorMessage {
      Section {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
          .accessibilityIdentifier("vehicle-editor-error")
      }
    }
    if currentEntryID != nil {
      Section {
        Button("Move to Trash", role: .destructive) { isConfirmingTrash = true }
      } footer: {
        Text("The Vehicle, photos, and edit history remain available for restoration.")
      }
    }
  }

  private var remainingPhotoCount: Int {
    max(0, FirstTimePhotoDraft.maximumCount - attachments.count - photoDrafts.count)
  }

  private func removeButton(label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: 26, height: 26)
        .background(Color.black.opacity(0.65), in: Circle())
    }
    .buttonStyle(.plain).padding(6).accessibilityLabel(label)
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
      } catch { errorMessage = error.localizedDescription }
    }
    pickerItems = []
  }

  @MainActor
  private func save() async {
    errorMessage = nil
    let parsedModelYear: Int?
    if modelYear.trimmed.isEmpty {
      parsedModelYear = nil
    } else if let value = Int(modelYear.trimmed) {
      parsedModelYear = value
    } else {
      errorMessage = "Model year must be a whole number."
      return
    }

    isWorking = true
    progressMessage = "Saving Vehicle..."
    let resolved: EntryOccurrence
    do { resolved = try occurrence.resolve(original: entry?.occurrence, span: true) } catch {
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
      occurredEnd: resolved.end,
      datePrecision: resolved.precision,
      occurredLabel: resolved.label ?? "",
      occurredTimezone: resolved.timezone,
      make: make,
      model: model,
      modelYear: parsedModelYear,
      color: color,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      tagNames: namesIncludingDraft(tagNames, tagInput),
      originalEntry: entry,
      sourceCapture: currentEntryID == nil ? sourceCapture : nil
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
      errorMessage = "Your Vehicle was saved. \(failedMessage)"
    } else if let onSaved {
      await onSaved()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func removeAttachment(_ attachment: VehicleAttachment) async {
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

private struct VehicleNameEditor: View {
  @Binding var names: [String]
  @Binding var input: String
  let options: [String]
  let placeholder: String
  let maximumCount: Int
  let maximumNameLength: Int

  private var selectedNames: Set<String> { Set(names.map { $0.lowercased() }) }
  private var suggestions: [String] { options.filter { !selectedNames.contains($0.lowercased()) } }

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
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
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
