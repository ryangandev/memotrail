#if DEBUG
  import SwiftUI

  struct PrimitiveSpecimens: View {
    @State private var message = "No demo actions yet."
    @State private var isSaving = false
    @State private var sheet: PresentedSheet?
    @State private var showingConfirmation = false

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
            GalleryCase(.pageHeaderFull) {
              MTPageHeader(
                eyebrow: "Monday, October 19", title: "Library",
                description: "Every Entry, Chapter, and First Time, newest first."
              ) {
                Button("Filter") { message = "Header filter activated." }
                  .mtButtonStyle(.secondary)
                Button("New entry", systemImage: MTIcon.plus.systemName) { sheet = .form }
                  .mtButtonStyle()
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.pageHeaderTitleOnly) {
              MTPageHeader(title: "First sourdough loaf at home")
            }
          }
        }

        GallerySpecimen(
          title: "EmptyState",
          api: "title · message · icon · actions · onTap"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.emptyStateWithAction) {
              MTEmptyState(
                title: "Your Library is empty",
                message: "Capture an Entry and it appears here.", icon: .plus
              ) {
                Button("Write your first Entry") { sheet = .form }.mtButtonStyle()
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.emptyStateInformational) {
              MTEmptyState(
                title: "No photos yet",
                message: "Photos you add to this Entry appear here.")
            }
            GalleryCaseSeparator()
            GalleryCase(.emptyStateButton) {
              MTEmptyState(
                title: "Start with a first worth remembering",
                message: "Add the first time you did something new.", icon: .star,
                onTap: { message = "Empty state action activated." })
            }
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
            eyebrow: "Timeline", title: "Add to Timeline",
            closeLabel: "Close the Add chooser", size: .fitted
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
      case .quiet: (icon, label) = (.more, "More actions for Travel")
      case .danger: (icon, label) = (.trash, "Move entry to Trash")
      }
    }
  }

  /// The Timeline's Add chooser.
  private enum GalleryChoice: CaseIterable {
    case chapter, firstTime

    var icon: MTIcon { self == .chapter ? .timeline : .star }
    var title: String { self == .chapter ? "Chapter" : "First Time" }
    var detail: String {
      self == .chapter
        ? "A stretch of your life, like a home, a job, or a school year."
        : "The first time you did something."
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
