@preconcurrency import Supabase
import SwiftUI

/// Web `/timeline` at phone width: each track's periods and moments, the chooser for what to
/// add, and the first-visit prompt for the birth date that starts the story.
struct TimelineView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @State private var controller: TimelineController
  @State private var profile: SettingsController
  @State private var residenceController: ResidenceController
  @State private var vehicleController: VehicleController
  @State private var firstTimesController: FirstTimesController
  @State private var sheet: TimelineSheet?
  @State private var reloadsAfterSheet = false
  @State private var managingTracks = false
  @State private var hasOfferedBirthDate = false
  @State private var openingRecordID: UUID?
  @State private var openedRecord: TimelineRecordPage?
  @Environment(AppNavigator.self) private var navigator

  init(
    client: SupabaseClient, user: AuthenticatedUser, isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    _controller = State(initialValue: TimelineController(client: client, ownerID: user.id))
    _profile = State(initialValue: SettingsController(client: client, ownerID: user.id))
    _residenceController = State(
      initialValue: ResidenceController(client: client, ownerID: user.id))
    _vehicleController = State(initialValue: VehicleController(client: client, ownerID: user.id))
    _firstTimesController = State(
      initialValue: FirstTimesController(client: client, ownerID: user.id))
  }

  private var birthDate: String? { profile.profile?.birthDate }
  /// Web shows Set birth date only once the profile has loaded without one.
  private var needsBirthDate: Bool {
    profile.profile != nil && birthDate == nil && controller.loadErrorMessage == nil
  }

  var body: some View {
    NavigationStack {
      MTPage(width: .canvas, spacing: MTSpacing.s4) {
        MTPageHeader(
          eyebrow: "Your life in context", title: "Timeline",
          description: "See the chapters and moments that shape your life."
        ) {
          Button {
            sheet = .chooser
          } label: {
            Label("Add moment", icon: .plus)
          }
          .mtButtonStyle()
          .disabled(controller.tracks.isEmpty)
          .accessibilityIdentifier("add-timeline-moment")
        }
        summary
        content
          .padding(.top, MTSpacing.s4)
      }
      // Leave the last track clear of the Quick capture button.
      .contentMargins(.bottom, MTSpacing.s12, for: .scrollContent)
      .refreshable { await load() }
      .navigationTitle("Timeline")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .sheet(item: $sheet, onDismiss: sheetDismissed) { sheet in
        switch sheet {
        case .chooser:
          TimelineTypeChooser { choose($0, trackID: controller.tracks.first?.id) }
        case .birthDate:
          TimelineBirthDatePrompt(profile: profile) { navigator.profileRevision += 1 }
        case .moment(let entry, let trackID):
          TimelineEditorSheet(
            controller: controller, entry: entry, initialTrackID: trackID,
            defaultTimezone: profile.profile?.timezone)
        case .home(let entry):
          ResidenceEditorSheet(
            controller: residenceController, entry: entry,
            defaultTimezone: profile.profile?.timezone)
        case .vehicle(let entry):
          VehicleEditorSheet(
            controller: vehicleController, entry: entry,
            defaultTimezone: profile.profile?.timezone)
        case .firstTime(let entry):
          FirstTimeEditorSheet(
            controller: firstTimesController, entry: entry,
            defaultTimezone: profile.profile?.timezone)
        }
      }
      .navigationDestination(isPresented: $managingTracks) {
        TimelineTracksView(client: client, ownerID: user.id)
      }
      .navigationDestination(item: $openedRecord) { page in
        switch page {
        case .home(let id):
          HomeDetailView(
            controller: residenceController, client: client, ownerID: user.id, entryID: id)
        case .vehicle(let id):
          VehicleDetailView(
            controller: vehicleController, client: client, ownerID: user.id, entryID: id)
        case .firstTime(let id):
          FirstTimeDetailView(
            controller: firstTimesController, client: client, ownerID: user.id, entryID: id)
        }
      }
      .onChange(of: managingTracks) {
        if !managingTracks { Task { await controller.reloadAfterMutation() } }
      }
      .onChange(of: openedRecord) {
        if openedRecord == nil { Task { await controller.reloadAfterMutation() } }
      }
      .task {
        guard !controller.hasLoaded else { return }
        await load()
        offerBirthDate()
      }
      .task(id: navigator.timelineEntryRequest) { await openRequestedEntry() }
      .onChange(of: controller.isLoading) { Task { await openRequestedEntry() } }
      .onChange(of: navigator.profileRevision) { Task { await profile.load() } }
    }
  }

  /// Web's summary line: Manage tracks, the counts, the years covered, and Set birth date.
  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Button("Manage tracks") { managingTracks = true }
        .buttonStyle(.plain)
        .font(MTFont.caption.weight(.medium))
        .foregroundStyle(MTColor.accent)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .accessibilityIdentifier("manage-timeline-tracks")
      ForEach(summaryFacts, id: \.self) { fact in
        Text("·").accessibilityHidden(true)
        Text(fact)
      }
      if needsBirthDate {
        Text("·").accessibilityHidden(true)
        Button("Set birth date") { sheet = .birthDate }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityIdentifier("timeline-set-birth-date")
      }
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.caption.weight(.regular))
    .foregroundStyle(MTColor.inkFaint)
  }

  private var summaryFacts: [String] {
    let entries = controller.entries
    return [
      countLabel(controller.tracks.count, "track"), countLabel(entries.count, "moment"),
      TimelineWorkspace.rangeLabel(entries: entries, birthDate: birthDate, reference: .now),
    ].compactMap(\.self)
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Timeline...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage, controller.tracks.isEmpty {
      MTEmptyState(title: "Timeline unavailable", message: message, icon: .clock) {
        Button("Try again") { Task { await load() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.tracks.isEmpty {
      MTEmptyState(
        title: "Your Timeline needs tracks",
        message: "Open Manage tracks to add a track or show a hidden one.", icon: .timeline
      ) {
        Button("Manage tracks") { managingTracks = true }
          .mtButtonStyle(.secondary)
      }
    } else {
      ForEach(controller.tracks) { track in
        TimelineTrackCard(
          track: track, openingRecordID: openingRecordID, add: { add(to: track) },
          select: { select($0) })
      }
    }
  }

  private func load() async {
    async let timeline: Void = controller.load()
    async let settings: Void = profile.load()
    _ = await (timeline, settings)
  }

  /// Web opens the birth date prompt on the first visit until one is saved; a record link from
  /// elsewhere opens that record instead.
  private func offerBirthDate() {
    guard !hasOfferedBirthDate, needsBirthDate else { return }
    hasOfferedBirthDate = true
    guard sheet == nil, navigator.timelineEntryRequest == nil else { return }
    sheet = .birthDate
  }

  private func add(to track: TimelineTrack) {
    switch track.systemKey {
    case "homes": choose(.home, trackID: track.id)
    case "vehicles": choose(.vehicle, trackID: track.id)
    case "first_times": choose(.firstTime, trackID: track.id)
    default: choose(.moment, trackID: track.id)
    }
  }

  private func choose(_ type: TimelineCreationType, trackID: UUID?) {
    switch type {
    case .moment:
      guard let trackID else { return }
      sheet = .moment(nil, trackID: trackID)
    case .home:
      present(.home(nil))
    case .vehicle:
      present(.vehicle(nil))
    case .firstTime:
      Task {
        await firstTimesController.load()
        present(.firstTime(nil))
      }
    }
  }

  /// Home, Vehicle, and First Time editors save through their own controllers, so the Timeline
  /// reloads once they close.
  private func present(_ editor: TimelineSheet) {
    reloadsAfterSheet = true
    sheet = editor
  }

  private func sheetDismissed() {
    guard sheet == nil, reloadsAfterSheet else { return }
    reloadsAfterSheet = false
    Task { await controller.reloadAfterMutation() }
  }

  /// Web `openEntry`: Homes, Vehicles, and First Times open their own pages. A Dashboard or
  /// Library link opens the record's editor, like Web `/timeline?entry=`.
  private func select(_ entry: TimelineEntry, fromLink: Bool = false) {
    guard openingRecordID == nil else { return }
    switch entry.specializedEditor {
    case nil:
      sheet = .moment(entry, trackID: entry.trackID)
    case .home where !fromLink:
      openedRecord = .home(entry.id)
    case .vehicle where !fromLink:
      openedRecord = .vehicle(entry.id)
    case .firstTime where !fromLink:
      openedRecord = .firstTime(entry.id)
    case .home:
      open(entry) {
        await residenceController.load()
        return residenceController.entry(id: entry.id).map { .home($0) }
      }
    case .vehicle:
      open(entry) {
        await vehicleController.load()
        return vehicleController.entry(id: entry.id).map { .vehicle($0) }
      }
    case .firstTime:
      open(entry) {
        await firstTimesController.load()
        return firstTimesController.entry(id: entry.id).map { .firstTime($0) }
      }
    }
  }

  private func open(
    _ entry: TimelineEntry, editor: @escaping @MainActor () async -> TimelineSheet?
  ) {
    openingRecordID = entry.id
    Task {
      let loaded = await editor()
      openingRecordID = nil
      guard let loaded else {
        MTToastCenter.shared.error("“\(entry.title)” could not be opened. Refresh and try again.")
        return
      }
      present(loaded)
    }
  }

  /// Opens the record a Dashboard or Library link asked for, like Web `/timeline?entry=`.
  private func openRequestedEntry() async {
    guard let id = navigator.timelineEntryRequest, !controller.isLoading else { return }
    if !controller.entries.contains(where: { $0.id == id }) { await controller.load() }
    // A newer load may have replaced this one; this runs again once it finishes.
    guard navigator.timelineEntryRequest == id, !controller.isLoading else { return }
    navigator.timelineEntryRequest = nil
    guard let entry = controller.entries.first(where: { $0.id == id }) else {
      MTToastCenter.shared.info("This record is no longer on your Timeline.")
      return
    }
    select(entry, fromLink: true)
  }
}

private enum TimelineCreationType: CaseIterable {
  case moment, home, vehicle, firstTime

  var icon: MTIcon {
    switch self {
    case .moment: .timeline
    case .home: .home
    case .vehicle: .car
    case .firstTime: .star
    }
  }

  var title: String {
    switch self {
    case .moment: "Moment"
    case .home: "Home"
    case .vehicle: "Vehicle"
    case .firstTime: "First Time"
    }
  }

  var detail: String {
    switch self {
    case .moment: "A flexible event or life stage on any Timeline track."
    case .home: "A place you called home, with its facts and memories."
    case .vehicle: "A car, bike, or other vehicle that carried your story."
    case .firstTime: "A beginning or milestone you want to remember."
    }
  }
}

/// A focused record page opened from a Timeline card.
private enum TimelineRecordPage: Hashable {
  case home(UUID)
  case vehicle(UUID)
  case firstTime(UUID)
}

private enum TimelineSheet: Identifiable {
  case chooser
  case birthDate
  case moment(TimelineEntry?, trackID: UUID)
  case home(ResidenceEntry?)
  case vehicle(VehicleEntry?)
  case firstTime(FirstTimeEntry?)

  var id: String {
    switch self {
    case .chooser: "chooser"
    case .birthDate: "birth-date"
    case .moment(let entry, let trackID): "moment-\(entry?.id ?? trackID)"
    case .home(let entry): "home-\(entry?.id.uuidString ?? "new")"
    case .vehicle(let entry): "vehicle-\(entry?.id.uuidString ?? "new")"
    case .firstTime(let entry): "first-time-\(entry?.id.uuidString ?? "new")"
    }
  }
}

/// Web `mobileTrack`: the track name and count, its add action, then each record.
private struct TimelineTrackCard: View {
  let track: TimelineTrack
  let openingRecordID: UUID?
  let add: () -> Void
  let select: (TimelineEntry) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: MTSpacing.s3) {
        VStack(alignment: .leading, spacing: 2) {
          Text(track.name)
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .accessibilityAddTraits(.isHeader)
          Text(countLabel(track.entries.count, "moment"))
            .font(.caption2)
            .foregroundStyle(MTColor.inkFaint)
        }
        Spacer(minLength: 0)
        MTIconButton(label: "Add a moment to \(track.name)", icon: .plus, size: .small, action: add)
          .foregroundStyle(MTColor.inkFaint)
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.vertical, MTSpacing.s3)
      .frame(minHeight: 62)
      MTListDivider()
      if track.entries.isEmpty {
        Text("No moments yet.")
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MTSpacing.s4)
          .padding(.vertical, MTSpacing.s5)
      } else {
        ForEach(track.entries) { entry in
          if entry.id != track.entries.first?.id { MTListDivider() }
          Button {
            select(entry)
          } label: {
            TimelineEntryRow(entry: entry, isOpening: openingRecordID == entry.id)
          }
          .buttonStyle(MTListRowButtonStyle())
          .accessibilityLabel("\(entry.title), \(entry.displayDate)")
        }
      }
    }
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
  }
}

private struct TimelineEntryRow: View {
  let entry: TimelineEntry
  let isOpening: Bool

  var body: some View {
    HStack(spacing: MTSpacing.s3) {
      Group {
        if entry.kind == .stage {
          Capsule().fill(MTColor.accent).frame(width: 14, height: 7)
        } else {
          Circle().fill(MTColor.warm).frame(width: 10, height: 10)
        }
      }
      .frame(width: 14)
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.title)
          .font(MTFont.label)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
        Text(entry.displayDate)
          .font(.caption2)
          .foregroundStyle(MTColor.inkFaint)
          .lineLimit(1)
      }
      Spacer(minLength: MTSpacing.s2)
      if isOpening {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      } else {
        Image(.chevron)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MTColor.inkMuted)
      }
    }
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s3)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .contentShape(Rectangle())
  }
}

/// Web `MomentTypeChooser`.
private struct TimelineTypeChooser: View {
  let choose: (TimelineCreationType) -> Void

  var body: some View {
    MTSheet(
      eyebrow: "New entry", title: "What are you adding?",
      closeLabel: "Close entry type chooser", size: .fitted
    ) {
      VStack(spacing: MTSpacing.s3) {
        ForEach(TimelineCreationType.allCases, id: \.self) { type in
          MTSheetOption(icon: type.icon, title: type.title, detail: type.detail) {
            choose(type)
          }
          .accessibilityLabel("Add \(type.title)")
          .accessibilityIdentifier("timeline-type-\(type)")
        }
      }
    }
  }
}

/// Web `BirthDatePrompt`: a picker-only birth date that starts the Timeline, saved like Settings.
private struct TimelineBirthDatePrompt: View {
  let profile: SettingsController
  let saved: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var birthDate = ""
  @State private var message: String?

  private var isSaving: Bool { profile.savingField == .birthDate }

  var body: some View {
    MTSheet(
      eyebrow: "Your starting point", title: "When did your story begin?",
      closeLabel: "Close birth date prompt", size: .fitted, isBusy: isSaving, message: message
    ) {
      Text(
        "Add your birth date so Timeline begins with your life, not just your earliest saved moment. It stays private and can be changed in Settings."
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
      MTDateField(label: "Birth date", value: $birthDate, size: .large, isRequired: true)
        .accessibilityIdentifier("timeline-birth-date")
    } footer: {
      HStack(spacing: MTSpacing.s2) {
        Spacer(minLength: 0)
        Button("Not now") { dismiss() }
          .mtButtonStyle(.secondary)
        Button("Start my Timeline") { Task { await save() } }
          .mtButtonStyle(isLoading: isSaving)
          .disabled(birthDate.isEmpty)
          .accessibilityIdentifier("timeline-save-birth-date")
      }
    }
  }

  private func save() async {
    message = nil
    let result = await profile.saveBirthDate(birthDate)
    guard result.isSaved else {
      message = result.message
      return
    }
    MTToastCenter.shared.success(result.message)
    saved()
    dismiss()
  }
}

/// Web `TimelineEditor`: the shape, title, track, when it happened, notes, and organization.
private struct TimelineEditorSheet: View {
  let controller: TimelineController
  let entry: TimelineEntry?
  let defaultTimezone: String?

  @Environment(\.dismiss) private var dismiss
  @State private var trackID: UUID
  @State private var kind: TimelineKind
  @State private var title: String
  @State private var note: String
  @State private var occurrence: OccurrenceDraft
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false

  init(
    controller: TimelineController, entry: TimelineEntry?, initialTrackID: UUID,
    defaultTimezone: String?
  ) {
    self.controller = controller
    self.entry = entry
    self.defaultTimezone = defaultTimezone
    _trackID = State(initialValue: entry?.trackID ?? initialTrackID)
    _kind = State(initialValue: entry?.kind ?? .event)
    _title = State(initialValue: entry?.title ?? "")
    _note = State(initialValue: entry?.body ?? "")
    let timezone = defaultTimezone ?? TimeZone.current.identifier
    _occurrence = State(
      initialValue: OccurrenceDraft(
        entry?.occurrence
          ?? EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone),
        undatedTimezone: timezone))
    _collectionNames = State(initialValue: entry?.collectionNames ?? [])
    _tagNames = State(initialValue: entry?.tagNames ?? [])
  }

  var body: some View {
    MTSheet(
      eyebrow: entry == nil ? "New Timeline moment" : "Edit moment",
      title: entry?.title ?? "Add to your story", closeLabel: "Close Timeline editor",
      closeIdentifier: "close-timeline-editor", isBusy: isWorking, message: errorMessage
    ) {
      shapePicker
      MTTextField(
        label: "Title", text: $title,
        prompt: kind == .stage ? "Living in Philadelphia" : "First ski day", isRequired: true,
        maxLength: TimelineEntryInput.titleLimit
      )
      .accessibilityIdentifier("timeline-title")
      MTSelectField(
        label: "Track", selection: $trackID, options: controller.tracks.map(\.id),
        title: { id in controller.tracks.first { $0.id == id }?.name ?? "" }, isRequired: true)
      OccurrenceEditor(
        value: $occurrence, span: kind == .stage, point: kind == .event,
        defaultTimezone: defaultTimezone)
      MTTextField(
        label: "Notes", text: $note, prompt: "What made this period or moment meaningful?",
        maxLength: TimelineEntryInput.bodyLimit, axis: .vertical, lines: 5...12
      )
      .accessibilityIdentifier("timeline-notes")
      MTOrganizationEditor(
        kind: .collection, names: $collectionNames, options: controller.collectionOptions)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: controller.tagOptions)
    } footer: {
      footer
    }
  }

  /// Web `kindPicker`: Period or Moment, and what that shape means.
  private var shapePicker: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Timeline shape")
      Picker("Timeline shape", selection: $kind) {
        Text("Period").tag(TimelineKind.stage)
        Text("Moment").tag(TimelineKind.event)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("timeline-shape")
      .onChange(of: kind) {
        guard kind == .event else { return }
        occurrence.end = ""
        occurrence.endMode = .date
        if occurrence.precision == .range { occurrence.precision = .day }
      }
      Text(kind.explanation)
        .font(MTFont.caption.weight(.regular))
        .foregroundStyle(MTColor.inkFaint)
    }
  }

  private var footer: some View {
    MTSheetFooter {
      trashButton
    } cancel: {
      cancelButton
    } primary: {
      saveButton
    }
  }

  @ViewBuilder private var trashButton: some View {
    if let entry {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("trash-timeline-moment")
        .confirmationDialog(
          "Move “\(entry.title)” to Trash?", isPresented: $isConfirmingTrash,
          titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Its history will be preserved.")
        }
    }
  }

  private var cancelButton: some View {
    Button("Cancel") { dismiss() }
      .mtButtonStyle(.secondary)
  }

  private var saveButton: some View {
    Button(entry == nil ? "Add moment" : "Save changes") { Task { await save() } }
      .mtButtonStyle(isLoading: isWorking)
      .accessibilityIdentifier("save-timeline-moment")
  }

  private func save() async {
    let resolved: EntryOccurrence
    do {
      resolved = try occurrence.resolve(original: entry?.occurrence, span: kind == .stage)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    isWorking = true
    errorMessage = nil
    let result = await controller.save(
      entry: entry, trackID: trackID, kind: kind, title: title, body: note,
      occurrence: resolved,
      collectionNames: collectionNames, tagNames: tagNames)
    isWorking = false
    guard result.succeeded else {
      errorMessage = result.message
      return
    }
    MTToastCenter.shared.success(result.message)
    dismiss()
  }

  private func moveToTrash() async {
    guard let entry else { return }
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(entry)
    isWorking = false
    guard result.succeeded else {
      errorMessage = result.message
      return
    }
    MTToastCenter.shared.info(result.message)
    dismiss()
  }
}
