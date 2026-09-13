import Foundation
@preconcurrency import Supabase
import SwiftUI

@MainActor
struct EntryPhotoGalleryView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  @State private var photos: [EntryPhotoInfo]?
  @State private var selected: EntryPhotoInfo?
  @State private var attempt = 0
  @State private var busy = false
  @State private var message: String?
  @State private var hasMore = false

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text("Current photos").font(MTTypography.title)
      Text(
        "Photos attached now, not the selected earlier version. Refresh to renew photo access or check for changes."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      Button(busy ? "Loading photos…" : photos == nil ? "Show photos" : "Refresh photos") {
        busy = true
        attempt += 1
      }.disabled(busy)
      if let message { Text(message).foregroundStyle(MTColor.warm) }
      if photos?.isEmpty == true {
        Text("No saved photos on this Entry.").foregroundStyle(MTColor.inkMuted)
      }
      if hasMore { Text("Showing the first 100 current photos.").font(MTTypography.caption) }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: MTSpacing.s3) {
        ForEach(photos ?? []) { photo in
          Button {
            selected = photo
          } label: {
            VStack(alignment: .leading, spacing: MTSpacing.s2) {
              EntryGalleryImage(photo: photo).frame(height: 160)
              Text(photo.name).font(MTTypography.caption).foregroundStyle(MTColor.ink)
            }.padding(MTSpacing.s2).frame(maxWidth: .infinity)
              .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.small))
          }.buttonStyle(.plain).accessibilityLabel("Open \(photo.name)")
        }
      }.id(attempt)
    }
    .task(id: attempt) {
      guard attempt > 0 else { return }
      await load()
    }
    .fullScreenCover(item: $selected) { photo in
      EntryPhotoViewer(photos: photos ?? [], selectedID: photo.id)
    }
  }

  private func load() async {
    photos = nil
    selected = nil
    message = nil
    hasMore = false
    defer { busy = false }
    do {
      let result: EntryPhotosResponse = try await MediaDelivery.metadataRequest(
        path: "api/media/photos", query: URLQueryItem(name: "entryId", value: entryID.uuidString),
        client: client, ownerID: ownerID)
      try Task.checkCancellation()
      photos = result.photos
      hasMore = result.hasMore
    } catch {
      if !Task.isCancelled {
        message = "Could not load photos. Check your connection and try again."
      }
    }
  }
}

@MainActor
private struct EntryGalleryImage: View {
  let photo: EntryPhotoInfo
  var body: some View {
    AsyncImage(url: photo.displayURL(base: AppConfiguration.apiURL)) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFit().accessibilityLabel(photo.name)
      case .empty where photo.displayURL(base: AppConfiguration.apiURL) != nil:
        ProgressView("Loading photo…").frame(maxWidth: .infinity, maxHeight: .infinity)
      default:
        Text("Photo unavailable. Close the viewer and refresh photos to retry.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
          .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

@MainActor
private struct EntryPhotoViewer: View {
  let photos: [EntryPhotoInfo]
  @State private var index: Int
  @Environment(\.dismiss) private var dismiss

  init(photos: [EntryPhotoInfo], selectedID: UUID) {
    self.photos = photos
    _index = State(initialValue: photos.firstIndex(where: { $0.id == selectedID }) ?? 0)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: MTSpacing.s3) {
        if photos.indices.contains(index) {
          Text(photos[index].name).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
          EntryGalleryImage(photo: photos[index]).id(photos[index].id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          HStack {
            Button("Previous") { index -= 1 }.disabled(index == 0).accessibilityLabel(
              "Previous photo")
            Spacer()
            Text("\(index + 1) of \(photos.count)").font(MTTypography.caption)
            Spacer()
            Button("Next") { index += 1 }.disabled(index == photos.count - 1).accessibilityLabel(
              "Next photo")
          }.buttonStyle(.bordered).controlSize(.large)
        }
      }.padding().background(MTColor.canvas).navigationTitle("Photo viewer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
    }.tint(MTColor.accent)
  }
}
