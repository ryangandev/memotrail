import SwiftUI
import UIKit

/// A capture saved on this iPhone that has not reached MemoTrail yet. One MemoTrail refused
/// says why, with Copy text and Discard, like Web's Pending sync card.
struct PendingCaptureRow: View {
  let entry: QueuedCapture
  /// Whether a sync run is sending this capture now.
  var isSyncing = false
  /// How many of its photos reached MemoTrail while it syncs.
  var photoProgress: CapturePhotoProgress? = nil
  /// Removes a refused capture after the person confirms, returning whether it was removed.
  var discard: () async -> Bool = { false }

  var body: some View {
    let occurrence = entry.effectiveOccurrence
    let title = entryDisplayTitle(entry.title, occurrence)
    VStack(alignment: .leading, spacing: 0) {
      // An untitled capture is already named by its date, like Web.
      if entry.title?.trimmed.nonEmpty != nil {
        Text(occurrence.displayLabel)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkFaint)
          .padding(.bottom, MTSpacing.s2)
      }
      Text(title)
        .font(MTFont.itemTitle)
        .foregroundStyle(MTColor.ink)
      if let excerpt = entry.body.trimmed.nonEmpty {
        Text(excerpt.flowingLines)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
          .lineLimit(3)
          .padding(.top, MTSpacing.s1_5)
      }
      MTFlowLayout(spacing: MTSpacing.s1_5) {
        if entry.rejection != nil {
          MTBadge(title: "Not accepted", tone: .warm)
        } else if isSyncing {
          MTBadge(title: "Syncing…", tone: .neutral)
        } else {
          MTBadge(title: "On this iPhone")
        }
        if !entry.attachments.isEmpty {
          MTBadge(
            title: countLabel(entry.attachments.count, "photo"),
            tone: .neutral)
        }
      }
      .padding(.top, MTSpacing.s3)
      if isSyncing, let photoProgress {
        MTUploadProgress(completed: photoProgress.completed, total: photoProgress.total)
          .padding(.top, MTSpacing.s3)
      }
      if let rejection = entry.rejection {
        CaptureRecoveryActions(
          message: rejection.message, text: entry.copyableText,
          copyLabel: "Copy the text of \(title)", discardLabel: "Discard \(title)",
          confirmTitle: "Discard this pending Entry?",
          confirmMessage: "Its text\(entry.attachments.isEmpty ? "" : " and photos") will be "
            + "removed from this iPhone. This cannot be undone.",
          discardedMessage: "Pending Entry discarded.", discard: discard)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(entry.rejection == nil ? Color.clear : MTColor.captureRefused)
    .accessibilityElement(children: entry.rejection == nil ? .combine : .contain)
  }
}

/// A capture stored on this iPhone that this version cannot read, like Web's unreadable card.
/// It is kept, with Copy text and Discard, until the person removes it.
struct UnreadableCaptureRow: View {
  let capture: UnreadableCapture
  var discard: () async -> Bool = { false }

  static let message =
    "This Entry was saved on this iPhone, but this version of MemoTrail cannot read it. "
    + "It is kept until you discard it."

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MTBadge(title: "Could not be read", tone: .warm)
      // Its title and note keep their own lines, so the two never read as one sentence.
      Text(capture.text)
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body)
        .lineLimit(6)
        .padding(.top, MTSpacing.s3)
      CaptureRecoveryActions(
        message: Self.message, text: capture.text,
        copyLabel: "Copy the text of this saved Entry",
        discardLabel: "Discard this saved Entry",
        confirmTitle: "Discard this saved Entry?",
        confirmMessage: "It will be removed from this iPhone, along with any photos it holds. "
          + "This cannot be undone.",
        discardedMessage: "Saved Entry discarded.", discard: discard)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(MTColor.captureRefused)
    .accessibilityElement(children: .contain)
  }
}

/// Why a capture stays on this iPhone, with Copy text and a confirmed Discard, like Web's
/// `RejectedCapture` and `UnreadableCaptureActions`.
private struct CaptureRecoveryActions: View {
  let message: String
  let text: String
  let copyLabel: String
  let discardLabel: String
  let confirmTitle: String
  let confirmMessage: String
  let discardedMessage: String
  let discard: () async -> Bool
  @State private var isConfirmingDiscard = false
  @State private var isDiscarding = false

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(message)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.warm)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: MTSpacing.s2) {
        if !text.isEmpty {
          Button(action: copyText) {
            Label("Copy text", icon: .copy)
          }
          .mtButtonStyle(.secondary, size: .small)
          .disabled(isDiscarding)
          .accessibilityLabel(copyLabel)
          .accessibilityIdentifier("capture-copy-text")
        }
        Button {
          isConfirmingDiscard = true
        } label: {
          Label("Discard", icon: .trash)
        }
        .mtButtonStyle(.danger, size: .small, isLoading: isDiscarding)
        .accessibilityLabel(discardLabel)
        .accessibilityIdentifier("capture-discard")
        .confirmationDialog(
          confirmTitle, isPresented: $isConfirmingDiscard, titleVisibility: .visible
        ) {
          Button("Discard", role: .destructive) {
            Task { await confirmDiscard() }
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(confirmMessage)
        }
      }
    }
    .padding(.top, MTSpacing.s3)
  }

  private func copyText() {
    UIPasteboard.general.string = text
    MTToastCenter.shared.success("Text copied.")
  }

  private func confirmDiscard() async {
    guard !isDiscarding else { return }
    isDiscarding = true
    defer { isDiscarding = false }
    if await discard() {
      MTToastCenter.shared.info(discardedMessage)
    } else {
      MTToastCenter.shared.error(
        "MemoTrail could not discard this Entry from this iPhone. Try again.")
    }
  }
}

/// Web `PendingCaptureList`: every capture still on this iPhone, oldest first, then the stored
/// captures this version cannot read.
struct PendingCaptureList: View {
  @Bindable var controller: CaptureController

  var body: some View {
    let entries = controller.pendingEntries
    let unreadable = controller.unreadableCaptures
    VStack(spacing: 0) {
      ForEach(entries) { entry in
        let isSyncing = controller.syncingEntryID == entry.id
        PendingCaptureRow(
          entry: entry, isSyncing: isSyncing,
          photoProgress: isSyncing ? controller.photoUploadProgress : nil
        ) {
          await controller.discardRejected(entry.id)
        }
        if entry.id != entries.last?.id || !unreadable.isEmpty {
          Divider().overlay(MTColor.border)
        }
      }
      ForEach(unreadable) { capture in
        UnreadableCaptureRow(capture: capture) { await controller.discardUnreadable(capture) }
        if capture.id != unreadable.last?.id {
          Divider().overlay(MTColor.border)
        }
      }
    }
    .accessibilityIdentifier("capture-pending-list")
  }
}

/// Web's Retry now: sends waiting captures at once, and stays out while only captures that
/// never sync again remain.
struct PendingCaptureRetryButton: View {
  @Bindable var controller: CaptureController

  var body: some View {
    if controller.waitingEntryCount > 0 {
      Button {
        Task { await controller.retryNow() }
      } label: {
        Label(controller.isSyncing ? "Syncing…" : "Retry now", icon: .refresh)
      }
      .mtButtonStyle(.secondary)
      .disabled(controller.isSyncing)
      .accessibilityIdentifier("capture-pending-retry")
    }
  }
}

/// Web `SyncStatus`'s Pending sync dialog: every capture still on this iPhone, with Retry now
/// while some wait and Copy text and Discard for the ones MemoTrail refused or cannot read.
struct PendingCapturesSheet: View {
  @Bindable var controller: CaptureController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    MTSheet(
      title: "Pending sync", description: controller.pendingDescription,
      closeLabel: "Close pending sync", closeIdentifier: "capture-pending-close",
      message: controller.captureError
    ) {
      PendingCaptureList(controller: controller)
    } footer: {
      PendingCaptureRetryButton(controller: controller)
    }
    // Once everything syncs or is discarded, the list closes, like Web.
    .onChange(of: controller.isQueueEmpty) { _, isEmpty in
      if isEmpty { dismiss() }
    }
    .task { controller.refreshQueue() }
  }
}

extension CaptureController {
  /// Whether nothing at all is stored on this iPhone, readable or not.
  var isQueueEmpty: Bool { pendingEntries.isEmpty && unreadableCaptures.isEmpty }

  /// Web's Pending sync description.
  var pendingDescription: String {
    let waiting = waitingEntryCount
    let rejected = rejectedEntryCount
    let unreadable = unreadableCaptures.count
    return [
      waiting > 0
        ? "\(countLabel(waiting, "Entry")) saved on this iPhone will sync when MemoTrail can be "
          + "reached." : nil,
      rejected > 0
        ? "MemoTrail did not accept \(countLabel(rejected, "Entry")); copy what you want to keep, "
          + "then discard \(rejected == 1 ? "it" : "them")." : nil,
      unreadable > 0
        ? "\(countLabel(unreadable, "saved Entry", plural: "saved Entries")) on this iPhone could "
          + "not be read; copy what you want to keep, then discard \(unreadable == 1 ? "it" : "them")."
        : nil,
    ].compactMap { $0 }.joined(separator: " ")
  }

  /// Web `SyncStatusButton`'s label: the counts of waiting, refused, and unreadable captures.
  var indicatorLabel: String {
    let rejected = rejectedEntryCount
    let unreadable = unreadableCaptures.count
    return [
      waitingEntryCount > 0 ? "\(waitingEntryCount) pending" : nil,
      rejected > 0 ? "\(rejected) not accepted" : nil,
      unreadable > 0 ? "\(unreadable) unreadable" : nil,
    ].compactMap { $0 }.joined(separator: " · ")
  }

  /// Whether a capture needs the person: refused by MemoTrail or unreadable here.
  var needsAttention: Bool { rejectedEntryCount > 0 || !unreadableCaptures.isEmpty }
}

extension String {
  /// Note line breaks flow into one excerpt, like HTML text in the Web cards.
  fileprivate var flowingLines: String {
    split(whereSeparator: \.isNewline).joined(separator: " ")
  }
}
