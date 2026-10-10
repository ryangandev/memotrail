#if DEBUG
  import SwiftUI

  // Sections follow the Web Design System order so both galleries can be reviewed side by side.
  enum DesignSystemSection: String, CaseIterable, Identifiable {
    case primitives, foundations, identity, layout, forms, writing, containers, feedback
    var id: String { rawValue }
    var index: String {
      String(format: "%02d", Self.allCases.firstIndex(of: self) ?? 0)
    }
    var title: String {
      switch self {
      case .primitives: "Shared primitives"
      case .foundations: "Foundations"
      case .identity: "Identity & icons"
      case .layout: "Layout"
      case .forms: "Forms"
      case .writing: "Writing & formatting"
      case .containers: "Containers & data"
      case .feedback: "Feedback & media"
      }
    }
    var detail: String {
      switch self {
      case .primitives: "Buttons, sheets, confirmations, page headers, and empty states."
      case .foundations:
        "Semantic colors, type roles, spacing, radius, shadow, motion, size, state, elevation, and materials."
      case .identity: "The MemoTrail mark, its motion, and the shared icon vocabulary."
      case .layout: "Page widths, gutters, and section rhythm."
      case .forms: "Text, search, select, and date fields, organization, photos, and labels."
      case .writing: "Rich text, a collapsible Aa toolbar, and saved note previews."
      case .containers: "Record and Collection cards, rich writing, and compact record summaries."
      case .feedback: "Toasts, upload progress, remote images, and inline states."
      }
    }
    var icon: MTIcon {
      switch self {
      case .primitives: .check
      case .foundations: .sparkle
      case .identity: .star
      case .layout: .dashboard
      case .forms: .edit
      case .writing: .bold
      case .containers: .archive
      case .feedback: .inbox
      }
    }
  }

  struct DesignSystemGallery: View {
    @State private var appearance = NativeAppearance.system
    @State private var previewSize: DynamicTypeSize?
    @Environment(\.dynamicTypeSize) private var systemSize

    var body: some View {
      MTPage(width: .canvas, spacing: MTSpacing.s6) {
        MTPageHeader(
          eyebrow: "Soft Ledger · iOS", title: "Design System",
          description:
            "A live inventory of MemoTrail's native tokens, reusable components, variants, and states."
        )
        GalleryPreviewStatus()
        MTCard {
          HStack(spacing: MTSpacing.s3) {
            MemoTrailMark().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: MTSpacing.s1) {
              Text("MemoTrail").font(MTFont.title).foregroundStyle(MTColor.ink)
              Text("Shared meaning. Native interactions.").font(MTFont.caption)
                .foregroundStyle(MTColor.inkMuted)
            }
          }
        }
        ForEach(DesignSystemSection.allCases) { section in
          NavigationLink(value: section) {
            MTCard {
              HStack(alignment: .top, spacing: MTSpacing.s3) {
                Text(section.index).font(MTFont.caption.monospaced()).foregroundStyle(
                  MTColor.inkFaint
                ).frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: MTSpacing.s1) {
                  Label(section.title, icon: section.icon).font(MTFont.heading)
                    .foregroundStyle(MTColor.ink)
                  Text(section.detail).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(.chevron).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("design-section-\(section.rawValue)")
        }
        Text(
          "Specimens use production components and local demo state only. Nothing is saved to your archive."
        )
        .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      }
      .navigationTitle("Design System").navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: DesignSystemSection.self) { section in
        DesignSystemSpecimens(section: section)
          .dynamicTypeSize(previewSize ?? systemSize)
          .preferredColorScheme(appearance.colorScheme)
          .preference(key: NativeReviewAppearancePreference.self, value: appearance)
          .toolbar { reviewControls }
      }
      .toolbar { reviewControls }
      .preferredColorScheme(appearance.colorScheme)
      .preference(key: NativeReviewAppearancePreference.self, value: appearance)
      .dynamicTypeSize(previewSize ?? systemSize)
    }

    @ToolbarContentBuilder private var reviewControls: some ToolbarContent {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Appearance", selection: $appearance) {
            ForEach(NativeAppearance.allCases, id: \.self) { value in Text(value.title).tag(value) }
          }
          Picker("Text size", selection: $previewSize) {
            Text("System text size").tag(nil as DynamicTypeSize?)
            Text("Standard text").tag(Optional(DynamicTypeSize.large))
            Text("Large text").tag(Optional(DynamicTypeSize.xxxLarge))
            Text("Accessibility text").tag(Optional(DynamicTypeSize.accessibility3))
          }
        } label: {
          Label("Preview settings", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("design-preview-settings")
        .accessibilityValue(appearance.title)
      }
    }
  }

  struct GalleryPreviewStatus: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      Text(colorScheme == .dark ? "Dark appearance" : "Light appearance")
        .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        .accessibilityIdentifier("design-preview-status")
    }
  }

  /// A titled specimen card mirroring the Web gallery: header, optional API summary, then content.
  struct GallerySpecimen<Content: View>: View {
    let title: String
    var api: String?
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text(title).font(MTFont.titleSmall).foregroundStyle(MTColor.ink)
            .accessibilityAddTraits(.isHeader)
          if let description {
            Text(description).font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          if let api {
            Text(api).font(MTFont.caption.monospaced()).foregroundStyle(MTColor.inkMuted)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MTSpacing.s4)
        Rectangle().fill(MTColor.border).frame(height: 1)
        content
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(MTSpacing.s4)
          .background(MTColor.surface)
      }
      .background(MTColor.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
    }
  }

  private struct DesignSystemSpecimens: View {
    let section: DesignSystemSection

    var body: some View {
      MTPage(width: .canvas, spacing: MTSpacing.s6) {
        MTPageHeader(
          eyebrow: "\(section.index) · Native components", title: section.title,
          description: section.detail)
        GalleryPreviewStatus()
        switch section {
        case .primitives: PrimitiveSpecimens()
        case .foundations: FoundationSpecimens()
        case .identity: IdentitySpecimens()
        case .layout: LayoutSpecimens()
        case .forms: FormSpecimens()
        case .writing: NativeWritingSpecimens()
        case .containers: ContainerSpecimens()
        case .feedback: FeedbackSpecimens()
        }
      }
      .navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
    }
  }

  #Preview {
    NavigationStack { DesignSystemGallery() }
  }
#endif
