@preconcurrency import Supabase
import SwiftUI

struct LocationMapView: View {
  private let client: SupabaseClient?
  private let ownerID: UUID
  @State private var controller: LocationMapController
  @State private var filter = LocationMapFilter()
  @State private var isShowingFilters = false
  @State private var focusAreaID: String?
  @State private var focusRevision = UUID()
  @State private var selection: MapRecordSelection?

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: LocationMapController(client: client, ownerID: ownerID))
  }

  #if DEBUG
    init(preview snapshot: LocationMapSnapshot) {
      client = nil
      ownerID = UUID()
      _controller = State(initialValue: LocationMapController { snapshot })
    }
  #endif

  private var filtered: [LocationMapItem] { filter.apply(to: controller.items) }
  private var areas: [LocationMapArea] { LocationMapArea.shortcuts(for: filtered) }
  private var focusItems: [LocationMapItem] {
    areas.first { $0.id == focusAreaID }?.items ?? filtered
  }

  var body: some View {
    VStack(spacing: 0) {
      controls
      ZStack {
        NativeLocationMap(items: filtered, focusItems: focusItems, focusRevision: focusRevision) {
          selection = MapRecordSelection(items: $0)
        }
        .accessibilityIdentifier("native-location-map")

        if controller.isLoading && !controller.hasLoaded {
          ProgressView("Loading your Locations...")
            .padding(MTSpacing.s4).background(
              .regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        } else if let message = controller.errorMessage {
          VStack(spacing: MTSpacing.s3) {
            MTFeedback(
              title: "Map unavailable", message: message, tone: .warm,
              systemImage: "exclamationmark.triangle")
            Button("Try again") {
              Task {
                await controller.load()
                resetFocus()
              }
            }
            .buttonStyle(MTActionStyle())
            .accessibilityIdentifier("map-retry")
          }
          .padding(MTSpacing.s4)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.large))
          .padding(MTSpacing.s4)
        } else if controller.hasLoaded && filtered.isEmpty {
          MTEmptyState(
            title: controller.items.isEmpty ? "No mapped records yet" : "No matching Locations",
            message: controller.items.isEmpty
              ? "Records with saved coordinates will appear here. An address without coordinates stays off the map."
              : "Try another Kind or year range.",
            systemImage: "map"
          )
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.large))
          .padding(MTSpacing.s4)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(MTColor.canvas)
    .navigationTitle("Map")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Refresh map", systemImage: "arrow.clockwise") {
          Task {
            await controller.load()
            resetFocus()
          }
        }.disabled(controller.isLoading)
      }
    }
    .sheet(isPresented: $isShowingFilters) {
      MapFilterSheet(filter: $filter)
    }
    .sheet(
      item: $selection,
      onDismiss: {
        if client != nil { Task { await controller.load() } }
      }
    ) { selected in
      NavigationStack {
        List {
          Section {
            ForEach(LocationMapArea.uniqueEntries(in: selected.items)) { item in
              NavigationLink {
                if let client {
                  WikiItemDestinationView(
                    client: client, ownerID: ownerID, entryID: item.entryID, kind: item.kind,
                    subtype: item.subtype)
                } else {
                  MTEmptyState(
                    title: item.title, message: "This is a synthetic preview record.",
                    systemImage: "book.closed")
                }
              } label: {
                MTRecordSummary(
                  title: item.title, subtitle: item.address,
                  kind: item.kind.displayName(subtype: item.subtype),
                  status: item.inboxStatus == "unreviewed" ? "In Inbox" : nil
                )
                .padding(.vertical, MTSpacing.s1)
              }
              .accessibilityIdentifier("map-record-\(item.entryID.uuidString.lowercased())")
            }
          } header: {
            Text("\(LocationMapArea.uniqueEntries(in: selected.items).count) records")
          }
        }
        .scrollContentBackground(.hidden).background(MTColor.canvas)
        .navigationTitle("Mapped records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { selection = nil } }
        }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .task {
      if !controller.hasLoaded {
        await controller.load()
        resetFocus()
      }
    }
    .onChange(of: filter) { resetFocus() }
    .onChange(of: controller.items) { resetFocus() }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack(alignment: .firstTextBaseline) {
        Text("Your life in places").font(MTFont.heading).foregroundStyle(MTColor.ink)
        Spacer()
        Button("Filters", systemImage: "line.3.horizontal.decrease") { isShowingFilters = true }
          .accessibilityIdentifier("map-filters")
      }
      Text(recordCountLabel)
        .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      if filter.fromYear != nil || filter.toYear != nil {
        Text(
          "Years \(filter.fromYear.map(String.init) ?? "Any") to \(filter.toYear.map(String.init) ?? "Any")"
        )
        .font(MTFont.caption).foregroundStyle(MTColor.accent)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MTSpacing.s2) {
          MTFilterChip(title: "All records", isSelected: filter.kind == nil) { filter.kind = nil }
          ForEach(WikiItemKind.allCases, id: \.self) { kind in
            MTFilterChip(title: kind.mapPlural, isSelected: filter.kind == kind) {
              filter.kind = kind
            }
            .accessibilityIdentifier("map-kind-\(kind.rawValue)")
          }
        }
      }
      if areas.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s2) {
            Button("Full map", systemImage: "arrow.up.left.and.arrow.down.right") { resetFocus() }
              .buttonStyle(.bordered)
              .accessibilityIdentifier("map-full-map")
            ForEach(areas) { area in
              MTFilterChip(
                title: "\(area.title) (\(area.entryCount))", isSelected: focusAreaID == area.id
              ) {
                selection = nil
                focusAreaID = area.id
                focusRevision = UUID()
              }
              .accessibilityIdentifier("map-city-\(area.items.first?.city ?? "")")
            }
          }
        }
      }
      if controller.truncated {
        Text("Showing the newest 5,000 Location links. Filters apply to loaded records.")
          .font(MTFont.caption).foregroundStyle(MTColor.warm)
      }
      if !filtered.isEmpty {
        Button("Browse mapped records", systemImage: "list.bullet") {
          selection = MapRecordSelection(items: filtered)
        }
        .font(MTFont.label)
        .accessibilityIdentifier("map-browse-records")
      }
    }
    .padding(MTSpacing.s4)
  }

  private func resetFocus() {
    selection = nil
    focusAreaID = nil
    focusRevision = UUID()
  }

  private var recordCountLabel: String {
    let records = Set(filtered.map(\.entryID)).count
    return
      "\(records) \(records == 1 ? "record" : "records") · \(filtered.count) \(filtered.count == 1 ? "Location" : "Locations")"
  }
}

private struct MapRecordSelection: Identifiable {
  let id = UUID()
  let items: [LocationMapItem]
}

private struct MapFilterSheet: View {
  @Binding var filter: LocationMapFilter
  @State private var kind: WikiItemKind?
  @State private var fromYear: String
  @State private var toYear: String
  @Environment(\.dismiss) private var dismiss

  init(filter: Binding<LocationMapFilter>) {
    _filter = filter
    _kind = State(initialValue: filter.wrappedValue.kind)
    _fromYear = State(initialValue: filter.wrappedValue.fromYear.map(String.init) ?? "")
    _toYear = State(initialValue: filter.wrappedValue.toYear.map(String.init) ?? "")
  }

  private var draft: LocationMapFilter? {
    guard fromYear.trimmed.isEmpty || Int(fromYear.trimmed) != nil,
      toYear.trimmed.isEmpty || Int(toYear.trimmed) != nil
    else { return nil }
    let value = LocationMapFilter(
      kind: kind, fromYear: Int(fromYear.trimmed), toYear: Int(toYear.trimmed))
    return value.isValid ? value : nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Kind") {
          Picker("Kind", selection: $kind) {
            Text("All records").tag(nil as WikiItemKind?)
            ForEach(WikiItemKind.allCases, id: \.self) { kind in
              Text(kind.mapPlural).tag(Optional(kind))
            }
          }
        }
        Section {
          TextField("From year (any)", text: $fromYear).keyboardType(.numberPad)
            .accessibilityIdentifier("map-from-year")
          TextField("To year (any)", text: $toYear).keyboardType(.numberPad)
            .accessibilityIdentifier("map-to-year")
          if draft == nil {
            Text("Use years from 1 to 9999, with the start year before the end year.")
              .foregroundStyle(MTColor.warm)
          }
        } header: {
          Text("Occurred year")
        } footer: {
          Text("Records without a known date are included only when no year filter is applied.")
        }
        Button("Reset filters") {
          kind = nil
          fromYear = ""
          toYear = ""
        }
      }
      .scrollContentBackground(.hidden).background(MTColor.canvas)
      .navigationTitle("Map filters").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            if let draft {
              filter = draft
              dismiss()
            }
          }.disabled(draft == nil)
        }
      }
    }
  }
}

extension WikiItemKind {
  var mapPlural: String {
    switch self {
    case .entry: "Entries"
    case .entity: "Entities"
    case .goal: "Goals"
    }
  }
}
