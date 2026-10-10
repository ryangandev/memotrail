#if DEBUG
  import SwiftUI

  struct FormSpecimens: View {
    @State private var notes = ""
    @State private var city = ""
    @State private var search = ""
    @State private var searchMessage = "Type a query to try this local-only preview."
    @State private var tagQuery = ""
    @State private var showRecords = "All records"
    @State private var sortOrder = "Newest first"
    @State private var defaultView = "Timeline"
    @State private var recordFilter = "All records"
    @State private var date = "2026-09-17"
    @State private var month = "2026-09"
    @State private var year = "2026"
    @State private var dateTime = "2026-09-17T14:30:00"
    @State private var from = "2026-09-01"
    @State private var start = "2026-09-17"
    @State private var birthDate = "1990-04-12"
    @State private var emptyDate = ""
    @State private var dueDate = ""
    @State private var timezone = "America/Los_Angeles"
    @State private var checked = true
    @State private var unchecked = false
    @State private var smallChecked = true
    @State private var smallUnchecked = false
    @State private var reminders = false
    @State private var withDescription = false
    @State private var tags = ["family", "travel"]
    @State private var collections = ["Early years"]
    @State private var occurrence = FormSpecimens.dayOccurrence
    @State private var showingEditor = false
    @State private var moveInReason = "Closer to work"
    @State private var homeCity = "Portland"

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
            "label · prompt · size: small | medium | large · isRequired · hidesLabel · error · note · maxLength · axis · lines",
          description:
            "Its font, height, border, and focus surface match SearchField and SelectField. An error marks the field invalid and says how to fix it."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.textFieldSizes) {
              MTFieldGrid {
                MTTextField(label: "Nickname", text: .constant("Alex"), size: .small)
                MTTextField(label: "Preferred name", text: .constant("Alex Morgan"))
                MTTextField(label: "Full name", text: .constant("Alexandra Morgan"), size: .large)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.textFieldStates) {
              MTFieldGrid {
                MTTextField(label: "Empty text field", text: .constant(""), prompt: "Add a name")
                MTTextField(
                  label: "Title", text: .constant("A moment worth keeping"), isRequired: true)
                MTTextField(label: "Disabled text field", text: .constant(""), prompt: "Unavailable")
                  .disabled(true)
                MTTextField(
                  label: "City", text: $city,
                  error: city.trimmed.isEmpty ? "Add a city before saving." : nil)
              }
            }
            GalleryCaseSeparator()
            Text("axis: vertical · lines").font(MTFont.identifier).foregroundStyle(MTColor.ink)
            MTTextField(
              label: "Notes", text: $notes, prompt: "What made this period or moment meaningful?",
              axis: .vertical, lines: 5...12)
          }
        }

        GallerySpecimen(
          title: "SearchField",
          api: "label · hidesLabel · prompt · size: small | medium | large · trailing · disabled",
          description:
            "One focus surface for the icon, text, and clear action. The search action stays composable, so each feature chooses its own submit behavior."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.searchFieldSizes) {
              VStack(alignment: .leading, spacing: MTSpacing.s4) {
                MTSearchField(
                  "Compact search", text: .constant(""), prompt: "Search your trail", size: .small)
                HStack(alignment: .bottom, spacing: MTSpacing.s2) {
                  MTSearchField("Search Locations", text: $search, prompt: "Search for an address")
                    .onSubmit(runSearch)
                  Button("Search", action: runSearch).mtButtonStyle(.secondary)
                }
                MTSearchField(
                  "Search your Life Wiki", text: .constant(""),
                  prompt: "A phrase, date, or question about your life...", size: .large)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.searchFieldHiddenLabel) {
              MTSearchField(
                "Find a tag", text: $tagQuery, prompt: "Search tag names", size: .large,
                hidesLabel: true
              ) {
                Text("24 tags").font(MTFont.caption).foregroundStyle(MTColor.inkFaint)
                  .accessibilityHidden(true)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.searchFieldDisabled) {
              MTSearchField("Disabled search", text: .constant(""), prompt: "Search unavailable")
                .disabled(true)
            }
            Text(searchMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              .accessibilityIdentifier("design-search-status")
          }
        }

        GallerySpecimen(
          title: "SelectField",
          api:
            "label · selection · options | groups · title · size: small | medium | large · isRequired · hidesLabel · disabled",
          description:
            "A labeled native menu with the same surface as SearchField. Groups title runs of options, like a Web optgroup."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.selectFieldSizes) {
              MTFieldGrid {
                MTSelectField(
                  label: "Sort by", selection: $sortOrder, options: ["Newest first", "Oldest first"],
                  title: { $0 }, size: .small)
                MTSelectField(
                  label: "Show records", selection: $showRecords,
                  options: ["All records", "Entries", "Homes & vehicles"], title: { $0 })
                MTSelectField(
                  label: "Default view", selection: $defaultView,
                  options: ["Dashboard", "Timeline", "Library"], title: { $0 }, size: .large)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.selectFieldGroups) {
              MTSelectField(
                label: "Record", selection: $recordFilter,
                groups: [
                  MTSelectGroup(options: ["All records"]),
                  MTSelectGroup(title: "Records", options: ["Entries", "Entities", "Goals"]),
                  MTSelectGroup(title: "Focused records", options: ["First Times", "People"]),
                ], title: { $0 }, isRequired: true)
            }
            GalleryCaseSeparator()
            GalleryCase(.selectFieldDisabled) {
              MTSelectField(
                label: "Unavailable filter", selection: .constant("Unavailable"),
                options: ["Unavailable"], title: { $0 }, size: .small
              )
              .disabled(true)
            }
          }
        }

        GallerySpecimen(
          title: "Checkbox",
          api: "title · detail · isOn · size: small | medium · disabled",
          description:
            "The whole row toggles the option. The title names it, and VoiceOver reads the detail after it."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.checkboxSizes) {
              VStack(alignment: .leading, spacing: 0) {
                MTCheckbox(title: "Unchecked", isOn: $unchecked)
                MTCheckbox(title: "Checked", detail: "Shown on the Timeline", isOn: $checked)
                MTCheckbox(title: "Small unchecked", isOn: $smallUnchecked, size: .small)
                MTCheckbox(
                  title: "Small checked", detail: "Still going on", isOn: $smallChecked,
                  size: .small)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.checkboxStates) {
              VStack(alignment: .leading, spacing: 0) {
                MTCheckbox(title: "Remind me", detail: "Controlled by this page", isOn: $reminders)
                MTCheckbox(
                  title: "With description",
                  detail:
                    "A longer explanation wraps below the label until it needs another line, and never runs past its container.",
                  isOn: $withDescription)
                MTCheckbox(title: "Disabled", isOn: .constant(false)).disabled(true)
                MTCheckbox(title: "Disabled checked", detail: "Cannot change", isOn: .constant(true))
                  .disabled(true)
              }
            }
            Text(reminders ? "Remind me is on." : "Remind me is off.")
              .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }

        GallerySpecimen(
          title: "DateField",
          api:
            "granularity: day | month | year · size: small | medium | large · includesTime · isRequired · timeZone · disabled",
          description:
            "Optional calendar values stored as wall-time text. The picker commits each change, and the clear button empties the field."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.dateFieldPrecision) {
              MTFieldGrid {
                MTDateField(label: "Filled date", value: $date)
                MTDateField(label: "Month precision", value: $month, granularity: .month)
                MTDateField(label: "Year precision", value: $year, granularity: .year)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.dateFieldWithTime) {
              MTDateField(label: "Exact date and time", value: $dateTime, includesTime: true)
            }
            GalleryCaseSeparator()
            GalleryCase(.dateFieldSizes) {
              MTFieldGrid {
                MTDateField(label: "From", value: $from, size: .small)
                MTDateField(label: "Start date", value: $start)
                MTDateField(label: "Birth date", value: $birthDate, size: .large)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.dateFieldStates) {
              MTFieldGrid {
                MTDateField(label: "Empty date", value: $emptyDate)
                MTDateField(label: "Due date", value: $dueDate, isRequired: true)
                MTDateField(label: "Disabled", value: .constant("2026-09-17")).disabled(true)
              }
            }
          }
        }

        GallerySpecimen(
          title: "TimeZoneField",
          api: "label · selection · referenceDate · note · searchable common and all time zones",
          description:
            "Offsets follow the reference date, so daylight-saving time shows the offset that applied then."
        ) {
          GalleryCase(.timeZoneFieldOffsets) {
            MTFieldGrid {
              MTTimeZoneField(
                label: "Default time zone", selection: $timezone, referenceDate: "2026-01-15",
                note: "Winter offset")
              MTTimeZoneField(
                label: "Same zone in summer", selection: $timezone, referenceDate: "2026-07-15",
                note: "Summer offset")
            }
          }
        }

        GallerySpecimen(
          title: "Badge",
          api: "MTBadge · tone · size · uppercase · one line · tags use # text"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.badgeTones) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTBadgeTone.allCases, id: \.self) { tone in
                  MTBadge(title: tone.rawValue, tone: tone)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.badgeSizes) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                ForEach(MTBadgeSize.allCases, id: \.self) { size in
                  MTBadge(title: size.rawValue, size: size)
                  MTBadge(title: size.rawValue, size: size, uppercase: true)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.badgeTags) {
              MTFlowLayout(spacing: MTSpacing.s2) {
                MTBadge(title: "#learning", size: .medium)
                MTBadge(title: "#旅行", size: .medium)
                MTBadge(title: "#family", tone: .neutral, size: .medium)
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.badgeTruncation) {
              VStack(alignment: .leading, spacing: MTSpacing.s2) {
                MTBadge(title: "A long label that stays on one line")
                MTBadge(
                  title: "#A long tag name that stays within the available width", size: .medium)
              }
              .padding(MTSpacing.s2)
              .frame(width: MTLayout.Gallery.truncationFrame, alignment: .leading)
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.small)
                  .strokeBorder(
                    MTColor.borderStrong,
                    style: StrokeStyle(
                      lineWidth: MTSize.Stroke.thin,
                      dash: [MTLayout.DashedBorder.dot, MTLayout.DashedBorder.gap]))
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.badgePhotoOverlay) {
              MTFlowLayout(spacing: MTSpacing.s3) {
                ForEach([MTBadgeTone.glassAccent, .glassNeutral], id: \.self) { tone in
                  GallerySampleArtwork()
                    .frame(
                      width: MTLayout.Gallery.photoSampleWidth,
                      height: MTLayout.Gallery.photoSampleHeight
                    )
                    .overlay(alignment: .topLeading) {
                      MTBadge(
                        title: tone == .glassAccent ? "Current" : "Earlier", tone: tone,
                        size: .micro, uppercase: true
                      )
                      .padding(MTSpacing.s3)
                    }
                    .overlay(alignment: .bottomTrailing) {
                      MTBadge(title: "3 photos", tone: .inverse, size: .micro, uppercase: true)
                        .padding(MTSpacing.s3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                }
              }
            }
            GalleryCaseSeparator()
            Text("MTOrganizationBadges").font(MTFont.identifier)
              .foregroundStyle(MTColor.ink)
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
          title: "FormSection",
          api: "title · tone: neutral | accent · content; MTFormNote(color:)",
          description:
            "The Web editor fieldset: the legend sits in a gap in the border, and fields inside rise onto the raised surface. The accent tone marks a panel that acts on the saved record."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            MTFormSection("Home details") {
              MTTextField(label: "Why you moved in", text: $moveInReason)
              MTDateField(label: "Start date", value: $date, isRequired: true)
            }
            MTFormSection("Location") {
              MTFormNote(
                "Save an address or position for this Home. It can appear on a future map alongside memories and events from the same area."
              )
              MTTextField(label: "City", text: $homeCity)
            }
            MTFormSection("Bucket List milestone", tone: .accent) {
              MTFormNote(
                "MemoTrail will mark the Goal Achieved and create a linked First Time with the same title."
              )
              Button {
              } label: {
                Label("Mark achieved and create First Time", icon: .check)
              }
              .mtButtonStyle()
            }
          }
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
                    MTColor.borderStrong, lineWidth: MTSize.Stroke.thin)
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
