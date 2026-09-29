#if DEBUG
  import SwiftUI

  struct FormSpecimens: View {
    @State private var name = "Alex Morgan"
    @State private var emptyName = ""
    @State private var notes = ""
    @State private var search = ""
    @State private var compactSearch = ""
    @State private var searchMessage = "No demo search yet."
    @State private var recordFilter = "All records"
    @State private var date = "2026-09-17"
    @State private var emptyDate = ""
    @State private var dateTime = "2026-09-17T14:30:00"
    @State private var month = "2026-09"
    @State private var year = "2026"
    @State private var timezone = "America/Los_Angeles"
    @State private var includesInbox = true
    @State private var showsPhotoDates = false
    @State private var tags = ["family", "travel"]
    @State private var collections = ["Early years"]
    @State private var occurrence = FormSpecimens.dayOccurrence
    @State private var showingEditor = false

    static var dayOccurrence: OccurrenceDraft {
      var draft = OccurrenceDraft(
        EntryOccurrence(
          precision: .day, start: nil, end: nil, label: nil, timezone: "America/Los_Angeles"))
      draft.start = "2026-09-17"
      return draft
    }

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "TextField",
          api:
            "label · prompt · size: small | medium | large · required · note · maxLength · axis · lines",
          description:
            "Plain text input with the same font, height, border, and focus surface as SearchField and SelectField."
        ) {
          MTFieldGrid {
            MTTextField(label: "Preferred name", text: $name, isRequired: true)
            MTTextField(label: "Empty text field", text: $emptyName, prompt: "Add a name")
            MTTextField(
              label: "Disabled text field", text: .constant(""), prompt: "Unavailable", size: .small
            )
            .disabled(true)
          }
          MTTextField(
            label: "Notes", text: $notes, prompt: "What made this period or moment meaningful?",
            axis: .vertical, lines: 5...12)
        }

        GallerySpecimen(
          title: "SearchField",
          api: "label · hidesLabel · prompt · size · trailing · clear · disabled",
          description:
            "One focus surface for the icon, text, and clear action. The search action stays composable, so each feature chooses its own submit behavior."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            HStack(alignment: .bottom, spacing: MTSpacing.s2) {
              MTSearchField("Search Locations", text: $search, prompt: "Search for an address")
                .onSubmit(runSearch)
              Button("Search", action: runSearch).mtButtonStyle(.secondary)
            }
            MTFieldGrid {
              MTSearchField(
                "Compact search", text: $compactSearch, prompt: "Search your trail", size: .small)
              MTSearchField("Disabled search", text: .constant(""), prompt: "Search unavailable")
                .disabled(true)
            }
            Text(searchMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              .accessibilityIdentifier("design-search-status")
          }
        }

        GallerySpecimen(
          title: "SelectField",
          api: "label · selection · options | groups · title · size · required · disabled",
          description:
            "A labeled native menu with the same surface as SearchField. Groups title runs of options, like a Web optgroup."
        ) {
          MTFieldGrid {
            MTSelectField(
              label: "Record", selection: $recordFilter,
              groups: [
                MTSelectGroup(options: ["All records"]),
                MTSelectGroup(title: "Records", options: ["Entries", "Entities", "Goals"]),
                MTSelectGroup(title: "Focused records", options: ["First Times", "People"]),
              ], title: { $0 })
            MTSelectField(
              label: "Unavailable filter", selection: .constant("Unavailable"),
              options: ["Unavailable"], title: { $0 }, size: .small
            )
            .disabled(true)
          }
        }

        GallerySpecimen(
          title: "DateField",
          api:
            "size · granularity: day | month | year · includesTime · required · timeZone · disabled",
          description:
            "Optional calendar values stored as wall-time text. The picker commits each change, and the clear button empties the field."
        ) {
          MTFieldGrid {
            MTDateField(label: "Filled date", value: $date, size: .small)
            MTDateField(label: "Empty date", value: $emptyDate)
            MTDateField(
              label: "Exact date and time", value: $dateTime, includesTime: true, size: .large)
            MTDateField(label: "Month precision", value: $month, granularity: .month)
            MTDateField(label: "Year precision", value: $year, granularity: .year)
            MTDateField(label: "Disabled", value: .constant("2026-09-17")).disabled(true)
          }
        }

        GallerySpecimen(
          title: "TimeZoneField",
          api: "label · selection · referenceDate · note · searchable common and all time zones",
          description:
            "Offsets follow the reference date, so daylight-saving time shows the offset that applied then."
        ) {
          MTFieldGrid {
            MTTimeZoneField(
              label: "Default time zone", selection: $timezone, referenceDate: "2026-01-15",
              note: "Winter offset")
            MTTimeZoneField(
              label: "Same zone in summer", selection: $timezone, referenceDate: "2026-07-15")
          }
        }

        GallerySpecimen(title: "Checkbox", api: "title · detail · isOn · disabled") {
          VStack(alignment: .leading, spacing: 0) {
            MTCheckbox(
              title: "Include Inbox captures", detail: "Show captures that are not organized yet",
              isOn: $includesInbox)
            MTCheckbox(title: "Show photo dates", isOn: $showsPhotoDates)
            MTCheckbox(title: "Unavailable option", isOn: .constant(true)).disabled(true)
          }
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

        GallerySpecimen(
          title: "OrganizationEditor",
          api: "kind: collection | tag · names · options · disabled",
          description:
            "Add opens a picker that finds existing names or creates one above the keyboard. Tags also add on a comma, and Done keeps text still in the search field."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            MTOrganizationEditor(
              kind: .tag, names: $tags,
              options: ["family", "travel", "milestone", "home"])
            MTOrganizationEditor(
              kind: .collection, names: $collections,
              options: ["Early years", "Family archive", "Travel journals"])
          }
        }

        GallerySpecimen(
          title: "OccurrenceEditor",
          api: "point · span · defaultTimezone · eight Date types",
          description:
            "The time zone appears for exact times and says whether the Entry overrides the Settings default."
        ) {
          OccurrenceEditor(value: $occurrence, defaultTimezone: "America/Los_Angeles")
        }

        GallerySpecimen(
          title: "PhotoField",
          api: "recordLabel · saved · new · limit · selection · progress · remove actions"
        ) {
          PhotoFieldSpecimen()
        }

        GallerySpecimen(
          title: "Native form & presentation",
          description:
            "An editor sheet composed from these fields keeps system focus, keyboard, and dismissal behavior."
        ) {
          Button("Open sample editor", systemImage: MTIcon.edit.systemName) { showingEditor = true }
            .mtButtonStyle().accessibilityIdentifier("design-open-editor")
        }

        MTFeedback(
          title: "Contextual validation",
          message: "Keep date precision and validation close to the relevant field.", tone: .warm,
          systemImage: "calendar.badge.exclamationmark")
      }
      .sheet(isPresented: $showingEditor) { GalleryEditorSheet() }
    }

    private func runSearch() {
      let query = search.trimmed
      searchMessage =
        query.isEmpty ? "Enter a search term first." : "Demo search: \(query). No request was sent."
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

  private struct GalleryEditorSheet: View {
    @State private var title = "A moment worth keeping"
    @State private var note = NSAttributedString(string: "")
    @State private var occurrence = FormSpecimens.dayOccurrence
    @State private var collections: [String] = []
    @State private var tags = ["personal"]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            MTTextField(label: "Title", text: $title, isRequired: true)
              .accessibilityIdentifier("design-editor-title")
            VStack(alignment: .leading, spacing: MTSpacing.s2) {
              MTFieldLabel(title: "Note")
              MTRichTextEditor(text: $note, accessibilityIdentifier: "design-editor-note")
                .background(MTColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                .overlay {
                  RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
                    MTColor.borderStrong, lineWidth: 1)
                }
            }
            OccurrenceEditor(value: $occurrence, defaultTimezone: "America/Los_Angeles")
            MTOrganizationEditor(
              kind: .collection, names: $collections,
              options: ["Early years", "Family archive"])
            MTOrganizationEditor(
              kind: .tag, names: $tags, options: ["personal", "family"])
            Text("A form specimen with no backend writes.")
              .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
          .padding(MTSpacing.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MTColor.surfaceRaised)
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
#endif
