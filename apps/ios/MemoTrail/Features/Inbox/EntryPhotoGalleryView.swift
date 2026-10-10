import Foundation
import PhotosUI
@preconcurrency import Supabase
import SwiftUI
import UIKit

/// Web `EntryPhotoGallery`: the photos attached now, never a selected earlier version's. Like
/// Web, they load on request, and photos can be added or moved to Trash here through the shared
/// photo field.
@MainActor
struct EntryPhotoGalleryView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  let onChanged: () async -> Void

  @State private var photos: [EntryPhotoInfo]?
  @State private var hasMore = false
  @State private var isBusy = false
  @State private var message: String?
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var pending: [FirstTimePhotoDraft] = []
  @State private var uploadProgress: (completed: Int, total: Int)?
  @State private var removing: EntryPhotoInfo?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.panelGap) {
      HStack(alignment: .center, spacing: MTSpacing.s3) {
        Text("Current photos")
          .font(MTFont.heading)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        Button(photos == nil ? "Show photos" : "Refresh photos") { Task { await load() } }
          .mtButtonStyle(.secondary, size: .small, isLoading: isBusy && pending.isEmpty)
          .disabled(isBusy)
          .accessibilityIdentifier("entry-photos-load")
      }
      note(
        "Photos attached now, not the selected earlier version. Refresh to renew photo access or check for changes."
      )
      if let message {
        Text(message)
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.warm)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let photos {
        MTPhotoField(
          recordLabel: "Entry",
          saved: photos.map {
            MTPhotoField.SavedPhoto(
              id: $0.id, url: $0.displayURL(base: AppConfiguration.apiURL), name: $0.name)
          },
          new: pending.map {
            MTPhotoField.NewPhoto(
              id: $0.id, image: UIImage(data: $0.data), name: $0.originalFilename)
          },
          limit: FirstTimePhotoDraft.maximumCount, selection: $pickerItems,
          progress: uploadProgress,
          removeSaved: { saved in removing = photos.first { $0.id == saved.id } },
          removeNew: { photo in pending.removeAll { $0.id == photo.id } }
        )
        .disabled(isBusy || hasMore)
        if photos.isEmpty, pending.isEmpty {
          note("No saved photos on this Entry.")
        }
        if hasMore {
          note("Showing the first 100 current photos.")
        }
        if !pending.isEmpty {
          Button("Upload photos") { Task { await upload() } }
            .mtButtonStyle(isLoading: isBusy)
            .accessibilityIdentifier("entry-photos-upload")
        }
      }
    }
    .padding(horizontalSizeClass == .regular ? MTSpacing.s5 : MTSpacing.panelGap)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Current photos")
    .onChange(of: pickerItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await selectPhotos(items) }
    }
    .confirmationDialog(
      "Move “\(removing?.name ?? "this photo")” to Trash?",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible, presenting: removing
    ) { photo in
      Button("Move photo to Trash", role: .destructive) { Task { await remove(photo) } }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("The original will be preserved for recovery.")
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(MTFont.supporting)
      .foregroundStyle(MTColor.inkMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func selectPhotos(_ items: [PhotosPickerItem]) async {
    defer { pickerItems = [] }
    guard let photos else { return }
    let available = max(0, FirstTimePhotoDraft.maximumCount - photos.count - pending.count)
    var failure: String?
    for item in items.prefix(available) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
          let mime = FirstTimeImageType.detect(
            data: data, typeIdentifiers: item.supportedContentTypes.map(\.identifier))
        else { throw FirstTimeEntryError.unsupportedPhotoType }
        let image = UIImage(data: data)
        pending.append(
          try FirstTimePhotoDraft.validate(
            data: data, mimeType: mime, originalFilename: nil,
            pixelWidth: image.map { Int($0.size.width * $0.scale) },
            pixelHeight: image.map { Int($0.size.height * $0.scale) }))
      } catch {
        failure = error.localizedDescription
      }
    }
    if items.count > available {
      failure = "Keep up to \(FirstTimePhotoDraft.maximumCount) photos with one Entry."
    }
    message = failure
  }

  private func upload() async {
    guard !isBusy, !pending.isEmpty else { return }
    isBusy = true
    message = nil
    var failed: [FirstTimePhotoDraft] = []
    let drafts = pending
    for (index, draft) in drafts.enumerated() {
      uploadProgress = (completed: index, total: drafts.count)
      do {
        if try await !EntryPhotoUpload.attach(
          draft, entryID: entryID, ownerID: ownerID, client: client)
        {
          failed.append(draft)
        }
      } catch {
        failed.append(draft)
      }
    }
    uploadProgress = nil
    pending = failed
    await fetch()
    isBusy = false
    if failed.isEmpty {
      MTToastCenter.shared.success("Photos attached.")
      await onChanged()
    } else {
      message =
        "Some photos are not confirmed. Keep this view open and select Upload photos again to retry safely."
    }
  }

  private func remove(_ photo: EntryPhotoInfo) async {
    guard !isBusy else { return }
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let rows: [TrashedResidenceAttachment] = try await client.rpc(
        "trash_entry_attachment",
        params: TrashResidenceAttachmentParameters(attachmentID: photo.id)
      ).execute().value
      guard rows.first?.attachmentID == photo.id else { throw URLError(.badServerResponse) }
      await fetch()
      MTToastCenter.shared.info("Photo moved to Trash. Restore it from Trash any time.")
      await onChanged()
    } catch {
      await fetch()
      message = "Could not confirm removal. Refresh to check the current photos before retrying."
    }
  }

  private func load() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    message = nil
    await fetch()
  }

  private func fetch() async {
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
