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

struct TimelineTracksView: View {
  let client: SupabaseClient
  let ownerID: UUID
  @State private var tracks: [TimelineTrackSetting] = []
  @State private var selected: TimelineTrackSetting?
  @State private var adding = false
  @State private var busy = false
  @State private var message: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(
          "Create space for each part of your life. Hidden tracks keep every moment and can be shown again anytime."
        )
        .foregroundStyle(MTColor.inkMuted)
        Text("Lower order numbers appear first. Equal numbers sort by name.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
        if let message { Text(message).foregroundStyle(MTColor.warm) }
        Button("Add track", systemImage: "plus") { adding = true }
          .buttonStyle(.bordered).disabled(busy)
        ForEach(tracks) { track in
          Button {
            selected = track
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Text(track.name).font(MTTypography.titleSmall).foregroundStyle(MTColor.ink)
                Text(
                  "\(track.systemKey == nil ? "Custom" : "Default") · \(track.entryCount) \(track.entryCount == 1 ? "moment" : "moments") · Order \(track.sortOrder)"
                )
                .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
                if track.isHidden {
                  Label("Hidden", systemImage: "eye.slash").font(MTTypography.caption)
                    .foregroundStyle(MTColor.inkMuted)
                }
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(MTColor.inkMuted)
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
              .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
          }.buttonStyle(.plain).disabled(busy)
        }
        if tracks.isEmpty && !busy && message == nil {
          Text("No tracks yet. Add your first chapter.")
        }
        if tracks.count < (tracks.first?.totalCount ?? 0) {
          Button("More tracks") { Task { await load(more: true) } }.disabled(busy)
        }
        if busy { ProgressView() }
      }.padding()
    }.background(MTColor.canvas).navigationTitle("Timeline tracks")
      .navigationBarTitleDisplayMode(.inline)
      .task { await load() }.refreshable { await load() }
      .sheet(
        isPresented: $adding, onDismiss: { Task { await load() } },
        content: { TrackEditorSheet(client: client, ownerID: ownerID, track: nil) }
      )
      .sheet(
        item: $selected, onDismiss: { Task { await load() } },
        content: { track in TrackEditorSheet(client: client, ownerID: ownerID, track: track) }
      )
  }
  private func load(more: Bool = false) async {
    guard !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let next: [TimelineTrackSetting] = try await client.rpc(
        "timeline_track_settings", params: TrackSettingsRequest(offset: more ? tracks.count : 0)
      ).execute().value
      if more { tracks.append(contentsOf: next) } else { tracks = next }
    } catch { message = "Could not load tracks. Pull to refresh and try again." }
  }
}

private struct TrackEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let client: SupabaseClient
  let ownerID: UUID
  let track: TimelineTrackSetting?
  @State private var name: String
  @State private var order: String
  @State private var hidden: Bool
  @State private var busy = false
  @State private var message: String?
  init(client: SupabaseClient, ownerID: UUID, track: TimelineTrackSetting?) {
    self.client = client
    self.ownerID = ownerID
    self.track = track
    _name = State(initialValue: track?.name ?? "")
    _order = State(initialValue: String(track?.sortOrder ?? 0))
    _hidden = State(initialValue: track?.isHidden ?? false)
  }
  private var input: TrackSaveRequest? {
    guard let value = Int(order.trimmed) else { return nil }
    let request = TrackSaveRequest(
      name: name, sortOrder: value, isHidden: hidden,
      trackID: track?.id, expectedRevision: track?.revision)
    return request.isValid ? request : nil
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
          TextField("Order", text: $order).autocorrectionDisabled()
          Toggle("Hide from Timeline", isOn: $hidden)
        } footer: {
          Text(
            "Names can have up to 100 characters. Order is a whole number between -1,000,000 and 1,000,000. Hiding never deletes moments."
          )
        }
        if let message { Section { Text(message).foregroundStyle(MTColor.warm) } }
      }.disabled(busy).scrollContentBackground(.hidden).background(MTColor.canvas)
        .navigationTitle(track == nil ? "New track" : "Edit track").navigationBarTitleDisplayMode(
          .inline
        )
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(busy)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(
              busy || input == nil)
          }
        }
    }.interactiveDismissDisabled(busy)
  }
  private func save() async {
    guard let input, !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let saved: UUID? = try await client.rpc("save_timeline_track", params: input).execute().value
      if saved == nil {
        message =
          "This track changed on another device. Cancel and refresh tracks before editing again."
      } else {
        dismiss()
      }
    } catch let error as PostgrestError where error.code == "23505" {
      message = "A track with this name already exists, including hidden tracks."
    } catch { message = "Could not save. Your edits are still here to retry." }
  }
}
