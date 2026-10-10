#if DEBUG
  import SwiftUI

  struct PrimitiveSpecimens: View {
    @State private var message = "No demo actions yet."
    @State private var isSaving = false
    @State private var sheet: PresentedSheet?
    @State private var showingConfirmation = false
    @State private var filtered = true

    private enum PresentedSheet: String, Identifiable {
      case form, compact, long
      var id: String { rawValue }
    }

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "Button",
          api: "mtButtonStyle · variant · size · isLoading · fillsWidth"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.buttonVariants) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTButtonVariant.allCases, id: \.self) { variant in
                  Button(variant.rawValue.capitalized) {
                    message = "\(variant.rawValue) button activated."
                  }
                  .mtButtonStyle(variant)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.buttonDisabled) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTButtonVariant.allCases, id: \.self) { variant in
                  Button(variant.rawValue.capitalized) {}.mtButtonStyle(variant).disabled(true)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.buttonLoading) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTButtonVariant.allCases, id: \.self) { variant in
                  Button("Saving") {}.mtButtonStyle(variant, isLoading: true)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.buttonSizes) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTButtonSize.allCases, id: \.self) { size in
                  Button(size.rawValue.capitalized, systemImage: MTIcon.plus.systemName) {
                    message = "\(size.rawValue) button activated."
                  }
                  .mtButtonStyle(.secondary, size: size)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.buttonLink) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                NavigationLink("View foundations", value: DesignSystemSection.foundations)
                  .mtButtonStyle()
                NavigationLink("Open containers", value: DesignSystemSection.containers)
                  .mtButtonStyle(.secondary)
              }
            }
            GalleryCaseSeparator()
            Text("fillsWidth").font(MTFont.identifier).foregroundStyle(MTColor.ink)
            Button {
              save()
            } label: {
              Label(isSaving ? "Saving..." : "Save to Library", icon: .check)
            }
            .mtButtonStyle(isLoading: isSaving, fillsWidth: true)
            .accessibilityIdentifier("design-save")
            Text(message).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              .accessibilityIdentifier("design-action-status")
          }
        }

        GallerySpecimen(
          title: "IconButton",
          api: "MTIconButton · label · icon · variant · size · isLoading · disabled"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.iconButtonVariants) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTIconButtonVariant.allCases, id: \.self) { variant in
                  let sample = IconButtonSample(variant)
                  MTIconButton(label: sample.label, icon: sample.icon, variant: variant) {
                    message = "\(sample.label) activated."
                  }
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.iconButtonSizes) {
              HStack(alignment: .bottom, spacing: MTSpacing.s6) {
                ForEach(MTIconButtonSize.allCases, id: \.self) { size in
                  VStack(spacing: MTSpacing.s2) {
                    MTIconButton(label: "Close entry editor, \(size.rawValue)", icon: .close, size: size)
                    {
                      message = "\(size.rawValue.capitalized) close activated."
                    }
                    Text(size.rawValue).font(MTFont.code).foregroundStyle(MTColor.inkMuted)
                      .accessibilityHidden(true)
                  }
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.iconButtonStates) {
              HStack(spacing: MTSpacing.s2) {
                MTIconButton(label: "Add demo entry", icon: .plus) {
                  message = "Add icon activated."
                }
                MTIconButton(label: "Disabled add entry", icon: .plus) {}.disabled(true)
                MTIconButton(label: "Saving entry", icon: .plus, isLoading: true) {}
              }
            }
          }
        }

        GallerySpecimen(
          title: "Dialog",
          api:
            "MTSheet · size: form | fitted · isBusy · eyebrow · description · message · footer · MTSheetFooter · MTSheetOption · confirmationDialog",
          description:
            "MTSheet is the Web Dialog: a form sheet for editors and long reading, a fitted sheet for short choices, and a system confirmation for destructive actions."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.dialogConfirmation) {
              Button("Open confirmation") { showingConfirmation = true }.mtButtonStyle(.danger)
            }
            GalleryCaseSeparator()
            GalleryCase(.dialogForm) {
              Button("Open form sheet") { sheet = .form }.mtButtonStyle(.secondary)
            }
            GalleryCaseSeparator()
            GalleryCase(.dialogShortChoice) {
              Button("Open fitted sheet") { sheet = .compact }.mtButtonStyle(.secondary)
            }
            GalleryCaseSeparator()
            GalleryCase(.dialogLongContent) {
              Button("Open long content") { sheet = .long }.mtButtonStyle(.secondary)
            }
            Text("Saving is simulated for 1.5 seconds. While saving, dismissal and duplicate saves are disabled.")
              .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }

        GallerySpecimen(
          title: "PageHeader",
          api:
            "eyebrow · title · description · actions · compact title on phones · actions wrap below a 260 pt copy basis"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            MTPageHeader(
              eyebrow: "Your life, remembered", title: "Memories",
              description: "The moments, people, and places that make up your story."
            ) {
              Button("Filter") { message = "Header filter activated." }
                .mtButtonStyle(.secondary)
              Button("Add memory", systemImage: MTIcon.plus.systemName) { sheet = .form }
                .mtButtonStyle()
            }
            Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin)
            MTPageHeader(eyebrow: "First Time", title: "First sourdough loaf at home") {
              Button {
                message = "Header edit activated."
              } label: {
                Label("Edit", icon: .edit)
              }
              .mtButtonStyle(.ghost, size: .small)
            }
            Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin)
            MTPageHeader(
              title: "A lifetime of small moments and meaningful places",
              description: "A longer heading without actions, to review wrapping at narrow widths.")
          }
        }

        GallerySpecimen(
          title: "SectionHeader",
          api: "title · detail · trailing action"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            MTSectionHeader("Ready to organize") {
              MTSectionLink(title: "Inbox · 3") { message = "Section link activated." }
            }
            MTSectionHeader("Recent Entries", detail: "The latest things added to your archive")
          }
        }

        GallerySpecimen(
          title: "EmptyState",
          api: "initial · filtered · no action · onTap · optional icon"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            MTEmptyState(
              title: "Your story starts here",
              message: "Capture a memory to begin building your trail.", icon: .plus
            ) {
              Button("Add your first memory") { sheet = .form }.mtButtonStyle()
            }
            MTEmptyState(
              title: filtered ? "No matching memories" : "Filters cleared",
              message: filtered
                ? "Try another search or clear your filters."
                : "This gallery uses local demo state, so no records are fetched.",
              icon: .search
            ) {
              Button(filtered ? "Clear filters" : "Reset demo filters") { filtered.toggle() }
                .mtButtonStyle(.secondary)
            }
            MTEmptyState(
              title: "Nothing here yet",
              message: "A quiet, informational state without an action or decorative icon.")
            MTEmptyState(
              title: "Start with a first worth remembering",
              message: "The whole state is one action. Only a title is required.", icon: .star,
              onTap: { message = "Empty state action activated." })
          }
        }
      }
      .confirmationDialog(
        "Remove this memory?", isPresented: $showingConfirmation, titleVisibility: .visible
      ) {
        Button("Remove memory", role: .destructive) {
          message = "Demo removal confirmed. Nothing was deleted."
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("It moves to Trash, where you can restore it later. This demo does not delete anything.")
      }
      .sheet(item: $sheet) { presented in
        switch presented {
        case .form:
          GalleryFormSheet {
            message = "Demo saved for \($0). No data was uploaded."
          }
        case .compact:
          MTSheet(
            eyebrow: "New entry", title: "What are you adding?",
            closeLabel: "Close entry type chooser", size: .fitted
          ) {
            VStack(spacing: MTSpacing.s3) {
              ForEach(GalleryChoice.allCases, id: \.self) { choice in
                MTSheetOption(icon: choice.icon, title: choice.title, detail: choice.detail) {
                  message = "\(choice.title) chosen."
                  sheet = nil
                }
              }
            }
          }
        case .long: GalleryLongSheet()
        }
      }
    }

    private func save() {
      isSaving = true
      message = "Saving preview..."
      Task {
        try? await Task.sleep(for: .seconds(1))
        isSaving = false
        message = "Preview saved to Library."
      }
    }
  }

  /// The Web gallery's icon button samples: each variant with the action it suits.
  private struct IconButtonSample {
    let icon: MTIcon
    let label: String

    init(_ variant: MTIconButtonVariant) {
      switch variant {
      case .primary: (icon, label) = (.plus, "Add entry")
      case .secondary: (icon, label) = (.edit, "Edit entry")
      case .ghost: (icon, label) = (.more, "More actions for Travel")
      case .danger: (icon, label) = (.trash, "Move entry to Trash")
      }
    }
  }

  private enum GalleryChoice: CaseIterable {
    case moment, home

    var icon: MTIcon { self == .moment ? .timeline : .home }
    var title: String { self == .moment ? "Moment" : "Home" }
    var detail: String {
      self == .moment
        ? "A flexible event or life stage on any Timeline track."
        : "A place you called home, with its facts and memories."
    }
  }

  private struct GalleryFormSheet: View {
    let saved: (String) -> Void
    @State private var title = ""
    @State private var date = ""
    @State private var isSaving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      MTSheet(
        eyebrow: "New memory", title: "Edit a memory",
        description: "Saving is simulated for 1.5 seconds. Closing and saving again wait for it.",
        closeLabel: "Close memory editor", isBusy: isSaving, message: failure
      ) {
        MTTextField(label: "Title", text: $title, prompt: "First ski day", isRequired: true)
        MTDateField(label: "Memory date", value: $date, isRequired: true)
      } footer: {
        MTSheetFooter {
          EmptyView()
        } cancel: {
          Button("Cancel") { dismiss() }
            .mtButtonStyle(.secondary)
        } primary: {
          Button("Save memory") { save() }
            .mtButtonStyle(isLoading: isSaving)
        }
      }
    }

    private func save() {
      guard !title.trimmed.isEmpty else {
        failure = "Add a title before saving."
        return
      }
      failure = nil
      isSaving = true
      Task {
        try? await Task.sleep(for: .milliseconds(1_500))
        saved(date.isEmpty ? "an undated memory" : date)
        dismiss()
      }
    }
  }

  private struct GalleryLongSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      MTSheet(
        title: "A longer story",
        description: "A form sheet with a scrolling body and a footer that stays visible.",
        closeLabel: "Close story"
      ) {
        VStack(alignment: .leading, spacing: MTSpacing.s4) {
          ForEach(1...12, id: \.self) { index in
            Text(
              "**Chapter \(index).** Small details give a memory its shape: the place, the people, and the things we noticed along the way. This sample exercises long content without changing the page behind it."
            )
            .font(MTFont.bodyLarge).foregroundStyle(MTColor.ink)
            .mtLineSpacing(MTLineHeight.body, textStyle: .body)
          }
        }
      } footer: {
        // Like MTSheetFooter, the primary action sits at the trailing edge.
        HStack {
          Spacer(minLength: 0)
          Button("Done reading") { dismiss() }.mtButtonStyle()
        }
      }
    }
  }
#endif
