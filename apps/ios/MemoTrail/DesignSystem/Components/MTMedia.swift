import PhotosUI
import SwiftUI

/// The Web ProgressiveImage: a shimmer while the photo loads, a short fade when it arrives,
/// and a quiet fallback when it cannot load. It fills the frame it is given.
struct MTRemoteImage: View {
  let url: URL?
  var fit: ContentMode = .fill
  var accessibilityLabel: String?
  var fallback = "Photo unavailable"
  var background: Color = MTColor.surfaceSubtle
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Color.clear
      .overlay {
        AsyncImage(
          url: url,
          transaction: Transaction(
            animation: reduceMotion ? nil : MTEasing.enter.animation(duration: MTMotion.standard))
        ) { phase in
          switch phase {
          case .success(let image):
            image.resizable().aspectRatio(contentMode: fit).transition(.opacity)
              .accessibilityLabel(accessibilityLabel ?? "Photo")
              .accessibilityAddTraits(.isImage)
              .accessibilityHidden(accessibilityLabel == nil)
          case .failure: fallbackView
          case .empty:
            if url == nil { fallbackView } else { MTLoadingSkeleton() }
          @unknown default: MTLoadingSkeleton()
          }
        }
      }
      .background(background)
      .clipped()
      // Clipping hides overflow but does not limit hit testing, so filled photos would take
      // taps meant for neighboring controls.
      .contentShape(Rectangle())
  }

  private var fallbackView: some View {
    Text(fallback)
      .font(MTFont.caption)
      .foregroundStyle(MTColor.inkMuted)
      .multilineTextAlignment(.center)
      .padding(MTSpacing.s3)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(MTColor.surfaceSubtle)
  }
}

/// The loading shimmer shared by photos and other media that is still arriving.
struct MTLoadingSkeleton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShimmering = false

  var body: some View {
    MTColor.surfaceSubtle
      .overlay {
        if !reduceMotion {
          GeometryReader { proxy in
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0.35),
                .init(color: MTColor.skeletonHighlight, location: 0.5),
                .init(color: .clear, location: 0.65),
              ], startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6)
            )
            .frame(width: proxy.size.width * 2.2)
            .offset(x: isShimmering ? -proxy.size.width * 1.2 : 0)
          }
        }
      }
      .clipped()
      .contentShape(Rectangle())
      .onAppear {
        withAnimation(
          MTEasing.inOut.animation(duration: MTMotion.shimmer).repeatForever(autoreverses: false)
        ) {
          isShimmering = true
        }
      }
      .accessibilityElement()
      .accessibilityLabel("Loading photo")
  }
}

/// Batch photo upload progress as a ring, counting completed files rather than bytes.
struct MTUploadProgress: View {
  enum Variant { case inline, overlay }

  let completed: Int
  let total: Int
  var variant: Variant = .inline

  private var fraction: Double {
    total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
  }
  private var percentage: Int { Int((fraction * 100).rounded()) }

  var body: some View {
    Group {
      switch variant {
      case .inline:
        HStack(spacing: MTSpacing.s3) {
          ring
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
            Text("Uploading photos").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
            Text("\(completed) of \(total)").font(MTFont.note).monospacedDigit()
              .foregroundStyle(MTColor.inkFaint)
          }
        }
      case .overlay:
        ZStack {
          MTColor.scrimMedium
          ring.mtShadow(MTShadow.mediaControl)
        }
        .allowsHitTesting(false)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Photo upload progress")
    .accessibilityValue("\(completed) of \(total) photos, \(percentage)%")
  }

  private var ring: some View {
    ZStack {
      Circle().fill(MTColor.surfaceRaised)
      Circle().stroke(MTColor.surfaceSubtle, lineWidth: MTLayout.UploadRing.stroke)
        .padding(MTLayout.UploadRing.inset)
      Circle().trim(from: 0, to: fraction)
        .stroke(MTColor.accent, lineWidth: MTLayout.UploadRing.stroke)
        .rotationEffect(.degrees(-90))
        .padding(MTLayout.UploadRing.inset)
      Text("\(percentage)%")
        .font(.mtIcon(MTSize.Icon.s10, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(MTColor.ink)
    }
    .frame(width: MTSize.hitTarget, height: MTSize.hitTarget)
    .animation(MTEasing.enter.animation(duration: MTMotion.standard), value: fraction)
  }
}

/// The Web EntryPhotoField: saved and newly selected photos in square tiles, a picker, and
/// upload progress on the first new photo. Callers validate and upload the picked items.
struct MTPhotoField: View {
  struct SavedPhoto: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let name: String?
  }

  struct NewPhoto: Identifiable {
    let id: UUID
    let image: UIImage?
    let name: String?
  }

  let recordLabel: String
  let saved: [SavedPhoto]
  let new: [NewPhoto]
  let limit: Int
  @Binding var selection: [PhotosPickerItem]
  var progress: (completed: Int, total: Int)?
  let removeSaved: (SavedPhoto) -> Void
  let removeNew: (NewPhoto) -> Void
  @State private var previewing: SavedPhoto?

  private var remaining: Int { max(0, limit - saved.count - new.count) }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Photos")
      if !saved.isEmpty || !new.isEmpty {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: MTLayout.Grid.photo), spacing: MTSpacing.s2)],
          spacing: MTSpacing.s2
        ) {
          ForEach(saved) { photo in
            tile(removeLabel: "Remove \(photo.name ?? "photo")", remove: { removeSaved(photo) }) {
              if photo.url != nil {
                Button {
                  previewing = photo
                } label: {
                  MTRemoteImage(url: photo.url)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(photo.name ?? "\(recordLabel) photo")")
              } else {
                Text("Private photo").font(MTFont.note).foregroundStyle(MTColor.inkFaint)
              }
            }
          }
          ForEach(Array(new.enumerated()), id: \.element.id) { index, photo in
            tile(
              removeLabel: "Remove selected \(photo.name ?? "photo")",
              remove: { removeNew(photo) }
            ) {
              if let image = photo.image {
                Color.clear.overlay {
                  Image(uiImage: image).resizable().scaledToFill()
                    .accessibilityLabel("Selected \(photo.name ?? "photo")")
                }
                .clipped()
                .contentShape(Rectangle())
              }
              MTBadge(title: "New", tone: .solidAccent, size: .micro, uppercase: true)
                .padding(MTSpacing.chipGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
              if index == 0, let progress, progress.total > 0, progress.completed < progress.total {
                MTUploadProgress(
                  completed: progress.completed, total: progress.total, variant: .overlay)
              }
            }
          }
        }
        .padding(.bottom, MTSpacing.s1)
      }
      PhotosPicker(
        selection: $selection, maxSelectionCount: max(1, remaining), matching: .images
      ) {
        Label("Add photos", icon: .photo)
      }
      .mtButtonStyle(.secondary)
      .disabled(remaining == 0)
      Text("Originals stay private. Up to \(limit) photos, 50 MB each.")
        .font(MTFont.note)
        .foregroundStyle(MTColor.inkFaint)
    }
    .sheet(item: $previewing) { photo in
      MTPhotoPreview(saved: saved, recordLabel: recordLabel, selectedID: photo.id)
    }
  }

  private func tile<Content: View>(
    removeLabel: String, remove: @escaping () -> Void, @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack {
      MTColor.surfaceSubtle
      content()
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
    .contentShape(RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .overlay(alignment: .topTrailing) {
      Button(action: remove) {
        Image(.close).font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
          .foregroundStyle(MTColor.inverseInk)
          .frame(width: MTLayout.PhotoTile.removeButton, height: MTLayout.PhotoTile.removeButton)
          .background(
            MTColor.inverseSurface, in: Circle()
          )
          .frame(width: MTLayout.PhotoTile.removeTarget, height: MTLayout.PhotoTile.removeTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(removeLabel)
    }
  }
}

/// Saved photos shown whole, one at a time, like Web's photo viewer: swipe, or use Previous and
/// Next beside the position, to check them before removing or keeping them.
struct MTPhotoPreview: View {
  struct Photo: Identifiable, Hashable {
    let id: UUID
    let url: URL?
    let name: String
  }

  let photos: [Photo]
  @State private var selectedID: UUID
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(photos: [Photo], selectedID: UUID) {
    self.photos = photos
    _selectedID = State(initialValue: selectedID)
  }

  /// A saved photo list, named by its record when a photo has no name of its own.
  init(saved: [MTPhotoField.SavedPhoto], recordLabel: String, selectedID: UUID) {
    self.init(
      photos: saved.enumerated().map { index, photo in
        Photo(id: photo.id, url: photo.url, name: photo.name ?? "\(recordLabel) photo \(index + 1)")
      }, selectedID: selectedID)
  }

  private var index: Int { photos.firstIndex { $0.id == selectedID } ?? 0 }

  var body: some View {
    NavigationStack {
      TabView(selection: $selectedID) {
        ForEach(photos) { photo in
          MTRemoteImage(
            url: photo.url, fit: .fit, accessibilityLabel: photo.name, background: .black
          )
          .tag(photo.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(MTColor.photoBackdrop.ignoresSafeArea())
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if photos.count > 1 { navigation }
      }
      .environment(\.colorScheme, .dark)
      .navigationTitle(photos.indices.contains(index) ? photos[index].name : "Photo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.large])
  }

  /// Web's viewer navigation: Previous, the position, and Next.
  private var navigation: some View {
    HStack(spacing: MTSpacing.s3) {
      Button("Previous") { move(by: -1) }
        .mtButtonStyle(.secondary, size: .small)
        .disabled(index == 0)
        .accessibilityLabel("Previous photo")
      Spacer(minLength: 0)
      Text("\(index + 1) of \(photos.count)")
        .font(MTFont.caption)
        .foregroundStyle(MTColor.inkMuted)
        .monospacedDigit()
      Spacer(minLength: 0)
      Button("Next") { move(by: 1) }
        .mtButtonStyle(.secondary, size: .small)
        .disabled(index == photos.count - 1)
        .accessibilityLabel("Next photo")
    }
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s3)
    .background(MTColor.photoBackdrop.ignoresSafeArea())
  }

  private func move(by offset: Int) {
    guard photos.indices.contains(index + offset) else { return }
    withAnimation(reduceMotion ? nil : MTEasing.enter.animation(duration: MTMotion.photoPage)) {
      selectedID = photos[index + offset].id
    }
  }
}
