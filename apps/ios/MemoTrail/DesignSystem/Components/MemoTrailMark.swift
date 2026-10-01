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
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.58), value: revealed)

        Circle()
          .trim(from: 290 / 360, to: revealed ? 340 / 360 : 290 / 360)
          .stroke(
            MTColor.warm,
            style: StrokeStyle(lineWidth: size * 0.109_375, lineCap: .round)
          )
          .frame(width: size * 0.605_469, height: size * 0.605_469)
          .rotationEffect(.degrees(turn))
          .animation(reduceMotion ? nil : .easeOut(duration: 0.34).delay(0.22), value: revealed)

        Circle()
          .trim(from: 35 / 360, to: revealed ? 255 / 360 : 35 / 360)
          .stroke(
            Color(red: 130 / 255, green: 173 / 255, blue: 152 / 255),
            style: StrokeStyle(lineWidth: size * 0.066_406, lineCap: .round)
          )
          .frame(width: size * 0.361_328, height: size * 0.361_328)
          .rotationEffect(.degrees(-turn))
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).delay(0.12), value: revealed)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .accessibilityHidden(true)
    .onAppear { revealed = true }
  }
}
