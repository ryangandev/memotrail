@preconcurrency import Supabase
import SwiftUI

/// Web `/first-times` at phone width: the archive of First Times as record cards that open each
/// First Time's own page, and Add First Time.
struct FirstTimesView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: FirstTimesController
  @State private var isAdding = false
  @State private var openedFirstTimeID: UUID?

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
        .accessibilityIdentifier("add-first-time")
      }
      summary
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("First Times")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      FirstTimeEditorSheet(controller: controller, entry: nil)
    }
    .navigationDestination(item: $openedFirstTimeID) { id in
      FirstTimeDetailView(controller: controller, client: client, ownerID: ownerID, entryID: id)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(count(controller.entries.count, "First Time"))
      Text("·").accessibilityHidden(true)
      Text(count(controller.photoCount, "photo"))
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.caption.weight(.regular))
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
      .frame(maxWidth: .infinity, minHeight: 180)
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
        columns: [GridItem(.adaptive(minimum: 300), spacing: MTSpacing.s5)],
        spacing: MTSpacing.s3
      ) {
        ForEach(Array(controller.entries.enumerated()), id: \.element.id) { index, entry in
          FirstTimeCard(entry: entry, index: index) { openedFirstTimeID = entry.id }
        }
      }
      .padding(.top, MTSpacing.s4)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("First Times archive")
    }
  }

  private func count(_ value: Int, _ singular: String) -> String {
    "\(value) \(value == 1 ? singular : "\(singular)s")"
  }
}

/// Web `FirstTimeCard`: a cover photo, else a map of its Location, else its place in the
/// archive; then the date, title, Location, a short reflection, and organization.
private struct FirstTimeCard: View {
  let entry: FirstTimeEntry
  let index: Int
  let open: () -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let photos = entry.originalAttachments
    MTRecordCard(accessibilityLabel: "\(entry.title), \(entry.displayDate)", action: open) {
      MTRecordCardVisual {
        if let cover = photos.first {
          MTRemoteImage(url: cover.signedURL)
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
        Text(entry.displayDate.uppercased())
          .font(.caption2.monospaced())
          .tracking(0.35)
          .foregroundStyle(MTColor.warm)
        Text(entry.title)
          .font(
            .system(horizontalSizeClass == .regular ? .title2 : .title3, design: .serif)
              .weight(.medium)
          )
          .tracking(-0.4)
          .foregroundStyle(MTColor.ink)
          .multilineTextAlignment(.leading)
          .padding(.top, MTSpacing.s1)
        if let location = entry.location {
          Label(location.name, icon: .map)
            .labelStyle(MTInlineIconLabelStyle())
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s2)
        }
        if let body = entry.body.trimmed.nonEmpty {
          Text(body)
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s2)
        }
        MTRecordCardFooter(
          status: entry.inboxStatus == "unreviewed" ? [("In Inbox", .warm)] : [],
          collectionNames: entry.collectionNames, tagNames: entry.tagNames)
      }
    }
  }

  /// Web `cardIndexFallback`: the card's place in the archive on a warm wash.
  private var indexMark: some View {
    Text(String(format: "%02d", index + 1))
      .font(.system(.title3, design: .monospaced))
      .foregroundStyle(MTColor.warm)
      .padding(.horizontal, MTSpacing.s5)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .background(
        LinearGradient(
          colors: [MTColor.warmSubtle, MTColor.surface], startPoint: .topLeading,
          endPoint: .bottomTrailing))
  }
}
