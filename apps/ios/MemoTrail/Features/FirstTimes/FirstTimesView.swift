@preconcurrency import Supabase
import SwiftUI

/// Web `/first-times` at phone width: the Entries marked First Time as record cards that open
/// each one's Item page, and Add First Time.
struct FirstTimesView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: FirstTimesController
  @State private var isAdding = false
  @Environment(AppNavigator.self) private var navigator

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: FirstTimesController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "A record of beginnings", title: "First Times",
        description: "Keep the small beginnings and major milestones worth finding again."
      ) {
        Button {
          isAdding = true
        } label: {
          Label("Add First Time", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("firsttimes-add")
      }
      // The counts say what is saved, so they wait for a successful load.
      if controller.showsSummary { summary }
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("First Times")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      EntryEditorSheet(client: client, ownerID: ownerID, mode: .new(.firstTime)) { _ in
        navigator.entriesChanged()
      }
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
    .onChange(of: navigator.entriesRevision) { Task { await controller.load() } }
  }

  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(countLabel(controller.entries.count, "First Time"))
      MTFlowSeparator()
      Text(countLabel(controller.photoCount, "photo"))
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.detail)
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("First Times summary")
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your First Times...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "First Times unavailable", message: message, icon: .star) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
      .padding(.top, MTSpacing.s4)
    } else if controller.entries.isEmpty {
      MTEmptyState(
        title: "Start with a first worth remembering",
        message: "Only a title is required. Dates, notes, and photos can come later.",
        icon: .star
      ) {
        isAdding = true
      }
      .padding(.top, MTSpacing.s4)
    } else {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: MTLayout.Grid.record), spacing: MTSpacing.s5)],
        spacing: MTSpacing.s3
      ) {
        ForEach(Array(controller.entries.enumerated()), id: \.element.id) { index, entry in
          FirstTimeCard(entry: entry, index: index, photoURLs: controller.photoURLs) {
            // First Times is a page in the More tab, so its Items open on that stack.
            navigator.morePath.append(ItemLink(entryID: entry.id))
          }
        }
      }
      .padding(.top, MTSpacing.s4)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("First Times")
    }
  }
}

/// Web `FirstTimeCard`: a cover photo, else a map of its Location, else its place in the
/// archive; then the date, title, Location, a short reflection, and organization.
private struct FirstTimeCard: View {
  let entry: FirstTimeRow
  let index: Int
  let photoURLs: [String: URL]
  let open: () -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let photos = entry.attachments.filter { $0.variant == "original" }
    MTRecordCard(accessibilityLabel: "\(entry.displayTitle), \(entry.dateLabel)", action: open) {
      MTRecordCardVisual {
        if let cover = photos.first {
          MTRemoteImage(url: photoURLs[cover.objectPath])
        } else {
          MTLocationSnapshot(
            latitude: entry.location?.latitude, longitude: entry.location?.longitude
          ) {
            indexMark
          }
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if photos.count > 1 {
          MTBadge(title: "\(photos.count) photos", tone: .inverse, size: .micro, uppercase: true)
            .padding(MTSpacing.s3)
        }
      }
      MTRecordCardBody {
        Text(entry.dateLabel.uppercased())
          .mtTextRole(.firstTimeDate)
          .foregroundStyle(MTColor.warm)
        Text(entry.displayTitle)
          .mtTextRole(horizontalSizeClass == .regular ? .recordCardTitle : .recordCardTitleCompact)
          .foregroundStyle(MTColor.ink)
          .multilineTextAlignment(.leading)
          .padding(.top, MTSpacing.s1)
        if let location = entry.location {
          Label(location.label, icon: .map)
            .labelStyle(MTInlineIconLabelStyle())
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s2)
        }
        if let body = entry.body.trimmed.nonEmpty {
          Text(body)
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s2)
        }
        MTRecordCardFooter(tagNames: entry.tagNames)
      }
    }
  }

  /// Web `cardIndexFallback`: the card's place in the archive on a warm wash.
  private var indexMark: some View {
    Text(String(format: "%02d", index + 1))
      .font(MTFont.listIndex)
      .foregroundStyle(MTColor.warm)
      .padding(.horizontal, MTSpacing.s5)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .background(
        LinearGradient(
          colors: [MTColor.warmSubtle, MTColor.surface], startPoint: .topLeading,
          endPoint: .bottomTrailing))
  }
}
