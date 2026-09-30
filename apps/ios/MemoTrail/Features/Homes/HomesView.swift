@preconcurrency import Supabase
import SwiftUI

/// Web `/homes` at phone width: current and earlier Homes as record cards that open each Home's
/// own page, and Add Home.
struct HomesView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: ResidenceController
  @State private var isAdding = false
  @State private var openedHomeID: UUID?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: ResidenceController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "The places that held your life", title: "Homes",
        description:
          "Keep each residence as a Home Entity, with the dates, location, and memories that made it yours."
      ) {
        Button {
          isAdding = true
        } label: {
          Label("Add Home", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("add-home")
      }
      summary
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("Homes")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      ResidenceEditorSheet(controller: controller, entry: nil)
    }
    .navigationDestination(item: $openedHomeID) { id in
      HomeDetailView(controller: controller, client: client, ownerID: ownerID, entryID: id)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(count(controller.entries.count, "home"))
      Text("·").accessibilityHidden(true)
      Text(count(controller.currentEntries.count, "current residence"))
      Text("·").accessibilityHidden(true)
      Text(count(controller.earlierEntries.count, "earlier home"))
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.caption.weight(.regular))
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Homes summary")
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Homes...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "Homes unavailable", message: message, icon: .home) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
      .padding(.top, MTSpacing.s4)
    } else if controller.entries.isEmpty {
      MTEmptyState(
        title: "Begin with somewhere you called home",
        message:
          "Add the best-known move-in date now. Exact addresses, reasons, photos, and memories can come later.",
        icon: .home
      ) {
        isAdding = true
      }
      .padding(.top, MTSpacing.s4)
    } else {
      if !controller.currentEntries.isEmpty {
        section("Current", detail: "Where life is happening now", controller.currentEntries)
      }
      if !controller.earlierEntries.isEmpty {
        section("Earlier homes", detail: "Places you lived before", controller.earlierEntries)
      }
    }
  }

  /// Web `HomeSection`: an uppercase heading, with its description beside it on wider screens.
  private func section(_ title: String, detail: String, _ entries: [ResidenceEntry])
    -> some View
  {
    let isRegular = horizontalSizeClass == .regular
    return VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
        Text(title.uppercased())
          .font(MTFont.label.weight(.semibold))
          .tracking(0.8)
          .foregroundStyle(MTColor.inkMuted)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        if isRegular {
          Text(detail).font(MTFont.caption.weight(.regular)).foregroundStyle(MTColor.inkFaint)
        }
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 300), spacing: MTSpacing.s5)],
        spacing: isRegular ? MTSpacing.s5 : MTSpacing.s3
      ) {
        ForEach(entries) { entry in
          HomeCard(entry: entry) { openedHomeID = entry.id }
        }
      }
    }
    .padding(.top, isRegular ? MTSpacing.s8 : MTSpacing.s6)
  }

  private func count(_ value: Int, _ singular: String) -> String {
    "\(value) \(value == 1 ? singular : "\(singular)s")"
  }
}

/// Web `HomeCard`: a cover photo, else a map of the Home's Location, else its mark; then the
/// dates, name, place, a short memory, and up to two Collections and tags.
private struct HomeCard: View {
  let entry: ResidenceEntry
  let open: () -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    MTRecordCard(accessibilityLabel: "\(entry.title), \(entry.displayRange)", action: open) {
      MTRecordCardVisual { visual }
        .overlay(alignment: .topLeading) {
          MTBadge(
            title: entry.isCurrent ? "Current" : "Earlier",
            tone: entry.isCurrent ? .glassAccent : .glassNeutral, size: .micro, uppercase: true
          )
          .padding(horizontalSizeClass == .regular ? MTSpacing.s3 : MTSpacing.s2)
        }
        .overlay(alignment: .bottomTrailing) {
          if entry.attachments.count > 1 {
            MTBadge(
              title: "\(entry.attachments.count) photos", tone: .inverse, size: .micro,
              uppercase: true
            )
            .padding(MTSpacing.s3)
          }
        }
      MTRecordCardBody {
        dates
        Text(entry.title)
          .font(
            .system(horizontalSizeClass == .regular ? .title2 : .title3, design: .serif)
              .weight(.medium)
          )
          .tracking(-0.4)
          .foregroundStyle(MTColor.ink)
          .multilineTextAlignment(.leading)
        Label(entry.displayLocation, icon: .map)
          .labelStyle(MTInlineIconLabelStyle())
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
        if let memory = entry.body.trimmed.nonEmpty {
          Text(memory)
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s1)
        }
        footer
      }
    }
  }

  @ViewBuilder private var visual: some View {
    if let cover = entry.attachments.first?.signedURL {
      MTRemoteImage(url: cover)
    } else {
      MTLocationSnapshot(latitude: entry.latitude, longitude: entry.longitude) {
        MTRecordMark(
          icon: .home,
          title: entry.city?.trimmed.nonEmpty ?? entry.country?.trimmed.nonEmpty
            ?? "A place in your trail")
      }
    }
  }

  /// The range in accent and how long it lasted, stacked on phones like Web below 780 px.
  private var dates: some View {
    let range = Text(entry.displayRange.uppercased()).foregroundStyle(MTColor.accent)
    let duration = Text(entry.durationLabel().uppercased()).foregroundStyle(MTColor.inkFaint)
    return Group {
      if horizontalSizeClass == .regular {
        HStack(spacing: MTSpacing.s3) {
          range
          Spacer(minLength: 0)
          duration
        }
      } else {
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          range
          duration
        }
      }
    }
    .font(.caption2.monospaced())
    .tracking(0.25)
  }

  /// Phones show the first two badges, like Web below 480 px.
  private var footer: some View {
    let badges =
      entry.collectionNames.prefix(2).map { $0 } + entry.tagNames.prefix(2).map { "#\($0)" }
    return HStack(alignment: .bottom, spacing: MTSpacing.s3) {
      MTFlowLayout(spacing: 5) {
        ForEach(
          Array(badges.prefix(horizontalSizeClass == .regular ? 4 : 2).enumerated()), id: \.offset
        ) { _, name in
          MTBadge(title: name, tone: .neutral, size: .micro)
        }
      }
      Spacer(minLength: 0)
      Image(.chevron)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(minHeight: 31 - MTSpacing.s3, alignment: .bottom)
    .padding(.top, MTSpacing.s3)
    .overlay(alignment: .top) { MTListDivider() }
    .padding(.top, MTSpacing.s2)
  }
}
