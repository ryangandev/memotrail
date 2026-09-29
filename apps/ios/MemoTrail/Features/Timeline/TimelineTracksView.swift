import Foundation
@preconcurrency import Supabase
import SwiftUI

struct TimelineTrackSetting: Decodable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let systemKey: String?
  let sortOrder: Int
  let isHidden: Bool
  let revision: Int
  let entryCount: Int
  let totalCount: Int
  enum CodingKeys: String, CodingKey {
    case id, name, revision
    case systemKey = "system_key"
    case sortOrder = "sort_order"
    case isHidden = "is_hidden"
    case entryCount = "entry_count"
    case totalCount = "total_count"
  }
}
struct TrackSettingsRequest: Encodable {
  let limit = 50
  let offset: Int
  enum CodingKeys: String, CodingKey {
    case limit = "p_limit"
    case offset = "p_offset"
  }
}
struct TrackSaveRequest: Encodable {
  let name: String
  let sortOrder: Int
  let isHidden: Bool
  let trackID: UUID?
  let expectedRevision: Int?
  var isValid: Bool {
    !name.trimmed.isEmpty && name.trimmed.unicodeScalars.count <= 100
      && (-1_000_000...1_000_000).contains(sortOrder)
      && (trackID == nil ? expectedRevision == nil : (expectedRevision ?? 0) > 0)
  }
  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case sortOrder = "p_sort_order"
    case isHidden = "p_is_hidden"
    case trackID = "p_track_id"
    case expectedRevision = "p_expected_revision"
  }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name.trimmed, forKey: .name)
    try container.encode(sortOrder, forKey: .sortOrder)
    try container.encode(isHidden, forKey: .isHidden)
    try container.encode(trackID, forKey: .trackID)
    try container.encode(expectedRevision, forKey: .expectedRevision)
  }
}

/// Web `/timeline/tracks` loading and `saveTrack`.
@MainActor
@Observable
final class TimelineTracksController {
  private(set) var tracks: [TimelineTrackSetting] = []
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  private(set) var loadErrorMessage: String?
  /// Increases after each full reload, so every card returns to its saved values.
  private(set) var generation = 0

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var hasMore: Bool { tracks.count < (tracks.first?.totalCount ?? 0) }

  func load(more: Bool = false) async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    do {
      try await validateSessionOwner()
      let next: [TimelineTrackSetting] = try await client.rpc(
        "timeline_track_settings", params: TrackSettingsRequest(offset: more ? tracks.count : 0)
      ).execute().value
      if more {
        tracks.append(contentsOf: next)
      } else {
        tracks = next
        generation += 1
      }
      loadErrorMessage = nil
    } catch {
      guard !(error is CancellationError) else { return }
      loadErrorMessage = "Tracks could not load. Pull to refresh or try again."
    }
  }

  /// Saves one track and returns Web's failure message, or nil once it saved.
  func save(_ request: TrackSaveRequest) async -> String? {
    guard request.isValid else {
      return
        "Use a name up to 100 characters and a whole-number order between -1,000,000 and 1,000,000."
    }
    do {
      try await validateSessionOwner()
      let saved: UUID? = try await client.rpc("save_timeline_track", params: request)
        .execute().value
      guard saved != nil else {
        return "This track changed on another device. Reload tracks before editing again."
      }
      await load()
      return nil
    } catch let error as PostgrestError where error.code == "23505" {
      return "A track with this name already exists, including hidden tracks."
    } catch {
      return "Could not save this track. Your edits are still here to retry."
    }
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

/// Web `/timeline/tracks`: every track as its own small form, with a new track on request.
struct TimelineTracksView: View {
  @State private var controller: TimelineTracksController
  @State private var isAdding = false
  @State private var newTrackGeneration = 0

  init(client: SupabaseClient, ownerID: UUID) {
    _controller = State(
      initialValue: TimelineTracksController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .standard, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "Choose the chapters you see", title: "Timeline tracks",
        description:
          "Create space for each part of your life. Hidden tracks keep every moment and can be shown again anytime."
      ) {
        Button(isAdding ? "Cancel new track" : "Add track") {
          isAdding.toggle()
          newTrackGeneration += 1
        }
        .mtButtonStyle(.secondary)
        .accessibilityIdentifier("add-timeline-track")
        Button("Reload tracks") { Task { await controller.load() } }
          .mtButtonStyle(.secondary, isLoading: controller.isLoading && controller.hasLoaded)
      }
      Text(
        "Lower order numbers appear first. Equal numbers sort by name. Reloading discards unsaved track edits."
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
      if isAdding {
        TimelineTrackForm(track: nil, save: controller.save) { isAdding = false }
          .id("new-\(newTrackGeneration)")
      }
      content
    }
    // Leave the last track clear of the Quick capture button.
    .contentMargins(.bottom, MTSpacing.s12, for: .scrollContent)
    .scrollDismissesKeyboard(.interactively)
    .refreshable { await controller.load() }
    .navigationTitle("Timeline tracks")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  @ViewBuilder private var content: some View {
    if !controller.hasLoaded {
      ProgressView()
        .tint(MTColor.accent)
        .frame(maxWidth: .infinity, minHeight: 120)
    } else if let message = controller.loadErrorMessage, controller.tracks.isEmpty {
      MTEmptyState(title: "Tracks unavailable", message: message, icon: .warning) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.tracks.isEmpty {
      MTEmptyState(
        title: "No tracks yet",
        message: "Add a track to give a part of your life its own row.", icon: .timeline)
    } else {
      ForEach(controller.tracks) { track in
        TimelineTrackForm(track: track, save: controller.save)
          .id("\(track.id)-\(track.revision)-\(controller.generation)")
      }
      if controller.hasMore {
        Button("More tracks") { Task { await controller.load(more: true) } }
          .mtButtonStyle(.secondary, isLoading: controller.isLoading)
          .frame(maxWidth: .infinity)
      }
    }
  }
}

/// Web `TrackForm`: the track's name and order, whether it shows, and its own save action.
private struct TimelineTrackForm: View {
  let track: TimelineTrackSetting?
  let save: (TrackSaveRequest) async -> String?
  var created: () -> Void = {}

  @State private var name: String
  @State private var order: String
  @State private var isHidden: Bool
  @State private var isSaving = false

  init(
    track: TimelineTrackSetting?, save: @escaping (TrackSaveRequest) async -> String?,
    created: @escaping () -> Void = {}
  ) {
    self.track = track
    self.save = save
    self.created = created
    _name = State(initialValue: track?.name ?? "")
    _order = State(initialValue: String(track?.sortOrder ?? 0))
    _isHidden = State(initialValue: track?.isHidden ?? false)
  }

  private var request: TrackSaveRequest? {
    guard let sortOrder = Int(order.trimmed) else { return nil }
    let request = TrackSaveRequest(
      name: name, sortOrder: sortOrder, isHidden: isHidden, trackID: track?.id,
      expectedRevision: track?.revision)
    return request.isValid ? request : nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s5) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(track?.name ?? "New track")
          .font(MTFont.titleSmall)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Text(summary)
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
      }
      .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        HStack(alignment: .top, spacing: MTSpacing.s4) {
          MTTextField(label: "Name", text: $name, maxLength: 100)
            .autocorrectionDisabled()
          MTTextField(label: "Order", text: $order)
            .keyboardType(.numbersAndPunctuation)
            .frame(width: 118)
        }
        MTCheckbox(title: "Hide from Timeline", isOn: $isHidden)
        Button(track == nil ? "Create track" : "Save track") { Task { await submit() } }
          .mtButtonStyle(isLoading: isSaving)
          .disabled(request == nil)
          .accessibilityIdentifier(track == nil ? "create-timeline-track" : "save-timeline-track")
      }
      .disabled(isSaving)
    }
    .padding(MTSpacing.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(track.map { "Edit \($0.name)" } ?? "New track")
  }

  private var summary: String {
    guard let track else { return "A new dimension of your story" }
    let moments = "\(track.entryCount) \(track.entryCount == 1 ? "moment" : "moments")"
    let parts: [String?] = [
      track.systemKey == nil ? "Custom" : "Default", moments, track.isHidden ? "Hidden" : nil,
    ]
    return parts.compactMap(\.self).joined(separator: " · ")
  }

  private func submit() async {
    guard let request, !isSaving else { return }
    isSaving = true
    let failure = await save(request)
    isSaving = false
    if let failure {
      MTToastCenter.shared.error(failure)
    } else {
      MTToastCenter.shared.success(track == nil ? "Track created." : "Track saved.")
      created()
    }
  }
}
