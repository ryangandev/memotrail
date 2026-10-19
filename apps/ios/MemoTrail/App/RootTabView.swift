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
  @State private var captureController: CaptureController
  @State private var captureTitle: String
  @State private var captureNote: NSAttributedString
  @State private var captureOccurrence: OccurrenceDraft?
  @State private var capturePhotos: [PhotoDraft]
  @State private var hasLocalDraft: Bool
  @State private var hasLoadedCapturePhotos = false
  /// Why the saved draft did not come back in full, shown once the composer is ready.
  @State private var draftNotice: String?
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
    let reading = draftStore.read(ownerID: user.id)
    let draft = reading.draft

    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    self.draftStore = draftStore
    self.photoStore = photoStore
    _homeController = State(
      initialValue: HomeController(client: client, ownerID: user.id)
    )
    _captureController = State(
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
    _draftNotice = State(initialValue: reading.notice)
  }

  var body: some View {
    TabView(selection: $navigator.selectedTab) {
      HomeView(
        client: client,
        user: user,
        isAuthenticationBusy: isAuthenticationBusy,
        signOut: signOut,
        controller: homeController,
        captureController: captureController,
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
        controller: captureController,
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
    .sheet(isPresented: $navigator.isShowingPendingCaptures) {
      PendingCapturesSheet(controller: captureController)
    }
    // A capture that reached MemoTrail changes every list that shows Entries.
    .onChange(of: captureController.entriesRevision) { navigator.entriesChanged() }
    .task {
      captureController.showDraftNotice(draftNotice)
      draftNotice = nil
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
    // A queued or unreadable capture still owns its photos until it is sent or discarded.
    let queuedPhotoIDs = Set(
      captureController.pendingEntries.flatMap { $0.attachments.map(\.id) }
        + captureController.unreadableCaptures.flatMap(\.photoIDs)
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
}

enum RootTabDestination: String, CaseIterable, Sendable {
  case home
  case timeline
  case library
  case more

  var title: String {
    switch self {
    case .home: "Dashboard"
    case .timeline: "Timeline"
    case .library: "Library"
    case .more: "More"
    }
  }

  /// The Web navigation icons: dashboard grid, timeline, archive box, and more.
  var systemImage: String {
    switch self {
    case .home: MTIcon.dashboard.systemName
    case .timeline: MTIcon.timeline.systemName
    case .library: MTIcon.archive.systemName
    case .more: MTIcon.more.systemName
    }
  }
}
