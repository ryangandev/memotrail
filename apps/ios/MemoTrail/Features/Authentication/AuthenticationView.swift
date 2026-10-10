import SwiftUI

/// Web `AuthGate` at phone width: the brand header, the welcome story, and the sign-in card.
struct AuthenticationView: View {
  let state: AuthenticationController.State
  let isBusy: Bool
  let errorMessage: String?
  let signIn: @MainActor () async -> Void
  #if DEBUG
    @State private var showingDesignSystem = false
  #endif

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        VStack(alignment: .leading, spacing: MTSpacing.s8) {
          story
          signInCard
          #if DEBUG
            Button("Design System", systemImage: "square.grid.2x2") { showingDesignSystem = true }
              .font(MTFont.caption)
              .accessibilityIdentifier("signed-out-design-system")
          #endif
        }
        .padding(.top, MTLayout.SignIn.top)
        .padding(.bottom, MTSpacing.s16)
      }
      .frame(maxWidth: MTLayout.SignIn.width, alignment: .leading)
      .padding(.horizontal, MTSpacing.s4)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background {
      // Web's warm glow near the top leading corner.
      RadialGradient(
        colors: [MTColor.warmGlow, MTColor.warmGlowFade],
        center: UnitPoint(x: 0.08, y: 0.15), startRadius: 0, endRadius: 300
      )
      .background(MTColor.canvas)
      .ignoresSafeArea()
    }
    #if DEBUG
      .sheet(isPresented: $showingDesignSystem) {
        NavigationStack {
          DesignSystemGallery()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showingDesignSystem = false }
            }
          }
        }
      }
    #endif
  }

  private var header: some View {
    HStack(spacing: MTLayout.SignIn.markGap) {
      MemoTrailMark()
        .frame(width: MTLayout.SignIn.headerMark, height: MTLayout.SignIn.headerMark)
      Text("MemoTrail")
        .mtTextRole(.wordmark)
        .foregroundStyle(MTColor.ink)
    }
    .frame(maxWidth: .infinity, minHeight: MTLayout.SignIn.headerHeight, alignment: .leading)
    .overlay(alignment: .bottom) { MTListDivider() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("MemoTrail")
    .accessibilityAddTraits(.isHeader)
  }

  private var story: some View {
    VStack(alignment: .leading, spacing: 0) {
      eyebrow("Your life, kept with context")
      Text("A quiet place for everything worth keeping.")
        .mtTextRole(.hero)
        .foregroundStyle(MTColor.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, MTSpacing.s4)
        .accessibilityAddTraits(.isHeader)
      Text(
        "Capture thoughts, first times, places, and the chapters that connect them. MemoTrail keeps the archive private and leaves the organization in your hands."
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.relaxed)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, MTSpacing.s6)
    }
  }

  private var signInCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      MemoTrailMark()
        .frame(width: MTLayout.SignIn.cardMark, height: MTLayout.SignIn.cardMark)
        .accessibilityHidden(true)
      eyebrow("Personal archive")
        .padding(.top, MTSpacing.s8)
      Text("Welcome to MemoTrail")
        .mtTextRole(.welcomeTitle)
        .foregroundStyle(MTColor.ink)
        .padding(.top, MTLayout.SignIn.titleGap)
        .accessibilityAddTraits(.isHeader)
      Text("Sign in to continue to your private space.")
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, MTSpacing.s2)
      signInControl
        .padding(.top, MTSpacing.s8)
      if let errorMessage {
        Text(errorMessage)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.warm)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, MTSpacing.s3)
          .accessibilityLabel("Sign-in error: \(errorMessage)")
      }
      Text("Google verifies your identity. MemoTrail never receives your Google password.")
        .font(MTFont.note)
        .foregroundStyle(MTColor.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, MTSpacing.s6)
    }
    .padding(MTSpacing.s6)
    .background(
      MTColor.surfaceRaisedTranslucent, in: RoundedRectangle(cornerRadius: MTRadius.xlarge)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.xlarge).strokeBorder(MTColor.borderStrong)
    }
    .mtShadow(MTShadow.floating)
  }

  @ViewBuilder private var signInControl: some View {
    switch state {
    case .checking:
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Opening your private space…")
          .font(MTFont.label)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.SignIn.controlHeight)
    case .setupRequired:
      // Web's Setup needed notice, naming the native configuration instead.
      VStack(alignment: .leading, spacing: MTSpacing.detailGap) {
        Text("Setup needed")
          .font(MTFont.label)
          .foregroundStyle(MTColor.ink)
        Text(
          "Add the Supabase URL, publishable key, Google iOS client ID, and URL scheme to Secrets.xcconfig, then rebuild the app."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(MTSpacing.s4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.warmSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.medium)
          .strokeBorder(MTColor.warningBorder)
      }
      .accessibilityElement(children: .combine)
    case .signedOut, .signedIn:
      // Web's own Google button: the G mark and "Continue with Google" on the card surface.
      Button {
        Task { await signIn() }
      } label: {
        HStack(spacing: MTSpacing.s3) {
          Image("GoogleMark")
            .resizable()
            .frame(width: MTLayout.SignIn.googleMark, height: MTLayout.SignIn.googleMark)
            .accessibilityHidden(true)
          Text(isBusy ? "Opening Google…" : "Continue with Google")
        }
        .font(MTFont.bodyEmphasis)
        .foregroundStyle(MTColor.ink)
        .frame(maxWidth: .infinity, minHeight: MTLayout.SignIn.controlHeight)
      }
      .buttonStyle(GoogleButtonStyle())
      .disabled(isBusy)
      .accessibilityIdentifier("google-sign-in")
    }
  }

  /// Web's `eyebrow` and `cardEyebrow`: small uppercase accent labels.
  private func eyebrow(_ text: String) -> some View {
    Text(text)
      .mtTextRole(.storyEyebrow)
      .foregroundStyle(MTColor.accent)
  }
}

/// Web `googleButton`: a bordered surface whose border takes the accent while pressed.
private struct GoogleButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.medium)
    configuration.label
      .background(configuration.isPressed ? MTColor.surface : MTColor.surfaceRaised, in: shape)
      .overlay {
        shape.strokeBorder(configuration.isPressed ? MTColor.accent : MTColor.borderStrong)
      }
      .contentShape(shape)
      .opacity(isEnabled ? 1 : MTState.Disabled.Opacity.soft)
      .animation(MTEasing.enter.animation(duration: MTMotion.quick), value: configuration.isPressed)
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
