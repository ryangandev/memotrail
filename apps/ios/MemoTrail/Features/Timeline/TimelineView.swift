@preconcurrency import Supabase
import SwiftUI

// P5: the Timeline canvas (bands, stacking, year marks, Today line, unanchored list).

/// Web `/timeline` at phone width: the Chapters of your life and your First Times, Add to
/// Timeline, and Set birth date when the profile has none.
struct TimelineView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @State private var controller: TimelineController
  @State private var profile: SettingsController
  @State private var sheet: TimelineSheet?
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
        summary
        content
          .padding(.top, MTSpacing.s4)
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

  /// Web's summary line: the counts, then Set birth date.
  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(countLabel(controller.chapters.count, "Chapter"))
      MTFlowSeparator()
      Text(countLabel(controller.firstTimes.count, "First Time"))
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

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Timeline...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
    } else if let message = controller.loadErrorMessage, controller.items.isEmpty {
      MTEmptyState(title: "Timeline unavailable", message: message, icon: .clock) {
        Button("Try again") { Task { await load() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.items.isEmpty {
      MTEmptyState(
        title: "Your Timeline is waiting",
        message: "Add a Chapter or a First Time to start your Timeline.", icon: .timeline)
    } else {
      TimelineBand(title: "Chapters", items: controller.chapters)
      TimelineBand(title: "First Times", items: controller.firstTimes)
    }
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

/// One band of the Timeline as a plain list: each item's title and date, opening its Item page.
private struct TimelineBand: View {
  let title: String
  let items: [TimelineItem]

  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        MTSectionHeader(title)
        VStack(spacing: 0) {
          ForEach(items) { item in
            NavigationLink(value: ItemLink(entryID: item.id)) {
              HStack(spacing: MTSpacing.s3) {
                VStack(alignment: .leading, spacing: MTSpacing.s1) {
                  Text(item.displayTitle)
                    .font(MTFont.itemTitle)
                    .foregroundStyle(MTColor.ink)
                  Text(item.dateLabel)
                    .font(MTFont.detail)
                    .foregroundStyle(MTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(.chevron)
                  .font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
                  .foregroundStyle(MTColor.inkFaint)
              }
              .padding(.vertical, MTSpacing.s3)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline-item-\(item.id.uuidString.lowercased())")
            if item.id != items.last?.id {
              Divider().overlay(MTColor.border)
            }
          }
        }
      }
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
