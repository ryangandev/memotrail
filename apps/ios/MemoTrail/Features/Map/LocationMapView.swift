@preconcurrency import Supabase
import SwiftUI

struct LocationMapView: View {
  private let client: SupabaseClient?
  private let ownerID: UUID
  @State private var controller: LocationMapController
  @State private var kind: WikiItemKind?
  @State private var fromYear = ""
  @State private var toYear = ""
  @State private var focusAreaID: String?
  @State private var focusRevision = UUID()
  /// The Locations of the pin or cluster chosen on the map, like Web `selectedIds`.
  @State private var selectedIDs: Set<String>?

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

  private var filter: LocationMapFilter {
    LocationMapFilter(kind: kind, fromYear: Int(fromYear), toYear: Int(toYear))
  }
  private var filtered: [LocationMapItem] { filter.apply(to: controller.items) }
  private var areas: [LocationMapArea] { LocationMapArea.shortcuts(for: filtered) }
  private var focusItems: [LocationMapItem] {
    areas.first { $0.id == focusAreaID }?.items ?? filtered
  }
  private var selected: [LocationMapItem] {
    guard let selectedIDs else { return [] }
    return LocationMapArea.uniqueEntries(in: filtered.filter { selectedIDs.contains($0.id) })
  }

  var body: some View {
    // Web `/map` at phone width: filters and areas above the map, its records below.
    ScrollViewReader { proxy in
      MTPage(width: .standard, spacing: MTSpacing.s4) {
        MTPageHeader(
          eyebrow: "Your life in places", title: "Map",
          description:
            "Explore the current coordinates attached to your memories, events, and other Wiki Items."
        )
        .padding(.bottom, MTSpacing.s4)
        filters
        if areas.count > 1 { areaShortcuts }
        if let message = controller.errorMessage {
          MapNotice(text: message) {
            Button("Try again") { Task { await reload() } }
              .mtButtonStyle(.secondary, size: .small)
              .accessibilityIdentifier("map-retry")
          }
        }
        if controller.truncated {
          MapNotice(
            text:
              "Showing the 5,000 most recently linked Locations. Filters apply only to these results."
          ) {}
        }
        map
        records.id(Self.recordsID)
      }
      .onChange(of: selectedIDs) { _, ids in
        guard ids != nil else { return }
        withAnimation(MTEasing.enter.animation(duration: MTMotion.standard)) {
          proxy.scrollTo(Self.recordsID, anchor: .bottom)
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Map")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await reload() }
    .task {
      if !controller.hasLoaded {
        await controller.load()
        resetFocus()
      }
    }
    .onChange(of: filter) { resetFocus() }
    .onChange(of: controller.items) { resetFocus() }
  }

  private static let recordsID = "map-records"

  /// Web `filters`: Category and an occurred-year range that apply as they change.
  private var filters: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSelectField(
        label: "Category", selection: $kind,
        options: [nil] + WikiItemKind.allCases.map(Optional.some),
        title: { $0?.mapPlural ?? "All records" }, size: .small
      )
      .accessibilityIdentifier("map-category")
      HStack(alignment: .top, spacing: MTSpacing.s3) {
        yearField("From year", text: $fromYear, identifier: "map-from-year")
        yearField("To year", text: $toYear, identifier: "map-to-year")
      }
      Text(countLabel(filtered.count, "Entry Location"))
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .accessibilityIdentifier("map-count")
    }
  }

  private func yearField(_ label: String, text: Binding<String>, identifier: String) -> some View {
    MTTextField(label: label, text: text, prompt: "Any", size: .small, maxLength: 4)
      // A number pad has no Return key, so the page could not dismiss it.
      .keyboardType(.numbersAndPunctuation)
      .submitLabel(.done)
      .autocorrectionDisabled()
      .accessibilityIdentifier(identifier)
      .onChange(of: text.wrappedValue) { _, value in
        let digits = value.filter { $0.isASCII && $0.isNumber }
        if digits != value { text.wrappedValue = digits }
      }
  }

  /// Web `areas`: the busiest places as shortcuts that zoom the map, and View all.
  private var areaShortcuts: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack {
        Text("Your areas")
          .font(MTFont.caption)
          .foregroundStyle(MTColor.inkMuted)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        Button("View all") { resetFocus() }
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkMuted)
          .frame(minHeight: MTLayout.InlineAction.height)
          .contentShape(Rectangle())
          .accessibilityIdentifier("map-view-all")
      }
      MTFlowLayout(spacing: MTSpacing.s2) {
        ForEach(areas) { area in
          Button {
            selectedIDs = nil
            focusAreaID = area.id
            focusRevision = UUID()
          } label: {
            MapAreaPill(area: area, isFocused: focusAreaID == area.id)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Zoom to \(area.title), \(countLabel(area.entryCount, "Entry"))")
          .accessibilityIdentifier("map-city-\(area.items.first?.city ?? "")")
        }
      }
    }
  }

  private var map: some View {
    ZStack {
      NativeLocationMap(items: filtered, focusItems: focusItems, focusRevision: focusRevision) {
        selectedIDs = Set($0.map(\.id))
      }
      .accessibilityIdentifier("native-location-map")
      if controller.isLoading && !controller.hasLoaded {
        ProgressView("Loading your Locations…")
          .font(MTFont.caption)
          .tint(MTColor.accent)
          .padding(MTSpacing.s4)
          .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      }
    }
    // Web `.map` at phone width: most of the screen, within a comfortable range.
    .containerRelativeFrame(.vertical) { height, _ in min(max(height * 0.58, 320), 480) }
    .background(MTColor.surfaceSubtle)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border) }
  }

  /// Web `detail`: the Entries at the chosen point, newest first.
  private var records: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(spacing: MTSpacing.s2) {
        Image(.map)
          .font(.mtIcon(MTSize.Icon.s17))
          .foregroundStyle(MTColor.accent)
          .accessibilityHidden(true)
        Text(
          selected.isEmpty ? "Choose a map point" : "\(countLabel(selected.count, "Entry")) here"
        )
        .font(MTFont.cardTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      }
      if selected.isEmpty {
        Text(
          filtered.isEmpty
            ? "No current Entries match these filters. Add a Location in an Entry to place it on this map."
            : "Pan, zoom, or select a pin to see what happened there."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(spacing: MTSpacing.s2) {
          ForEach(selected) { item in
            NavigationLink {
              destination(item)
            } label: {
              MapRecordRow(item: item)
            }
            .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
            .accessibilityIdentifier("map-record-\(item.entryID.uuidString.lowercased())")
          }
        }
      }
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border) }
  }

  @ViewBuilder private func destination(_ item: LocationMapItem) -> some View {
    if let client {
      WikiItemDestinationView(
        client: client, ownerID: ownerID, entryID: item.entryID, kind: item.kind,
        subtype: item.subtype)
    } else {
      MTEmptyState(
        title: item.title, message: "This is a synthetic preview record.",
        systemImage: "book.closed")
    }
  }

  private func reload() async {
    await controller.load()
    resetFocus()
  }

  private func resetFocus() {
    selectedIDs = nil
    focusAreaID = nil
    focusRevision = UUID()
  }
}

/// Web `areaButton`: a place and its Entry count on a pill.
private struct MapAreaPill: View {
  let area: LocationMapArea
  let isFocused: Bool

  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      Text(area.title).foregroundStyle(MTColor.ink)
      Text("\(area.entryCount)").foregroundStyle(MTColor.inkMuted)
    }
    .font(MTFont.detail)
    .padding(.horizontal, MTSpacing.s3)
    .frame(minHeight: MTSize.Field.small)
    .background(isFocused ? MTColor.accentSubtle : MTColor.surfaceRaised, in: Capsule())
    .overlay { Capsule().strokeBorder(isFocused ? MTColor.accent : MTColor.border) }
    .contentShape(Capsule())
  }
}

/// Web `detail li a`: the Entry's title over its kind, address, and date.
private struct MapRecordRow: View {
  let item: LocationMapItem

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s1) {
      Text(item.title)
        .font(MTFont.label)
        .foregroundStyle(MTColor.ink)
        .multilineTextAlignment(.leading)
      MTWordFlow(.caption1) {
        Text(item.kind.displayName(subtype: item.subtype))
        MTFlowSeparator()
        Text(item.address)
        if let occurredAt = item.occurredAt {
          MTFlowSeparator()
          // Like Web, the stored UTC calendar date.
          Text(
            occurredAt.formatted(
              Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)))
        }
      }
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .multilineTextAlignment(.leading)
    }
    .padding(MTSpacing.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Web map `notice`: a bordered note above the map.
private struct MapNotice<Action: View>: View {
  let text: String
  @ViewBuilder let action: Action

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(text)
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
      action
    }
    .padding(MTSpacing.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay { RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.border) }
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
