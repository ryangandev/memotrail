import PhotosUI
import SwiftUI
import UIKit

/// The Web CaptureComposer: one formatted note, an optional relevant date, voice, and photos,
/// saved to the Inbox through the offline queue.
struct CaptureCard: View {
  @Binding var note: NSAttributedString
  @Binding var occurrence: OccurrenceDraft?
  @State private var showOccurrence = false
  @Binding var photos: [FirstTimePhotoDraft]

  let isSaving: Bool
  let hasLocalDraft: Bool
  let message: InboxController.CaptureMessage?
  var focusRequest = 0
  let addPhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  let save: @MainActor () async -> Void

  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isLoadingPhotos = false
  @State private var photoError: String?
  @State private var voiceController = VoiceTranscriptionController()

  private var isBusy: Bool { isSaving || isLoadingPhotos || voiceController.isActive }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: MTSpacing.s3) {
        Image(.sparkle)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 32, height: 32)
          .background(MTColor.accentSubtle, in: Circle())
          .accessibilityHidden(true)
        Text("What\u{2019}s on your mind?")
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
      }
      .padding(.horizontal, MTSpacing.s5)
      .padding(.top, MTSpacing.s5)

      MTRichTextEditor(
        text: $note, placeholder: "What is on your mind?", accessibilityIdentifier: "capture-body",
        isEmbedded: true, minimumHeight: 120, focusRequest: focusRequest
      )
      .disabled(isSaving || voiceController.isActive)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.top, MTSpacing.s2)

      if let status {
        Label(status.text, systemImage: status.systemImage)
          .font(MTFont.caption)
          .foregroundStyle(status.color)
          .padding(.horizontal, MTSpacing.s5)
          .padding(.bottom, MTSpacing.s3)
          .accessibilityIdentifier(status.identifier)
      }

      if let occurrence {
        HStack(spacing: MTSpacing.s3) {
          Label(
            (try? occurrence.resolve().displayLabel) ?? "Date needs attention", icon: .calendar
          )
          .font(MTFont.caption)
          .foregroundStyle(MTColor.accent)
          Spacer(minLength: 0)
          Button("Edit date") { showOccurrence = true }
            .mtButtonStyle(.ghost, size: .small)
        }
        .padding(.horizontal, MTSpacing.s5)
        .padding(.vertical, MTSpacing.s2)
        .background(MTColor.accentSubtle.opacity(0.6))
      }

      if !photos.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s2) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
              photoThumbnail(photo, index: index)
            }
          }
          .padding(.horizontal, MTSpacing.s5)
          .padding(.vertical, MTSpacing.s3)
        }
        .accessibilityLabel("Draft photos")
        .accessibilityIdentifier("capture-photo-preview")
      }

      Divider().overlay(MTColor.border)

      HStack(spacing: MTSpacing.s1) {
        quietButton(
          label: occurrence == nil ? "Add relevant date" : "Edit relevant date", icon: .calendar,
          isActive: occurrence != nil, identifier: "capture-date"
        ) {
          if occurrence == nil {
            occurrence = OccurrenceDraft(
              EntryOccurrence(
                precision: .exact, start: Date(), end: nil, label: nil,
                timezone: TimeZone.current.identifier))
          }
          showOccurrence = true
        }
        .disabled(isBusy)

        voiceButton
        photoPicker

        Spacer(minLength: MTSpacing.s2)

        Button {
          Task { await save() }
        } label: {
          HStack(spacing: MTSpacing.s2) {
            Text("Save to Inbox")
            Image(.chevron).font(.system(size: 11, weight: .semibold))
          }
        }
        .mtButtonStyle(.primary, isLoading: isSaving)
        .disabled(isBusy)
        .accessibilityIdentifier("save-entry")
      }
      .padding(.horizontal, MTSpacing.s3)
      .padding(.vertical, MTSpacing.s3)
    }
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
        MTColor.borderStrong, lineWidth: 1)
    }
    .mtShadow(MTShadow.raised)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Quick capture")
    .onChange(of: pickerItems) { _, items in
      Task { await loadPhotos(from: items) }
    }
    .onChange(of: voiceController.transcribedText) { _, transcribedText in
      // Like Web, dictated text replaces the draft note as plain text.
      if let transcribedText { note = NSAttributedString(string: transcribedText) }
    }
    .sheet(isPresented: $showOccurrence) {
      NavigationStack {
        Form {
          Section {
            OccurrenceEditor(value: occurrenceBinding)
          }
          Section {
            Button("Use capture time") {
              occurrence = nil
              showOccurrence = false
            }
          }
        }
        .navigationTitle("Relevant date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showOccurrence = false }
          }
        }
      }
    }
    .onDisappear {
      voiceController.stop(silently: true)
    }
  }

  private struct Status {
    let text: String
    let systemImage: String
    let color: Color
    let identifier: String
  }

  private var status: Status? {
    if let photoError {
      return Status(
        text: photoError, systemImage: "exclamationmark.circle.fill", color: MTColor.warm,
        identifier: "capture-photo-error")
    }
    if let voiceMessage = voiceController.message {
      return Status(
        text: voiceMessage,
        systemImage: voiceController.hasError
          ? "exclamationmark.circle.fill"
          : (voiceController.isActive ? "waveform" : "checkmark.circle.fill"),
        color: voiceController.hasError ? MTColor.warm : MTColor.inkMuted,
        identifier: "capture-voice-message")
    }
    if let message {
      return Status(
        text: message.text,
        systemImage: message.style == .success
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
        color: message.style == .success ? MTColor.success : MTColor.warm,
        identifier: "capture-message")
    }
    if hasLocalDraft {
      return Status(
        text: "Draft saved on this iPhone.", systemImage: MTIcon.history.systemName,
        color: MTColor.inkMuted, identifier: "draft-message")
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
      .frame(width: 80, height: 80)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
      .contentShape(RoundedRectangle(cornerRadius: MTRadius.medium))

      Button {
        Task { await remove(photo.id) }
      } label: {
        Image(.close)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 24, height: 24)
          .background(
            Color(red: 24 / 255, green: 24 / 255, blue: 20 / 255).opacity(0.72), in: Circle()
          )
          .frame(width: 36, height: 36)
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

/// The Web composer's quiet icon action: muted until active, then tinted on a soft fill.
private struct CaptureQuietIcon: View {
  let icon: MTIcon
  let isActive: Bool
  var tint: Color = MTColor.accent

  var body: some View {
    Image(icon)
      .font(.system(size: 17))
      .foregroundStyle(isActive ? tint : MTColor.inkMuted)
      .frame(width: 40, height: 36)
      .background(
        isActive ? (tint == MTColor.warm ? MTColor.warmSubtle : MTColor.accentSubtle) : .clear,
        in: RoundedRectangle(cornerRadius: MTRadius.small)
      )
      .contentShape(Rectangle())
  }
}
