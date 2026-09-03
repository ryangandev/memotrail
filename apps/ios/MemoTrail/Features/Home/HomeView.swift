import Supabase
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
  @Binding private var hasLocalDraft: Bool
  @State private var isShowingAccount = false
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
    _hasLocalDraft = hasLocalDraft
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          CaptureCard(
            title: $captureTitle,
            note: $captureBody,
            isSaving: captureController.isSaving,
            hasLocalDraft: hasLocalDraft,
            message: captureController.captureMessage,
            titleFocus: $isTitleFocused,
            save: saveCapture
          )

          if !captureController.pendingEntries.isEmpty {
            pendingCaptureSection
          }

          homeContent
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .background(MTColor.canvas)
      .navigationTitle("Home")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          MemoTrailBrand()
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
      .refreshable {
        await refresh()
      }
      .sheet(isPresented: $isShowingAccount) {
        AccountView(
          user: user,
          isBusy: isAuthenticationBusy,
          signOut: signOut
        )
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

  private var header: some View {
    HStack(alignment: .bottom, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.warm)

        Text(
          "\(HomePresentation.greeting(at: .now, timezone: .current)), \(HomePresentation.firstName(controller.snapshot?.profileDisplayName ?? user.name))."
        )
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)
        .fixedSize(horizontal: false, vertical: true)

        Text("A calm view of what is active, recent, and waiting for you.")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
      }

      Spacer(minLength: 0)

      NavigationLink {
        SearchView(client: client, ownerID: user.id, embedded: true)
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 42, height: 42)
          .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
          .overlay {
            RoundedRectangle(cornerRadius: MTRadius.medium)
              .stroke(MTColor.borderStrong, lineWidth: 1)
          }
      }
      .accessibilityLabel("Search your trail")
      .accessibilityIdentifier("home-search")
    }
  }

  private var pendingCaptureSection: some View {
    Label(
      "\(captureController.pendingEntries.count) \(captureController.pendingEntries.count == 1 ? "Entry" : "Entries") waiting to sync",
      systemImage: "clock.arrow.circlepath"
    )
    .font(MTTypography.caption)
    .foregroundStyle(MTColor.inkMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s3)
    .background(
      MTColor.accentSubtle.opacity(0.42), in: RoundedRectangle(cornerRadius: MTRadius.medium)
    )
    .accessibilityIdentifier("home-pending-entries")
  }

  @ViewBuilder
  private var homeContent: some View {
    if controller.isLoading, !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView()
        Text("Loading Home...")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    } else if let message = controller.loadErrorMessage, controller.snapshot == nil {
      homeMessage(
        title: "Home is taking a moment",
        message: message,
        systemImage: "clock"
      )
    } else if let snapshot = controller.snapshot {
      todaySection(snapshot)

      if !snapshot.currentStages.isEmpty {
        currentStagesSection(snapshot.currentStages)
      }

      recentEntriesSection(snapshot.recentEntries)

      if let message = controller.loadErrorMessage {
        Label(message, systemImage: "exclamationmark.circle.fill")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }
    }
  }

  private func todaySection(_ snapshot: HomeSnapshot) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionHeading("Today", detail: "The small signals that shape today")

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: MTSpacing.s3),
          GridItem(.flexible(), spacing: MTSpacing.s3),
        ],
        spacing: MTSpacing.s3
      ) {
        HomeStatCard(
          value: "\(snapshot.inboxCount)",
          title: "Waiting in Inbox",
          detail: countLabel(snapshot.inboxCount, singular: "Entry"),
          systemImage: "tray"
        )
        HomeStatCard(
          value: "\(snapshot.completedHabitCount)",
          title: "Habits complete",
          detail: snapshot.habitProgressLabel,
          systemImage: "checkmark"
        )
        HomeStatCard(
          value: "\(snapshot.currentStageCount)",
          title: "Life in progress",
          detail: countLabel(snapshot.currentStageCount, singular: "current chapter"),
          systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
        )
        HomeStatCard(
          value: "\(snapshot.entryCount)",
          title: "Entries kept",
          detail:
            "\(snapshot.firstTimeCount) First Times · \(snapshot.collectionCount) Collections",
          systemImage: "archivebox"
        )
      }
      .accessibilityIdentifier("home-today-stats")
    }
  }

  private func currentStagesSection(_ stages: [HomeStage]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionHeading("Current chapters", detail: "The overlapping chapters you are living now")

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: MTSpacing.s3) {
          ForEach(stages) { stage in
            VStack(alignment: .leading, spacing: MTSpacing.s3) {
              Text(stage.trackName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(MTColor.warm)

              Text(stage.title)
                .font(MTTypography.titleSmall)
                .foregroundStyle(MTColor.ink)
                .lineLimit(2)

              Text(stage.displayDate)
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkFaint)
            }
            .frame(width: 242)
            .frame(minHeight: 116, alignment: .topLeading)
            .padding(MTSpacing.s4)
            .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
            .overlay {
              RoundedRectangle(cornerRadius: MTRadius.large)
                .stroke(MTColor.border, lineWidth: 1)
            }
          }
        }
      }
      .accessibilityIdentifier("home-current-chapters")
    }
  }

  private func recentEntriesSection(_ entries: [HomeEntry]) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionHeading("Recent Entries", detail: "The latest things added to your archive")

      if entries.isEmpty {
        homeMessage(
          title: "Your trail starts here",
          message: "Capture a thought above and it will become your first recent Entry.",
          systemImage: "sparkles"
        )
      } else {
        LazyVStack(spacing: MTSpacing.s3) {
          ForEach(entries) { entry in
            HomeRecentEntryCard(entry: entry)
          }
        }
      }
    }
    .accessibilityIdentifier("home-recent-entries")
  }

  private func sectionHeading(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(MTTypography.title)
        .foregroundStyle(MTColor.ink)

      Text(detail)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkFaint)
    }
  }

  private func homeMessage(title: String, message: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(MTColor.accent)

      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        Text(title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)

        Text(message)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceSubtle.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }
  }

  @MainActor
  private func saveCapture() async {
    let didSave = await captureController.save(title: captureTitle, body: captureBody)

    if didSave {
      captureTitle = ""
      captureBody = ""
      hasLocalDraft = false
    }
  }

  private func refresh() async {
    _ = await captureController.synchronizePendingEntries()
    await controller.load()
  }

  private func countLabel(_ count: Int, singular: String) -> String {
    "\(count) \(count == 1 ? singular : "\(singular)s")"
  }
}

private struct MemoTrailBrand: View {
  var body: some View {
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
}

private struct HomeStatCard: View {
  let value: String
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack(alignment: .top) {
        Text(value)
          .font(.system(size: 34, weight: .medium, design: .serif))
          .foregroundStyle(MTColor.ink)

        Spacer(minLength: MTSpacing.s2)

        Image(systemName: systemImage)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 32, height: 32)
          .background(MTColor.accentSubtle, in: Circle())
      }

      Spacer(minLength: MTSpacing.s2)

      Text(title)
        .font(MTTypography.label)
        .foregroundStyle(MTColor.ink)

      Text(detail)
        .font(.system(size: 10))
        .foregroundStyle(MTColor.inkFaint)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
    .padding(MTSpacing.s4)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}

private struct HomeRecentEntryCard: View {
  let entry: HomeEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let imageURL = entry.coverAttachment?.signedURL {
        AsyncImage(url: imageURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          case .failure:
            imagePlaceholder
          case .empty:
            ProgressView()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          @unknown default:
            imagePlaceholder
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 172)
        .clipped()
      }

      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.displayType.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(MTColor.warm)

          Spacer()

          Text(entry.displayDate)
            .font(.system(size: 10))
            .foregroundStyle(MTColor.inkFaint)
        }

        Text(entry.title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
          .lineLimit(2)

        if let excerpt = entry.displayExcerpt {
          Text(excerpt)
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(3)
            .lineSpacing(2)
        }

        if !organizationLabels.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MTSpacing.s1) {
              ForEach(organizationLabels.prefix(3), id: \.self) { label in
                Text(label)
                  .font(.system(size: 10, weight: .medium))
                  .foregroundStyle(MTColor.accent)
                  .padding(.horizontal, MTSpacing.s2)
                  .padding(.vertical, 4)
                  .background(MTColor.accentSubtle, in: Capsule())
              }
            }
          }
        }
      }
      .padding(MTSpacing.s4)
    }
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var organizationLabels: [String] {
    entry.collectionNames + entry.tagNames.map { "#\($0)" }
  }

  private var imagePlaceholder: some View {
    ZStack {
      MTColor.surfaceSubtle
      Image(systemName: "photo")
        .foregroundStyle(MTColor.inkFaint)
    }
  }
}
