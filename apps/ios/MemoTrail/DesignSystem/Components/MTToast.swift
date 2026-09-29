import SwiftUI
import UIKit

enum MTToastTone: Sendable {
  case success, info, error

  fileprivate var systemImage: String {
    switch self {
    case .success: "checkmark.circle.fill"
    case .info: "info.circle.fill"
    case .error: "exclamationmark.circle.fill"
    }
  }

  fileprivate var color: Color { self == .error ? MTColor.warm : MTColor.accent }
}

struct MTToast: Identifiable, Equatable, Sendable {
  let id = UUID()
  let message: String
  let tone: MTToastTone
}

/// Transient action feedback matching the Web `notify` helpers: success and info stay for
/// 4.5 seconds, errors for 8, and at most three are visible. Toasts appear at the top of a
/// pass-through window so they stay above sheets and clear of the keyboard.
@MainActor
@Observable
final class MTToastCenter {
  static let shared = MTToastCenter()

  private(set) var toasts: [MTToast] = []
  @ObservationIgnored fileprivate var frames: [UUID: CGRect] = [:]
  @ObservationIgnored private var window: MTToastWindow?

  func success(_ message: String) { show(message, tone: .success) }
  func info(_ message: String) { show(message, tone: .info) }
  func error(_ message: String) { show(message, tone: .error) }

  func show(_ message: String, tone: MTToastTone) {
    installWindow()
    let toast = MTToast(message: message, tone: tone)
    withAnimation(.snappy(duration: MTMotion.standard)) {
      toasts.append(toast)
      if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
    }
    UIAccessibility.post(notification: .announcement, argument: message)
    let duration: Duration = tone == .error ? .seconds(8) : .milliseconds(4_500)
    Task {
      try? await Task.sleep(for: duration)
      dismiss(toast.id)
    }
  }

  func dismiss(_ id: UUID) {
    frames[id] = nil
    withAnimation(.snappy(duration: MTMotion.standard)) { toasts.removeAll { $0.id == id } }
  }

  fileprivate func contains(_ point: CGPoint) -> Bool {
    frames.values.contains { $0.contains(point) }
  }

  private func installWindow() {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard
      let scene = scenes.first(where: { $0.activationState == .foregroundActive })
        ?? scenes.first
    else { return }
    // Follow the app appearance, including the in-app Light or Dark preference.
    let style = scene.windows.first(where: \.isKeyWindow)?.traitCollection.userInterfaceStyle
    if window?.windowScene !== scene {
      let window = MTToastWindow(windowScene: scene)
      window.windowLevel = UIWindow.Level(UIWindow.Level.normal.rawValue + 1)
      let host = UIHostingController(rootView: MTToastStack(center: self))
      host.view.backgroundColor = .clear
      window.rootViewController = host
      window.isHidden = false
      self.window = window
    }
    window?.overrideUserInterfaceStyle = style ?? .unspecified
  }
}

/// Passes every touch outside a visible toast through to the app.
private final class MTToastWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    MTToastCenter.shared.contains(point) ? super.hitTest(point, with: event) : nil
  }
}

private struct MTToastStack: View {
  let center: MTToastCenter

  var body: some View {
    VStack(spacing: MTSpacing.s2) {
      ForEach(center.toasts) { toast in
        MTToastView(toast: toast) { center.dismiss(toast.id) }
          .background {
            GeometryReader { proxy in
              Color.clear
                .onAppear { center.frames[toast.id] = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, frame in
                  if center.toasts.contains(toast) { center.frames[toast.id] = frame }
                }
            }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .frame(maxWidth: 420)
    .padding(.horizontal, MTSpacing.s4)
    .padding(.top, MTSpacing.s2)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private struct MTToastView: View {
  let toast: MTToast
  let dismiss: () -> Void
  @State private var drag: CGFloat = 0

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
      Image(systemName: toast.tone.systemImage)
        .font(.system(size: 15))
        .foregroundStyle(toast.tone.color)
        .frame(width: 18)
        .accessibilityHidden(true)
      Text(toast.message)
        .font(MTFont.label)
        .foregroundStyle(MTColor.ink)
        .mtLineSpacing(MTLineHeight.body, textStyle: .footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: dismiss) {
        Image(.close).font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MTColor.inkMuted)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.vertical, -MTSpacing.s2)
      .accessibilityLabel("Dismiss notification")
    }
    .padding(.leading, MTSpacing.s4)
    .padding(.trailing, MTSpacing.s2)
    .padding(.vertical, MTSpacing.s3)
    .frame(minHeight: 52)
    .background {
      // The Web toast's 3 point tone border on the leading edge, inside the rounded card.
      ZStack(alignment: .leading) {
        MTColor.surfaceRaised
        toast.tone.color.frame(width: 3)
      }
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
    }
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
        MTColor.borderStrong, lineWidth: 1)
    }
    .mtShadow(MTShadow.floating)
    .offset(y: min(0, drag))
    .gesture(
      DragGesture(minimumDistance: 8)
        .onChanged { drag = $0.translation.height }
        .onEnded { value in
          if value.translation.height < -24 { dismiss() } else { withAnimation { drag = 0 } }
        }
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("toast")
  }
}
