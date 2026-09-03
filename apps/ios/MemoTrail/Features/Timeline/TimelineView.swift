import Supabase
import SwiftUI

struct TimelineView: View {
  @State private var controller: TimelineController
  @State private var residenceController: ResidenceController
  @State private var vehicleController: VehicleController
  @State private var editorSelection: TimelineEditorSelection?
  @State private var residenceEditorSelection: ResidenceEditorSelection?
  @State private var vehicleEditorSelection: VehicleEditorSelection?
  @State private var residenceErrorMessage: String?
  @State private var vehicleErrorMessage: String?

  init(client: SupabaseClient, ownerID: UUID) {
    _controller = State(
      initialValue: TimelineController(client: client, ownerID: ownerID)
    )
    _residenceController = State(
      initialValue: ResidenceController(client: client, ownerID: ownerID)
    )
    _vehicleController = State(
      initialValue: VehicleController(client: client, ownerID: ownerID)
    )
  }

  var body: some View {
    NavigationStack {
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
      .navigationTitle("Timeline")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            openEditor(trackID: controller.tracks.first?.id)
          } label: {
            Image(systemName: "plus")
          }
          .disabled(controller.tracks.isEmpty)
          .accessibilityLabel("Add Timeline moment")
          .accessibilityIdentifier("add-timeline-moment")
        }
      }
      .refreshable {
        await controller.load()
      }
      .sheet(item: $editorSelection) { selection in
        TimelineEditorSheet(
          controller: controller,
          entry: selection.entry,
          initialTrackID: selection.initialTrackID,
          tracks: controller.tracks
        )
      }
      .sheet(
        item: $residenceEditorSelection,
        onDismiss: {
          Task { await controller.load() }
        }
      ) { selection in
        ResidenceEditorSheet(controller: residenceController, entry: selection.entry)
      }
      .sheet(
        item: $vehicleEditorSelection,
        onDismiss: {
          Task { await controller.load() }
        }
      ) { selection in
        VehicleEditorSheet(controller: vehicleController, entry: selection.entry)
      }
      .alert(
        "Home unavailable",
        isPresented: Binding(
          get: { residenceErrorMessage != nil },
          set: { if !$0 { residenceErrorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { residenceErrorMessage = nil }
      } message: {
        Text(residenceErrorMessage ?? "")
      }
      .alert(
        "Vehicle unavailable",
        isPresented: Binding(
          get: { vehicleErrorMessage != nil },
          set: { if !$0 { vehicleErrorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { vehicleErrorMessage = nil }
      } message: {
        Text(vehicleErrorMessage ?? "")
      }
      .task {
        if !controller.hasLoaded {
          await controller.load()
        }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("YOUR LIFE IN CONTEXT")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.inkFaint)

      Text("Timeline")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("See the chapters, places, and moments that overlap your story.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Label(trackCountLabel, systemImage: "square.stack.3d.up")
      Text("·")
      Text(entryCountLabel)

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
        Text("Loading your Timeline...")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let loadErrorMessage = controller.loadErrorMessage {
      timelineMessage(
        title: "Timeline unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.tracks.isEmpty {
      timelineMessage(
        title: "Your Timeline needs tracks",
        message: "Pull to refresh after your default Timeline tracks are available.",
        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
      )
    } else {
      LazyVStack(spacing: MTSpacing.s4) {
        ForEach(controller.tracks) { track in
          TimelineTrackCard(
            track: track,
            addMoment: { openEditor(trackID: track.id) },
            selectEntry: { entry in
              switch entry.specializedEditor {
              case .home:
                Task { await openResidence(entryID: entry.id) }
              case .vehicle:
                Task { await openVehicle(entryID: entry.id) }
              case nil:
                editorSelection = TimelineEditorSelection(
                  entry: entry,
                  initialTrackID: entry.trackID
                )
              }
            }
          )
        }
      }
    }
  }

  private func timelineMessage(
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

  private func openEditor(trackID: UUID?) {
    guard let trackID else { return }
    editorSelection = TimelineEditorSelection(entry: nil, initialTrackID: trackID)
  }

  @MainActor
  private func openResidence(entryID: UUID) async {
    await residenceController.load()
    guard let entry = residenceController.entry(id: entryID) else {
      residenceErrorMessage =
        residenceController.loadErrorMessage
        ?? "This Home could not be opened. Refresh the Timeline and try again."
      return
    }
    residenceEditorSelection = ResidenceEditorSelection(entry: entry)
  }

  @MainActor
  private func openVehicle(entryID: UUID) async {
    await vehicleController.load()
    guard let entry = vehicleController.entry(id: entryID) else {
      vehicleErrorMessage =
        vehicleController.loadErrorMessage
        ?? "This Vehicle could not be opened. Refresh the Timeline and try again."
      return
    }
    vehicleEditorSelection = VehicleEditorSelection(entry: entry)
  }

  private var trackCountLabel: String {
    "\(controller.tracks.count) \(controller.tracks.count == 1 ? "track" : "tracks")"
  }

  private var entryCountLabel: String {
    "\(controller.entryCount) \(controller.entryCount == 1 ? "moment" : "moments")"
  }
}

private struct TimelineTrackCard: View {
  let track: TimelineTrack
  let addMoment: () -> Void
  let selectEntry: (TimelineEntry) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: MTSpacing.s3) {
        VStack(alignment: .leading, spacing: 2) {
          Text(track.name)
            .font(MTTypography.titleSmall)
            .foregroundStyle(MTColor.ink)

          Text(momentCountLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkFaint)
        }

        Spacer()

        Button(action: addMoment) {
          Image(systemName: "plus")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.small))
        }
        .buttonStyle(.plain)
        .foregroundStyle(MTColor.accent)
        .accessibilityLabel("Add a moment to \(track.name)")
      }
      .padding(MTSpacing.s4)

      Divider()
        .overlay(MTColor.border)

      if track.entries.isEmpty {
        Button(action: addMoment) {
          Label("Add the first moment", systemImage: "plus.circle")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MTSpacing.s4)
        }
        .buttonStyle(.plain)
      } else {
        ForEach(track.entries) { entry in
          Button {
            selectEntry(entry)
          } label: {
            TimelineEntryRow(entry: entry)
          }
          .buttonStyle(.plain)

          if entry.id != track.entries.last?.id {
            Divider()
              .padding(.leading, 50)
              .overlay(MTColor.border)
          }
        }
      }
    }
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var momentCountLabel: String {
    "\(track.entries.count) \(track.entries.count == 1 ? "moment" : "moments")"
  }
}

private struct TimelineEntryRow: View {
  let entry: TimelineEntry

  var body: some View {
    HStack(spacing: MTSpacing.s3) {
      marker

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.title)
          .font(MTTypography.label)
          .foregroundStyle(MTColor.ink)
          .lineLimit(2)

        Text(entry.displayDate)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(MTColor.inkFaint)
          .lineLimit(1)
      }

      Spacer(minLength: MTSpacing.s2)

      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s2)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var marker: some View {
    if entry.kind == .stage {
      Capsule()
        .fill(MTColor.accent)
        .frame(width: 18, height: 7)
        .frame(width: 22)
    } else {
      Circle()
        .fill(MTColor.warm)
        .frame(width: 10, height: 10)
        .frame(width: 22)
    }
  }
}

private struct TimelineEditorSelection: Identifiable {
  let id = UUID()
  let entry: TimelineEntry?
  let initialTrackID: UUID
}

private struct TimelineEditorSheet: View {
  let controller: TimelineController
  let entry: TimelineEntry?
  let tracks: [TimelineTrack]

  @Environment(\.dismiss) private var dismiss
  @State private var trackID: UUID
  @State private var kind: TimelineKind
  @State private var title: String
  @State private var note: String
  @State private var occurredStart: Date
  @State private var occurredEnd: Date
  @State private var hasEndDate: Bool
  @State private var datePrecision: TimelineDatePrecision
  @State private var occurredLabel: String
  @State private var occurredTimezone: String
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false

  init(
    controller: TimelineController,
    entry: TimelineEntry?,
    initialTrackID: UUID,
    tracks: [TimelineTrack]
  ) {
    self.controller = controller
    self.entry = entry
    self.tracks = tracks
    _trackID = State(initialValue: entry?.trackID ?? initialTrackID)
    _kind = State(initialValue: entry?.kind ?? .stage)
    _title = State(initialValue: entry?.title ?? "")
    _note = State(initialValue: entry?.body ?? "")
    _occurredStart = State(initialValue: entry?.occurredStart ?? Date())
    _occurredEnd = State(initialValue: entry?.occurredEnd ?? Date())
    _hasEndDate = State(initialValue: entry?.occurredEnd != nil)
    _datePrecision = State(initialValue: entry?.datePrecision ?? .range)
    _occurredLabel = State(initialValue: entry?.occurredLabel ?? "")
    _occurredTimezone = State(
      initialValue: entry?.occurredTimezone ?? TimeZone.current.identifier
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Moment type", selection: $kind) {
            ForEach(TimelineKind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind)
            }
          }
          .pickerStyle(.segmented)

          Text(kind.explanation)
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
        }

        Section("Content") {
          TextField("Title", text: $title, axis: .vertical)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("timeline-title")

          TextEditor(text: $note)
            .frame(minHeight: 140)
            .accessibilityLabel("Notes")
            .accessibilityIdentifier("timeline-notes")
        }

        Section("Place in Timeline") {
          Picker("Track", selection: $trackID) {
            ForEach(tracks) { track in
              Text(track.name).tag(track.id)
            }
          }

          Picker("Date precision", selection: $datePrecision) {
            ForEach(precisionOptions, id: \.self) { precision in
              Text(precision.displayName).tag(precision)
            }
          }

          DatePicker(
            kind == .stage ? "Start date" : "Date",
            selection: $occurredStart,
            displayedComponents: .date
          )

          if kind == .stage {
            Toggle("Has end date", isOn: $hasEndDate)

            if hasEndDate {
              DatePicker(
                "End date",
                selection: $occurredEnd,
                in: occurredStart...,
                displayedComponents: .date
              )
            }
          }

          TextField("Human date label (optional)", text: $occurredLabel)
            .textInputAutocapitalization(.sentences)
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
              .accessibilityIdentifier("timeline-editor-error")
          }
        }

        if entry != nil {
          Section {
            Button("Move to Trash", role: .destructive) {
              isConfirmingTrash = true
            }
            .disabled(isWorking)
          } footer: {
            Text("The moment and its edit history will be preserved for future restoration.")
          }
        }
      }
      .navigationTitle(entry == nil ? "New Timeline Moment" : "Edit Timeline Moment")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: title) {
        if title.count > TimelineEntryInput.titleLimit {
          title = String(title.prefix(TimelineEntryInput.titleLimit))
        }
      }
      .onChange(of: note) {
        if note.count > TimelineEntryInput.bodyLimit {
          note = String(note.prefix(TimelineEntryInput.bodyLimit))
        }
      }
      .onChange(of: occurredLabel) {
        if occurredLabel.count > TimelineEntryInput.labelLimit {
          occurredLabel = String(occurredLabel.prefix(TimelineEntryInput.labelLimit))
        }
      }
      .onChange(of: occurredStart) {
        occurredTimezone = TimeZone.current.identifier
        if occurredEnd < occurredStart {
          occurredEnd = occurredStart
        }
      }
      .onChange(of: occurredEnd) {
        occurredTimezone = TimeZone.current.identifier
      }
      .onChange(of: kind) {
        hasEndDate = false
        datePrecision = kind == .stage ? .range : .day
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
          .accessibilityIdentifier("save-timeline-moment")
        }
      }
      .overlay {
        if isWorking {
          ProgressView()
            .padding(MTSpacing.s4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
      .confirmationDialog(
        "Move this moment to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) {
          Task { await moveToTrash() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its history will be preserved.")
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  private var precisionOptions: [TimelineDatePrecision] {
    [.day, .month, .year, .approximate, .age, .range, .unknown]
  }

  @MainActor
  private func save() async {
    isWorking = true
    errorMessage = nil

    let result = await controller.save(
      entry: entry,
      trackID: trackID,
      kind: kind,
      title: title,
      body: note,
      occurredStart: occurredStart,
      occurredEnd: kind == .stage && hasEndDate ? occurredEnd : nil,
      datePrecision: datePrecision,
      occurredLabel: occurredLabel,
      occurredTimezone: occurredTimezone
    )

    isWorking = false

    switch result.status {
    case .saved:
      dismiss()
    case .conflict, .error, .trashed:
      errorMessage = result.message
    }
  }

  @MainActor
  private func moveToTrash() async {
    guard let entry else { return }

    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(entry)
    isWorking = false

    switch result.status {
    case .trashed:
      dismiss()
    case .conflict, .error, .saved:
      errorMessage = result.message
    }
  }
}
