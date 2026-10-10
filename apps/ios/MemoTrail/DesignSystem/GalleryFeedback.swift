#if DEBUG
  import PhotosUI
  import SwiftUI

  struct FeedbackSpecimens: View {
    @State private var uploaded = 3
    @State private var toastMessage = ""

    private func message(_ sample: String) -> String { toastMessage.trimmed.nonEmpty ?? sample }

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "Toast", api: "MTToastCenter.shared · success · info · error · tone",
          description:
            "Like Web, toasts rise from the bottom, above sheets and clear of the tab bar, sheet actions, and keyboard. Errors stay longer, and swiping down dismisses one early."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            GalleryCase(.toastTones) {
              GalleryToasts(
                toasts: MTToastTone.allCases.map { MTToast(message: $0.sampleMessage, tone: $0) })
            }
            GalleryCaseSeparator()
            GalleryCase(.toastLongMessage) {
              GalleryToasts(toasts: [
                MTToast(
                  message:
                    "Could not upload 3 photos. They stay on this device and upload when MemoTrail can be reached.",
                  tone: .error)
              ])
            }
            GalleryCaseSeparator()
            // A custom message previews wrapping, and typing it shows toasts over the keyboard.
            MTTextField(
              label: "Message", text: $toastMessage, prompt: "Each button's sample message"
            )
            .accessibilityIdentifier("toast-message")
            MTFlowLayout(spacing: MTSpacing.s2) {
              Button("Show success") { MTToastCenter.shared.success(message("Changes saved.")) }
                .mtButtonStyle()
              Button("Show info") { MTToastCenter.shared.info(message("Moved to Trash.")) }
                .mtButtonStyle(.secondary)
              Button("Show error") {
                MTToastCenter.shared.error(message("Could not save. Try again."))
              }
              .mtButtonStyle(.danger)
            }
          }
        }

        GallerySpecimen(
          title: "UploadProgress", api: "completed · total · variant: inline | overlay",
          description: "Counts completed files, not uploaded bytes."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTUploadProgress(completed: uploaded, total: 5)
            ZStack {
              GallerySampleArtwork()
              MTUploadProgress(completed: uploaded, total: 5, variant: .overlay)
            }
            .frame(width: MTLayout.Gallery.sampleTile, height: MTLayout.Gallery.sampleTile)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
            Button("Advance upload", systemImage: MTIcon.refresh.systemName) {
              uploaded = uploaded >= 5 ? 0 : uploaded + 1
            }
            .mtButtonStyle(.secondary, size: .small)
          }
        }

        GallerySpecimen(
          title: "RemoteImage", api: "url · fit: fill | fit · accessibilityLabel · fallback",
          description:
            "Loading is normally brief while the photo downloads. Failure replaces the shimmer with the fallback."
        ) {
          HStack(alignment: .top, spacing: MTSpacing.s2) {
            imageState("Loading", MTLoadingSkeleton())
            imageState(
              "Loaded", MTRemoteImage(url: GallerySamples.artworkURL, accessibilityLabel: "Coast"))
            imageState(
              "Failure",
              MTRemoteImage(url: GallerySamples.missingImageURL, fallback: "Photo unavailable"))
          }
        }

        GallerySpecimen(
          title: "Inline feedback", api: "title · message · tone · systemImage",
          description: "Persistent context that belongs next to the content it explains."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTFeedback(
              title: "Saved to Library", message: "Your Entry is ready to revisit.",
              tone: .success, systemImage: "checkmark.circle")
            MTFeedback(
              title: "Draft saved on this iPhone",
              message: "You can return to it before publishing.", tone: .neutral,
              systemImage: "clock.arrow.circlepath")
            MTFeedback(
              title: "Connection unavailable",
              message: "Your draft is safe. Try again when you are online.", tone: .warm,
              systemImage: "wifi.slash")
          }
        }

        GallerySpecimen(title: "Loading", api: "ProgressView · label") {
          ProgressView("Loading your records...")
            .font(MTFont.caption)
            .tint(MTColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MTSpacing.s4)
        }
      }
    }

    private func imageState(_ title: String, _ image: some View) -> some View {
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        image
          .aspectRatio(4 / 3, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
        Text(title).font(MTFont.note).foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity)
    }
  }

  extension MTToastTone {
    /// The Web gallery's sample message for each tone.
    fileprivate var sampleMessage: String {
      switch self {
      case .success: "Entry saved."
      case .info: "Pending Entry discarded."
      case .error: "Could not move to Trash. Try again."
      }
    }
  }

  /// Toasts drawn in place, at the toast center's width. Each reads as one element, so VoiceOver
  /// and UI tests reach only the live toasts' dismiss actions.
  private struct GalleryToasts: View {
    let toasts: [MTToast]

    var body: some View {
      VStack(spacing: MTSpacing.s2) {
        ForEach(toasts) { toast in
          MTToastView(toast: toast) {}
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(toast.tone.rawValue.capitalized) toast: \(toast.message)")
        }
      }
      .frame(maxWidth: MTSize.Toast.width)
      .padding(.vertical, MTSpacing.s2)
    }
  }

  /// The Web EntryPhotoField specimen: two saved photos to page between in the preview, local
  /// selections, and simulated upload.
  struct PhotoFieldSpecimen: View {
    @State private var saved = [
      MTPhotoField.SavedPhoto(
        id: UUID(), url: GallerySamples.artworkURL, name: "coast-memory.jpg"),
      MTPhotoField.SavedPhoto(
        id: UUID(), url: GallerySamples.artworkURL, name: "harbor-walk.jpg"),
    ]
    @State private var new: [MTPhotoField.NewPhoto] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var uploaded: Int?

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        MTPhotoField(
          recordLabel: "Entry", saved: saved, new: new, limit: 10, selection: $selection,
          progress: uploaded.map { (completed: $0, total: new.count) },
          removeSaved: { photo in saved.removeAll { $0.id == photo.id } },
          removeNew: { photo in new.removeAll { $0.id == photo.id } })
        HStack(spacing: MTSpacing.s2) {
          Button("Add sample") {
            new.append(
              MTPhotoField.NewPhoto(
                id: UUID(), image: GallerySamples.artworkImage, name: "sample-\(new.count + 1).png")
            )
          }
          .mtButtonStyle(.ghost, size: .small)
          Button("Simulate upload") { simulateUpload() }
            .mtButtonStyle(.ghost, size: .small)
            .disabled(new.isEmpty || uploaded != nil)
        }
        Text("\(saved.count) saved · \(new.count) new")
          .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          .accessibilityIdentifier("design-photo-status")
        Text(
          "Select local photos or add a sample to preview progress centered on the first new photo. Nothing is uploaded."
        )
        .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      }
      .onChange(of: selection) { _, items in
        Task {
          for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            new.append(MTPhotoField.NewPhoto(id: UUID(), image: UIImage(data: data), name: nil))
          }
          selection = []
        }
      }
    }

    private func simulateUpload() {
      uploaded = 0
      Task {
        while let count = uploaded, count < new.count {
          try? await Task.sleep(for: .milliseconds(700))
          uploaded = count + 1
        }
        try? await Task.sleep(for: .milliseconds(400))
        uploaded = nil
      }
    }
  }

  extension GallerySamples {
    /// The sample landscape rendered once to a temporary PNG, so remote-image specimens load it
    /// through the same URL path as real photos.
    @MainActor static let artworkImage: UIImage? = renderArtwork()

    @MainActor private static func renderArtwork() -> UIImage? {
      let renderer = ImageRenderer(
        content: GallerySampleArtwork().frame(
          width: MTLayout.Gallery.artworkWidth, height: MTLayout.Gallery.artworkHeight))
      renderer.scale = 1
      return renderer.uiImage
    }

    @MainActor static let artworkURL: URL? = {
      let url = FileManager.default.temporaryDirectory.appending(path: "gallery-coast.png")
      guard let data = artworkImage?.pngData(), (try? data.write(to: url)) != nil else {
        return nil
      }
      return url
    }()

    /// Data that is not an image, like the error body of an expired photo link.
    static let missingImageURL = URL(string: "data:image/png;base64,bm90IGFuIGltYWdl")
  }
#endif
