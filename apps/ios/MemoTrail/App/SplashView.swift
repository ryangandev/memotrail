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
          .frame(width: 132, height: 132)

        Text("MemoTrail")
          .font(.system(size: 32, weight: .medium, design: .serif))
          .foregroundStyle(MTColor.ink)
          .opacity(wordmarkVisible ? 1 : 0)
          .offset(y: wordmarkVisible ? 0 : 7)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("MemoTrail is opening")
    .onAppear {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.42)) {
        wordmarkVisible = true
      }
    }
  }
}

#Preview {
  SplashView()
}
