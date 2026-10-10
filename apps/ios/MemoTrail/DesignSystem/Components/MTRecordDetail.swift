import SwiftUI

extension EnvironmentValues {
  /// The fill behind text, select, and date fields. Form sections raise it above their surface,
  /// like Web `--editor-field-surface`.
  @Entry var mtFieldFill: Color = MTColor.surface
}

/// Web `formSection`: a titled group of editor fields on its own surface, with the uppercase
/// legend set into a gap in the top border. The accent tone marks a section that acts on the
/// saved record, like the Goal editor's Bucket List milestone.
struct MTFormSection<Content: View>: View {
  enum Tone: Sendable { case neutral, accent }

  let title: String
  let tone: Tone
  private let content: Content
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(_ title: String, tone: Tone = .neutral, @ViewBuilder content: () -> Content) {
    self.title = title
    self.tone = tone
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.large)
    // Opacity over the neutral colors matches Web's `color-mix` in sRGB.
    let isAccent = tone == .accent
    VStack(alignment: .leading, spacing: MTSpacing.s4) { content }
      .environment(\.mtFieldFill, MTColor.surfaceRaised)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Web pads sections by 16 px on phones and 20 px elsewhere.
      .padding(horizontalSizeClass == .regular ? MTSpacing.s5 : MTSpacing.s4)
      .padding(.top, MTSpacing.s1)
      .background {
        shape.fill(MTColor.surface)
          .overlay(shape.fill(isAccent ? MTColor.accentNotice : .clear))
      }
      .overlay {
        shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin)
          .overlay(
            shape.strokeBorder(
              isAccent ? MTColor.accentGroupBorder : .clear, lineWidth: MTSize.Stroke.thin)
          )
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
      .mtTextRole(.legend)
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

/// A quiet explanation inside a form section, like Web `formSection > p`. Some sections set it
/// fainter, like the Goal editor's Related Items.
struct MTFormNote: View {
  let text: String
  let color: Color

  init(_ text: String, color: Color = MTColor.inkMuted) {
    self.text = text
    self.color = color
  }

  var body: some View {
    Text(text)
      .font(MTFont.detail)
      .foregroundStyle(color)
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
            .font(MTFont.detail)
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

  /// Whether any fact has a value; like Web `Fact`, empty ones are left out.
  static func hasValues(_ facts: [(label: String, value: String?)]) -> Bool {
    facts.contains { $0.value?.trimmed.nonEmpty != nil }
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
        .font(MTFont.quietTitle)
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
/// columns on wider screens. Selecting one shows it whole, with the others a swipe away.
struct MTRecordPhotos: View {
  let recordLabel: String
  let photos: [MTPhotoField.SavedPhoto]
  @State private var previewing: MTPhotoField.SavedPhoto?

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: MTLayout.Grid.detail), spacing: MTSpacing.s3)],
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
      MTPhotoPreview(saved: photos, recordLabel: recordLabel, selectedID: photo.id)
    }
  }
}

/// A record card's visual when it has no photo or map: its icon and place over a soft accent
/// wash, like Web `homeMark`. Phones center it vertically, like Web below 480 px.
struct MTRecordMark: View {
  let icon: MTIcon
  let title: String
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let isRegular = horizontalSizeClass == .regular
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Image(icon).font(.mtIcon(MTSize.Icon.s22, weight: .medium)).foregroundStyle(MTColor.accent)
      Text(title)
        .font(isRegular ? MTFont.quietTitle : MTFont.quietTitleSmall)
        .foregroundStyle(MTColor.inkMuted)
        .lineLimit(2)
    }
    .frame(
      maxWidth: .infinity, maxHeight: .infinity,
      alignment: isRegular ? .bottomLeading : .leading
    )
    .padding(isRegular ? MTSpacing.s5 : MTSpacing.s4)
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

/// Web `FocusedRecordDetail`: a record's own page with its photos, facts, Story, and Organize,
/// an Edit action beside the title, and Version history. `extra` follows Organize, such as a
/// Goal's connected items.
struct MTFocusedRecordPage<Extra: View>: View {
  let kind: String
  let title: String
  var photos: [MTPhotoField.SavedPhoto] = []
  let facts: [(label: String, value: String?)]
  var story: String?
  var storyTitle = "Story"
  var collectionNames: [String] = []
  var tagNames: [String] = []
  let edit: () -> Void
  var history: (() -> Void)?
  @ViewBuilder var extra: Extra

  /// Identifiers follow the Kind, such as `edit-first-time`.
  private var slug: String { kind.lowercased().replacingOccurrences(of: " ", with: "-") }

  var body: some View {
    MTPage(width: .compact, spacing: MTSpacing.s6) {
      MTPageHeader(eyebrow: kind, title: title) {
        Button(action: edit) {
          Label("Edit", icon: .edit)
        }
        .mtButtonStyle(.ghost, size: .small)
        .accessibilityLabel("Edit \(kind)")
        .accessibilityIdentifier("edit-\(slug)")
      }
      VStack(alignment: .leading, spacing: MTSpacing.s8) {
        if !photos.isEmpty {
          MTRecordPhotos(recordLabel: kind, photos: photos)
        }
        if MTFactList.hasValues(facts) {
          MTFactList(facts: facts)
        }
        if let story = story?.trimmed.nonEmpty {
          MTDetailSection(storyTitle) {
            Text(story)
              .font(MTFont.bodyLarge)
              .foregroundStyle(MTColor.ink)
              .mtLineSpacing(MTLineHeight.relaxed)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if !collectionNames.isEmpty || !tagNames.isEmpty {
          MTDetailSection("Organize") {
            MTFlowLayout(spacing: MTSpacing.s2) {
              ForEach(collectionNames, id: \.self) { MTBadge(title: $0, tone: .neutral) }
              ForEach(tagNames, id: \.self) { MTBadge(title: "#\($0)", tone: .neutral) }
            }
          }
        }
        extra
      }
      if let history {
        Button("Version history", action: history)
          .mtButtonStyle(.secondary)
          .accessibilityIdentifier("\(slug)-version-history")
      }
    }
  }
}

extension MTFocusedRecordPage where Extra == EmptyView {
  init(
    kind: String, title: String, photos: [MTPhotoField.SavedPhoto] = [],
    facts: [(label: String, value: String?)], story: String? = nil, storyTitle: String = "Story",
    collectionNames: [String] = [], tagNames: [String] = [], edit: @escaping () -> Void,
    history: (() -> Void)? = nil
  ) {
    self.init(
      kind: kind, title: title, photos: photos, facts: facts, story: story,
      storyTitle: storyTitle, collectionNames: collectionNames, tagNames: tagNames, edit: edit,
      history: history
    ) { EmptyView() }
  }
}

/// Web `FocusedDetailUnavailable`: the record may be in Trash or no longer accessible.
struct MTFocusedRecordUnavailable: View {
  let kind: String
  let backTitle: String
  let back: () -> Void

  var body: some View {
    MTPage(width: .compact, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: kind, title: "\(kind) unavailable",
        description: "This record may have moved to Trash or no longer be accessible.")
      Button(backTitle, action: back)
        .mtButtonStyle()
    }
  }
}
