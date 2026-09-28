@preconcurrency import Supabase
import SwiftUI

struct TrashView: View {
  @State private var controller: TrashController
  @State private var deleteConfirmation: TrashItem?
  @State private var batchTask: Task<Void, Never>?

  private let embedded: Bool

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false) {
    self.embedded = embedded
    _controller = State(initialValue: TrashController(client: client, ownerID: ownerID))
  }

  @ViewBuilder
  var body: some View {
    if embedded {
      archiveView
    } else {
      NavigationStack {
        archiveView
      }
    }
  }

  private var archiveView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s5) {
        header
        retentionNote

        Button("Empty Trash", role: .destructive) {
          batchTask = Task { await controller.prepareEmptyTrash() }
        }
        .buttonStyle(.bordered)
        .disabled(controller.isBusy || controller.isLoading || controller.totalCount == 0)
        .accessibilityIdentifier("empty-trash")

        if controller.isEmptying {
          ProgressView(
            "\(controller.emptyProgress) of \(controller.emptyTotal) confirmed deleted. Keep this screen open."
          )
          .font(MTTypography.caption)
        }

        if let notice = controller.notice {
          noticeView(notice)
        }

        content
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle("Trash")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .refreshable {
      await controller.load()
    }
    .task {
      if !controller.hasLoaded {
        await controller.load()
      }
    }
    .onDisappear {
      batchTask?.cancel()
      controller.cancelEmptyTrash()
    }
    .sheet(
      isPresented: Binding(
        get: { controller.emptySnapshot != nil },
        set: { if !$0 { controller.cancelEmptyTrash() } }
      )
    ) {
      if let targets = controller.emptySnapshot {
        ScrollView {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            Text("Empty \(targets.count) items from Trash?").font(MTTypography.title)
            Text(
              "This includes all Trash pages, not just visible items. Their records, associated history and private photos will be permanently removed. Removing a Collection only removes its grouping, not active Entries. This cannot be undone."
            )
            Text(
              "Only this prepared list is included. Items added to Trash later are not deleted. If an item changes or a request cannot be confirmed, deletion stops for a fresh review."
            )
            .foregroundStyle(MTColor.inkMuted)
            Button("Cancel", role: .cancel) { controller.cancelEmptyTrash() }
              .buttonStyle(.bordered).frame(maxWidth: .infinity)
            Button("Permanently delete confirmed items", role: .destructive) {
              batchTask = Task { await controller.emptyTrash() }
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
          }
          .font(MTTypography.body).foregroundStyle(MTColor.ink)
          .padding(MTSpacing.s6).frame(maxWidth: .infinity)
        }.background(MTColor.canvas)
      }
    }
    .alert(
      deleteConfirmation.map { "Delete “\($0.title)” forever?" } ?? "Delete forever?",
      isPresented: Binding(
        get: { deleteConfirmation != nil },
        set: { isPresented in
          if !isPresented { deleteConfirmation = nil }
        }
      ),
      presenting: deleteConfirmation
    ) { item in
      Button("Delete forever", role: .destructive) {
        deleteConfirmation = nil
        Task { await controller.deleteForever(item) }
      }
      Button("Cancel", role: .cancel) {
        deleteConfirmation = nil
      }
    } message: { item in
      Text("\(deletionDescription(item)) This cannot be undone.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text("RECOVERABLE BY DESIGN")
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.warm)

        Text("Trash")
          .font(MTTypography.display)
          .foregroundStyle(MTColor.ink)

        Text(
          "Restore something you still need, or permanently remove it with an explicit confirmation."
        )
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
      }

      HStack(spacing: MTSpacing.s3) {
        Image(systemName: "clock")
          .font(.system(size: 17, weight: .medium))

        VStack(alignment: .leading, spacing: 2) {
          Text("30-day retention")
            .font(MTTypography.label)
            .foregroundStyle(MTColor.ink)
          Text("Dates are shown per item")
            .font(.system(size: 10))
            .foregroundStyle(MTColor.inkFaint)
        }

        Spacer()
      }
      .foregroundStyle(MTColor.warm)
      .padding(MTSpacing.s4)
      .background(MTColor.warmSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    }
  }

  private var retentionNote: some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(systemName: "archivebox")
        .font(.system(size: 17))
        .foregroundStyle(MTColor.warm)

      Text(
        "Items remain recoverable during their retention window. Reaching the shown date makes an item eligible for cleanup, but MemoTrail does not claim it was automatically deleted."
      )
      .font(MTTypography.caption)
      .foregroundStyle(MTColor.inkMuted)
      .lineSpacing(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var content: some View {
    if controller.isLoading, !controller.hasLoaded {
      stateView(
        title: "Loading Trash...",
        message: "Checking the items that are still recoverable.",
        systemImage: "arrow.clockwise"
      )
    } else if let loadErrorMessage = controller.loadErrorMessage,
      controller.items.isEmpty
    {
      stateView(
        title: "Trash unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.items.isEmpty {
      stateView(
        title: "Nothing in Trash",
        message:
          "Removed Entries, People, Places, Collections, and individual photos will appear here.",
        systemImage: "trash"
      )
    } else {
      HStack {
        Text("\(controller.items.count) of \(controller.totalCount)")
        Spacer()
        Text("Newest removals first")
      }
      .font(.system(size: 10))
      .foregroundStyle(MTColor.inkFaint)

      LazyVStack(spacing: MTSpacing.s4) {
        ForEach(controller.items) { item in
          TrashItemCard(
            item: item,
            isBusy: controller.isBusy,
            isPending: controller.pendingItemID == item.id,
            onDelete: {
              controller.clearNotice()
              deleteConfirmation = item
            },
            onRestore: {
              Task { await controller.restore(item) }
            }
          )
        }
      }

      if let loadErrorMessage = controller.loadErrorMessage {
        Label(loadErrorMessage, systemImage: "exclamationmark.circle")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }

      if controller.canLoadMore {
        Button("Load more", systemImage: "arrow.down") {
          Task { await controller.loadMore() }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("load-more-trash")
      }
    }
  }

  private func noticeView(_ notice: TrashController.Notice) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(systemName: notice.tone == .success ? "checkmark.circle" : "exclamationmark.circle")
      Text(notice.message)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        controller.clearNotice()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss message")
    }
    .font(MTTypography.caption)
    .foregroundStyle(notice.tone == .success ? MTColor.success : MTColor.warm)
    .padding(MTSpacing.s3)
    .background(
      notice.tone == .success ? MTColor.accentSubtle : MTColor.warmSubtle,
      in: RoundedRectangle(cornerRadius: MTRadius.medium)
    )
    .accessibilityElement(children: .combine)
  }

  private func stateView(title: String, message: String, systemImage: String) -> some View {
    VStack(spacing: MTSpacing.s3) {
      if controller.isLoading {
        ProgressView()
          .tint(MTColor.warm)
      } else {
        Image(systemName: systemImage)
          .font(.system(size: 24))
          .foregroundStyle(MTColor.warm)
      }

      Text(title)
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)
      Text(message)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkMuted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 240)
    .padding(MTSpacing.s6)
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
    }
  }

  private func deletionDescription(_ item: TrashItem) -> String {
    switch item.kind {
    case .collection:
      "Only the Collection and its grouping links will be removed. Your Entries and photos stay in the archive."
    case .attachment:
      "The private photo file and its attachment record will be removed."
    case .person:
      "The Person and their version history will be removed."
    case .entry:
      "The Entry, private photos, relationships, specialized details, and version history will be removed."
    }
  }
}

private struct TrashItemCard: View {
  let item: TrashItem
  let isBusy: Bool
  let isPending: Bool
  let onDelete: () -> Void
  let onRestore: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let signedURL = item.signedURL {
        AsyncImage(url: signedURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          case .failure:
            imagePlaceholder
          case .empty:
            ZStack {
              MTColor.surfaceSubtle
              ProgressView()
                .tint(MTColor.warm)
            }
          @unknown default:
            imagePlaceholder
          }
        }
        .frame(height: 170)
        .clipped()
      }

      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(spacing: MTSpacing.s2) {
          Label(item.displayKind, systemImage: item.kind.systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.warm)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(MTColor.warmSubtle, in: Capsule())

          Spacer()

          Text("Removed \(item.deletionDateLabel)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(MTColor.inkFaint)
        }

        Text(item.title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
          .lineLimit(2)

        if let detail = item.displayDetail {
          Text(detail)
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkMuted)
            .lineSpacing(2)
            .lineLimit(3)
        }

        Label(item.retentionLabel(), systemImage: "clock")
          .font(.system(size: 10))
          .foregroundStyle(MTColor.inkFaint)

        Divider()
          .overlay(MTColor.border)

        HStack(spacing: MTSpacing.s3) {
          Button(action: onRestore) {
            if isPending {
              ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            } else {
              Text("Restore")
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.bordered)
          .tint(MTColor.accent)
          .disabled(isBusy)
          .accessibilityLabel("Restore \(item.title)")

          Button("Delete forever", role: .destructive, action: onDelete)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(isBusy)
            .accessibilityLabel("Delete \(item.title) forever")
        }
      }
      .padding(MTSpacing.s4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var imagePlaceholder: some View {
    ZStack {
      MTColor.surfaceSubtle
      Image(systemName: "photo")
        .font(.system(size: 28))
        .foregroundStyle(MTColor.warm)
    }
  }
}
