import Foundation
import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

@MainActor
struct EntryPhotoGalleryView: View {
  static let unavailable = "Photo unavailable. Close the viewer and refresh photos to retry."
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  let onChanged: () async -> Void
  @State private var photos: [EntryPhotoInfo]?
  @State private var selected: EntryPhotoInfo?
  @State private var attempt = 0
  @State private var busy = false
  @State private var message: String?
  @State private var hasMore = false
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var pending: [FirstTimePhotoDraft] = []
  @State private var removing: EntryPhotoInfo?
  @State private var confirmRemoval = false

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
      if let photos {
        PhotosPicker(
          selection: $pickerItems,
          maxSelectionCount: max(1, FirstTimePhotoDraft.maximumCount - photos.count),
          matching: .images
        ) {
          Label("Add photos", systemImage: "photo.badge.plus")
        }.disabled(
          busy || hasMore || !pending.isEmpty || photos.count >= FirstTimePhotoDraft.maximumCount)
      }
      Text(
        "Up to 12 photos, 50 MB each. Selected photos stay in this view until you upload or leave."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      if !pending.isEmpty {
        Text("Selected photos").font(MTTypography.title)
        ForEach(Array(pending.enumerated()), id: \.element.id) { index, draft in
          HStack {
            Text(draft.originalFilename ?? "Selected photo \(index + 1)").font(MTTypography.caption)
            Spacer()
            Button("Discard selection") { pending.removeAll { $0.id == draft.id } }.disabled(busy)
          }
        }
        Button(busy ? "Saving photos…" : "Upload photos") { Task { await upload() } }.disabled(busy)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: MTSpacing.s3) {
        ForEach(photos ?? []) { photo in
          VStack(spacing: MTSpacing.s2) {
            Button {
              selected = photo
            } label: {
              VStack(alignment: .leading, spacing: MTSpacing.s2) {
                MTRemoteImage(
                  url: photo.displayURL(base: AppConfiguration.apiURL), fit: .fit,
                  accessibilityLabel: photo.name, fallback: Self.unavailable
                ).frame(height: 160)
                Text(photo.name).font(MTTypography.caption).foregroundStyle(MTColor.ink)
              }.padding(MTSpacing.s2).frame(maxWidth: .infinity)
                .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.small))
            }.buttonStyle(.plain).accessibilityLabel("Open \(photo.name)")
            Button("Move to Trash", role: .destructive) {
              removing = photo
              confirmRemoval = true
            }
            .disabled(busy || !pending.isEmpty).accessibilityLabel("Move \(photo.name) to Trash")
          }
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
    .onChange(of: pickerItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await selectPhotos(items) }
    }
    .confirmationDialog(
      "Move photo to Trash?", isPresented: $confirmRemoval, titleVisibility: .visible
    ) {
      if let removing {
        Button("Move to Trash", role: .destructive) { Task { await remove(removing) } }
      }
    } message: {
      Text("The original will be preserved. You can restore the photo from Trash.")
    }
  }

  private func selectPhotos(_ items: [PhotosPickerItem]) async {
    guard !busy, pending.isEmpty, let photos else {
      pickerItems = []
      return
    }
    busy = true
    message = nil
    defer {
      pickerItems = []
      busy = false
    }
    for item in items.prefix(max(0, FirstTimePhotoDraft.maximumCount - photos.count)) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
          let mime = FirstTimeImageType.detect(
            data: data, typeIdentifiers: item.supportedContentTypes.map(\.identifier))
        else { throw FirstTimeEntryError.unsupportedPhotoType }
        let image = UIImage(data: data)
        pending.append(
          try FirstTimePhotoDraft.validate(
            data: data, mimeType: mime,
            originalFilename: nil, pixelWidth: image.map { Int($0.size.width * $0.scale) },
            pixelHeight: image.map { Int($0.size.height * $0.scale) }))
      } catch { message = error.localizedDescription }
    }
  }

  private func upload() async {
    guard !busy, !pending.isEmpty else { return }
    busy = true
    message = nil
    var failed: [FirstTimePhotoDraft] = []
    for draft in pending {
      do {
        if try await !EntryPhotoUpload.attach(
          draft, entryID: entryID, ownerID: ownerID, client: client)
        {
          failed.append(draft)
        }
      } catch { failed.append(draft) }
    }
    pending = failed
    await load(manageBusy: false)
    if failed.isEmpty {
      if photos != nil { message = "Photos attached." }
      await onChanged()
    } else {
      message =
        "Some photos are not confirmed. Keep this view open and select Upload photos again to retry safely."
    }
    busy = false
  }

  private func remove(_ photo: EntryPhotoInfo) async {
    guard !busy, pending.isEmpty else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let rows: [TrashedResidenceAttachment] = try await client.rpc(
        "trash_entry_attachment",
        params: TrashResidenceAttachmentParameters(attachmentID: photo.id)
      ).execute().value
      guard rows.first?.attachmentID == photo.id,
        try await client.auth.session.user.id == ownerID
      else { throw URLError(.badServerResponse) }
      await load(manageBusy: false)
      if photos != nil { message = "Photo moved to Trash. Restore it from Trash any time." }
      await onChanged()
    } catch {
      message = "Could not confirm removal. Refresh to check the current photos before retrying."
    }
  }

  private func load(manageBusy: Bool = true) async {
    if manageBusy { busy = true }
    photos = nil
    selected = nil
    message = nil
    hasMore = false
    defer { if manageBusy { busy = false } }
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
          MTRemoteImage(
            url: photos[index].displayURL(base: AppConfiguration.apiURL), fit: .fit,
            accessibilityLabel: photos[index].name, fallback: EntryPhotoGalleryView.unavailable
          ).id(photos[index].id)
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
