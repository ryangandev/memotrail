import PhotosUI
import SwiftUI
import UIKit

/// The Web CaptureComposer: one formatted note, an optional relevant date, voice, and photos,
/// saved to the Inbox through the offline queue. The page style is a raised card on the
/// Dashboard; the dialog style is the open body of Quick Capture.
/// Specified in packages/design-system/components/capture-composer.yaml.
struct CaptureCard: View {
  @Binding var note: NSAttributedString
  @Binding var occurrence: OccurrenceDraft?
  @Binding var photos: [FirstTimePhotoDraft]

  var style = MTCaptureComposerDefaults.style
  let isSaving: Bool
  let hasLocalDraft: Bool
  let error: String?
  var focusRequest = 0
  let addPhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  let save: @MainActor () async -> Void

  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isLoadingPhotos = false
  @State private var photoError: String?
  @State private var voiceController = VoiceTranscriptionController()

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
        focusRequest: focusRequest
      )
      .disabled(isSaving || voiceController.isActive)
      .padding(.horizontal, inlinePadding - MTSpacing.s3)
      .padding(.top, MTSpacing.s2)
      .padding(.bottom, MTSpacing.s2)

      if occurrence != nil {
        // Web `captureOccurrencePanel`: the date fields open in place under the note.
        VStack(alignment: .leading, spacing: MTSpacing.s4) {
          OccurrenceEditor(value: occurrenceBinding)
          Button("Use capture time") { occurrence = nil }
            .mtButtonStyle(.secondary)
            .accessibilityIdentifier("capture-use-capture-time")
        }
        .disabled(isBusy)
        .padding(.horizontal, inlinePadding)
        .padding(.vertical, MTSpacing.s4)
        .overlay(alignment: .top) { MTListDivider() }
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

      HStack(spacing: MTSpacing.s1) {
        quietButton(
          label: occurrence == nil ? "Date" : "Custom date", icon: .calendar,
          isActive: occurrence != nil, identifier: "capture-date", action: toggleRelevantDate
        )
        .disabled(isBusy)

        voiceButton
        photoPicker

        Spacer(minLength: MTSpacing.s2)

        Button {
          Task { await save() }
        } label: {
          HStack(spacing: MTSpacing.s2) {
            Text("Save to Inbox")
            Image(.chevron).font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
          }
        }
        .mtButtonStyle(.primary, isLoading: isSaving)
        .disabled(isBusy)
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
      // Like Web, dictated text replaces the draft note as plain text.
      if let transcribedText { note = NSAttributedString(string: transcribedText) }
    }
    .onDisappear {
      voiceController.stop(silently: true)
    }
  }

  /// Web `toggleRelevantDate`: starts from the capture moment, or returns to it.
  private func toggleRelevantDate() {
    occurrence =
      occurrence == nil
      ? OccurrenceDraft(
        EntryOccurrence(
          precision: .exact, start: Date(), end: nil, label: nil,
          timezone: TimeZone.current.identifier))
      : nil
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

  private func photoThumbnail(_ photo: FirstTimePhotoDraft, index: Int) -> some View {
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

  private var occurrenceBinding: Binding<OccurrenceDraft> {
    Binding(
      get: {
        occurrence
          ?? OccurrenceDraft(
            EntryOccurrence(
              precision: .unknown, start: nil, end: nil, label: nil,
              timezone: TimeZone.current.identifier))
      },
      set: { occurrence = $0 }
    )
  }

  private var voiceButton: some View {
    Button {
      if voiceController.isActive {
        voiceController.stop()
      } else {
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
      maxSelectionCount: max(1, FirstTimePhotoDraft.maximumCount - photos.count),
      matching: .images
    ) {
      CaptureQuietIcon(icon: .photo, isActive: hasPhotos)
    }
    .buttonStyle(.plain)
    .disabled(isBusy || photos.count >= FirstTimePhotoDraft.maximumCount)
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

    let availableCount = max(0, FirstTimePhotoDraft.maximumCount - photos.count)

    for item in items.prefix(availableCount) {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw InboxCaptureError.photoUnavailable
        }
        guard
          let mimeType = FirstTimeImageType.detect(
            data: data,
            typeIdentifiers: item.supportedContentTypes.map(\.identifier)
          )
        else {
          throw FirstTimeEntryError.unsupportedPhotoType
        }

        let image = UIImage(data: data)
        let draft = try FirstTimePhotoDraft.validate(
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
