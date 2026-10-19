import PhotosUI
import SwiftUI
import UIKit

/// The Web CaptureComposer: one formatted note, an optional day with an optional time, voice,
/// and photos, saved to the Library through the offline queue. The page style is a raised card
/// on the Dashboard; the dialog style is the open body of Quick Capture. Command-Return saves
/// from a hardware keyboard.
/// Specified in packages/design-system/components/capture-composer.yaml.
struct CaptureCard: View {
  @Binding var note: NSAttributedString
  @Binding var occurrence: OccurrenceDraft?
  @Binding var photos: [PhotoDraft]

  var style = MTCaptureComposerDefaults.style
  let isSaving: Bool
  let hasLocalDraft: Bool
  let error: String?
  var focusRequest = 0
  /// How many photos of the capture being sent have reached MemoTrail, like Web's ring.
  var uploadProgress: CapturePhotoProgress? = nil
  let addPhoto: @MainActor (PhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  let save: @MainActor () async -> Void

  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isLoadingPhotos = false
  @State private var photoError: String?
  @State private var voiceController = VoiceTranscriptionController()
  /// The note as it was when dictation began, which dictated words are added to.
  @State private var voiceBase = NSAttributedString()

  private var isBusy: Bool { isSaving || isLoadingPhotos || voiceController.isActive }
  /// Web `--capture-inline-padding` at phone width.
  private var inlinePadding: CGFloat { style == .page ? MTSpacing.s5 : MTSpacing.s4 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if style == .page {
        HStack(spacing: MTSpacing.s3) {
          CaptureSpark()
          Text("What\u{2019}s on your mind?")
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, inlinePadding)
        .padding(.top, MTSpacing.s5)
      }

      MTRichTextEditor(
        text: $note, placeholder: "What is on your mind?", accessibilityIdentifier: "capture-body",
        variant: .embedded, minimumHeight: MTLayout.RichText.captureMinHeight,
        focusRequest: focusRequest, onSubmit: submitFromKeyboard
      )
      .disabled(isSaving || voiceController.isActive)
      .padding(.horizontal, inlinePadding - MTSpacing.s3)
      .padding(.top, MTSpacing.s2)
      .padding(.bottom, MTSpacing.s2)

      if let occurrence {
        // Web `captureDatePanel`: a day with an optional time opens in place under the note.
        CaptureDateControl(
          value: Binding(
            get: { CaptureDate.value(occurrence) },
            set: { self.occurrence = CaptureDate.draft(value: $0, timezone: occurrence.timezone) }
          ),
          timezone: TimeZone(identifier: occurrence.timezone) ?? .current
        )
        .disabled(isBusy)
        .padding(.horizontal, inlinePadding)
        .padding(.vertical, MTSpacing.s3)
        .overlay(alignment: .top) { MTListDivider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Date")
        .accessibilityIdentifier("capture-date-panel")
      }

      if !photos.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s3) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
              photoThumbnail(photo, index: index)
            }
          }
          .padding(.horizontal, inlinePadding)
          .padding(.vertical, MTSpacing.s4)
        }
        .background(MTColor.surfaceSubtle)
        .overlay(alignment: .top) { MTListDivider() }
        .accessibilityLabel("Draft photos")
        .accessibilityIdentifier("capture-photo-preview")
      }

      if let status {
        // Web `captureVoiceStatus`: a tinted strip above the actions.
        Label(status.text, systemImage: status.systemImage)
          .font(MTFont.caption)
          .foregroundStyle(status.color)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, inlinePadding)
          .padding(.vertical, MTSpacing.s2)
          .frame(maxWidth: .infinity, minHeight: MTSize.Capture.statusHeight, alignment: .leading)
          .background(status.background)
          .overlay(alignment: .top) { MTListDivider() }
          .accessibilityIdentifier(status.identifier)
      }

      if let uploadProgress {
        MTUploadProgress(completed: uploadProgress.completed, total: uploadProgress.total)
          .padding(.horizontal, inlinePadding)
          .padding(.vertical, MTSpacing.s2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .top) { MTListDivider() }
          .accessibilityIdentifier("capture-upload-progress")
      }

      HStack(spacing: MTSpacing.s1) {
        quietButton(
          label: "Date", icon: .calendar,
          isActive: occurrence != nil, identifier: "capture-date", action: toggleDate
        )
        .accessibilityValue(occurrence == nil ? "Off" : "On")
        .accessibilityHint(
          occurrence == nil
            ? "Chooses the day this Entry is about" : "Saves this Entry at the capture time")
        .disabled(isBusy)

        voiceButton
        photoPicker

        Spacer(minLength: MTSpacing.s2)

        Button {
          Task { await save() }
        } label: {
          HStack(spacing: MTSpacing.s2) {
            Text("Save")
            Image(.chevron).font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
          }
        }
        .mtButtonStyle(.primary, isLoading: isSaving)
        .disabled(isBusy)
        // Quick Capture is the whole dialog, so Command-Return saves wherever focus is in it.
        // On the Dashboard the shortcut belongs to the note alone, through the editor.
        .keyboardShortcut(style == .dialog ? KeyboardShortcut(.return, modifiers: .command) : nil)
        .accessibilityHint("Command-Return saves from a keyboard")
        .accessibilityIdentifier("save-entry")
      }
      .padding(.leading, inlinePadding - MTSpacing.s2)
      .padding(.trailing, inlinePadding)
      .padding(.vertical, MTSpacing.s2)
      .frame(minHeight: MTSize.Capture.actionBarHeight)
      .background(MTColor.surface)
      .overlay(alignment: .top) { MTListDivider() }
    }
    .background {
      if style == .page { MTColor.surfaceRaised }
    }
    .clipShape(RoundedRectangle(cornerRadius: style == .page ? MTRadius.large : 0))
    .overlay {
      if style == .page {
        RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
          MTColor.borderStrong, lineWidth: MTSize.Stroke.thin)
      }
    }
    .mtShadow(style == .page ? MTShadow.raised : [])
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Quick capture")
    .onChange(of: pickerItems) { _, items in
      Task { await loadPhotos(from: items) }
    }
    .onChange(of: voiceController.transcribedText) { _, transcribedText in
      // Dictated words follow the note, which keeps the formatting it had.
      if let transcribedText { note = VoiceTranscriptText.applying(transcribedText, to: voiceBase) }
    }
    .onDisappear {
      voiceController.stop(silently: true)
    }
  }

  /// Web `toggleDate`: choosing a date starts on today; turning it off saves the capture time.
  private func toggleDate() {
    occurrence =
      occurrence == nil
      ? CaptureDate.today(now: Date(), timezone: TimeZone.current.identifier) : nil
  }

  /// Web's Command-Return: saves unless the composer is busy, like its disabled Save button.
  private func submitFromKeyboard() {
    guard !isBusy else { return }
    Task { await save() }
  }

  private struct Status {
    enum Tone { case neutral, accent, warm }

    let text: String
    let systemImage: String
    let tone: Tone
    let identifier: String

    var color: Color {
      switch tone {
      case .neutral: MTColor.inkMuted
      case .accent: MTColor.accent
      case .warm: MTColor.warm
      }
    }
    var background: Color {
      switch tone {
      case .neutral: MTColor.surfaceSubtle
      case .accent: MTColor.accentSubtle
      case .warm: MTColor.warmSubtle
      }
    }
  }

  private var status: Status? {
    if let photoError {
      return Status(
        text: photoError, systemImage: "exclamationmark.circle.fill", tone: .warm,
        identifier: "capture-photo-error")
    }
    if let voiceMessage = voiceController.message {
      return Status(
        text: voiceMessage,
        systemImage: voiceController.hasError
          ? MTIcon.mic.systemName
          : (voiceController.isActive ? "waveform" : MTIcon.sparkle.systemName),
        tone: voiceController.hasError ? .warm : .accent,
        identifier: "capture-voice-message")
    }
    if let error {
      return Status(
        text: error, systemImage: "exclamationmark.circle.fill", tone: .warm,
        identifier: "capture-message")
    }
    if hasLocalDraft {
      return Status(
        text: "Draft saved on this iPhone.", systemImage: MTIcon.history.systemName,
        tone: .neutral, identifier: "draft-message")
    }
    return nil
  }

  private func quietButton(
    label: String, icon: MTIcon, isActive: Bool, identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CaptureQuietIcon(icon: icon, isActive: isActive)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }

  private func photoThumbnail(_ photo: PhotoDraft, index: Int) -> some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if let image = UIImage(data: photo.data) {
          Image(uiImage: image).resizable().scaledToFill()
            .accessibilityLabel("Selected photo \(index + 1)")
        } else {
          Image(.photo).foregroundStyle(MTColor.inkFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MTColor.surfaceSubtle)
        }
      }
      .frame(width: MTSize.Capture.thumbnail, height: MTSize.Capture.thumbnail)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.borderStrong)
      }
      .contentShape(RoundedRectangle(cornerRadius: MTRadius.medium))

      Button {
        Task { await remove(photo.id) }
      } label: {
        Image(.close)
          .font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
          .foregroundStyle(MTColor.inverseInk)
          .frame(
            width: MTSize.Capture.removeButton,
            height: MTSize.Capture.removeButton
          )
          .background(
            MTColor.inverseSurface, in: Circle()
          )
          .frame(
            width: MTLayout.PhotoTile.captureRemoveTarget,
            height: MTLayout.PhotoTile.captureRemoveTarget
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isSaving || isLoadingPhotos)
      .accessibilityLabel("Remove selected photo \(index + 1)")
    }
  }

  private var voiceButton: some View {
    Button {
      if voiceController.isActive {
        voiceController.stop()
      } else {
        voiceBase = note
        Task { await voiceController.start(currentText: note.string) }
      }
    } label: {
      CaptureQuietIcon(
        icon: voiceController.isActive ? .stop : .mic, isActive: voiceController.isActive,
        tint: MTColor.warm)
    }
    .buttonStyle(.plain)
    .disabled(isSaving || isLoadingPhotos)
    .accessibilityLabel(voiceController.isActive ? "Stop voice capture" : "Start voice capture")
    .accessibilityValue(voiceController.phase == .listening ? "Listening" : "")
    .accessibilityHint("Transcribes speech into the note without saving audio")
    .accessibilityIdentifier("capture-voice")
  }

  private var photoPicker: some View {
    let hasPhotos = !photos.isEmpty
    return PhotosPicker(
      selection: $pickerItems,
      maxSelectionCount: max(1, PhotoDraft.maximumCount - photos.count),
      matching: .images
    ) {
      CaptureQuietIcon(icon: .photo, isActive: hasPhotos)
    }
    .buttonStyle(.plain)
    .disabled(isBusy || photos.count >= PhotoDraft.maximumCount)
    .accessibilityLabel("Add photos")
    .accessibilityValue("\(photos.count) selected")
    .accessibilityIdentifier("capture-add-photos")
  }

  @MainActor
  private func loadPhotos(from items: [PhotosPickerItem]) async {
    guard !items.isEmpty, !isLoadingPhotos else { return }

    isLoadingPhotos = true
    photoError = nil
    defer {
      pickerItems = []
      isLoadingPhotos = false
    }

    let availableCount = max(0, PhotoDraft.maximumCount - photos.count)

    for item in items.prefix(availableCount) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw CaptureError.photoUnavailable
        }
        guard
          let mimeType = PhotoImageType.detect(
            data: data,
            typeIdentifiers: item.supportedContentTypes.map(\.identifier)
          )
        else {
          throw PhotoDraftError.unsupportedType
        }

        let image = UIImage(data: data)
        let draft = try PhotoDraft.validate(
          data: data,
          mimeType: mimeType,
          originalFilename: nil,
          pixelWidth: image.map { Int($0.size.width * $0.scale) },
          pixelHeight: image.map { Int($0.size.height * $0.scale) }
        )
        try await addPhoto(draft)
      } catch {
        photoError = error.localizedDescription
      }
    }
  }

  @MainActor
  private func remove(_ photoID: UUID) async {
    photoError = nil

    do {
      try await removePhoto(photoID)
    } catch {
      photoError = "MemoTrail could not remove that local photo. Try again."
    }
  }
}

/// Web `captureSpark`: the sparkle on a soft accent circle beside the composer's question.
struct CaptureSpark: View {
  var body: some View {
    Image(.sparkle)
      .font(.mtIcon(MTSize.Icon.s15, weight: .medium))
      .foregroundStyle(MTColor.accent)
      .frame(width: MTSize.Capture.spark, height: MTSize.Capture.spark)
      .background(MTColor.accentSubtle, in: Circle())
      .accessibilityHidden(true)
  }
}

/// The Web composer's quiet icon action: muted until active, then tinted on a soft fill.
private struct CaptureQuietIcon: View {
  let icon: MTIcon
  let isActive: Bool
  var tint: Color = MTColor.accent

  var body: some View {
    Image(icon)
      .font(.mtIcon(MTSize.Icon.s17))
      .foregroundStyle(isActive ? tint : MTColor.inkMuted)
      .frame(width: MTLayout.Capture.quietIconWidth, height: MTSize.Capture.quietAction)
      .background(
        isActive ? (tint == MTColor.warm ? MTColor.warmSubtle : MTColor.accentSubtle) : .clear,
        in: RoundedRectangle(cornerRadius: MTRadius.small)
      )
      .contentShape(Rectangle())
  }
}

/// Web `DatePickerField` with `includeTime`, as the composer's Date panel: a day, an optional
/// time of day, and Clear, which leaves the capture time.
private struct CaptureDateControl: View {
  @Binding var value: String
  let timezone: TimeZone
  @State private var isPickingDay = false
  @State private var isPickingTime = false

  private var day: String { CaptureDate.day(of: value) }
  private var time: String { CaptureDate.time(of: value) }
  private var dayDate: Date? { MTDateText.date(day, granularity: .day, includesTime: false) }
  private var timeDate: Date? {
    time.isEmpty
      ? nil : MTDateText.date("\(day)T\(time)", granularity: .day, includesTime: true)
  }
  private var dayText: String? { dayDate.map { MTDateText.display($0, granularity: .day) } }
  private var timeText: String? { timeDate.map { MTDateText.displayTime($0) } }

  var body: some View {
    HStack(spacing: MTSpacing.s1) {
      Button {
        isPickingDay = true
      } label: {
        HStack(spacing: MTSpacing.s2) {
          Image(.calendar).foregroundStyle(MTColor.inkFaint)
          Text(dayText ?? "Select date")
            .foregroundStyle(dayText == nil ? MTColor.inkFaint : MTColor.ink)
            .lineLimit(1)
          Spacer(minLength: MTSpacing.s2)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Choose date")
      .accessibilityValue(dayText ?? "Not set")
      .accessibilityIdentifier("capture-date-day")
      .popover(isPresented: $isPickingDay) {
        picker(title: "Date", done: "capture-date-day-done") {
          DatePicker("Date", selection: dayBinding, displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .frame(minWidth: MTSize.DatePicker.width)
        }
      }

      Button {
        isPickingTime = true
      } label: {
        HStack(spacing: MTSpacing.s1_5) {
          Image(.clock).foregroundStyle(timeText == nil ? MTColor.inkFaint : MTColor.inkMuted)
          Text(timeText ?? "Add time")
            .foregroundStyle(timeText == nil ? MTColor.inkMuted : MTColor.ink)
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, MTSpacing.s2)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(day.isEmpty)
      .accessibilityLabel("Choose date time")
      .accessibilityValue(timeText ?? "Not set")
      .accessibilityIdentifier("capture-date-time")
      .popover(isPresented: $isPickingTime) {
        picker(title: "Time", done: "capture-date-time-done", commit: commitShownTime) {
          VStack(spacing: MTSpacing.s2) {
            DatePicker("Time", selection: timeBinding, displayedComponents: [.hourAndMinute])
              .datePickerStyle(.wheel)
              .labelsHidden()
              .frame(width: MTSize.DatePicker.width)
            if !time.isEmpty {
              Button("Remove time") {
                value = CaptureDate.value(day: day, time: "")
                isPickingTime = false
              }
              .mtButtonStyle(.secondary, size: .small)
              .accessibilityIdentifier("capture-date-remove-time")
            }
          }
        }
      }

      if !value.isEmpty {
        Button {
          value = ""
        } label: {
          Image(.close).font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(MTColor.inkMuted)
        .frame(width: MTLayout.InlineAction.height, height: MTLayout.InlineAction.height)
        .contentShape(Rectangle())
        .accessibilityLabel("Clear date")
        .accessibilityIdentifier("capture-date-clear")
      }
    }
    .font(MTFont.body)
    .mtFieldSurface(
      size: MTFieldSize(MTDateFieldDefaults.size), isFocused: isPickingDay || isPickingTime)
  }

  /// The day shown in the calendar: the chosen one, or today in the capture's zone.
  private var dayBinding: Binding<Date> {
    Binding(
      get: { dayDate ?? MTDateText.calendar.startOfDay(for: MTDateText.now(in: timezone)) },
      set: {
        value = CaptureDate.value(
          day: MTDateText.text($0, granularity: .day, includesTime: false), time: time)
      })
  }

  /// The time shown on the wheel: the chosen one, or now in the capture's zone.
  private var timeBinding: Binding<Date> {
    Binding(
      get: { timeDate ?? MTDateText.now(in: timezone) },
      set: { setTime($0) })
  }

  private func setTime(_ date: Date) {
    let text = MTDateText.text(date, granularity: .day, includesTime: true)
    value = CaptureDate.value(day: day, time: CaptureDate.time(of: text))
  }

  /// Done keeps the time the wheel shows, even when the person did not turn it.
  private func commitShownTime() {
    if time.isEmpty, !day.isEmpty { setTime(MTDateText.now(in: timezone)) }
  }

  private func picker<Content: View>(
    title: String, done identifier: String, commit: @escaping () -> Void = {},
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 0) {
      content()
        .environment(\.timeZone, .gmt)
        .environment(\.calendar, MTDateText.calendar)
        .tint(MTColor.accent)
        .padding(.horizontal, MTSpacing.s3)
        .padding(.top, MTSpacing.s2)
      Divider().overlay(MTColor.border)
      HStack {
        Text(title).font(MTFont.caption).foregroundStyle(MTColor.inkMuted).lineLimit(1)
        Spacer()
        Button("Done") {
          commit()
          isPickingDay = false
          isPickingTime = false
        }
        .mtButtonStyle(.primary, size: .small)
        .accessibilityIdentifier(identifier)
      }
      .padding(MTSpacing.s3)
    }
    .background(MTColor.surfaceRaised)
    .presentationCompactAdaptation(.popover)
  }
}
