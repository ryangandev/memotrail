import SwiftUI

/// Web `EntryPhotos`: an Item page's photos, shown below its writing. They are added and removed
/// in the editor; here they open in a preview that pages through them. One photo is wide, two
/// are 3:2, and three or more are squares, three to a row.
struct ItemPhotosView: View {
  let photos: [EntryPhotoInfo]
  let hasMore: Bool
  var baseURL = AppConfiguration.apiURL
  @State private var previewing: Selection?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private struct Selection: Identifiable {
    let id: UUID
  }

  private var items: [Item] {
    photos.map { Item(id: $0.id, name: $0.name, url: $0.displayURL(base: baseURL)) }
  }

  private struct Item: Identifiable {
    let id: UUID
    let name: String
    let url: URL?
  }

  var body: some View {
    let items = items
    let gap = horizontalSizeClass == .regular ? MTSpacing.s2 : MTSpacing.s1_5
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: gap), count: min(items.count, 3)),
        spacing: gap
      ) {
        ForEach(items) { item in
          tile(item)
        }
      }
      if hasMore {
        Text("Showing the first \(items.count) photos.")
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkFaint)
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Photos")
    .accessibilityIdentifier("item-photos")
    .sheet(item: $previewing) { selection in
      MTPhotoPreview(
        photos: items.compactMap { item in
          item.url.map { MTPhotoPreview.Photo(id: item.id, url: $0, name: item.name) }
        }, selectedID: selection.id)
    }
  }

  @ViewBuilder
  private func tile(_ item: Item) -> some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.medium)
    let ratio = aspectRatio
    Group {
      if item.url != nil {
        Button {
          previewing = Selection(id: item.id)
        } label: {
          Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { MTRemoteImage(url: item.url, accessibilityLabel: item.name) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.name)")
      } else {
        Color.clear
          .aspectRatio(ratio, contentMode: .fit)
          .overlay {
            Text("Photo unavailable")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkFaint)
              .multilineTextAlignment(.center)
              .padding(MTSpacing.s2)
          }
          .background(MTColor.surfaceSubtle)
          .accessibilityLabel("\(item.name), photo unavailable")
      }
    }
    .clipShape(shape)
    .contentShape(shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
    .accessibilityIdentifier("item-photo-\(item.id.uuidString.lowercased())")
  }

  /// Web's tile shapes, written as ratios of spacing steps: 16:9, 3:2, and square.
  private var aspectRatio: CGFloat {
    let afterFirst = photos.dropFirst()
    if afterFirst.isEmpty { return MTSpacing.s4 / MTSpacing.s2_25 }
    if afterFirst.dropFirst().isEmpty { return MTSpacing.s6 / MTSpacing.s4 }
    return MTSpacing.s4 / MTSpacing.s4
  }
}
