@preconcurrency import Supabase
import SwiftUI

struct PlacesView: View {
  @State private var controller: PlaceController
  @State private var editorSelection: PlaceEditorSelection?
  private let embedded: Bool
  private let focusedPlaceID: UUID?

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false, focusedPlaceID: UUID? = nil) {
    self.embedded = embedded
    self.focusedPlaceID = focusedPlaceID
    _controller = State(initialValue: PlaceController(client: client, ownerID: ownerID))
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
    .navigationTitle("Places")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          editorSelection = PlaceEditorSelection(entry: nil)
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add Place")
        .accessibilityIdentifier("add-place")
      }
    }
    .refreshable { await controller.load() }
    .sheet(item: $editorSelection) { selection in
      PlaceEditorSheet(controller: controller, entry: selection.entry)
    }
    .task { if !controller.hasLoaded { await controller.load() } }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("A GEOGRAPHY OF YOUR ARCHIVE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)
      Text("Places")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)
      Text(
        "Keep reusable locations once, then connect them to the memories that give them meaning."
      )
      .font(MTTypography.body)
      .foregroundStyle(MTColor.inkMuted)
      .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text("\(controller.entries.count) \(controller.entries.count == 1 ? "place" : "places")")
      Text("·")
      Text("\(controller.linkedEntries.count) with memories")
      Text("·")
      Label("\(controller.mappedCount)", systemImage: "map")
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
        Text("Loading your Places...").foregroundStyle(MTColor.inkMuted)
      }
      .font(MTTypography.body)
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "Places unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if let focusedPlaceID {
      if let place = controller.entries.first(where: { $0.id == focusedPlaceID }) {
        placeSection(title: "SOURCE PLACE", entries: [place])
      } else {
        archiveMessage(
          title: "Place unavailable",
          message: "This Place is no longer available in the loaded workspace.",
          systemImage: "archivebox")
      }
    } else if controller.entries.isEmpty {
      Button {
        editorSelection = PlaceEditorSelection(entry: nil)
      } label: {
        archiveMessage(
          title: "Pin the first place in your story",
          message:
            "Start with a name. Address, coordinates, notes, and connected memories can come later.",
          systemImage: "map"
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Add your first Place")
    } else {
      if !controller.linkedEntries.isEmpty {
        placeSection(title: "IN YOUR STORY", entries: controller.linkedEntries)
      }
      if !controller.unlinkedEntries.isEmpty {
        placeSection(title: "UNLINKED PLACES", entries: controller.unlinkedEntries)
      }
    }
  }

  private func placeSection(title: String, entries: [PlaceEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)
      ForEach(entries) { entry in
        Button {
          editorSelection = PlaceEditorSelection(entry: entry)
        } label: {
          PlaceArchiveCard(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(entry.name)")
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
        Text(message)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
          .multilineTextAlignment(.leading)
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

private struct PlaceArchiveCard: View {
  let entry: PlaceEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      placeVisual
        .frame(height: 154)
        .clipped()

      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        Label(entry.locationLabel, systemImage: "mappin.and.ellipse")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.accent)
          .lineLimit(2)

        HStack(alignment: .firstTextBaseline) {
          Text(entry.name)
            .font(MTTypography.titleSmall)
            .foregroundStyle(MTColor.ink)
            .multilineTextAlignment(.leading)
          Spacer(minLength: MTSpacing.s2)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }

        if let notes = entry.notes?.trimmed.nonEmpty {
          Text(notes)
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
        }

        if !entry.linkedEntries.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.linkedEntries.prefix(2)) { linked in
              Text(
                "\(linked.relationship == "home" ? "Home" : linked.itemKind.displayName(subtype: linked.itemSubtype)): \(linked.displayTitle)"
              )
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkMuted)
              .lineLimit(1)
            }
            if entry.linkedEntries.count > 2 {
              Text("+\(entry.linkedEntries.count - 2) more")
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkFaint)
            }
          }
        }

        HStack(spacing: MTSpacing.s3) {
          Label(
            "\(entry.linkedEntryCount) linked \(entry.linkedEntryCount == 1 ? "Entry" : "Entries")",
            systemImage: "link"
          )
          if entry.homeCount > 0 { Label("Home", systemImage: "house.fill") }
        }
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkFaint)
      }
      .padding(MTSpacing.s4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
  }

  @ViewBuilder
  private var placeVisual: some View {
    if let attachment = entry.coverAttachment {
      PlaceRemoteImage(attachment: attachment)
    } else {
      ZStack {
        MTColor.surfaceSubtle
        Canvas { context, size in
          var path = Path()
          let interval: CGFloat = 34
          for x in stride(from: 0, through: size.width, by: interval) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
          }
          for y in stride(from: 0, through: size.height, by: interval) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
          }
          context.stroke(path, with: .color(MTColor.border), lineWidth: 0.7)
        }
        VStack(spacing: MTSpacing.s2) {
          Image(systemName: "map")
            .font(.system(size: 27, weight: .medium))
            .foregroundStyle(MTColor.accent)
          Text(entry.coordinateLabel ?? "Coordinates not added")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkMuted)
        }
        .padding(MTSpacing.s3)
        .background(MTColor.surface.opacity(0.86), in: Capsule())
      }
    }
  }
}

private struct PlaceRemoteImage: View {
  let attachment: PlaceAttachment

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
    .accessibilityLabel(attachment.originalFilename ?? "Place memory photo")
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

struct PlaceEditorSelection: Identifiable {
  let id = UUID()
  let entry: PlaceEntry?
}

struct PlaceEditorSheet: View {
  let controller: PlaceController
  let entry: PlaceEntry?

  @Environment(\.dismiss) private var dismiss
  @State private var currentPlaceID: UUID?
  @State private var currentRevision: Int?
  @State private var name: String
  @State private var address: String
  @State private var city: String
  @State private var region: String
  @State private var country: String
  @State private var latitude: String
  @State private var longitude: String
  @State private var notes: String
  @State private var relatedEntryIDs: [UUID]
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false

  init(controller: PlaceController, entry: PlaceEntry?) {
    self.controller = controller
    self.entry = entry
    _currentPlaceID = State(initialValue: entry?.id)
    _currentRevision = State(initialValue: entry?.revision)
    _name = State(initialValue: entry?.name ?? "")
    _address = State(initialValue: entry?.address ?? "")
    _city = State(initialValue: entry?.city ?? "")
    _region = State(initialValue: entry?.region ?? "")
    _country = State(initialValue: entry?.country ?? "")
    _latitude = State(initialValue: entry?.latitude.map { String($0) } ?? "")
    _longitude = State(initialValue: entry?.longitude.map { String($0) } ?? "")
    _notes = State(initialValue: entry?.notes ?? "")
    _relatedEntryIDs = State(initialValue: entry?.relatedEntries.map(\.id) ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        detailsSection
        coordinatesSection
        notesSection
        relationshipsSection
        linkedPhotosSection
        statusSections
      }
      .navigationTitle(entry == nil ? "New Place" : "Edit Place")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: name) { trim(&name, to: PlaceInput.nameLimit) }
      .onChange(of: address) { trim(&address, to: PlaceInput.addressLimit) }
      .onChange(of: city) { trim(&city, to: PlaceInput.locationPartLimit) }
      .onChange(of: region) { trim(&region, to: PlaceInput.locationPartLimit) }
      .onChange(of: country) { trim(&country, to: PlaceInput.locationPartLimit) }
      .onChange(of: notes) { trim(&notes, to: PlaceInput.notesLimit) }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(entry == nil ? "Add" : "Save") { Task { await save() } }
            .fontWeight(.semibold)
            .disabled(isWorking)
            .accessibilityIdentifier("save-place")
        }
      }
      .overlay {
        if isWorking {
          VStack(spacing: MTSpacing.s2) {
            ProgressView()
            Text("Saving Place...")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkMuted)
          }
          .padding(MTSpacing.s4)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
      .confirmationDialog(
        "Move this Place to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its details and edit history will remain available for restoration.")
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  private var detailsSection: some View {
    Section("Place details") {
      TextField("Name", text: $name)
        .textInputAutocapitalization(.words)
        .accessibilityIdentifier("place-name")
      TextField("Address (optional)", text: $address, axis: .vertical)
        .textInputAutocapitalization(.words)
        .textContentType(.fullStreetAddress)
      TextField("City (optional)", text: $city)
        .textInputAutocapitalization(.words)
        .textContentType(.addressCity)
      TextField("Region (optional)", text: $region)
        .textInputAutocapitalization(.words)
        .textContentType(.addressState)
      TextField("Country (optional)", text: $country)
        .textInputAutocapitalization(.words)
        .textContentType(.countryName)
    }
  }

  private var coordinatesSection: some View {
    Section {
      TextField("Latitude", text: $latitude)
        .keyboardType(.numbersAndPunctuation)
        .accessibilityIdentifier("place-latitude")
      TextField("Longitude", text: $longitude)
        .keyboardType(.numbersAndPunctuation)
        .accessibilityIdentifier("place-longitude")
    } header: {
      Text("Map coordinates")
    } footer: {
      Text(
        "Add both values or leave both empty. Coordinates prepare this archive for a future map view."
      )
    }
  }

  private var notesSection: some View {
    Section("Notes") {
      TextEditor(text: $notes)
        .frame(minHeight: 120)
        .accessibilityLabel("Notes")
        .accessibilityIdentifier("place-notes")
    }
  }

  private var relationshipsSection: some View {
    Section {
      if let entry, !entry.protectedEntries.isEmpty {
        ForEach(entry.protectedEntries) { linked in
          Label {
            VStack(alignment: .leading, spacing: 3) {
              Text(linked.displayTitle).foregroundStyle(MTColor.ink)
              Text("Home record · managed from Homes")
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkFaint)
            }
          } icon: {
            Image(systemName: "house.fill").foregroundStyle(MTColor.accent)
          }
        }
      }

      if relatedEntryIDs.isEmpty {
        Text("No related Entries yet")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkFaint)
      } else {
        ForEach(relatedEntryIDs, id: \.self) { id in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(relatedTitle(id)).foregroundStyle(MTColor.ink).lineLimit(2)
              if let type = relatedType(id) {
                Text(type.displayName)
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
            .accessibilityLabel("Unlink \(relatedTitle(id))")
          }
        }
      }

      if !availableLinkOptions.isEmpty, relatedEntryIDs.count < PlaceInput.relatedEntryLimit {
        Menu("Link an Entry", systemImage: "link.badge.plus") {
          ForEach(availableLinkOptions) { option in
            Button {
              relatedEntryIDs.append(option.id)
            } label: {
              Text("\(option.displayTitle) · \(option.displayType)")
            }
          }
        }
      }
    } header: {
      Text("Connected Entries")
    } footer: {
      Text("Related links are editable here. Home links stay protected and are managed from Homes.")
    }
  }

  @ViewBuilder
  private var linkedPhotosSection: some View {
    if !linkedAttachments.isEmpty {
      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s3) {
            ForEach(linkedAttachments) { attachment in
              PlaceRemoteImage(attachment: attachment)
                .frame(width: 132, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
            }
          }
        }
      } header: {
        Text("Memory photos")
      } footer: {
        Text("These originals belong to connected Entries and remain managed from those records.")
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
          .accessibilityIdentifier("place-editor-error")
      }
    }

    if currentPlaceID != nil {
      Section {
        Button("Move to Trash", role: .destructive) { isConfirmingTrash = true }
          .disabled(!(entry?.canMoveToTrash ?? false))
      } footer: {
        if let entry, !entry.canMoveToTrash {
          Text(trashProtectionMessage(entry))
        } else {
          Text("The Place and edit history remain available for restoration.")
        }
      }
    }
  }

  private var availableLinkOptions: [PlaceLinkOption] {
    let protectedIDs = Set(entry?.protectedEntries.map(\.id) ?? [])
    return controller.linkOptions.filter {
      !relatedEntryIDs.contains($0.id) && !protectedIDs.contains($0.id)
    }
  }

  private var linkedAttachments: [PlaceAttachment] {
    entry?.linkedEntries.flatMap(\.attachments) ?? []
  }

  private func relatedTitle(_ id: UUID) -> String {
    controller.linkOptions.first { $0.id == id }?.displayTitle
      ?? entry?.relatedEntries.first { $0.id == id }?.displayTitle
      ?? "Related Entry"
  }

  private func relatedType(_ id: UUID) -> String? {
    controller.linkOptions.first { $0.id == id }.map {
      $0.itemKind.displayName(subtype: $0.itemSubtype)
    }
      ?? entry?.relatedEntries.first { $0.id == id }.map {
        $0.itemKind.displayName(subtype: $0.itemSubtype)
      }
  }

  private func trashProtectionMessage(_ entry: PlaceEntry) -> String {
    if !entry.protectedEntries.isEmpty { return "Remove its Home link before trashing this Place." }
    if relatedEntryIDs.isEmpty { return "Save the unlinked Place before moving it to Trash." }
    return "Unlink every Entry before moving this Place to Trash."
  }

  @MainActor
  private func save() async {
    errorMessage = nil
    let parsedLatitude = coordinate(latitude)
    let parsedLongitude = coordinate(longitude)
    guard parsedLatitude.isValid, parsedLongitude.isValid else {
      errorMessage = PlaceEntryError.invalidCoordinates.localizedDescription
      return
    }

    isWorking = true
    let result = await controller.save(
      placeID: currentPlaceID,
      expectedRevision: currentRevision,
      name: name,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: parsedLatitude.value,
      longitude: parsedLongitude.value,
      notes: notes,
      relatedEntryIDs: relatedEntryIDs
    )
    guard result.status == .saved, let identity = result.identity else {
      isWorking = false
      errorMessage = result.message
      return
    }
    currentPlaceID = identity.id
    currentRevision = identity.revision
    await controller.reloadAfterMutation()
    isWorking = false
    dismiss()
  }

  @MainActor
  private func moveToTrash() async {
    guard let currentPlaceID, let currentRevision, entry?.canMoveToTrash == true else { return }
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(
      placeID: currentPlaceID,
      expectedRevision: currentRevision
    )
    isWorking = false
    if result.status == .trashed { dismiss() } else { errorMessage = result.message }
  }

  private func coordinate(_ value: String) -> (isValid: Bool, value: Double?) {
    let value = value.trimmed
    guard !value.isEmpty else { return (true, nil) }
    guard let number = Double(value), number.isFinite else { return (false, nil) }
    return (true, number)
  }

  private func trim(_ value: inout String, to limit: Int) {
    if value.count > limit { value = String(value.prefix(limit)) }
  }
}
