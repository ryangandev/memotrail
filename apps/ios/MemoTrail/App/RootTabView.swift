@preconcurrency import Supabase
import SwiftUI

struct RootTabView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  private let draftStore: CaptureDraftStore
  private let photoStore: CapturePhotoStore
  @State private var homeController: HomeController
  @State private var inboxController: CaptureController
  @State private var captureTitle: String
  @State private var captureNote: NSAttributedString
  @State private var captureOccurrence: OccurrenceDraft?
  @State private var capturePhotos: [PhotoDraft]
  @State private var hasLocalDraft: Bool
  @State private var hasLoadedCapturePhotos = false
  @State private var navigator = AppNavigator()

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    draftStore: CaptureDraftStore = CaptureDraftStore(),
    queueStore: CaptureQueueStore = CaptureQueueStore(),
    photoStore: CapturePhotoStore = CapturePhotoStore()
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
      initialValue: CaptureController(
        client: client,
        ownerID: user.id,
        queueStore: queueStore,
        photoStore: photoStore
      )
    )
    _captureTitle = State(initialValue: draft?.title ?? "")
    _captureNote = State(initialValue: draft?.note ?? NSAttributedString())
    _captureOccurrence = State(initialValue: draft?.captureOccurrence)
    _capturePhotos = State(initialValue: [])
    _hasLocalDraft = State(initialValue: draft != nil)
  }

  var body: some View {
    TabView(selection: $navigator.selectedTab) {
      HomeView(
        client: client,
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut,
        controller: homeController,
        captureController: inboxController,
        captureTitle: $captureTitle,
        captureNote: $captureNote,
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
        controller: inboxController
      )
      .tabItem {
        Label(RootTabDestination.inbox.title, systemImage: RootTabDestination.inbox.systemImage)
      }
      .tag(RootTabDestination.inbox)
      .badge(inboxBadgeCount)

      TimelineView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .tabItem {
        Label(
          RootTabDestination.timeline.title, systemImage: RootTabDestination.timeline.systemImage)
      }
      .tag(RootTabDestination.timeline)

      LibraryView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .tabItem {
        Label(
          RootTabDestination.library.title, systemImage: RootTabDestination.library.systemImage)
      }
      .tag(RootTabDestination.library)

      MoreView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .tabItem {
        Label(RootTabDestination.more.title, systemImage: RootTabDestination.more.systemImage)
      }
      .tag(RootTabDestination.more)
    }
    .environment(navigator)
    .fullScreenCover(isPresented: $navigator.isShowingQuickCapture) {
      QuickCaptureView(
        controller: inboxController,
        title: $captureTitle,
        note: $captureNote,
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
    .onChange(of: captureNote) {
      persistDraft()
    }
    .onChange(of: captureOccurrence) {
      persistDraft()
    }
    .onChange(of: inboxController.pendingEntries.count) { previousCount, count in
      guard count < previousCount else { return }
      Task { await homeController.load() }
    }
    // Organizing or trashing a capture changes the Dashboard counts and Ready to organize.
    .onChange(of: inboxController.entries.count) { previousCount, count in
      guard count < previousCount else { return }
      Task { await homeController.load() }
    }
    .task {
      await loadCapturePhotosIfNeeded()
    }
  }

  private func persistDraft() {
    if captureTitle.count > CaptureInput.titleLimit {
      captureTitle = String(captureTitle.prefix(CaptureInput.titleLimit))
    }

    // Web counts the note limit in UTF-16 code units, like NSAttributedString.
    if captureNote.length > CaptureInput.bodyLimit {
      captureNote = captureNote.attributedSubstring(
        from: NSRange(location: 0, length: CaptureInput.bodyLimit))
    }

    hasLocalDraft =
      draftStore.save(
        title: captureTitle,
        body: captureNote.string,
        bodyRich: captureNote.length > 0 ? EntryEmphasisContent(attributedText: captureNote) : nil,
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
  private func addCapturePhoto(_ draft: PhotoDraft) async throws {
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
  case more

  var title: String {
    switch self {
    case .home: "Dashboard"
    case .inbox: "Inbox"
    case .timeline: "Timeline"
    case .library: "Library"
    case .more: "More"
    }
  }

  /// The Web navigation icons: dashboard grid, inbox tray, timeline, archive box, and more.
  var systemImage: String {
    switch self {
    case .home: MTIcon.dashboard.systemName
    case .inbox: MTIcon.inbox.systemName
    case .timeline: MTIcon.timeline.systemName
    case .library: MTIcon.archive.systemName
    case .more: MTIcon.more.systemName
    }
  }
}
