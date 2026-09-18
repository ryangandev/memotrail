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
      Text("PERSONAL LANDMARKS IN YOUR STORY")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)
      Text("Places")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)
      Text("Save the personally meaningful places you want to remember.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text("\(controller.entries.count) \(controller.entries.count == 1 ? "place" : "places")")
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
        systemImage: "exclamationmark.triangle")
    } else if let focusedPlaceID {
      if let place = controller.entries.first(where: { $0.id == focusedPlaceID }) {
        placeSection(entries: [place])
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
          title: "Remember your first Place",
          message: "A Place is a small personal record, not a copy of an Entry or Home.",
          systemImage: "map")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Add your first Place")
    } else {
      placeSection(entries: controller.entries)
    }
  }

  private func placeSection(entries: [PlaceEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text("SAVED PLACES")
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
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(systemName: "map")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(MTColor.accent)
        .frame(width: 54, height: 54)
        .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(entry.name)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
        Label(entry.locationLabel, systemImage: "mappin.and.ellipse")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.accent)
        if let notes = entry.notes?.trimmed.nonEmpty {
          Text(notes)
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(3)
        }
      }
      Spacer(minLength: MTSpacing.s2)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
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
  @State private var notes: String
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
    _notes = State(initialValue: entry?.notes ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Place details") {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.words)
            .accessibilityIdentifier("place-name")
          TextField("Address or description (optional)", text: $address, axis: .vertical)
            .textInputAutocapitalization(.words)
          TextField("City (optional)", text: $city)
            .textInputAutocapitalization(.words)
          TextField("Region (optional)", text: $region)
            .textInputAutocapitalization(.words)
          TextField("Country (optional)", text: $country)
            .textInputAutocapitalization(.words)
        }
        Section("Memory") {
          TextEditor(text: $notes)
            .frame(minHeight: 120)
            .accessibilityLabel("Notes")
            .accessibilityIdentifier("place-notes")
        }
        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
          }
        }
        if currentPlaceID != nil {
          Section {
            Button("Move to Trash", role: .destructive) { isConfirmingTrash = true }
              .disabled(isWorking)
          } footer: {
            Text("The Place and edit history remain available for restoration.")
          }
        }
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

  @MainActor
  private func save() async {
    errorMessage = nil
    isWorking = true
    let result = await controller.save(
      placeID: currentPlaceID,
      expectedRevision: currentRevision,
      name: name,
      address: address,
      city: city,
      region: region,
      country: country,
      latitude: entry?.latitude,
      longitude: entry?.longitude,
      notes: notes
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
    guard let currentPlaceID, let currentRevision else { return }
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(
      placeID: currentPlaceID,
      expectedRevision: currentRevision
    )
    isWorking = false
    if result.status == .trashed { dismiss() } else { errorMessage = result.message }
  }

  private func trim(_ value: inout String, to limit: Int) {
    if value.count > limit { value = String(value.prefix(limit)) }
  }
}
