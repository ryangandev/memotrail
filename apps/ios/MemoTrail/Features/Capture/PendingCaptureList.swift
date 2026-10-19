import SwiftUI
import UIKit

/// A capture saved on this iPhone that has not reached MemoTrail yet. One MemoTrail refused
/// says why, with Copy text and Discard, like Web's Pending sync card.
struct PendingCaptureRow: View {
  let entry: QueuedCapture
  /// Removes a refused capture after the person confirms, returning whether it was removed.
  var discard: () async -> Bool = { false }
  @State private var isConfirmingDiscard = false
  @State private var isDiscarding = false

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
        if entry.rejection == nil {
          MTBadge(title: "On this iPhone")
        } else {
          MTBadge(title: "Not accepted", tone: .warm)
        }
        if !entry.attachments.isEmpty {
          MTBadge(
            title: countLabel(entry.attachments.count, "photo"),
            tone: .neutral)
        }
      }
      .padding(.top, MTSpacing.s3)
      if let rejection = entry.rejection {
        rejectionDetails(rejection, title: title)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(entry.rejection == nil ? Color.clear : MTColor.captureRefused)
    .accessibilityElement(children: entry.rejection == nil ? .combine : .contain)
  }

  private func rejectionDetails(_ rejection: QueuedCaptureRejection, title: String) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(rejection.message)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.warm)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: MTSpacing.s2) {
        if !entry.copyableText.isEmpty {
          Button(action: copyText) {
            Label("Copy text", icon: .copy)
          }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityLabel("Copy the text of \(title)")
        }
        Button {
          isConfirmingDiscard = true
        } label: {
          Label("Discard", icon: .trash)
        }
        .mtButtonStyle(.danger, size: .small, isLoading: isDiscarding)
        .accessibilityLabel("Discard \(title)")
        .confirmationDialog(
          "Discard this pending Entry?", isPresented: $isConfirmingDiscard,
          titleVisibility: .visible
        ) {
          Button("Discard", role: .destructive) {
            Task { await confirmDiscard() }
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "Its text\(entry.attachments.isEmpty ? "" : " and photos") will be removed from "
              + "this iPhone. This cannot be undone.")
        }
      }
    }
    .padding(.top, MTSpacing.s3)
  }

  private func copyText() {
    UIPasteboard.general.string = entry.copyableText
    MTToastCenter.shared.success("Text copied.")
  }

  private func confirmDiscard() async {
    guard !isDiscarding else { return }
    isDiscarding = true
    defer { isDiscarding = false }
    if await discard() {
      MTToastCenter.shared.info("Pending Entry discarded.")
    } else {
      MTToastCenter.shared.error(
        "MemoTrail could not discard this Entry from this iPhone. Try again.")
    }
  }
}

/// Web `SyncStatus`'s Pending sync dialog: every capture still on this iPhone, with Retry now
/// while some wait and Copy text and Discard for the ones MemoTrail refused.
struct PendingCapturesSheet: View {
  @Bindable var controller: CaptureController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    MTSheet(
      title: "Pending sync", description: description, closeLabel: "Close pending sync",
      closeIdentifier: "capture-pending-close", message: controller.captureError
    ) {
      VStack(spacing: 0) {
        ForEach(controller.pendingEntries) { entry in
          PendingCaptureRow(entry: entry) { await controller.discardRejected(entry.id) }
          if entry.id != controller.pendingEntries.last?.id {
            Divider().overlay(MTColor.border)
          }
        }
      }
      .accessibilityIdentifier("capture-pending-list")
    } footer: {
      if controller.waitingEntryCount > 0 {
        Button {
          Task { await controller.synchronizePendingEntries() }
        } label: {
          Label(controller.isSyncing ? "Syncing…" : "Retry now", icon: .refresh)
        }
        .mtButtonStyle(.secondary)
        .disabled(controller.isSyncing)
        .accessibilityIdentifier("capture-pending-retry")
      }
    }
    // Once everything syncs or is discarded, the list closes, like Web.
    .onChange(of: controller.pendingEntries.isEmpty) { _, isEmpty in
      if isEmpty { dismiss() }
    }
  }

  /// Web's Pending sync description.
  private var description: String {
    let waiting = controller.waitingEntryCount
    let rejected = controller.rejectedEntryCount
    return [
      waiting > 0
        ? "\(countLabel(waiting, "Entry")) saved on this iPhone will sync when MemoTrail can be "
          + "reached." : nil,
      rejected > 0
        ? "MemoTrail did not accept \(countLabel(rejected, "Entry")); copy what you want to keep, "
          + "then discard \(rejected == 1 ? "it" : "them")." : nil,
    ].compactMap { $0 }.joined(separator: " ")
  }
}

extension String {
  /// Note line breaks flow into one excerpt, like HTML text in the Web cards.
  fileprivate var flowingLines: String {
    split(whereSeparator: \.isNewline).joined(separator: " ")
  }
}
