import SwiftUI
import UIKit

// MTToastTone and MTToastDefaults are generated from
// packages/design-system/components/toast.yaml, which also lists each tone's tokens.
extension MTToastTone {
  fileprivate var systemImage: String {
    switch self {
    case .success: "checkmark.circle.fill"
    case .info: "info.circle.fill"
    case .error: "exclamationmark.circle.fill"
    }
  }

  fileprivate var color: Color { self == .error ? MTColor.danger : MTColor.accent }

  /// How long a toast in this tone stays: errors stay longer, so there is time to read them.
  var duration: Duration {
    .seconds(self == .error ? MTMotion.toastError : MTMotion.toast)
  }
}

struct MTToast: Identifiable, Equatable, Sendable {
  let id = UUID()
  let message: String
  let tone: MTToastTone
}

/// Transient action feedback matching the Web `notify` helpers: success and info stay for
/// `MTMotion.toast`, errors for `MTMotion.toastError`, and at most three are visible. Like Web, toasts rise from the
/// bottom, in a pass-through window above sheets. They sit clear of the tab bar, a sheet's
/// actions, and the keyboard, and leave the top free for back and close buttons.
@MainActor
@Observable
final class MTToastCenter {
  static let shared = MTToastCenter()

  /// Space kept below toasts above the home indicator or keyboard, which clears the tab bar
  /// and a sheet's action footer.
  static let bottomClearance = MTLayout.Toast.bottomClearance

  /// The distance from the window's bottom edge to the lowest toast: above the home indicator
  /// or the keyboard, whichever reaches higher, plus `bottomClearance`.
  static func bottomInset(windowMaxY: CGFloat, safeAreaBottom: CGFloat, keyboardTop: CGFloat?)
    -> CGFloat
  {
    let keyboardOverlap = keyboardTop.map { max(0, windowMaxY - $0) } ?? 0
    return max(safeAreaBottom, keyboardOverlap) + bottomClearance
  }

  private(set) var toasts: [MTToast] = []
  /// The keyboard's top edge in screen coordinates while it is shown.
  fileprivate private(set) var keyboardTop: CGFloat?
  @ObservationIgnored fileprivate var frames: [UUID: CGRect] = [:]
  @ObservationIgnored private var window: MTToastWindow?
  @ObservationIgnored private var keyboardObservers: [NSObjectProtocol] = []

  /// Follows the keyboard from launch, so a first toast shown over it still sits above it.
  func trackKeyboard() {
    guard keyboardObservers.isEmpty else { return }
    let notifications = NotificationCenter.default
    keyboardObservers = [
      notifications.addObserver(
        forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
      ) { [weak self] notification in
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let top = frame?.minY
        MainActor.assumeIsolated { self?.keyboardTop = top }
      },
      notifications.addObserver(
        forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.keyboardTop = nil }
      },
    ]
  }

  func success(_ message: String) { show(message, tone: .success) }
  func info(_ message: String) { show(message, tone: .info) }
  func error(_ message: String) { show(message, tone: .error) }

  func show(_ message: String, tone: MTToastTone) {
    trackKeyboard()
    installWindow()
    let toast = MTToast(message: message, tone: tone)
    withAnimation(.snappy(duration: MTMotion.standard)) {
      toasts.append(toast)
      if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
    }
    UIAccessibility.post(notification: .announcement, argument: message)
    Task {
      try? await Task.sleep(for: tone.duration)
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
    GeometryReader { proxy in
      let inset = MTToastCenter.bottomInset(
        windowMaxY: proxy.frame(in: .global).maxY, safeAreaBottom: proxy.safeAreaInsets.bottom,
        keyboardTop: center.keyboardTop)
      stack
        .padding(.bottom, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    // The center measures the keyboard, so this window ignores its own keyboard inset.
    .ignoresSafeArea(.keyboard)
    .animation(.snappy(duration: MTMotion.standard), value: center.keyboardTop)
  }

  private var stack: some View {
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
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .frame(maxWidth: MTSize.Toast.width)
    .padding(.horizontal, MTSpacing.s4)
  }
}

/// One toast. The toast center stacks them; the design-system gallery draws them in place.
/// Specified in packages/design-system/components/toast.yaml.
struct MTToastView: View {
  let toast: MTToast
  let dismiss: () -> Void
  @State private var drag: CGFloat = 0

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
      Image(systemName: toast.tone.systemImage)
        .font(.mtIcon(MTSize.Icon.s15))
        .foregroundStyle(toast.tone.color)
        .frame(width: MTSize.Toast.icon)
        .accessibilityHidden(true)
      Text(toast.message)
        .font(MTFont.label)
        .foregroundStyle(MTColor.ink)
        .mtLineSpacing(MTLineHeight.body, textStyle: .footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: dismiss) {
        Image(.close).font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
          .foregroundStyle(MTColor.inkMuted)
          .frame(width: MTLayout.InlineAction.height, height: MTLayout.InlineAction.height)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.vertical, -MTSpacing.s2)
      .accessibilityLabel("Dismiss notification")
    }
    .padding(.leading, MTSpacing.s4)
    .padding(.trailing, MTSpacing.s2)
    .padding(.vertical, MTSpacing.s3)
    .frame(minHeight: MTSize.Toast.minHeight)
    .background {
      // The Web toast's 3 point tone border on the leading edge, inside the rounded card.
      ZStack(alignment: .leading) {
        MTColor.surfaceRaised
        toast.tone.color.frame(width: MTSize.Stroke.thick)
      }
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
    }
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
        MTColor.borderStrong, lineWidth: MTSize.Stroke.thin)
    }
    .mtShadow(MTShadow.floating)
    .offset(y: max(0, drag))
    .gesture(
      DragGesture(minimumDistance: 8)
        .onChanged { drag = $0.translation.height }
        .onEnded { value in
          if value.translation.height > 24 { dismiss() } else { withAnimation { drag = 0 } }
        }
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("toast")
  }
}
