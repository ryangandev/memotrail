import SwiftUI

struct MemoTrailMark: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed: Bool
  private let turn: Double

  /// `turn` rotates the outer ring and accent while the inner ring counter-rotates, like the Web brand.
  init(animated: Bool = false, turn: Double = 0) {
    _revealed = State(initialValue: !animated)
    self.turn = turn
  }

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)

      ZStack {
        Circle()
          .trim(from: 10 / 360, to: revealed ? 255 / 360 : 10 / 360)
          .stroke(
            MTColor.accent,
            style: StrokeStyle(lineWidth: size * 0.109_375, lineCap: .round)
          )
          .frame(width: size * 0.605_469, height: size * 0.605_469)
          .rotationEffect(.degrees(turn))
          .animation(
            reduceMotion ? nil : MTEasing.inOut.animation(duration: MTMotion.markRing),
            value: revealed)

        Circle()
          .trim(from: 290 / 360, to: revealed ? 340 / 360 : 290 / 360)
          .stroke(
            MTColor.warm,
            style: StrokeStyle(lineWidth: size * 0.109_375, lineCap: .round)
          )
          .frame(width: size * 0.605_469, height: size * 0.605_469)
          .rotationEffect(.degrees(turn))
          .animation(
            reduceMotion
              ? nil
              : MTEasing.enter.animation(duration: MTMotion.markTrail)
                .delay(MTMotion.markTrailDelay), value: revealed)

        Circle()
          .trim(from: 35 / 360, to: revealed ? 255 / 360 : 35 / 360)
          .stroke(
            MTColor.markRing,
            style: StrokeStyle(lineWidth: size * 0.066_406, lineCap: .round)
          )
          .frame(width: size * 0.361_328, height: size * 0.361_328)
          .rotationEffect(.degrees(-turn))
          .animation(
            reduceMotion
              ? nil
              : MTEasing.inOut.animation(duration: MTMotion.markInnerRing)
                .delay(MTMotion.quick), value: revealed)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .accessibilityHidden(true)
    .onAppear { revealed = true }
  }
}
