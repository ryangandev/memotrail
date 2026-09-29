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
      case .foundations: "Semantic colors, type roles, spacing, radius, shadow, and motion."
      case .identity: "The MemoTrail mark, its motion, and the shared icon vocabulary."
      case .layout: "Page widths, gutters, and section rhythm."
      case .forms: "Search, fields, pickers, dates, labels, and native presentation."
      case .writing: "Rich text, a collapsible Aa toolbar, and saved note previews."
      case .containers: "Record summaries, long content, and photo placeholders."
      case .feedback: "Empty, loading, error, success, and local draft states."
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

  private struct FilterChipSpecimen: View {
    @State private var selectedKind = "Entries"

    var body: some View {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MTSpacing.s2) {
          ForEach(["All records", "Entries", "Entities", "Goals"], id: \.self) { title in
            MTFilterChip(title: title, isSelected: selectedKind == title) { selectedKind = title }
          }
        }
      }
    }
  }

  private struct FormSpecimens: View {
    @State private var query = ""
    @State private var showingEditor = false

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(title: "Search field", api: "prompt · text") {
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            MTSearchField(prompt: "Find in your Life Wiki", text: $query)
            Text(query.isEmpty ? "Search is empty." : "Search preview: \(query)").font(
              MTFont.caption
            )
            .foregroundStyle(MTColor.inkMuted)
          }
        }
        GallerySpecimen(
          title: "Native form & presentation",
          description: "Fields keep system focus, selection, keyboard, and date-picker behavior."
        ) {
          Button("Open sample editor", systemImage: "square.and.pencil") { showingEditor = true }
            .mtButtonStyle().accessibilityIdentifier("design-open-editor")
        }
        GallerySpecimen(
          title: "Badge",
          api:
            "micro | small | medium · accent, neutral, warm, success, outline, solidAccent, inverse · uppercase · one line"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTFlowLayout(spacing: MTSpacing.s2) {
              MTBadge(title: "Entry", size: .micro, uppercase: true)
              MTBadge(title: "Home", tone: .neutral, uppercase: true)
              MTBadge(title: "Keyword search", size: .medium)
              MTBadge(title: "In Inbox", tone: .warm)
              MTBadge(title: "Vehicle", tone: .outline)
              MTBadge(title: "Saved", tone: .success)
              MTBadge(title: "3 photos", tone: .inverse)
              MTBadge(title: "Current", tone: .solidAccent)
              MTBadge(title: "#learning", size: .medium)
              MTBadge(title: "#旅行", size: .medium)
            }
            MTBadge(title: "A long label that stays on one line within the available width")
            MTBadge(title: "#值得记住的那些很长很长的日常片段，一行之内保持完整的形状", size: .medium)
            MTOrganizationBadges(
              collectionNames: ["Early years"], tagNames: ["family", "travel", "milestone", "home"])
          }
        }
        GallerySpecimen(title: "FilterChip", api: "title · isSelected · action") {
          FilterChipSpecimen()
        }
        MTFeedback(
          title: "Contextual validation",
          message: "Keep date precision and validation close to the relevant field.", tone: .warm,
          systemImage: "calendar.badge.exclamationmark")
      }
      .sheet(isPresented: $showingEditor) { DesignSystemEditor() }
    }
  }

  private struct ContainerSpecimens: View {
    @State private var chinese = false

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        Toggle("Preview Chinese & long content", isOn: $chinese)
        MTCard {
          MTRecordSummary(
            title: chinese ? "第一次沿着海岸慢慢走，记住了风、灯塔，以及那天没有说完的故事。" : "A quiet afternoon by the coast",
            subtitle: chinese
              ? "旧金山，加利福尼亚 · 2026年9月" : "San Francisco, California · September 2026",
            kind: "First Time")
        }
        MTCard {
          MTRecordSummary(
            title: "The next chapter", subtitle: "No occurred date · On this iPhone", kind: "Entry",
            status: "In Inbox")
        }
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTMediaPlaceholder(state: .empty).frame(height: 160)
            MTRecordSummary(title: "Our first home", subtitle: "Austin, Texas", kind: "Home")
          }
        }
        MTMediaPlaceholder(state: .loading).frame(height: 120)
        MTMediaPlaceholder(state: .failed).frame(height: 120)
      }
    }
  }

  private struct FeedbackSpecimens: View {
    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        MTFeedback(
          title: "Saved to Library", message: "Your Entry is ready to revisit.", tone: .success,
          systemImage: "checkmark.circle")
        MTFeedback(
          title: "Draft saved on this iPhone", message: "You can return to it before publishing.",
          tone: .neutral, systemImage: "clock.arrow.circlepath")
        MTFeedback(
          title: "Connection unavailable",
          message: "Your draft is safe. Try again when you are online.", tone: .warm,
          systemImage: "wifi.slash")
        MTCard {
          ProgressView("Loading your records...").frame(maxWidth: .infinity).padding(
            .vertical, MTSpacing.s4)
        }
        MTEmptyState(
          title: "Nothing here yet",
          message: "Capture something worth keeping, then organize it into Library.",
          icon: .library)
      }
    }
  }

  private struct DesignSystemEditor: View {
    @State private var title = "A moment worth keeping"
    @State private var note = NSAttributedString(string: "")
    @State private var date = Date()
    @State private var precision = "Day"
    @State private var includeDate = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        Form {
          Section("Entry") {
            TextField("Title", text: $title).accessibilityIdentifier("design-editor-title")
            MTRichTextEditor(text: $note, accessibilityIdentifier: "design-editor-note")
          }
          Section("When it happened") {
            Toggle("Include a date", isOn: $includeDate)
            if includeDate {
              Picker("Precision", selection: $precision) {
                Text("Day").tag("Day")
                Text("Exact time").tag("Exact time")
              }
              DatePicker(
                "Occurred", selection: $date,
                displayedComponents: precision == "Day" ? [.date] : [.date, .hourAndMinute])
            }
          }
          Section {
            MTBadge(title: "#personal", tone: .accent)
            Button("Add photo", systemImage: "photo.badge.plus") {}.disabled(true)
          } footer: {
            Text("A form specimen with no backend writes.")
          }
        }
        .scrollContentBackground(.hidden).background(MTColor.canvas)
        .navigationTitle("Sample editor").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { dismiss() }.disabled(title.trimmed.isEmpty)
          }
        }
      }
    }
  }

  #Preview {
    NavigationStack { DesignSystemGallery() }
  }
#endif
