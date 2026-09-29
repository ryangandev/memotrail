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
  @State private var captureNote: NSAttributedString
  @State private var captureOccurrence: OccurrenceDraft?
  @State private var capturePhotos: [FirstTimePhotoDraft]
  @State private var hasLocalDraft: Bool
  @State private var hasLoadedCapturePhotos = false
  @State private var navigator = AppNavigator()
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

      MoreView(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .tabItem {
        Label(RootTabDestination.more.title, systemImage: RootTabDestination.more.systemImage)
      }
      .tag(RootTabDestination.more)
    }
    .overlay(alignment: .bottomTrailing) {
      if navigator.selectedTab.usesGlobalCaptureButton {
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
    .environment(navigator)
    .fullScreenCover(isPresented: $isShowingQuickCapture) {
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
    if captureTitle.count > InboxCapture.titleLimit {
      captureTitle = String(captureTitle.prefix(InboxCapture.titleLimit))
    }

    // Web counts the note limit in UTF-16 code units, like NSAttributedString.
    if captureNote.length > InboxCapture.bodyLimit {
      captureNote = captureNote.attributedSubstring(
        from: NSRange(location: 0, length: InboxCapture.bodyLimit))
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

  /// The Dashboard has its own composer; the other lists capture from this button, like the
  /// Web header's capture action.
  var usesGlobalCaptureButton: Bool {
    self == .inbox || self == .timeline || self == .library
  }
}

private struct QuickCaptureView: View {
  @Bindable var controller: InboxController
  @Binding var title: String
  @Binding var note: NSAttributedString
  @Binding var occurrence: OccurrenceDraft?
  @Binding var photos: [FirstTimePhotoDraft]
  let addPhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  @Binding var hasLocalDraft: Bool

  @Environment(\.dismiss) private var dismiss

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
            note: $note,
            occurrence: $occurrence,
            photos: $photos,
            isSaving: controller.isSaving,
            hasLocalDraft: hasLocalDraft,
            message: controller.captureMessage,
            focusRequest: 1,
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
    }
  }

  @MainActor
  private func save() async {
    let didSave = await controller.save(
      title: title, note: note, occurrenceDraft: occurrence, photos: photos)

    if didSave {
      title = ""
      note = NSAttributedString()
      occurrence = nil
      photos = []
      hasLocalDraft = false
      dismiss()
    }
  }
}
