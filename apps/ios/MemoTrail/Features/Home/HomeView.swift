@preconcurrency import Supabase
import SwiftUI

// P6: the Dashboard's final layout.
struct HomeView: View {
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let client: SupabaseClient
  @Bindable private var controller: HomeController
  @Bindable private var captureController: CaptureController
  @Binding private var captureTitle: String
  @Binding private var captureNote: NSAttributedString
  @Binding private var captureOccurrence: OccurrenceDraft?
  @Binding private var capturePhotos: [PhotoDraft]
  private let addCapturePhoto: @MainActor (PhotoDraft) async throws -> Void
  private let removeCapturePhoto: @MainActor (UUID) async throws -> Void
  @Binding private var hasLocalDraft: Bool
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.scenePhase) private var scenePhase

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    controller: HomeController,
    captureController: CaptureController,
    captureTitle: Binding<String>,
    captureNote: Binding<NSAttributedString>,
    captureOccurrence: Binding<OccurrenceDraft?>,
    capturePhotos: Binding<[PhotoDraft]>,
    addCapturePhoto: @escaping @MainActor (PhotoDraft) async throws -> Void,
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
    _captureNote = captureNote
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
          note: $captureNote,
          occurrence: $captureOccurrence,
          photos: $capturePhotos,
          isSaving: captureController.isSaving,
          hasLocalDraft: hasLocalDraft,
          error: captureController.captureError,
          addPhoto: addCapturePhoto,
          removePhoto: removeCapturePhoto,
          save: saveCapture
        )

        if !captureController.pendingEntries.isEmpty {
          pendingCaptureSection
        }

        if let snapshot = controller.snapshot {
          memorySection
          nowSection(snapshot)
          recentSection(snapshot.recentEntries)
        } else if controller.isLoading {
          ProgressView("Loading your Dashboard...")
            .font(MTFont.caption)
            .tint(MTColor.accent)
            .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.dashboard)
        }
      }
      .navigationTitle("Dashboard")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .itemDestination(client: client, ownerID: user.id)
      .refreshable {
        await refresh()
      }
      .task {
        if !controller.hasLoaded {
          await refresh()
        }
      }
      .onChange(of: navigator.profileRevision) { Task { await controller.load() } }
      .onChange(of: navigator.entriesRevision) { Task { await controller.load() } }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active, controller.hasLoaded else { return }
        Task { await refresh() }
      }
    }
  }

  private var pendingCaptureSection: some View {
    // Captures MemoTrail refused need the person, so they read warm like Web's indicator.
    let hasRejected = captureController.rejectedEntryCount > 0
    return Button {
      navigator.showPendingCaptures()
    } label: {
      Label(captureController.pendingSummary, icon: hasRejected ? .warning : .history)
    }
    .buttonStyle(.plain)
    .font(MTFont.caption)
    .foregroundStyle(hasRejected ? MTColor.warm : MTColor.inkMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s3)
    .background(
      hasRejected ? MTColor.warmNotice : MTColor.accentNotice,
      in: RoundedRectangle(cornerRadius: MTRadius.medium)
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

  private var memorySection: some View {
    section("A memory for today", action: "Library") {
      navigator.show(.library)
    } content: {
      if let memory = controller.resurfacedMemory {
        NavigationLink(value: ItemLink(entryID: memory.entry.id)) {
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

  /// Web `Now`: the Chapters happening now, with durations measured to the snapshot's day.
  private func nowSection(_ snapshot: HomeSnapshot) -> some View {
    let asOf = EntryTimestamp.date(from: "\(snapshot.snapshotDate)T12:00:00Z") ?? .now
    return section("Now", action: "Timeline") {
      navigator.show(.timeline)
    } content: {
      if snapshot.nowItems.isEmpty {
        MTEmptyState(
          title: "Life is still unfolding",
          message: "Chapters you are in right now appear here.",
          icon: .timeline)
      } else {
        VStack(spacing: MTSpacing.s3) {
          ForEach(snapshot.nowItems) { item in
            NavigationLink(value: ItemLink(entryID: item.id)) {
              DashboardNowCard(item: item, asOf: asOf)
            }
            .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
          }
        }
      }
    }
    .accessibilityIdentifier("home-now")
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
            NavigationLink(value: ItemLink(entryID: entry.id)) {
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
      title: captureTitle, note: captureNote, occurrenceDraft: captureOccurrence,
      photos: capturePhotos)

    if didSave {
      captureTitle = ""
      captureNote = NSAttributedString()
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
