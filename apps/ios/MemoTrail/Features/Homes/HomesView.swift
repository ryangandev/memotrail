import PhotosUI
import Supabase
import SwiftUI
import UIKit

struct HomesView: View {
  @State private var controller: ResidenceController
  @State private var editorSelection: ResidenceEditorSelection?

  private let embedded: Bool

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false) {
    self.embedded = embedded
    _controller = State(initialValue: ResidenceController(client: client, ownerID: ownerID))
  }

  @ViewBuilder
  var body: some View {
    if embedded {
      archiveView
    } else {
      NavigationStack { archiveView }
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
    .navigationTitle("Homes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          editorSelection = ResidenceEditorSelection(entry: nil)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add Home")
        .accessibilityIdentifier("add-home")
      }
    }
    .refreshable { await controller.load() }
    .sheet(item: $editorSelection) { selection in
      ResidenceEditorSheet(controller: controller, entry: selection.entry)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("THE PLACES THAT HELD YOUR LIFE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)

      Text("Homes")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Keep each residence as a chapter with its Place, dates, memories, and photos.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text(homeCountLabel)
      Text("·")
      Text("\(controller.currentEntries.count) current")
      Text("·")
      Label("\(controller.photoCount)", systemImage: "photo")

      Spacer()

      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small)
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
        Text("Loading your Homes...")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "Homes unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.entries.isEmpty {
      archiveMessage(
        title: "Start with one address",
        message: "Add the place you live now. Earlier homes and details can come later.",
        systemImage: "house"
      )
    } else {
      if !controller.currentEntries.isEmpty {
        residenceSection(title: "CURRENT", entries: controller.currentEntries)
      }
      if !controller.earlierEntries.isEmpty {
        residenceSection(title: "EARLIER", entries: controller.earlierEntries)
      }
    }
  }

  private func residenceSection(title: String, entries: [ResidenceEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)

      ForEach(entries) { entry in
        Button {
          editorSelection = ResidenceEditorSelection(entry: entry)
        } label: {
          ResidenceArchiveCard(entry: entry)
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
      RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var homeCountLabel: String {
    "\(controller.entries.count) \(controller.entries.count == 1 ? "home" : "homes")"
  }
}

private struct ResidenceArchiveCard: View {
  let entry: ResidenceEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment = entry.attachments.first {
        ResidenceRemoteImage(attachment: attachment)
          .frame(height: 190)
          .clipped()
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
                  .padding(.horizontal, 6)
                  .padding(.vertical, 3)
                  .background(MTColor.accentSubtle, in: Capsule())
              }
            }

            Text(entry.title)
              .font(MTTypography.titleSmall)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)

            Label(entry.displayLocation, systemImage: "mappin.and.ellipse")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkMuted)
          }

          Spacer(minLength: MTSpacing.s2)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }

        Text(entry.durationLabel())
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

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
                ResidencePill(label: name, systemImage: "archivebox")
              }
              ForEach(entry.tagNames, id: \.self) { name in
                ResidencePill(label: name, systemImage: "number")
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
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border, lineWidth: 1)
    }
  }
}

private struct ResidenceRemoteImage: View {
  let attachment: ResidenceAttachment

  var body: some View {
    AsyncImage(url: attachment.signedURL) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
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
    .accessibilityLabel(attachment.originalFilename ?? "Home photo")
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

private struct ResidencePill: View {
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

struct ResidenceEditorSelection: Identifiable {
  let id = UUID()
  let entry: ResidenceEntry?
}

struct ResidenceEditorSheet: View {
  let controller: ResidenceController
  let entry: ResidenceEntry?

  @Environment(\.dismiss) private var dismiss
  @State private var currentEntryID: UUID?
  @State private var currentRevision: Int?
  @State private var currentPlaceID: UUID?
  @State private var title: String
  @State private var note: String
  @State private var occurredStart: Date
  @State private var occurredEnd: Date
  @State private var isCurrent: Bool
  @State private var datePrecision: ResidenceDatePrecision
  @State private var occurredLabel: String
  @State private var occurredTimezone: String
  @State private var selectedSavedPlaceID: UUID?
  @State private var placeName: String
  @State private var address: String
  @State private var city: String
  @State private var region: String
  @State private var country: String
  @State private var latitude: String
  @State private var longitude: String
  @State private var placeNotes: String
  @State private var moveInReason: String
  @State private var moveOutReason: String
  @State private var collectionNames: [String]
  @State private var collectionInput = ""
  @State private var tagNames: [String]
  @State private var tagInput = ""
  @State private var attachments: [ResidenceAttachment]
  @State private var photoDrafts: [FirstTimePhotoDraft] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isWorking = false
  @State private var progressMessage: String?
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false
  @State private var attachmentToRemove: ResidenceAttachment?

  init(controller: ResidenceController, entry: ResidenceEntry?) {
    self.controller = controller
    self.entry = entry
    _currentEntryID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _currentPlaceID = State(initialValue: entry?.placeID)
    _title = State(initialValue: entry?.title ?? "")
    _note = State(initialValue: entry?.body ?? "")
    _occurredStart = State(initialValue: entry?.occurredStart ?? Date())
    _occurredEnd = State(initialValue: entry?.occurredEnd ?? Date())
    _isCurrent = State(initialValue: entry?.occurredEnd == nil)
    _datePrecision = State(initialValue: entry?.datePrecision ?? .range)
    _occurredLabel = State(initialValue: entry?.occurredLabel ?? "")
    _occurredTimezone = State(
      initialValue: entry?.occurredTimezone ?? TimeZone.current.identifier
    )
    _selectedSavedPlaceID = State(initialValue: entry?.placeID)
    _placeName = State(initialValue: entry?.placeName ?? "")
    _address = State(initialValue: entry?.address ?? "")
    _city = State(initialValue: entry?.city ?? "")
    _region = State(initialValue: entry?.region ?? "")
    _country = State(initialValue: entry?.country ?? "")
    _latitude = State(initialValue: entry?.latitude.map { String($0) } ?? "")
    _longitude = State(initialValue: entry?.longitude.map { String($0) } ?? "")
    _placeNotes = State(initialValue: entry?.placeNotes ?? "")
    _moveInReason = State(initialValue: entry?.moveInReason ?? "")
    _moveOutReason = State(initialValue: entry?.moveOutReason ?? "")
    _collectionNames = State(initialValue: entry?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? [])
    _attachments = State(initialValue: entry?.attachments ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        chapterSection
        datesSection
        placeSection
        organizationSections
        photosSection
        statusSections
      }
      .navigationTitle(entry == nil ? "New Home" : "Edit Home")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: title) { trim(&title, to: ResidenceEntryInput.titleLimit) }
      .onChange(of: note) { trim(&note, to: ResidenceEntryInput.bodyLimit) }
      .onChange(of: occurredLabel) { trim(&occurredLabel, to: ResidenceEntryInput.labelLimit) }
      .onChange(of: selectedSavedPlaceID) { _, placeID in
        guard let placeID, let place = controller.placeOptions.first(where: { $0.id == placeID })
        else {
          if placeID == nil { currentPlaceID = nil }
          return
        }
        apply(place)
      }
      .onChange(of: occurredStart) { occurredTimezone = TimeZone.current.identifier }
      .onChange(of: pickerItems) { _, items in Task { await loadPhotos(from: items) } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(entry == nil ? "Add" : "Save") { Task { await save() } }
            .fontWeight(.semibold)
            .disabled(isWorking)
            .accessibilityIdentifier("save-home")
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
        "Move this Home to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its Place, photos, and edit history will be preserved.")
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

  private var chapterSection: some View {
    Section("Home chapter") {
      TextField("Home name", text: $title, axis: .vertical)
        .textInputAutocapitalization(.words)
        .accessibilityIdentifier("home-title")
      TextEditor(text: $note)
        .frame(minHeight: 130)
        .accessibilityLabel("Memories")
        .accessibilityIdentifier("home-memories")
    }
  }

  private var datesSection: some View {
    Section {
      DatePicker("Move-in", selection: $occurredStart, displayedComponents: .date)
      Toggle("Current residence", isOn: $isCurrent)
      if !isCurrent {
        DatePicker("Move-out", selection: $occurredEnd, displayedComponents: .date)
      }
      Picker("Date precision", selection: $datePrecision) {
        ForEach(ResidenceDatePrecision.allCases, id: \.self) { precision in
          Text(precision.displayName).tag(precision)
        }
      }
      TextField("Human date label (optional)", text: $occurredLabel)
        .textInputAutocapitalization(.sentences)
      TextField("Why you moved in (optional)", text: $moveInReason, axis: .vertical)
      if !isCurrent {
        TextField("Why you moved out (optional)", text: $moveOutReason, axis: .vertical)
      }
    } header: {
      Text("When")
    } footer: {
      Text("Use the best-known dates. A label such as “Ages 12 to 25” can preserve context.")
    }
  }

  private var placeSection: some View {
    Section {
      if !controller.placeOptions.isEmpty {
        Picker("Saved Place", selection: $selectedSavedPlaceID) {
          Text("Create a new Place").tag(nil as UUID?)
          ForEach(controller.placeOptions) { place in
            Text(place.name).tag(place.id as UUID?)
          }
        }
      }
      TextField("Place name", text: $placeName)
        .textInputAutocapitalization(.words)
      TextField("Exact address", text: $address, axis: .vertical)
        .textContentType(.fullStreetAddress)
      TextField("City", text: $city)
        .textInputAutocapitalization(.words)
      TextField("State or region", text: $region)
        .textInputAutocapitalization(.words)
      TextField("Country", text: $country)
        .textInputAutocapitalization(.words)
      TextField("Latitude (optional)", text: $latitude)
        .keyboardType(.numbersAndPunctuation)
      TextField("Longitude (optional)", text: $longitude)
        .keyboardType(.numbersAndPunctuation)
      TextField("Place notes (optional)", text: $placeNotes, axis: .vertical)
    } header: {
      Text("Place")
    } footer: {
      Text("Exact addresses stay private and remain searchable only inside your account.")
    }
  }

  @ViewBuilder
  private var organizationSections: some View {
    Section {
      ResidenceNameEditor(
        names: $collectionNames,
        input: $collectionInput,
        options: controller.collectionOptions,
        placeholder: "Add a Collection",
        maximumCount: ResidenceEntryInput.collectionLimit,
        maximumNameLength: ResidenceEntryInput.collectionNameLimit
      )
    } header: {
      Text("Collections")
    }

    Section {
      ResidenceNameEditor(
        names: $tagNames,
        input: $tagInput,
        options: controller.tagOptions,
        placeholder: "Add a tag",
        maximumCount: ResidenceEntryInput.tagLimit,
        maximumNameLength: ResidenceEntryInput.tagNameLimit
      )
    } header: {
      Text("Tags")
    }
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
                ResidenceRemoteImage(attachment: attachment)
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
      .accessibilityIdentifier("add-home-photos")
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
          .accessibilityIdentifier("home-editor-error")
      }
    }

    if currentEntryID != nil {
      Section {
        Button("Move to Trash", role: .destructive) { isConfirmingTrash = true }
          .disabled(isWorking)
      } footer: {
        Text("The Home, Place, photos, and edit history remain available for restoration.")
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
    .buttonStyle(.plain)
    .padding(6)
    .accessibilityLabel(label)
  }

  private func apply(_ place: ResidencePlace) {
    currentPlaceID = place.id
    placeName = place.name
    address = place.address ?? ""
    city = place.city ?? ""
    region = place.region ?? ""
    country = place.country ?? ""
    latitude = place.latitude.map { String($0) } ?? ""
    longitude = place.longitude.map { String($0) } ?? ""
    placeNotes = place.notes ?? ""
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
        else {
          throw FirstTimeEntryError.unsupportedPhotoType
        }

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
    guard let parsedLatitude = parseCoordinate(latitude),
      let parsedLongitude = parseCoordinate(longitude)
    else {
      errorMessage = "Coordinates must be valid numbers."
      return
    }

    isWorking = true
    progressMessage = "Saving Home..."
    let result = await controller.save(
      entryID: currentEntryID,
      expectedRevision: currentRevision,
      title: title,
      body: note,
      occurredStart: occurredStart,
      occurredEnd: isCurrent ? nil : occurredEnd,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone,
      placeID: currentPlaceID,
      placeName: placeName,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: parsedLatitude,
      longitude: parsedLongitude,
      placeNotes: placeNotes,
      moveInReason: moveInReason,
      moveOutReason: isCurrent ? "" : moveOutReason,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      tagNames: namesIncludingDraft(tagNames, tagInput)
    )

    guard result.status == .saved, let identity = result.identity else {
      isWorking = false
      progressMessage = nil
      errorMessage = result.message
      return
    }

    currentEntryID = identity.id
    currentRevision = identity.revision
    currentPlaceID = identity.placeID
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
      errorMessage = "Your Home was saved. \(failedMessage)"
    } else {
      dismiss()
    }
  }

  private func parseCoordinate(_ value: String) -> Double?? {
    let value = value.trimmed
    if value.isEmpty { return .some(nil) }
    guard let number = Double(value), number.isFinite else { return nil }
    return .some(number)
  }

  @MainActor
  private func removeAttachment(_ attachment: ResidenceAttachment) async {
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

  private func namesIncludingDraft(_ names: [String], _ draft: String) -> [String] {
    let name = draft.trimmed
    return name.isEmpty ? names : names + [name]
  }
}

private struct ResidenceNameEditor: View {
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
          if input.count > maximumNameLength {
            input = String(input.prefix(maximumNameLength))
          }
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
