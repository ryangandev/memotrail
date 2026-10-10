import SwiftUI

struct SplashView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var wordmarkVisible = false

  var body: some View {
    ZStack {
      MTColor.canvas
        .ignoresSafeArea()

      VStack(spacing: MTSpacing.s5) {
        MemoTrailMark(animated: true)
          .frame(width: MTLayout.Splash.mark, height: MTLayout.Splash.mark)

        Text("MemoTrail")
          .font(MTFont.wordmarkLarge)
          .foregroundStyle(MTColor.ink)
          .opacity(wordmarkVisible ? 1 : 0)
          .offset(y: wordmarkVisible ? 0 : MTLayout.Splash.wordmarkRise)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("MemoTrail is opening")
    .onAppear {
      withAnimation(
        reduceMotion
          ? nil
          : MTEasing.enter.animation(duration: MTMotion.wordmarkReveal)
            .delay(MTMotion.wordmarkDelay)
      ) {
        wordmarkVisible = true
      }
    }
  }
}

#Preview {
  SplashView()
}
