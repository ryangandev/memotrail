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
    let presented = entry.presentedEntry
    VStack(alignment: .leading, spacing: 0) {
      Text(presented.occurrence.displayLabel)
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkFaint)
      Text(presented.displayTitle)
        .font(MTFont.itemTitle)
        .foregroundStyle(MTColor.ink)
        .padding(.top, MTSpacing.s2)
      if let excerpt = presented.displayExcerpt {
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
        rejectionDetails(rejection, title: presented.displayTitle)
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

extension String {
  /// Note line breaks flow into one excerpt, like HTML text in the Web cards.
  fileprivate var flowingLines: String {
    split(whereSeparator: \.isNewline).joined(separator: " ")
  }
}
