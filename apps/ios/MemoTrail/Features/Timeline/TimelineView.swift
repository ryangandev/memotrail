@preconcurrency import Supabase
import SwiftUI

/// Web `/timeline`: the Chapters of your life and your First Times on a scrolling canvas of
/// years, items without a calendar date listed apart, Add to Timeline, and Set birth date when
/// the profile has none. The birth date is only ever asked for here, on request.
struct TimelineView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @State private var controller: TimelineController
  @State private var profile: SettingsController
  @State private var sheet: TimelineSheet?
  /// The visible width of the canvas card, so a short Timeline fills it.
  @State private var viewportWidth = 0.0
  /// Each title's measured width at the band item font; titles use an estimate until measured.
  @State private var titleWidths: [UUID: Double] = [:]
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
  }

  /// Web shows Set birth date only once the profile has loaded without one.
  private var needsBirthDate: Bool {
    profile.profile != nil && profile.profile?.birthDate == nil
      && controller.loadErrorMessage == nil
  }

  private var layout: TimelineLayout {
    createTimelineLayout(
      controller.items.compactMap {
        $0.layoutSource(titleWidth: titleWidths[$0.id] ?? estimateLabelWidth($0.displayTitle))
      },
      referenceDate: controller.referenceDate, birthDate: profile.profile?.birthDate,
      fillWidthPixels: viewportWidth)
  }

  var body: some View {
    NavigationStack {
      MTPage(width: .canvas, spacing: MTSpacing.s4) {
        MTPageHeader(
          eyebrow: "Your life in context", title: "Timeline",
          description: "See the Chapters of your life and your First Times."
        ) {
          Button {
            sheet = .chooser
          } label: {
            Label("Add to Timeline", icon: .plus)
          }
          .mtButtonStyle()
          .accessibilityIdentifier("timeline-add")
        }
        content
      }
      // Leave the last item clear of the Quick capture button.
      .contentMargins(.bottom, MTSpacing.s12, for: .scrollContent)
      .refreshable { await load() }
      .navigationTitle("Timeline")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .itemDestination(client: client, ownerID: user.id)
      .sheet(item: $sheet) { sheet in
        switch sheet {
        case .chooser:
          // A new item replaces the chooser with the editor.
          TimelineTypeChooser { self.sheet = .editor($0) }
        case .birthDate:
          TimelineBirthDatePrompt(profile: profile) { navigator.profileRevision += 1 }
        case .editor(let marks):
          EntryEditorSheet(client: client, ownerID: user.id, mode: .new(marks)) { _ in
            navigator.entriesChanged()
          }
        }
      }
      .task {
        guard !controller.hasLoaded else { return }
        await load()
      }
      .onChange(of: navigator.profileRevision) { Task { await profile.load() } }
      .onChange(of: navigator.entriesRevision) { Task { await controller.load() } }
    }
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      summary(layout: nil)
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Timeline...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
    } else if let message = controller.loadErrorMessage, controller.items.isEmpty {
      summary(layout: nil)
      MTEmptyState(title: "Timeline unavailable", message: message, icon: .clock) {
        Button("Try again") { Task { await load() } }
          .mtButtonStyle(.secondary)
      }
    } else {
      let layout = self.layout
      summary(layout: layout)
      canvasCard(layout: layout)
        .padding(.top, MTSpacing.s4)
    }
  }

  /// Web's summary line: the counts and the years shown, then Set birth date.
  private func summary(layout: TimelineLayout?) -> some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(countLabel(controller.chapters.count, "Chapter"))
      MTFlowSeparator()
      Text(countLabel(controller.firstTimeCount, "First Time"))
      if let layout, controller.items.contains(where: { $0.windowStart != nil }) {
        MTFlowSeparator()
        Text("\(String(layout.startYear)) to \(String(layout.endYear))")
      }
      // Its border sets the button apart, so no separator dangles when it wraps.
      if needsBirthDate {
        Button("Set birth date") { sheet = .birthDate }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityIdentifier("timeline-set-birth-date")
      }
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.detail)
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Timeline summary")
  }

  /// Web `.desktopTimeline`: the hint, the canvas that scrolls across years, and the items
  /// that have no calendar date.
  private func canvasCard(layout: TimelineLayout) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
        Text("Scroll across years").foregroundStyle(MTColor.inkMuted)
        Spacer(minLength: 0)
        Text("Select anything to open it").foregroundStyle(MTColor.inkFaint)
          .multilineTextAlignment(.trailing)
      }
      .font(MTFont.caption)
      .padding(.horizontal, MTSpacing.s4)
      .padding(.vertical, MTSpacing.s3)
      .frame(maxWidth: .infinity)
      .background(MTColor.surface)
      .overlay(alignment: .bottom) { MTColor.border.frame(height: MTSize.Stroke.thin) }
      ScrollView(.horizontal) {
        TimelineCanvas(
          layout: layout, chapters: controller.chapters, firstTimes: controller.firstTimes
        ) { sheet = .chooser }
      }
      // A long Timeline opens on its latest years, where the Today line is.
      .defaultScrollAnchor(.trailing)
      .onGeometryChange(for: Double.self) {
        Double($0.size.width)
      } action: {
        viewportWidth = $0
      }
      .accessibilityIdentifier("timeline-viewport")
      if !controller.undated.isEmpty {
        undatedItems
      }
    }
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .strokeBorder(MTColor.borderStrong, lineWidth: MTSize.Stroke.thin)
    }
    .mtShadow(MTShadow.raised)
    .background { titleProbe }
  }

  /// Web `.undatedItems`.
  private var undatedItems: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("Without a calendar date")
        .font(MTFont.sheetTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      Text("These have no calendar date, so they are not placed on the years above.")
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body)
      VStack(spacing: MTSpacing.s2) {
        ForEach(controller.undated) { item in
          NavigationLink(value: ItemLink(entryID: item.id)) {
            Text("\(item.displayTitle), \(item.undatedLabel)")
              .font(MTFont.body)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, MTSpacing.s4)
              .padding(.vertical, MTSpacing.s3)
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.medium)
                  .strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin)
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("timeline-undated-\(item.id.uuidString.lowercased())")
        }
      }
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { MTColor.border.frame(height: MTSize.Stroke.thin) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Without a calendar date")
    .accessibilityIdentifier("timeline-undated-section")
  }

  /// Web's hidden `labelProbe`: every dated title at the band item font, so the layout knows
  /// which fit inside their bar. It follows Dynamic Type, because the text is the real text.
  private var titleProbe: some View {
    ZStack {
      ForEach(controller.items.filter { $0.windowStart != nil }) { item in
        Text(item.displayTitle)
          .font(MTFont.micro)
          .lineLimit(1)
          .fixedSize()
          .onGeometryChange(for: Double.self) {
            Double($0.size.width).rounded(.up)
          } action: {
            titleWidths[item.id] = $0
          }
      }
    }
    .opacity(0)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func load() async {
    async let timeline: Void = controller.load()
    async let settings: Void = profile.load()
    _ = await (timeline, settings)
  }
}

private enum TimelineSheet: Identifiable {
  case chooser
  case birthDate
  case editor(EntryMarks)

  var id: String {
    switch self {
    case .chooser: "chooser"
    case .birthDate: "birth-date"
    case .editor(let marks): "editor-\(marks.isChapter)-\(marks.isFirstTime)"
    }
  }
}

/// Web `TimelineTypeChooser`: a Chapter or a First Time.
private struct TimelineTypeChooser: View {
  let choose: (EntryMarks) -> Void

  var body: some View {
    MTSheet(
      eyebrow: "Add to Timeline", title: "What are you adding?",
      closeLabel: "Close Timeline chooser", size: .fitted
    ) {
      VStack(spacing: MTSpacing.s3) {
        MTSheetOption(
          icon: .timeline, title: "Chapter",
          detail: "A stretch of your life, like a home, a job, or a school year."
        ) { choose(.chapter) }
        .accessibilityLabel("Add Chapter")
        .accessibilityIdentifier("timeline-type-chapter")
        MTSheetOption(icon: .star, title: "First Time", detail: "The first time you did something.")
        {
          choose(.firstTime)
        }
        .accessibilityLabel("Add First Time")
        .accessibilityIdentifier("timeline-type-first-time")
      }
    }
  }
}

/// Web `BirthDatePrompt`: a picker-only birth date that starts the Timeline, saved like
/// Settings. It opens only from Set birth date.
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
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
          .accessibilityIdentifier("timeline-cancel-birth-date")
        Button("Save birth date") { Task { await save() } }
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
