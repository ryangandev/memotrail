@preconcurrency import Supabase
import SwiftUI

struct RootTabView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let draftStore: InboxDraftStore
  private let photoStore: InboxPhotoStore
  @State private var homeController: HomeController
  @State private var inboxController: InboxController
  @State private var captureTitle: String
  @State private var captureBody: String
  @State private var captureOccurrence: OccurrenceDraft?
  @State private var capturePhotos: [FirstTimePhotoDraft]
  @State private var hasLocalDraft: Bool
  @State private var hasLoadedCapturePhotos = false
  @State private var selectedTab = RootTabDestination.home
  @State private var isShowingQuickCapture = false

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    draftStore: InboxDraftStore = InboxDraftStore(),
    queueStore: InboxQueueStore = InboxQueueStore(),
    photoStore: InboxPhotoStore = InboxPhotoStore()
  ) {
    let draft = draftStore.load(ownerID: user.id)

    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    self.draftStore = draftStore
    self.photoStore = photoStore
    _homeController = State(
      initialValue: HomeController(client: client, ownerID: user.id)
    )
    _inboxController = State(
      initialValue: InboxController(
        client: client,
        ownerID: user.id,
        queueStore: queueStore,
        photoStore: photoStore
      )
    )
    _captureTitle = State(initialValue: draft?.title ?? "")
    _captureBody = State(initialValue: draft?.body ?? "")
    _captureOccurrence = State(initialValue: draft?.captureOccurrence)
    _capturePhotos = State(initialValue: [])
    _hasLocalDraft = State(initialValue: draft != nil)
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      HomeView(
        client: client,
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut,
        controller: homeController,
        captureController: inboxController,
        captureTitle: $captureTitle,
        captureBody: $captureBody,
        captureOccurrence: $captureOccurrence,
        capturePhotos: $capturePhotos,
        addCapturePhoto: addCapturePhoto,
        removeCapturePhoto: removeCapturePhoto,
        hasLocalDraft: $hasLocalDraft
      )
      .tabItem {
        Label(RootTabDestination.home.title, systemImage: RootTabDestination.home.systemImage)
      }
      .tag(RootTabDestination.home)

      InboxView(
        client: client,
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut,
        controller: inboxController,
        captureTitle: $captureTitle,
        captureBody: $captureBody,
        captureOccurrence: $captureOccurrence,
        capturePhotos: $capturePhotos,
        addCapturePhoto: addCapturePhoto,
        removeCapturePhoto: removeCapturePhoto,
        hasLocalDraft: $hasLocalDraft
      )
      .tabItem {
        Label(RootTabDestination.inbox.title, systemImage: RootTabDestination.inbox.systemImage)
      }
      .tag(RootTabDestination.inbox)
      .badge(inboxBadgeCount)

      TimelineView(client: client, ownerID: user.id)
        .tabItem {
          Label(
            RootTabDestination.timeline.title,
            systemImage: RootTabDestination.timeline.systemImage
          )
        }
        .tag(RootTabDestination.timeline)

      LibraryView(client: client, ownerID: user.id)
        .tabItem {
          Label(
            RootTabDestination.library.title, systemImage: RootTabDestination.library.systemImage)
        }
        .tag(RootTabDestination.library)
    }
    .overlay(alignment: .bottomTrailing) {
      if selectedTab.usesGlobalCaptureButton {
        Button {
          isShowingQuickCapture = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(MTColor.accentInk)
            .frame(width: 50, height: 50)
            .background(MTColor.accent, in: Circle())
            .shadow(color: MTColor.scrim.opacity(0.16), radius: 10, y: 5)
        }
        .padding(.trailing, MTSpacing.s4)
        .padding(.bottom, 66)
        .accessibilityLabel("Quick capture")
        .accessibilityIdentifier("global-quick-capture")
      }
    }
    .fullScreenCover(isPresented: $isShowingQuickCapture) {
      QuickCaptureView(
        controller: inboxController,
        title: $captureTitle,
        draftBody: $captureBody,
        occurrence: $captureOccurrence,
        photos: $capturePhotos,
        addPhoto: addCapturePhoto,
        removePhoto: removeCapturePhoto,
        hasLocalDraft: $hasLocalDraft
      )
    }
    .onChange(of: captureTitle) {
      persistDraft()
    }
    .onChange(of: captureBody) {
      persistDraft()
    }
    .onChange(of: captureOccurrence) {
      persistDraft()
    }
    .onChange(of: inboxController.pendingEntries.count) { previousCount, count in
      guard count < previousCount else { return }
      Task { await homeController.load() }
    }
    .task {
      await loadCapturePhotosIfNeeded()
    }
  }

  private func persistDraft() {
    if captureTitle.count > InboxCapture.titleLimit {
      captureTitle = String(captureTitle.prefix(InboxCapture.titleLimit))
    }

    if captureBody.count > InboxCapture.bodyLimit {
      captureBody = String(captureBody.prefix(InboxCapture.bodyLimit))
    }

    hasLocalDraft =
      draftStore.save(
        title: captureTitle,
        body: captureBody,
        occurrenceDraft: captureOccurrence,
        ownerID: user.id
      ) || !capturePhotos.isEmpty
  }

  @MainActor
  private func loadCapturePhotosIfNeeded() async {
    guard !hasLoadedCapturePhotos else { return }
    hasLoadedCapturePhotos = true

    let photoStore = photoStore
    let ownerID = user.id
    let loadedPhotos =
      (try? await Task.detached {
        try photoStore.load(ownerID: ownerID)
      }.value) ?? []
    let queuedPhotoIDs = Set(
      inboxController.pendingEntries.flatMap { $0.attachments.map(\.id) }
    )
    capturePhotos = loadedPhotos.filter { !queuedPhotoIDs.contains($0.id) }
    hasLocalDraft =
      draftStore.load(ownerID: ownerID) != nil || !capturePhotos.isEmpty
  }

  @MainActor
  private func addCapturePhoto(_ draft: FirstTimePhotoDraft) async throws {
    let photoStore = photoStore
    let ownerID = user.id
    try await Task.detached {
      try photoStore.save(draft, ownerID: ownerID)
    }.value
    capturePhotos.append(draft)
    hasLocalDraft = true
  }

  @MainActor
  private func removeCapturePhoto(_ photoID: UUID) async throws {
    let photoStore = photoStore
    let ownerID = user.id
    try await Task.detached {
      try photoStore.remove(photoID: photoID, ownerID: ownerID)
    }.value
    capturePhotos.removeAll { $0.id == photoID }
    hasLocalDraft =
      draftStore.load(ownerID: ownerID) != nil || !capturePhotos.isEmpty
  }

  private var inboxBadgeCount: Int {
    let synchronizedCount =
      inboxController.hasLoaded
      ? inboxController.entries.count
      : (homeController.snapshot?.inboxCount ?? 0)
    return synchronizedCount + inboxController.pendingEntries.count
  }
}

enum RootTabDestination: String, CaseIterable, Sendable {
  case home
  case inbox
  case timeline
  case library

  var title: String {
    switch self {
    case .home: "Home"
    case .inbox: "Inbox"
    case .timeline: "Timeline"
    case .library: "Library"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .inbox: "tray"
    case .timeline: "point.bottomleft.forward.to.point.topright.scurvepath"
    case .library: "books.vertical"
    }
  }

  var usesGlobalCaptureButton: Bool {
    self != .home && self != .inbox
  }
}

private struct QuickCaptureView: View {
  @Bindable var controller: InboxController
  @Binding var title: String
  @Binding var draftBody: String
  @Binding var occurrence: OccurrenceDraft?
  @Binding var photos: [FirstTimePhotoDraft]
  let addPhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  @Binding var hasLocalDraft: Bool

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isTitleFocused: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MTSpacing.s6) {
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            Text("QUICK CAPTURE")
              .font(MTTypography.caption)
              .tracking(1.1)
              .foregroundStyle(MTColor.warm)

            Text("Keep what is on your mind")
              .font(MTTypography.title)
              .foregroundStyle(MTColor.ink)
          }

          CaptureCard(
            title: $title,
            note: $draftBody,
            occurrence: $occurrence,
            photos: $photos,
            isSaving: controller.isSaving,
            hasLocalDraft: hasLocalDraft,
            message: controller.captureMessage,
            titleFocus: $isTitleFocused,
            addPhoto: addPhoto,
            removePhoto: removePhoto,
            save: save
          )

          if !controller.pendingEntries.isEmpty {
            Label(
              "\(controller.pendingEntries.count) \(controller.pendingEntries.count == 1 ? "Entry" : "Entries") waiting to sync",
              systemImage: "clock.arrow.circlepath"
            )
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkMuted)
          }

          Spacer(minLength: MTSpacing.s8)
        }
        .padding(MTSpacing.s4)
      }
      .background(MTColor.canvas)
      .navigationTitle("New Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .task {
        isTitleFocused = true
      }
    }
  }

  @MainActor
  private func save() async {
    let didSave = await controller.save(
      title: title,
      body: draftBody,
      occurrenceDraft: occurrence,
      photos: photos
    )

    if didSave {
      title = ""
      draftBody = ""
      occurrence = nil
      photos = []
      hasLocalDraft = false
      dismiss()
    }
  }
}
