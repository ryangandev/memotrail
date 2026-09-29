@preconcurrency import Supabase
import SwiftUI

struct HomeView: View {
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let client: SupabaseClient
  @Bindable private var controller: HomeController
  @Bindable private var captureController: InboxController
  @Binding private var captureTitle: String
  @Binding private var captureBody: String
  @Binding private var captureOccurrence: OccurrenceDraft?
  @Binding private var capturePhotos: [FirstTimePhotoDraft]
  private let addCapturePhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  private let removeCapturePhoto: @MainActor (UUID) async throws -> Void
  @Binding private var hasLocalDraft: Bool
  @State private var isShowingAccount = false
  @Environment(AppNavigator.self) private var navigator
  @FocusState private var isTitleFocused: Bool
  @Environment(\.scenePhase) private var scenePhase

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    controller: HomeController,
    captureController: InboxController,
    captureTitle: Binding<String>,
    captureBody: Binding<String>,
    captureOccurrence: Binding<OccurrenceDraft?>,
    capturePhotos: Binding<[FirstTimePhotoDraft]>,
    addCapturePhoto: @escaping @MainActor (FirstTimePhotoDraft) async throws -> Void,
    removeCapturePhoto: @escaping @MainActor (UUID) async throws -> Void,
    hasLocalDraft: Binding<Bool>
  ) {
    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    self.controller = controller
    self.captureController = captureController
    _captureTitle = captureTitle
    _captureBody = captureBody
    _captureOccurrence = captureOccurrence
    _capturePhotos = capturePhotos
    self.addCapturePhoto = addCapturePhoto
    self.removeCapturePhoto = removeCapturePhoto
    _hasLocalDraft = hasLocalDraft
  }

  var body: some View {
    NavigationStack {
      MTPage(width: .wide) {
        MTPageHeader(
          eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
          title:
            "\(HomePresentation.greeting(at: .now, timezone: .current)), \(HomePresentation.firstName(controller.snapshot?.profileDisplayName ?? user.name)).",
          description: "A calm view of what is active, recent, and waiting for you.")

        if let snapshot = controller.snapshot {
          DashboardRibbon(snapshot: snapshot, navigator: navigator)
        }

        if controller.snapshot == nil, let message = controller.loadErrorMessage {
          MTFeedback(
            title: "Home is taking a moment", message: message, tone: .warm,
            systemImage: "clock")
        }

        CaptureCard(
          title: $captureTitle,
          note: $captureBody,
          occurrence: $captureOccurrence,
          photos: $capturePhotos,
          isSaving: captureController.isSaving,
          hasLocalDraft: hasLocalDraft,
          message: captureController.captureMessage,
          titleFocus: $isTitleFocused,
          addPhoto: addCapturePhoto,
          removePhoto: removeCapturePhoto,
          save: saveCapture
        )

        if !captureController.pendingEntries.isEmpty {
          pendingCaptureSection
        }

        if let snapshot = controller.snapshot {
          readyToOrganize(snapshot)
          memorySection
          chaptersSection(snapshot.currentStages)
          recentSection(snapshot.recentEntries)
        } else if controller.isLoading {
          ProgressView("Loading your Dashboard...")
            .font(MTFont.caption)
            .tint(MTColor.accent)
            .frame(maxWidth: .infinity, minHeight: 150)
        }
      }
      .navigationTitle("Dashboard")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          MemoTrailBrand()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Search your trail", systemImage: MTIcon.search.systemName) {
            navigator.show(.library)
          }
          .accessibilityIdentifier("home-search")
          Button("Profile", systemImage: "person.crop.circle.fill") {
            isShowingAccount = true
          }
          .accessibilityLabel("Open Settings for \(user.name)")
        }
      }
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .navigationDestination(for: DashboardRecord.self) { record in
        WikiItemDestinationView(
          client: client, ownerID: user.id, entryID: record.id, kind: record.kind,
          subtype: record.subtype)
      }
      .refreshable {
        await refresh()
      }
      .sheet(isPresented: $isShowingAccount) {
        NavigationStack {
          NativeSettingsView(
            client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingAccount = false }
            }
          }
        }
      }
      .task {
        if !controller.hasLoaded {
          await refresh()
        }
      }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active, controller.hasLoaded else { return }
        Task { await refresh() }
      }
    }
  }

  private var pendingCaptureSection: some View {
    Label(
      "\(captureController.pendingEntries.count) \(captureController.pendingEntries.count == 1 ? "Entry" : "Entries") waiting to sync",
      icon: .history
    )
    .font(MTFont.caption)
    .foregroundStyle(MTColor.inkMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s3)
    .background(
      MTColor.accentSubtle.opacity(0.42), in: RoundedRectangle(cornerRadius: MTRadius.medium)
    )
    .accessibilityIdentifier("home-pending-entries")
  }

  private func section<Content: View>(
    _ title: String, action: String, open: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader(title) {
        MTSectionLink(title: action, action: open)
      }
      content()
    }
  }

  private func readyToOrganize(_ snapshot: HomeSnapshot) -> some View {
    section("Ready to organize", action: "Inbox · \(snapshot.inboxCount)") {
      navigator.show(.inbox)
    } content: {
      if controller.inboxPreview.isEmpty {
        MTEmptyState(
          title: "A little room to think",
          message:
            "Your Inbox is clear. New captures will wait here until you are ready to organize them.",
          icon: .inbox)
      } else {
        VStack(spacing: 0) {
          ForEach(controller.inboxPreview) { entry in
            DashboardInboxRow(entry: entry) { navigator.reviewInboxEntry(entry.id) }
            if entry.id != controller.inboxPreview.last?.id {
              Divider().overlay(MTColor.border)
            }
          }
        }
      }
    }
    .padding(MTSpacing.s5)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
    .accessibilityIdentifier("home-inbox-preview")
  }

  private var memorySection: some View {
    section("A memory for today", action: "Library") {
      navigator.show(.library)
    } content: {
      if let memory = controller.resurfacedMemory {
        NavigationLink(value: DashboardRecord(memory.entry)) {
          DashboardMemoryCard(entry: memory.entry)
        }
        .buttonStyle(MTCardButtonStyle(radius: MTRadius.large))
      } else {
        MTEmptyState(
          title: "Room for a memory",
          message: "As your archive grows, an older dated Entry will find its way back here.",
          icon: .sparkle)
      }
    }
    .accessibilityIdentifier("home-resurfaced-memory")
  }

  private func chaptersSection(_ stages: [HomeStage]) -> some View {
    section("Current chapters", action: "Timeline") {
      navigator.show(.timeline)
    } content: {
      if stages.isEmpty {
        MTEmptyState(
          title: "Life is still unfolding",
          message: "Current periods and focused records from your Timeline will appear here.",
          icon: .timeline)
      } else {
        VStack(spacing: MTSpacing.s3) {
          ForEach(stages) { stage in
            DashboardChapterCard(stage: stage) { navigator.openTimelineEntry(stage.id) }
          }
        }
      }
    }
    .accessibilityIdentifier("home-current-chapters")
  }

  private func recentSection(_ entries: [HomeEntry]) -> some View {
    section("Recent Entries", action: "View all") {
      navigator.show(.library)
    } content: {
      if entries.isEmpty {
        MTEmptyState(
          title: "Your trail starts here",
          message: "Entries you save to Library will appear here, ready to return to.",
          icon: .archive)
      } else {
        VStack(spacing: 0) {
          ForEach(entries) { entry in
            NavigationLink(value: DashboardRecord(entry)) {
              DashboardEntryRow(entry: entry)
            }
            .buttonStyle(.plain)
            if entry.id != entries.last?.id {
              Divider().overlay(MTColor.border)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("home-recent-entries")
  }

  @MainActor
  private func saveCapture() async {
    let didSave = await captureController.save(
      title: captureTitle,
      body: captureBody,
      occurrenceDraft: captureOccurrence,
      photos: capturePhotos
    )

    if didSave {
      captureTitle = ""
      captureBody = ""
      captureOccurrence = nil
      capturePhotos = []
      hasLocalDraft = false
    }
  }

  private func refresh() async {
    _ = await captureController.synchronizePendingEntries()
    await controller.load()
  }
}

private struct MemoTrailBrand: View {
  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      MemoTrailMark()
        .frame(width: 28, height: 28)

      Text("MemoTrail")
        .font(.system(size: 18, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)
    }
  }
}
