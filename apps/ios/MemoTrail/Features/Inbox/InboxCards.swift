import SwiftUI

/// A calm message inside an Inbox list: loading trouble, an empty Inbox, or waiting to sync.
struct InboxMessage<Actions: View>: View {
  let icon: MTIcon
  let title: String
  let message: String
  private let actions: Actions

  init(icon: MTIcon, title: String, message: String, @ViewBuilder actions: () -> Actions) {
    self.icon = icon
    self.title = title
    self.message = message
    self.actions = actions()
  }

  var body: some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(MTColor.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        Text(title)
          .font(.system(.body, design: .serif).weight(.medium))
          .foregroundStyle(MTColor.ink)
        Text(message)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkFaint)
          .mtLineSpacing(MTLineHeight.body)
        actions.padding(.top, MTSpacing.s2)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, MTSpacing.s6)
    .padding(.vertical, MTSpacing.s8)
    .accessibilityElement(children: .contain)
  }
}

extension InboxMessage where Actions == EmptyView {
  init(icon: MTIcon, title: String, message: String) {
    self.init(icon: icon, title: title, message: message) { EmptyView() }
  }
}

extension View {
  /// Web's recoverable Move to Trash confirmation for one capture, anchored to its button.
  func captureTrashConfirmation(
    _ title: String, isPresented: Binding<Bool>, confirm: @escaping () -> Void
  ) -> some View {
    confirmationDialog(
      "Move “\(title)” to Trash?", isPresented: isPresented, titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive, action: confirm)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can restore it later from Trash.")
    }
  }
}

/// A capture waiting for review, like a Web `EntryReviewList` card: its date, title, note,
/// organization, then Move to Trash and Organize.
struct InboxCaptureRow: View {
  let entry: InboxEntry
  let isTrashing: Bool
  let organize: () -> Void
  /// Runs after the person confirms.
  let moveToTrash: () -> Void
  @State private var isConfirmingTrash = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(entry.occurrence.displayLabel)
        .font(MTFont.caption.weight(.regular))
        .foregroundStyle(MTColor.inkFaint)
      Text(entry.displayTitle)
        .font(.system(.body, design: .serif).weight(.medium))
        .foregroundStyle(MTColor.ink)
        .padding(.top, MTSpacing.s2)
      if let excerpt = entry.displayExcerpt {
        Text(excerpt.flowingLines)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
          .padding(.top, 6)
      }
      MTFlowLayout(spacing: 6) {
        MTBadge(title: "Needs review", tone: .warm)
        if entry.itemKind != .entry || entry.itemSubtype == "first_time" {
          MTBadge(title: entry.itemKind.displayName, tone: .neutral)
          MTBadge(title: entry.itemKind.displayName(subtype: entry.itemSubtype), tone: .neutral)
        }
        ForEach(entry.collectionNames, id: \.self) { MTBadge(title: $0, tone: .neutral) }
        ForEach(entry.tagNames.prefix(3), id: \.self) { MTBadge(title: "#\($0)", tone: .neutral) }
        if entry.tagNames.count > 3 {
          MTBadge(title: "+\(entry.tagNames.count - 3)", tone: .neutral)
        }
      }
      .padding(.top, MTSpacing.s3)
      HStack(spacing: MTSpacing.s2) {
        Spacer(minLength: 0)
        Button {
          isConfirmingTrash = true
        } label: {
          Label("Move to Trash", icon: .trash)
        }
        .mtButtonStyle(.ghost, isLoading: isTrashing)
        .accessibilityLabel("Move \(entry.displayTitle) to Trash")
        .captureTrashConfirmation(
          entry.displayTitle, isPresented: $isConfirmingTrash, confirm: moveToTrash)
        Button(action: organize) {
          HStack(spacing: MTSpacing.s2) {
            Text("Organize")
            Image(.chevron).font(.system(size: 12, weight: .semibold))
          }
        }
        .mtButtonStyle(.secondary)
        .accessibilityLabel("Organize \(entry.displayTitle)")
        .accessibilityIdentifier("review-entry-\(entry.id.uuidString.lowercased())")
      }
      .padding(.top, MTSpacing.s3)
      .disabled(isTrashing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
  }
}

/// A capture saved on this iPhone that has not reached MemoTrail yet.
struct PendingCaptureRow: View {
  let entry: QueuedInboxEntry

  var body: some View {
    let presented = entry.presentedEntry
    VStack(alignment: .leading, spacing: 0) {
      Text(presented.occurrence.displayLabel)
        .font(MTFont.caption.weight(.regular))
        .foregroundStyle(MTColor.inkFaint)
      Text(presented.displayTitle)
        .font(.system(.body, design: .serif).weight(.medium))
        .foregroundStyle(MTColor.ink)
        .padding(.top, MTSpacing.s2)
      if let excerpt = presented.displayExcerpt {
        Text(excerpt.flowingLines)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
          .lineLimit(3)
          .padding(.top, 6)
      }
      MTFlowLayout(spacing: 6) {
        MTBadge(title: "On this iPhone")
        if !entry.attachments.isEmpty {
          MTBadge(
            title:
              "\(entry.attachments.count) \(entry.attachments.count == 1 ? "photo" : "photos")",
            tone: .neutral)
        }
      }
      .padding(.top, MTSpacing.s3)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .accessibilityElement(children: .combine)
  }
}

extension String {
  /// Note line breaks flow into one excerpt, like HTML text in the Web cards.
  fileprivate var flowingLines: String {
    split(whereSeparator: \.isNewline).joined(separator: " ")
  }
}
