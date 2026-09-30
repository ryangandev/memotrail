import SwiftUI

extension EnvironmentValues {
  /// The fill behind text, select, and date fields. Form sections raise it above their surface,
  /// like Web `--editor-field-surface`.
  @Entry var mtFieldFill: Color = MTColor.surface
}

/// Web `formSection`: a titled group of editor fields on its own surface, with the uppercase
/// legend set into a gap in the top border.
struct MTFormSection<Content: View>: View {
  let title: String
  private let content: Content
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.large)
    VStack(alignment: .leading, spacing: MTSpacing.s4) { content }
      .environment(\.mtFieldFill, MTColor.surfaceRaised)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Web pads sections by 16 px on phones and 20 px elsewhere.
      .padding(horizontalSizeClass == .regular ? MTSpacing.s5 : MTSpacing.s4)
      .padding(.top, MTSpacing.s1)
      .background(MTColor.surface, in: shape)
      .overlay {
        shape.strokeBorder(MTColor.border, lineWidth: 1)
          .mask {
            Rectangle()
              .overlay(alignment: .topLeading) {
                // The legend's whole padded box, not only its glyphs, interrupts the border.
                placed(legend.hidden().background(Color.black)).blendMode(.destinationOut)
              }
              .compositingGroup()
          }
      }
      .overlay(alignment: .topLeading) { placed(legend).accessibilityAddTraits(.isHeader) }
      .padding(.top, MTSpacing.s2)
  }

  private var legend: some View {
    Text(title.uppercased())
      .font(MTFont.caption.weight(.semibold))
      .tracking(0.7)
      .foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, MTSpacing.s2)
  }

  /// Centers the legend on the top border, inset from the leading corner.
  private func placed(_ legend: some View) -> some View {
    legend
      .alignmentGuide(.top) { $0[VerticalAlignment.center] }
      .padding(.leading, MTSpacing.s4)
  }
}

/// A quiet explanation inside a form section, like Web `formSection > p`.
struct MTFormNote: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(MTFont.caption.weight(.regular))
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// Web focused-record `facts`: labeled values, each under a rule. Empty values are left out.
struct MTFactList: View {
  let facts: [(label: String, value: String?)]

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s5) {
      ForEach(Array(visibleFacts.enumerated()), id: \.offset) { _, fact in
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text(fact.label)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
          Text(fact.value)
            .font(MTFont.bodyLarge)
            .foregroundStyle(MTColor.ink)
            .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, MTSpacing.s3)
        .overlay(alignment: .top) { MTListDivider() }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var visibleFacts: [(label: String, value: String)] {
    facts.compactMap { fact in fact.value?.trimmed.nonEmpty.map { (fact.label, $0) } }
  }
}

/// Web focused-record `section`: a serif heading under a rule, such as Story or Organize.
struct MTDetailSection<Content: View>: View {
  let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(.system(.title3, design: .serif))
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, MTSpacing.s5)
    .overlay(alignment: .top) { MTListDivider() }
  }
}

/// Web focused-record `photos`: each saved photo at 4:3, one column on phones and 220 point
/// columns on wider screens. Selecting one shows it whole.
struct MTRecordPhotos: View {
  let recordLabel: String
  let photos: [MTPhotoField.SavedPhoto]
  @State private var previewing: MTPhotoField.SavedPhoto?

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 220), spacing: MTSpacing.s3)],
      spacing: MTSpacing.s3
    ) {
      ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
        let name = photo.name ?? "\(recordLabel) photo \(index + 1)"
        Button {
          previewing = photo
        } label: {
          Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { MTRemoteImage(url: photo.url, accessibilityLabel: name) }
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
            .contentShape(RoundedRectangle(cornerRadius: MTRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview \(name)")
      }
    }
    .sheet(item: $previewing) { photo in
      MTPhotoPreview(url: photo.url, name: photo.name ?? "\(recordLabel) photo")
    }
  }
}

/// A record card's visual when it has no photo or map: its icon and place over a soft accent
/// wash, like Web `homeMark`.
struct MTRecordMark: View {
  let icon: MTIcon
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Image(icon).font(.system(size: 22, weight: .medium)).foregroundStyle(MTColor.accent)
      Text(title)
        .font(.system(.subheadline, design: .serif))
        .foregroundStyle(MTColor.inkMuted)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .padding(MTSpacing.s4)
    .background {
      ZStack {
        LinearGradient(
          colors: [MTColor.surface, MTColor.surfaceSubtle], startPoint: .topLeading,
          endPoint: .bottomTrailing)
        RadialGradient(
          colors: [MTColor.accentSubtle, .clear], center: UnitPoint(x: 0.78, y: 0.24),
          startRadius: 0, endRadius: 140)
      }
    }
    .accessibilityHidden(true)
  }
}
