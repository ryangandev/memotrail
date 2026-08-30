import SwiftUI

struct CaptureCard: View {
  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: MTSpacing.s3) {
        Image(systemName: "sparkles")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 34, height: 34)
          .background(MTColor.accentSubtle, in: Circle())

        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text("What is worth keeping?")
            .font(MTTypography.titleSmall)
            .foregroundStyle(MTColor.ink)

          Text("A thought, a first, something learned, or whatever is on your mind.")
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkFaint)
            .lineSpacing(3)
        }

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
      .padding(MTSpacing.s4)

      Divider()
        .overlay(MTColor.border)

      HStack(spacing: MTSpacing.s1) {
        attachmentButton("Voice", systemImage: "mic")
        attachmentButton("Photo", systemImage: "photo")

        Spacer()

        Button {} label: {
          HStack(spacing: MTSpacing.s2) {
            Text("Save to Inbox")
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
          }
          .font(MTTypography.label)
          .foregroundStyle(MTColor.accentInk)
          .padding(.horizontal, MTSpacing.s3)
          .frame(height: 36)
          .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
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

  private func attachmentButton(_ title: String, systemImage: String) -> some View {
    Button(title, systemImage: systemImage) {}
      .labelStyle(.iconOnly)
      .font(.system(size: 17))
      .foregroundStyle(MTColor.inkMuted)
      .frame(width: 38, height: 36)
      .contentShape(Rectangle())
      .accessibilityLabel(title)
  }
}

#Preview {
  CaptureCard()
    .padding()
    .background(MTColor.canvas)
}
