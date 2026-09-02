import Supabase
import SwiftUI

struct InboxView: View {
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let draftStore: InboxDraftStore
  @State private var controller: InboxController
  @State private var captureTitle: String
  @State private var captureBody: String
  @State private var hasLocalDraft: Bool
  @State private var isShowingAccount = false
  @FocusState private var isTitleFocused: Bool
  @Environment(\.scenePhase) private var scenePhase

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    draftStore: InboxDraftStore = InboxDraftStore(),
    queueStore: InboxQueueStore = InboxQueueStore()
  ) {
    let draft = draftStore.load(ownerID: user.id)

    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    self.draftStore = draftStore
    _controller = State(
      initialValue: InboxController(
        client: client,
        ownerID: user.id,
        queueStore: queueStore
      )
    )
    _captureTitle = State(initialValue: draft?.title ?? "")
    _captureBody = State(initialValue: draft?.body ?? "")
    _hasLocalDraft = State(initialValue: draft != nil)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          CaptureCard(
            title: $captureTitle,
            note: $captureBody,
            isSaving: controller.isSaving,
            hasLocalDraft: hasLocalDraft,
            message: controller.captureMessage,
            titleFocus: $isTitleFocused,
            save: saveCapture
          )
          if !controller.pendingEntries.isEmpty {
            pendingSection
          }
          entrySection
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .refreshable {
        await controller.refresh()
      }
      .background(MTColor.canvas)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: MTSpacing.s2) {
            Text("M")
              .font(.system(size: 14, weight: .semibold, design: .serif))
              .foregroundStyle(MTColor.accentInk)
              .frame(width: 28, height: 28)
              .background(
                MTColor.accent,
                in: UnevenRoundedRectangle(
                  cornerRadii: .init(
                    topLeading: 8,
                    bottomLeading: 3,
                    bottomTrailing: 8,
                    topTrailing: 8
                  )
                )
              )

            Text("MemoTrail")
              .font(.system(size: 18, weight: .medium, design: .serif))
              .foregroundStyle(MTColor.ink)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Profile", systemImage: "person.crop.circle.fill") {
            isShowingAccount = true
          }
          .accessibilityLabel("Open account for \(user.name)")
        }
      }
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $isShowingAccount) {
        AccountView(
          user: user,
          isBusy: isAuthenticationBusy,
          signOut: signOut
        )
      }
      .task {
        if !controller.hasLoaded {
          await controller.refresh()
        }
      }
      .onChange(of: captureTitle) {
        persistDraft()
      }
      .onChange(of: captureBody) {
        persistDraft()
      }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active, controller.hasLoaded else { return }
        Task { await controller.refresh() }
      }
    }
  }

  private var pendingSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Text("PENDING SYNC")
            .font(MTTypography.label)
            .tracking(0.7)
            .foregroundStyle(MTColor.ink)

          Text(pendingCountLabel)
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
        }

        Spacer()

        Button {
          Task { await controller.refresh() }
        } label: {
          if controller.isSyncing {
            ProgressView()
              .controlSize(.small)
          } else {
            Label("Retry now", systemImage: "arrow.clockwise")
          }
        }
        .font(MTTypography.caption)
        .buttonStyle(.bordered)
        .disabled(controller.isSyncing)
        .accessibilityIdentifier("retry-pending-entries")
      }

      LazyVStack(spacing: 0) {
        ForEach(controller.pendingEntries) { entry in
          PendingEntryCard(entry: entry)

          if entry.id != controller.pendingEntries.last?.id {
            Divider()
              .overlay(MTColor.border)
          }
        }
      }
      .background(MTColor.accentSubtle.opacity(0.22))
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.inkFaint)

        Text("Inbox")
          .font(MTTypography.display)
          .foregroundStyle(MTColor.ink)
      }

      Spacer()

      Button("New entry", systemImage: "plus") {
        isTitleFocused = true
      }
      .labelStyle(.iconOnly)
      .font(.system(size: 18, weight: .medium))
      .foregroundStyle(MTColor.accentInk)
      .frame(width: 42, height: 42)
      .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .accessibilityLabel("New entry")
    }
  }

  private var entrySection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        Text("UNSORTED")
          .font(MTTypography.label)
          .tracking(0.7)
          .foregroundStyle(MTColor.ink)

        Text(entryCountLabel)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        if controller.isLoading, controller.hasLoaded {
          ProgressView()
            .controlSize(.small)
        }
      }

      Group {
        if !controller.hasLoaded, controller.isLoading {
          loadingState
        } else if let loadErrorMessage = controller.loadErrorMessage,
          controller.entries.isEmpty
        {
          errorState(loadErrorMessage)
        } else if controller.entries.isEmpty {
          emptyState
        } else {
          entryList
        }
      }
      .background(MTColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }

      if let loadErrorMessage = controller.loadErrorMessage,
        !controller.entries.isEmpty
      {
        Label(loadErrorMessage, systemImage: "exclamationmark.circle.fill")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }
    }
  }

  private var entryList: some View {
    LazyVStack(spacing: 0) {
      ForEach(controller.entries) { entry in
        EntryCard(entry: entry)

        if entry.id != controller.entries.last?.id {
          Divider()
            .overlay(MTColor.border)
        }
      }
    }
  }

  private var loadingState: some View {
    HStack(spacing: MTSpacing.s3) {
      ProgressView()
      Text("Loading your Inbox...")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
    }
    .frame(maxWidth: .infinity, minHeight: 112)
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: MTSpacing.s3) {
      Label("Inbox unavailable", systemImage: "exclamationmark.triangle")
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)

      Text(message)
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .multilineTextAlignment(.center)

      Button("Try again") {
        Task { await controller.load() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .padding(MTSpacing.s4)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      controller.pendingEntries.isEmpty ? "Your Inbox is ready" : "Waiting to sync",
      systemImage: "tray",
      description: Text(
        controller.pendingEntries.isEmpty
          ? "Save a thought above and it will appear here."
          : "Pending Entries will appear here after MemoTrail reconnects."
      )
    )
    .foregroundStyle(MTColor.inkMuted)
    .frame(maxWidth: .infinity, minHeight: 190)
  }

  private var entryCountLabel: String {
    let count = controller.entries.count
    return "\(count) \(count == 1 ? "entry" : "entries")"
  }

  private var pendingCountLabel: String {
    let count = controller.pendingEntries.count
    return "\(count) \(count == 1 ? "Entry" : "Entries") on this iPhone"
  }

  @MainActor
  private func saveCapture() async {
    let didSave = await controller.save(title: captureTitle, body: captureBody)

    if didSave {
      draftStore.clear(ownerID: user.id)
      captureTitle = ""
      captureBody = ""
      hasLocalDraft = false
    }
  }

  private func persistDraft() {
    if captureTitle.count > InboxCapture.titleLimit {
      captureTitle = String(captureTitle.prefix(InboxCapture.titleLimit))
    }

    if captureBody.count > InboxCapture.bodyLimit {
      captureBody = String(captureBody.prefix(InboxCapture.bodyLimit))
    }

    hasLocalDraft = draftStore.save(
      title: captureTitle,
      body: captureBody,
      ownerID: user.id
    )
  }
}
