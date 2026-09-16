import GoogleSignInSwift
import SwiftUI

struct AuthenticationView: View {
  let state: AuthenticationController.State
  let isBusy: Bool
  let errorMessage: String?
  let signIn: @MainActor () async -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MTSpacing.s10) {
        brand
        story
        signInCard
      }
      .frame(maxWidth: 560, alignment: .leading)
      .padding(.horizontal, MTSpacing.s6)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background {
      ZStack(alignment: .topLeading) {
        MTColor.canvas
        Circle()
          .fill(MTColor.warmSubtle.opacity(0.7))
          .frame(width: 360, height: 360)
          .blur(radius: 70)
          .offset(x: -190, y: -160)
      }
      .ignoresSafeArea()
    }
  }

  private var brand: some View {
    HStack(spacing: MTSpacing.s3) {
      MemoTrailMark()
        .frame(width: 32, height: 32)

      Text("MemoTrail")
        .font(.system(size: 20, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("MemoTrail")
  }

  private var story: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("YOUR LIFE, KEPT WITH CONTEXT")
        .font(MTTypography.caption.weight(.semibold))
        .tracking(1.25)
        .foregroundStyle(MTColor.accent)

      Text("A quiet place for everything worth keeping.")
        .font(.system(size: 43, weight: .medium, design: .serif))
        .tracking(-1.2)
        .foregroundStyle(MTColor.ink)
        .fixedSize(horizontal: false, vertical: true)

      Text(
        "Capture thoughts, first times, people, places, and the chapters that connect them."
      )
      .font(MTTypography.body)
      .foregroundStyle(MTColor.inkMuted)
      .lineSpacing(4)
    }
  }

  private var signInCard: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("PERSONAL ARCHIVE")
        .font(MTTypography.caption.weight(.semibold))
        .tracking(1.2)
        .foregroundStyle(MTColor.accent)

      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(cardTitle)
          .font(.system(size: 27, weight: .medium, design: .serif))
          .foregroundStyle(MTColor.ink)

        Text(cardMessage)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .fixedSize(horizontal: false, vertical: true)
      }

      if state == .checking {
        HStack(spacing: MTSpacing.s3) {
          ProgressView()
            .tint(MTColor.accent)
          Text("Opening your private space…")
            .font(MTTypography.label)
            .foregroundStyle(MTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
      } else if state == .setupRequired {
        Label {
          Text(
            "Add the Supabase URL, publishable key, Google iOS client ID, and URL scheme to Secrets.xcconfig."
          )
        } icon: {
          Image(systemName: "wrench.and.screwdriver")
        }
        .font(MTTypography.label)
        .foregroundStyle(MTColor.inkMuted)
        .padding(MTSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MTColor.warmSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      } else {
        GoogleSignInButton {
          Task { await signIn() }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .disabled(isBusy)
        .opacity(isBusy ? 0.7 : 1)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("Sign-in error: \(errorMessage)")
      }

      Text(
        "Google verifies your identity. MemoTrail never receives your Google password."
      )
      .font(.system(size: 10))
      .foregroundStyle(MTColor.inkFaint)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(MTSpacing.s6)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.xlarge))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.xlarge)
        .stroke(MTColor.borderStrong, lineWidth: 1)
    }
    .shadow(color: MTColor.scrim.opacity(0.09), radius: 24, y: 12)
  }

  private var cardTitle: String {
    state == .setupRequired ? "Finish app setup" : "Welcome to MemoTrail"
  }

  private var cardMessage: String {
    state == .setupRequired
      ? "Public configuration is incomplete. No server secret belongs in the iOS app."
      : "Sign in to continue to your private space."
  }
}

struct AccountView: View {
  let user: AuthenticatedUser
  let isBusy: Bool
  let signOut: @MainActor () async -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: MTSpacing.s6) {
        Text(user.initial)
          .font(.system(size: 30, weight: .medium, design: .serif))
          .foregroundStyle(MTColor.accentInk)
          .frame(width: 72, height: 72)
          .background(MTColor.accent, in: Circle())

        VStack(spacing: MTSpacing.s2) {
          Text(user.name)
            .font(.system(size: 24, weight: .medium, design: .serif))
            .foregroundStyle(MTColor.ink)

          Text(user.email)
            .font(MTTypography.label)
            .foregroundStyle(MTColor.inkMuted)
        }

        Text("This is your private MemoTrail space.")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)

        Spacer()

        Button(role: .destructive) {
          Task {
            await signOut()
            dismiss()
          }
        } label: {
          if isBusy {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text("Sign Out")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBusy)
      }
      .padding(MTSpacing.s6)
      .background(MTColor.canvas)
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }
}

#Preview("Signed out") {
  AuthenticationView(
    state: .signedOut,
    isBusy: false,
    errorMessage: nil,
    signIn: {}
  )
}

#Preview("Setup required") {
  AuthenticationView(
    state: .setupRequired,
    isBusy: false,
    errorMessage: nil,
    signIn: {}
  )
}
