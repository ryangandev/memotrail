#if DEBUG
  import SwiftUI

  enum DesignSystemSection: String, CaseIterable, Identifiable {
    case foundations, actions, forms, records, feedback
    var id: String { rawValue }
    var title: String {
      switch self {
      case .foundations: "Foundations"
      case .actions: "Actions & labels"
      case .forms: "Forms & sheets"
      case .records: "Records & media"
      case .feedback: "Feedback & states"
      }
    }
    var detail: String {
      switch self {
      case .foundations: "Brand, semantic colors, type, spacing, and motion."
      case .actions: "Native buttons, filter chips, badges, and disabled states."
      case .forms: "Search, fields, pickers, dates, and native presentation."
      case .records: "Record summaries, long content, and photo placeholders."
      case .feedback: "Empty, loading, error, success, and local draft states."
      }
    }
    var systemImage: String {
      switch self {
      case .foundations: "paintpalette"
      case .actions: "hand.tap"
      case .forms: "rectangle.and.pencil.and.ellipsis"
      case .records: "book.closed"
      case .feedback: "bubble.left.and.text.bubble.right"
      }
    }
  }

  struct DesignSystemGallery: View {
    @State private var appearance = NativeAppearance.system
    @State private var previewSize: DynamicTypeSize?
    @Environment(\.dynamicTypeSize) private var systemSize

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: MTSpacing.s6) {
          MTPageHeader(
            eyebrow: "Soft Ledger · iOS", title: "Design System",
            description: "A native foundation for the things worth keeping.")
          DesignPreviewStatus()
          MTCard {
            HStack(spacing: MTSpacing.s3) {
              MemoTrailMark().frame(width: 40, height: 40)
              VStack(alignment: .leading, spacing: MTSpacing.s1) {
                Text("MemoTrail").font(MTFont.title).foregroundStyle(MTColor.ink)
                Text("Shared meaning. Native interactions.").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted)
              }
            }
          }
          Text("COMPONENTS").font(MTFont.caption.weight(.medium)).tracking(1).foregroundStyle(
            MTColor.warm)
          ForEach(DesignSystemSection.allCases) { section in
            NavigationLink(value: section) {
              MTCard {
                HStack(alignment: .top, spacing: MTSpacing.s3) {
                  Image(systemName: section.systemImage).foregroundStyle(MTColor.accent).frame(
                    width: 24)
                  VStack(alignment: .leading, spacing: MTSpacing.s1) {
                    Text(section.title).font(MTFont.heading).foregroundStyle(MTColor.ink)
                    Text(section.detail).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").font(MTFont.caption).foregroundStyle(
                    MTColor.inkMuted)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("design-section-\(section.rawValue)")
          }
          Text(
            "These specimens use the same components as the new Map screen. Existing screens will be migrated after review."
          )
          .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        }
        .padding(MTSpacing.s4)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .background(MTColor.canvas)
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

  private struct DesignPreviewStatus: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      Text(colorScheme == .dark ? "Dark appearance" : "Light appearance")
        .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        .accessibilityIdentifier("design-preview-status")
    }
  }

  private struct DesignSystemSpecimens: View {
    let section: DesignSystemSection
    @State private var query = ""
    @State private var selectedKind = "Entries"
    @State private var isSaving = false
    @State private var actionMessage = "Tap an action to preview its state."
    @State private var showingEditor = false
    @State private var showingConfirmation = false
    @State private var chinese = false
    @State private var markRotated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: MTSpacing.s6) {
          MTPageHeader(
            eyebrow: "Native components", title: section.title, description: section.detail)
          DesignPreviewStatus()
          switch section {
          case .foundations: foundations
          case .actions: actions
          case .forms: forms
          case .records: records
          case .feedback: feedback
          }
        }
        .padding(MTSpacing.s4)
        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
      }
      .background(MTColor.canvas)
      .navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showingEditor) { DesignSystemEditor() }
      .confirmationDialog(
        "Move this preview record to Trash?", isPresented: $showingConfirmation,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) {
          actionMessage = "Preview record moved to Trash."
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This only changes the specimen. Your records are untouched.")
      }
    }

    private var foundations: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s6) {
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("The moments that make a life").font(MTFont.display)
            Text("Keep a little context").font(MTFont.title)
            Text("An Entry worth revisiting").font(MTFont.heading)
            Text("A calm archive for your memories, people, and chapters.").font(MTFont.body)
            Text("Saved on this iPhone").font(MTFont.label)
            Text("Caption · 日期与上下文").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }.foregroundStyle(MTColor.ink)
        }
        specimenTitle("Semantic colors")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: MTSpacing.s3) {
          ForEach(colorSpecimens, id: \.0) { name, color in
            VStack(alignment: .leading, spacing: MTSpacing.s2) {
              RoundedRectangle(cornerRadius: MTRadius.medium).fill(color).frame(height: 48)
                .overlay { RoundedRectangle(cornerRadius: MTRadius.medium).stroke(MTColor.border) }
              Text(name).font(MTFont.caption).foregroundStyle(MTColor.ink)
            }
          }
        }
        specimenTitle("Spacing & shape")
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            ForEach([4, 8, 12, 16, 24, 32], id: \.self) { value in
              HStack {
                Text("\(value) pt").font(MTFont.caption).frame(minWidth: 56, alignment: .leading)
                RoundedRectangle(cornerRadius: 4).fill(MTColor.accent).frame(
                  width: CGFloat(value) * 4, height: 8)
              }
            }
            Text("Cards 18 pt · Fields 12 pt · Labels capsule").font(MTFont.caption)
              .foregroundStyle(MTColor.inkMuted)
          }
        }
        specimenTitle("Restrained motion")
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MemoTrailMark().frame(width: 64, height: 64).rotationEffect(
              .degrees(markRotated ? 90 : 0))
            Button("Preview motion") {
              guard !reduceMotion else { return }
              withAnimation(.easeInOut(duration: MTMotion.deliberate)) { markRotated.toggle() }
            }.buttonStyle(MTActionStyle(emphasis: .secondary))
            Text(
              reduceMotion
                ? "Reduce Motion is on. The mark stays still."
                : "Motion follows the system Reduce Motion preference."
            )
            .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }
      }
    }

    private var actions: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Button {
              saveSpecimen()
            } label: {
              HStack {
                if isSaving { ProgressView().tint(MTColor.accentInk) }
                Text(isSaving ? "Saving..." : "Save to Library")
              }
            }.buttonStyle(MTActionStyle()).disabled(isSaving).accessibilityIdentifier("design-save")
            Button("Add photo", systemImage: "photo.badge.plus") {
              actionMessage = "Photo action selected."
            }
            .buttonStyle(MTActionStyle(emphasis: .secondary))
            Button("Add photo", systemImage: "photo.badge.plus") {}.buttonStyle(
              MTActionStyle(emphasis: .secondary)
            ).disabled(true)
            Button("Move to Trash", role: .destructive) { showingConfirmation = true }.buttonStyle(
              .bordered
            ).tint(.red)
            Text(actionMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              .accessibilityIdentifier("design-action-status")
          }
        }
        specimenTitle("Filter chips")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s2) {
            ForEach(["All records", "Entries", "Entities", "Goals"], id: \.self) { title in
              MTFilterChip(title: title, isSelected: selectedKind == title) { selectedKind = title }
            }
          }
        }
        specimenTitle("Status & organization labels")
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          MTBadge(title: "Unreviewed")
          MTBadge(title: "First Time", tone: .accent)
          MTBadge(title: "On this iPhone", tone: .warm)
          MTBadge(title: "Saved", tone: .success)
          MTBadge(title: "#值得记住的那些很长很长的日常片段", tone: .accent)
        }
      }
    }

    private var forms: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        MTSearchField(prompt: "Find in your Life Wiki", text: $query)
        Text(query.isEmpty ? "Search is empty." : "Search preview: \(query)").font(MTFont.caption)
          .foregroundStyle(MTColor.inkMuted)
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("Native form & presentation").font(MTFont.heading)
            Text("Fields keep system focus, selection, keyboard, and date-picker behavior.").font(
              MTFont.body
            ).foregroundStyle(MTColor.inkMuted)
            Button("Open sample editor", systemImage: "square.and.pencil") { showingEditor = true }
              .buttonStyle(MTActionStyle()).accessibilityIdentifier("design-open-editor")
          }
        }
        MTFeedback(
          title: "Contextual validation",
          message: "Keep date precision and validation close to the relevant field.", tone: .warm,
          systemImage: "calendar.badge.exclamationmark")
      }
    }

    private var records: some View {
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

    private var feedback: some View {
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
        MTCard {
          MTEmptyState(
            title: "Nothing here yet",
            message: "Capture something worth keeping, then organize it into Library.",
            systemImage: "books.vertical")
        }
      }
    }

    private var colorSpecimens: [(String, Color)] {
      [
        ("Canvas", MTColor.canvas), ("Surface", MTColor.surface), ("Raised", MTColor.surfaceRaised),
        ("Accent", MTColor.accent), ("Warm", MTColor.warm), ("Ink", MTColor.ink),
        ("Muted ink", MTColor.inkMuted), ("Border", MTColor.border),
      ]
    }
    private func specimenTitle(_ title: String) -> some View {
      Text(title).font(MTFont.heading).foregroundStyle(MTColor.ink).accessibilityAddTraits(
        .isHeader)
    }
    private func saveSpecimen() {
      isSaving = true
      actionMessage = "Saving preview..."
      Task {
        try? await Task.sleep(for: .seconds(1))
        isSaving = false
        actionMessage = "Preview saved to Library."
      }
    }
  }

  private struct DesignSystemEditor: View {
    @State private var title = "A moment worth keeping"
    @State private var note = ""
    @State private var date = Date()
    @State private var precision = "Day"
    @State private var includeDate = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        Form {
          Section("Entry") {
            TextField("Title", text: $title).accessibilityIdentifier("design-editor-title")
            TextField("Write a note...", text: $note, axis: .vertical).lineLimit(3...8)
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
