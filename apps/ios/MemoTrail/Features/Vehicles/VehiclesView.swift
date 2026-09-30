@preconcurrency import Supabase
import SwiftUI

/// Web `/vehicles` at phone width: one Vehicle archive, current first, as record cards that open
/// each Vehicle's own page, and Add Vehicle.
struct VehiclesView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: VehicleController
  @State private var isAdding = false
  @State private var openedVehicleID: UUID?

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: VehicleController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "The machines that carried your story", title: "Vehicles",
        description:
          "Keep each car, bike, or other vehicle as an Entity, with the dates, facts, and memories that made it yours."
      ) {
        Button {
          isAdding = true
        } label: {
          Label("Add Vehicle", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("add-vehicle")
      }
      summary
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("Vehicles")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      VehicleEditorSheet(controller: controller, entry: nil)
    }
    .navigationDestination(item: $openedVehicleID) { id in
      VehicleDetailView(controller: controller, client: client, ownerID: ownerID, entryID: id)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var summary: some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Text(count(controller.entries.count, "vehicle"))
      Text("·").accessibilityHidden(true)
      Text(count(controller.currentEntries.count, "current vehicle"))
      Text("·").accessibilityHidden(true)
      Text(count(controller.earlierEntries.count, "earlier vehicle"))
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.caption.weight(.regular))
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Vehicles summary")
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Vehicles...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "Vehicles unavailable", message: message, icon: .car) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
      .padding(.top, MTSpacing.s4)
    } else if controller.entries.isEmpty {
      MTEmptyState(
        title: "Begin with a vehicle that carried you",
        message:
          "Add its name and best-known start date now. Specs, photos, and memories can come later.",
        icon: .car
      ) {
        isAdding = true
      }
      .padding(.top, MTSpacing.s4)
    } else {
      MTRecordSection("Vehicle archive", detail: "Current first, followed by earlier vehicles") {
        ForEach(controller.entries) { entry in
          VehicleCard(entry: entry) { openedVehicleID = entry.id }
        }
      }
    }
  }

  private func count(_ value: Int, _ singular: String) -> String {
    "\(value) \(value == 1 ? singular : "\(singular)s")"
  }
}

/// Web `VehicleCard`: a cover photo, else a map of the Vehicle's Location, else its facts; then
/// the dates, name, facts, Location, a short memory, and organization.
private struct VehicleCard: View {
  let entry: VehicleEntry
  let open: () -> Void

  var body: some View {
    MTEntityCard(
      title: entry.title, range: entry.displayRange, duration: entry.durationLabel(),
      isCurrent: entry.isCurrent, coverURL: entry.attachments.first?.signedURL,
      photoCount: entry.attachments.count, latitude: entry.location?.latitude,
      longitude: entry.location?.longitude, markIcon: .car, markTitle: entry.factsLabel,
      facts: [MTEntityCard.Fact(icon: .car, text: entry.factsLabel)]
        + (entry.location.map { [MTEntityCard.Fact(icon: .map, text: $0.name)] } ?? []),
      memory: entry.body, collectionNames: entry.collectionNames, tagNames: entry.tagNames,
      action: open)
  }
}
