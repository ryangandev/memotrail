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

  private func section(_ title: String, detail: String, _ entries: [ResidenceEntry])
    -> some View
  {
    MTRecordSection(title, detail: detail) {
      ForEach(entries) { entry in
        HomeCard(entry: entry) { openedHomeID = entry.id }
      }
    }
  }

  private func count(_ value: Int, _ singular: String) -> String {
    "\(value) \(value == 1 ? singular : "\(singular)s")"
  }
}

/// Web `HomeCard`: a cover photo, else a map of the Home's Location, else its mark; then the
/// dates, name, place, a short memory, and organization.
private struct HomeCard: View {
  let entry: ResidenceEntry
  let open: () -> Void

  var body: some View {
    MTEntityCard(
      title: entry.title, range: entry.displayRange, duration: entry.durationLabel(),
      isCurrent: entry.isCurrent, coverURL: entry.attachments.first?.signedURL,
      photoCount: entry.attachments.count, latitude: entry.latitude, longitude: entry.longitude,
      markIcon: .home,
      markTitle: entry.city?.trimmed.nonEmpty ?? entry.country?.trimmed.nonEmpty
        ?? "A place in your trail",
      facts: [MTEntityCard.Fact(icon: .map, text: entry.displayLocation)], memory: entry.body,
      collectionNames: entry.collectionNames, tagNames: entry.tagNames, action: open)
  }
}
