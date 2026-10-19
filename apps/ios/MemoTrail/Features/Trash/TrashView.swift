@preconcurrency import Supabase
import SwiftUI

/// Web `/trash`: removed Entries and photos, newest first. Each restores or, after an explicit
/// confirmation, is deleted forever; Empty Trash deletes a prepared list.
struct TrashView: View {
  @State private var controller: TrashController
  @State private var confirmation: TrashItem?
  @State private var batchTask: Task<Void, Never>?
  /// The Entries revision this page last reacted to, so its own changes reload it only once.
  @State private var seenRevision = 0
  @Environment(AppNavigator.self) private var navigator

  init(client: SupabaseClient, ownerID: UUID) {
    _controller = State(initialValue: TrashController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .standard, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Recoverable by design", title: "Trash",
        description:
          "Restore something you still need, or permanently remove it with an explicit confirmation."
      ) {
        retentionBadge
      }
      retentionNote
      if controller.loadErrorMessage == nil, controller.totalCount > 0 {
        Button(controller.isPreparingEmptyTrash ? "Preparing Trash…" : "Empty Trash") {
          batchTask = Task { announce(await controller.prepareEmptyTrash()) }
        }
        .mtButtonStyle(.danger)
        .disabled(controller.isBusy || confirmation != nil)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("empty-trash")
      }
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("Trash")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if !controller.hasLoaded { await controller.load() }
      // Like Web, opening Trash finishes removing the files of anything deleted forever.
      await controller.finishPendingMediaRemoval()
    }
    .onChange(of: navigator.entriesRevision) { _, revision in
      // An Entry moved to Trash, restored, or synced elsewhere shows at once.
      guard revision != seenRevision else { return }
      seenRevision = revision
      Task { await controller.load() }
    }
    .onDisappear {
      batchTask?.cancel()
      controller.cancelEmptyTrash()
    }
    .sheet(item: $confirmation) { item in
      DeleteForeverSheet(item: item, controller: controller) { announce($0) }
    }
    .sheet(
      isPresented: Binding(
        get: { controller.emptySnapshot != nil },
        set: { if !$0 { controller.cancelEmptyTrash() } })
    ) {
      EmptyTrashSheet(controller: controller, reviewsExist: controller.reviewsExist) {
        batchTask = Task { announce(await controller.emptyTrash()) }
      }
    }
  }

  /// Web's header badge: the retention window, with each item's own dates below.
  private var retentionBadge: some View {
    HStack(spacing: MTSpacing.s3) {
      Image(.clock).font(.mtIcon(MTSize.Icon.s17, weight: .medium))
      VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
        Text("30-day retention")
          .font(MTFont.caption)
          .foregroundStyle(MTColor.ink)
        Text("Dates are shown per item")
          .font(MTFont.note)
          .foregroundStyle(MTColor.inkFaint)
      }
    }
    .foregroundStyle(MTColor.warm)
    .padding(.vertical, MTSpacing.s3)
    .padding(.horizontal, MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.warmSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .combine)
  }

  private var retentionNote: some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(.archive)
        .font(.mtIcon(MTSize.Icon.s17))
        .foregroundStyle(MTColor.warm)
        .accessibilityHidden(true)
      Text(
        "Items remain recoverable during their retention window. Reaching the shown date makes an item eligible for cleanup, but this screen does not claim it was automatically deleted."
      )
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
  }

  @ViewBuilder private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading Trash...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
    } else if let message = controller.loadErrorMessage, controller.items.isEmpty {
      MTEmptyState(title: "Trash is unavailable", message: message, icon: .refresh) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.items.isEmpty {
      MTEmptyState(
        title: "Nothing in Trash",
        message:
          "Removed Entries and individual photos will appear here. Legacy records remain recoverable too.",
        icon: .trash)
    } else {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack {
          Text("1-\(controller.items.count) of \(controller.totalCount)")
            .foregroundStyle(MTColor.inkMuted)
          Spacer(minLength: MTSpacing.s2)
          Text("Newest removals first")
            .foregroundStyle(MTColor.inkFaint)
        }
        .font(MTFont.detail)
        ForEach(controller.items) { item in
          TrashItemCard(
            item: item, timezone: controller.timezone, renderedAt: controller.renderedAt,
            isDisabled: controller.isBusy || confirmation != nil,
            isRestoring: controller.pendingItemID == item.id
          ) {
            Task {
              let notice = await controller.restore(item)
              announce(notice)
              if notice?.tone == .success { restored() }
            }
          } delete: {
            confirmation = item
          }
        }
        if controller.items.count < controller.totalCount || controller.loadErrorMessage != nil {
          MTLoadMore(isLoading: controller.isLoading, message: controller.loadErrorMessage) {
            await controller.loadMore()
          }
        }
      }
    }
  }

  /// A restored Entry or photo is back in Library, Tags, and the other tabs.
  private func restored() {
    navigator.entriesChanged()
    seenRevision = navigator.entriesRevision
  }

  private func announce(_ notice: TrashController.Notice?) {
    guard let notice else { return }
    switch notice.tone {
    case .success: MTToastCenter.shared.success(notice.message)
    case .error: MTToastCenter.shared.error(notice.message)
    }
  }
}

/// Web's Trash card: the photo or the item's mark, its Kind, removal date, title, detail, and
/// how long it stays restorable, then Restore and Delete forever.
private struct TrashItemCard: View {
  let item: TrashItem
  let timezone: String
  let renderedAt: Date
  let isDisabled: Bool
  let isRestoring: Bool
  let restore: () -> Void
  let delete: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        visual
          .frame(width: MTLayout.RecordCard.trashVisualWidth)
          .frame(maxHeight: .infinity)
          .clipped()
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          MTFlowLayout(spacing: MTSpacing.s2) {
            MTBadge(title: item.displayKind, tone: .warm)
            Text("Removed \(item.deletionDateLabel(timezone: timezone))")
              .font(MTFont.note)
              .foregroundStyle(MTColor.inkFaint)
          }
          Text(item.title)
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, MTSpacing.s3)
          if let detail = item.displayDetail {
            Text(detail)
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
              .lineLimit(2)
              .padding(.top, MTSpacing.s1_25)
          }
          retention
            .padding(.top, MTSpacing.s3)
        }
        .padding(MTSpacing.s3)
        .frame(
          maxWidth: .infinity, minHeight: MTLayout.RecordCard.trashMinHeight, alignment: .topLeading
        )
      }
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: MTSpacing.s2) {
        Button(isRestoring ? "Restoring..." : "Restore", action: restore)
          .mtButtonStyle(.secondary, fillsWidth: true)
          .accessibilityLabel("Restore \(item.title)")
        Button("Delete forever", action: delete)
          .mtButtonStyle(.danger, fillsWidth: true)
          .accessibilityLabel("Delete \(item.title) forever")
      }
      .disabled(isDisabled)
      .padding(MTSpacing.s3)
      .overlay(alignment: .top) { MTListDivider() }
    }
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var visual: some View {
    ZStack {
      Rectangle().fill(MTColor.surfaceSubtle)
      Rectangle().fill(
        LinearGradient(
          colors: [MTColor.warmWash, .clear], startPoint: .topLeading,
          endPoint: UnitPoint(x: 0.75, y: 0.9)))
      if let url = item.signedURL {
        MTRemoteImage(url: url, accessibilityLabel: "")
      } else {
        Image(item.kind == .attachment ? .photo : .timeline)
          .font(.mtIcon(MTSize.Icon.s23))
          .foregroundStyle(MTColor.warm)
      }
    }
  }

  /// Web's retention line: how long the item stays restorable, then the date.
  private var retention: some View {
    let retention = item.retention(referenceDate: renderedAt, timezone: timezone)
    return HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
      Image(.clock).font(.mtIcon(MTSize.Icon.s11))
      if let date = retention.date {
        Text("\(retention.status) \(Text(date).foregroundStyle(MTColor.inkMuted))")
      } else {
        Text(retention.status)
      }
    }
    .font(MTFont.note)
    .foregroundStyle(MTColor.inkFaint)
  }
}

/// Web's Delete forever dialog, which stays open until the deletion is confirmed.
private struct DeleteForeverSheet: View {
  let item: TrashItem
  let controller: TrashController
  let announce: (TrashController.Notice?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var isDeleting = false

  var body: some View {
    MTSheet(
      eyebrow: "Permanent action", title: "Delete “\(item.title)” forever?",
      description: item.deletionConfirmation(reviewsExist: controller.reviewsExist),
      closeLabel: "Close", closeIdentifier: "close-delete-forever", size: .fitted,
      isBusy: isDeleting
    ) {
      EmptyView()
    } footer: {
      MTSheetFooter {
        EmptyView()
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(isDeleting ? "Deleting..." : "Delete forever") {
          Task {
            isDeleting = true
            let notice = await controller.deleteForever(item)
            isDeleting = false
            announce(notice)
            if notice.tone == .success { dismiss() }
          }
        }
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("confirm-delete-forever")
      }
    }
  }
}

/// Web's Empty Trash dialog: the prepared list only, with progress while it deletes.
private struct EmptyTrashSheet: View {
  let controller: TrashController
  let reviewsExist: Bool
  let confirm: () -> Void

  var body: some View {
    let count = controller.emptySnapshot?.count ?? controller.emptyTotal
    MTSheet(
      eyebrow: "Permanent action", title: "Empty \(countLabel(count, "item")) from Trash?",
      description:
        "This includes all Trash pages, not just the visible items. Their records and private photos will be permanently removed.\(reviewsExist ? " \(ReviewDeletion.sentence)" : "") This cannot be undone.",
      closeLabel: "Close", closeIdentifier: "close-empty-trash", size: .fitted,
      isBusy: controller.isEmptying
    ) {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        Text(
          "Only this prepared list is included. Items added to Trash later are not deleted. If an item changes or a request cannot be confirmed, deletion stops for a fresh review."
        )
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
        if controller.isEmptying {
          Text(
            "\(controller.emptyProgress) of \(controller.emptyTotal) confirmed deleted. Keep this page open."
          )
          .font(MTFont.caption)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.updatesFrequently)
        }
      }
    } footer: {
      MTSheetFooter {
        EmptyView()
      } cancel: {
        Button("Cancel") { controller.cancelEmptyTrash() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(
          controller.isEmptying ? "Emptying Trash…" : "Permanently delete confirmed items",
          action: confirm
        )
        .mtButtonStyle(.danger)
        .accessibilityIdentifier("confirm-empty-trash")
      }
    }
  }
}
