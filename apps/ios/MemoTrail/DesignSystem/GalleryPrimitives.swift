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
          api: "MTButtonStyle · primary · secondary · ghost · danger · small / medium / large"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(MTButtonVariant.allCases, id: \.self) { variant in
              VStack(alignment: .leading, spacing: MTSpacing.s2) {
                Text(variant.title).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
                ViewThatFits(in: .horizontal) {
                  HStack(spacing: MTSpacing.s2) { variantRow(variant) }
                  VStack(alignment: .leading, spacing: MTSpacing.s2) { variantRow(variant) }
                }
              }
            }
            Text("sizes").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
            HStack(spacing: MTSpacing.s2) {
              ForEach(MTButtonSize.allCases, id: \.self) { size in
                Button(size.title, systemImage: MTIcon.plus.systemName) {
                  message = "\(size.title) button activated."
                }
                .mtButtonStyle(.secondary, size: size)
              }
            }
            Text("icon · full width").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
            HStack(spacing: MTSpacing.s2) {
              MTIconButton(label: "Add demo entry", icon: .plus, variant: .primary) {
                message = "Add icon activated."
              }
              MTIconButton(label: "Edit demo entry", icon: .edit, variant: .secondary) {
                message = "Edit icon activated."
              }
              MTIconButton(label: "More demo actions", icon: .more) {
                message = "More icon activated."
              }
              MTIconButton(label: "Saving entry", icon: .plus, variant: .primary, isLoading: true) {
              }
            }
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
          title: "Sheets & confirmations",
          api: "MTSheet · form · fitted · message · footer · MTSheetOption · confirmationDialog",
          description:
            "MTSheet is the Web Dialog: a form sheet for editors, a fitted sheet for short choices, and confirmations for destructive actions."
        ) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: MTSpacing.s2) { presentationButtons }
            VStack(alignment: .leading, spacing: MTSpacing.s2) { presentationButtons }
          }
        }

        GallerySpecimen(
          title: "PageHeader",
          api: "eyebrow · title · description · actions · compact title on phones"
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
            Rectangle().fill(MTColor.border).frame(height: 1)
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
        Text("The memory will move to Trash, where it can be restored.")
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

    @ViewBuilder private func variantRow(_ variant: MTButtonVariant) -> some View {
      Button("Continue") { message = "\(variant.title) button activated." }
        .mtButtonStyle(variant)
      Button("Disabled") {}.mtButtonStyle(variant).disabled(true)
      Button("Saving") {}.mtButtonStyle(variant, isLoading: true)
    }

    @ViewBuilder private var presentationButtons: some View {
      Button("Open confirmation") { showingConfirmation = true }.mtButtonStyle(.danger)
      Button("Open form sheet") { sheet = .form }.mtButtonStyle(.secondary)
      Button("Open fitted sheet") { sheet = .compact }.mtButtonStyle(.secondary)
      Button("Open long content") { sheet = .long }.mtButtonStyle(.secondary)
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
        MTDateField(label: "Memory date", value: $date)
      } footer: {
        HStack(spacing: MTSpacing.s2) {
          Button("Cancel") { dismiss() }
            .mtButtonStyle(.secondary, fillsWidth: true)
          Button("Save memory") { save() }
            .mtButtonStyle(isLoading: isSaving, fillsWidth: true)
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
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(1...12, id: \.self) { index in
              Text(
                "**Chapter \(index).** Small details give a memory its shape: the place, the people, and the things we noticed along the way."
              )
              .font(MTFont.bodyLarge).foregroundStyle(MTColor.ink)
              .mtLineSpacing(MTLineHeight.body, textStyle: .body)
            }
          }
          .padding(MTSpacing.s4)
        }
        .background(MTColor.canvas)
        .navigationTitle("A longer story").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done reading") { dismiss() } }
        }
      }
    }
  }
#endif
