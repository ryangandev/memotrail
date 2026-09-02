import SwiftUI

struct CaptureCard: View {
  @Binding var title: String
  @Binding var note: String

  let isSaving: Bool
  let hasLocalDraft: Bool
  let message: InboxController.CaptureMessage?
  let titleFocus: FocusState<Bool>.Binding
  let save: @MainActor () async -> Void

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
        .accessibilityIdentifier("capture-body")

        if let message {
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

      Divider()
        .overlay(MTColor.border)

      HStack(spacing: MTSpacing.s1) {
        upcomingAttachment("Voice", systemImage: "mic")
        upcomingAttachment("Photo", systemImage: "photo")

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
        .disabled(isSaving)
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
  }

  private func upcomingAttachment(_ title: String, systemImage: String) -> some View {
    Button(title, systemImage: systemImage) {}
      .labelStyle(.iconOnly)
      .font(.system(size: 17))
      .foregroundStyle(MTColor.inkFaint)
      .frame(width: 38, height: 36)
      .contentShape(Rectangle())
      .disabled(true)
      .accessibilityLabel(title)
      .accessibilityHint("Coming next")
  }
}
