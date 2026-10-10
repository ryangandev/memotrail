@preconcurrency import Supabase
import SwiftUI

/// Web `/inbox`: the captures waiting for a place, each ready to organize or move to Trash.
/// New captures start from the Dashboard composer or the Quick capture button.
struct InboxView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void
  @Bindable var controller: InboxController

  @State private var selectedEntry: InboxEntry?
  @State private var trashingEntryID: UUID?
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      MTPage(width: .compact) {
        MTPageHeader(
          eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
          title: "Inbox",
          description: "Review and organize the captures waiting for a place.")
        if !controller.pendingEntries.isEmpty {
          pendingSection
        }
        entrySection
      }
      // Leave the last card's actions clear of the Quick capture button.
      .contentMargins(.bottom, MTSpacing.s12, for: .scrollContent)
      .refreshable {
        await controller.refresh()
      }
      .navigationTitle("Inbox")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .sheet(item: $selectedEntry) { entry in
        EntryReviewSheet(
          client: client,
          ownerID: user.id,
          entry: entry,
          collectionOptions: controller.collectionOptions,
          tagOptions: controller.tagOptions,
          moveToTrash: { await moveToTrash(entry) }
        ) { draft, intent in
          await controller.review(entry: entry, draft: draft, intent: intent)
        }
      }
      .task {
        if !controller.hasLoaded {
          await controller.refresh()
        }
      }
      .task(id: navigator.inboxReviewRequest) {
        guard let id = navigator.inboxReviewRequest else { return }
        if !controller.entries.contains(where: { $0.id == id }) { await controller.refresh() }
        openRequestedReview()
      }
      .onChange(of: controller.isLoading) { openRequestedReview() }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active, controller.hasLoaded else { return }
        Task { await controller.refresh() }
      }
    }
  }

  /// Opens the capture a Dashboard link asked for, like Web `/inbox?entry=`.
  private func openRequestedReview() {
    guard let id = navigator.inboxReviewRequest, controller.hasLoaded, !controller.isLoading
    else { return }
    navigator.inboxReviewRequest = nil
    guard let entry = controller.entries.first(where: { $0.id == id }) else {
      MTToastCenter.shared.info("This capture is no longer waiting in the Inbox.")
      return
    }
    selectedEntry = entry
  }

  private var pendingSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      // Like Web's Pending sync, it also holds captures MemoTrail refused, which never retry.
      MTSectionHeader(
        "Pending sync", variant: .list, detail: "\(captureCount(controller.pendingEntries.count)) on this iPhone"
      ) {
        if controller.waitingEntryCount > 0 {
          Button {
            Task { await controller.refresh() }
          } label: {
            Label("Retry now", icon: .refresh)
          }
          .mtButtonStyle(.ghost, size: .small, isLoading: controller.isSyncing)
          .accessibilityIdentifier("retry-pending-entries")
        }
      }
      MTListSurface {
        ForEach(controller.pendingEntries) { entry in
          PendingCaptureRow(entry: entry) { await controller.discardRejected(entry.id) }
          if entry.id != controller.pendingEntries.last?.id {
            MTListDivider()
          }
        }
      }
    }
    .accessibilityIdentifier("inbox-pending-entries")
  }

  private var entrySection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader("Ready to organize", variant: .list, detail: captureCount(controller.entries.count)) {
        if controller.isLoading, controller.hasLoaded {
          ProgressView().controlSize(.small).tint(MTColor.accent)
        }
      }
      MTListSurface {
        if !controller.hasLoaded, controller.isLoading {
          ProgressView("Loading your Inbox...")
            .font(MTFont.caption)
            .tint(MTColor.accent)
            .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.list)
        } else if let message = controller.loadErrorMessage, controller.entries.isEmpty {
          InboxMessage(icon: .clock, title: "Inbox unavailable", message: message) {
            Button("Try again") { Task { await controller.refresh() } }
              .mtButtonStyle(.secondary, size: .small)
          }
        } else if controller.entries.isEmpty {
          if controller.waitingEntryCount == 0 {
            InboxMessage(
              icon: .inbox, title: "Your Inbox is ready",
              message: "New captures will wait here until you give them a place.")
          } else {
            InboxMessage(
              icon: .history, title: "Waiting to sync",
              message: "Captures on this iPhone will appear here after MemoTrail reconnects.")
          }
        } else {
          ForEach(controller.entries) { entry in
            InboxCaptureRow(
              entry: entry, isTrashing: trashingEntryID == entry.id,
              organize: { selectedEntry = entry },
              moveToTrash: { Task { await moveToTrash(entry) } })
            if entry.id != controller.entries.last?.id {
              MTListDivider()
            }
          }
        }
      }
      if let message = controller.loadErrorMessage, !controller.entries.isEmpty {
        Label(message, icon: .warning)
          .font(MTFont.caption)
          .foregroundStyle(MTColor.warm)
      }
    }
    .accessibilityIdentifier("inbox-ready-to-organize")
  }

  private func captureCount(_ count: Int) -> String {
    countLabel(count, "capture")
  }

  /// Web `moveEntryToTrash`: move the capture, close its review, and confirm with a toast.
  @MainActor @discardableResult
  private func moveToTrash(_ entry: InboxEntry) async -> Bool {
    guard trashingEntryID == nil else { return false }
    trashingEntryID = entry.id
    defer { trashingEntryID = nil }
    if let message = await controller.moveToTrash(entry) {
      MTToastCenter.shared.error(message)
      return false
    }
    MTToastCenter.shared.info("Capture moved to Trash.")
    return true
  }
}
