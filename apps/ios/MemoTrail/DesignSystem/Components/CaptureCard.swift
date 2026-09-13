import PhotosUI
import SwiftUI
import UIKit

struct CaptureCard: View {
  @Binding var title: String
  @Binding var note: String
  @Binding var occurrence: OccurrenceDraft?
  @State private var showOccurrence = false
  @Binding var photos: [FirstTimePhotoDraft]

  let isSaving: Bool
  let hasLocalDraft: Bool
  let message: InboxController.CaptureMessage?
  let titleFocus: FocusState<Bool>.Binding
  let addPhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  let removePhoto: @MainActor (UUID) async throws -> Void
  let save: @MainActor () async -> Void

  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isLoadingPhotos = false
  @State private var photoError: String?
  @State private var voiceController = VoiceTranscriptionController()

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(alignment: .center, spacing: MTSpacing.s3) {
          Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(MTColor.accent)
            .frame(width: 34, height: 34)
            .background(MTColor.accentSubtle, in: Circle())

          VStack(alignment: .leading, spacing: MTSpacing.s1) {
            Text("What is worth keeping?")
              .font(MTTypography.titleSmall)
              .foregroundStyle(MTColor.ink)

            Text("A thought, a first, something learned, or whatever is on your mind.")
              .font(MTTypography.body)
              .foregroundStyle(MTColor.inkFaint)
              .lineSpacing(3)
          }
        }

        TextField("Optional title", text: $title)
          .focused(titleFocus)
          .font(MTTypography.bodyLarge)
          .foregroundStyle(MTColor.ink)
          .textInputAutocapitalization(.sentences)
          .submitLabel(.next)
          .accessibilityIdentifier("capture-title")

        Divider()
          .overlay(MTColor.border)

        TextField(
          "Write a note...",
          text: $note,
          axis: .vertical
        )
        .lineLimit(3...10)
        .font(MTTypography.body)
        .foregroundStyle(MTColor.ink)
        .textInputAutocapitalization(.sentences)
        .disabled(isSaving || voiceController.isActive)
        .accessibilityIdentifier("capture-body")

        if let photoError {
          Label(photoError, systemImage: "exclamationmark.circle.fill")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.warm)
            .accessibilityIdentifier("capture-photo-error")
        } else if let voiceMessage = voiceController.message {
          Label(
            voiceMessage,
            systemImage: voiceController.hasError
              ? "exclamationmark.circle.fill"
              : (voiceController.isActive ? "waveform" : "checkmark.circle.fill")
          )
          .font(MTTypography.caption)
          .foregroundStyle(voiceController.hasError ? MTColor.warm : MTColor.inkMuted)
          .accessibilityIdentifier("capture-voice-message")
        } else if let message {
          Label(
            message.text,
            systemImage: message.style == .success
              ? "checkmark.circle.fill"
              : "exclamationmark.circle.fill"
          )
          .font(MTTypography.caption)
          .foregroundStyle(message.style == .success ? MTColor.success : MTColor.warm)
          .accessibilityIdentifier("capture-message")
        } else if hasLocalDraft {
          Label("Draft saved on this iPhone.", systemImage: "clock.arrow.circlepath")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkMuted)
            .accessibilityIdentifier("draft-message")
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(MTSpacing.s4)

      if let occurrence {
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text((try? occurrence.resolve().displayLabel) ?? "Date needs attention")
            .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
          Button("Edit date") { showOccurrence = true }
            .font(MTTypography.label).foregroundStyle(MTColor.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(MTSpacing.s4)
        .background(MTColor.accentSubtle)
      }

      if !photos.isEmpty {
        Divider()
          .overlay(MTColor.border)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s3) {
            ForEach(photos) { photo in
              ZStack(alignment: .topTrailing) {
                if let image = UIImage(data: photo.data) {
                  Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                } else {
                  Image(systemName: "photo")
                    .foregroundStyle(MTColor.inkFaint)
                    .frame(width: 88, height: 80)
                    .background(MTColor.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
                }

                Button {
                  Task { await remove(photo.id) }
                } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.66), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving || isLoadingPhotos)
                .padding(5)
                .accessibilityLabel("Remove selected photo")
              }
            }
          }
          .padding(.horizontal, MTSpacing.s4)
          .padding(.vertical, MTSpacing.s3)
        }
        .background(MTColor.surfaceSubtle.opacity(0.72))
        .accessibilityIdentifier("capture-photo-preview")
      }

      Divider()
        .overlay(MTColor.border)

      HStack(spacing: MTSpacing.s1) {
        Button {
          if occurrence == nil {
            occurrence = OccurrenceDraft(
              EntryOccurrence(
                precision: .exact, start: Date(), end: nil, label: nil,
                timezone: TimeZone.current.identifier))
          }
          showOccurrence = true
        } label: {
          Image(systemName: "calendar")
            .font(.system(size: 17))
            .foregroundStyle(occurrence == nil ? MTColor.inkFaint : MTColor.accent)
            .frame(width: 38, height: 36)
            .background(
              occurrence == nil ? Color.clear : MTColor.accentSubtle,
              in: RoundedRectangle(cornerRadius: MTRadius.small)
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel(occurrence == nil ? "Add relevant date" : "Edit relevant date")
        .accessibilityIdentifier("capture-date")
        .disabled(isSaving || isLoadingPhotos || voiceController.isActive)

        voiceButton
        photoPicker

        Spacer()

        Button {
          Task {
            await save()
          }
        } label: {
          HStack(spacing: MTSpacing.s2) {
            if isSaving {
              ProgressView()
                .controlSize(.small)
                .tint(MTColor.accentInk)
            } else {
              Text("Save to Inbox")
              Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
            }
          }
          .font(MTTypography.label)
          .foregroundStyle(MTColor.accentInk)
          .padding(.horizontal, MTSpacing.s3)
          .frame(minWidth: 130, minHeight: 36)
          .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
        .disabled(isSaving || isLoadingPhotos || voiceController.isActive)
        .accessibilityIdentifier("save-entry")
      }
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, MTSpacing.s2)
      .background(MTColor.surface)
    }
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.borderStrong, lineWidth: 1)
    }
    .shadow(color: MTColor.scrim.opacity(0.06), radius: 16, y: 8)
    .onChange(of: pickerItems) { _, items in
      Task { await loadPhotos(from: items) }
    }
    .onChange(of: voiceController.transcribedText) { _, transcribedText in
      if let transcribedText {
        note = transcribedText
      }
    }
    .sheet(isPresented: $showOccurrence) {
      NavigationStack {
        Form {
          OccurrenceEditor(value: occurrenceBinding)
          Button("Use capture time") {
            occurrence = nil
            showOccurrence = false
          }
        }
        .navigationTitle("Relevant date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Close") { showOccurrence = false }
          }
        }
      }
    }
    .onDisappear {
      voiceController.stop(silently: true)
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
      titleFocus.wrappedValue = false
      if voiceController.isActive {
        voiceController.stop()
      } else {
        Task { await voiceController.start(currentText: note) }
      }
    } label: {
      Image(systemName: voiceController.isActive ? "stop.fill" : "mic")
        .font(.system(size: voiceController.isActive ? 13 : 17, weight: .medium))
        .foregroundStyle(voiceController.isActive ? MTColor.warm : MTColor.inkFaint)
        .frame(width: 38, height: 36)
        .background(
          voiceController.isActive ? MTColor.warmSubtle : Color.clear,
          in: RoundedRectangle(cornerRadius: MTRadius.small)
        )
        .contentShape(Rectangle())
    }
    .disabled(isSaving || isLoadingPhotos)
    .accessibilityLabel(voiceController.isActive ? "Stop voice capture" : "Start voice capture")
    .accessibilityValue(voiceController.phase == .listening ? "Listening" : "")
    .accessibilityHint("Transcribes speech into the Entry body without saving audio")
    .accessibilityIdentifier("capture-voice")
  }

  private var photoPicker: some View {
    let photoCount = photos.count
    let hasPhotos = photoCount > 0

    return PhotosPicker(
      selection: $pickerItems,
      maxSelectionCount: max(1, FirstTimePhotoDraft.maximumCount - photoCount),
      matching: .images
    ) {
      Image(systemName: "photo")
        .font(.system(size: 17))
        .foregroundStyle(hasPhotos ? MTColor.accent : MTColor.inkFaint)
        .frame(width: 38, height: 36)
        .background(
          hasPhotos ? MTColor.accentSubtle : Color.clear,
          in: RoundedRectangle(cornerRadius: MTRadius.small)
        )
        .contentShape(Rectangle())
    }
    .disabled(
      isSaving || isLoadingPhotos || voiceController.isActive
        || photoCount >= FirstTimePhotoDraft.maximumCount
    )
    .accessibilityLabel("Add photos")
    .accessibilityValue("\(photoCount) selected")
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
