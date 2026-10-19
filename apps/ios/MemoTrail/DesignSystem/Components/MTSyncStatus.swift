import SwiftUI

/// Web `SyncStatusButton` in the workspace header: the counts of captures waiting on this
/// iPhone, refused by MemoTrail, or unreadable. The label turns warm when a capture needs the
/// person, and the dot pulses while a sync runs.
/// Specified in packages/design-system/components/sync-status.yaml.
struct MTSyncStatusButton: View {
  /// The counts, such as "2 pending · 1 not accepted".
  let label: String
  /// MemoTrail refused a capture or could not read one, so only the person can resolve it.
  var needsAttention = false
  var isSyncing = false
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: MTSpacing.s1_5) {
        dot
        Text(label)
          .font(MTFont.micro)
          .lineLimit(1)
      }
      .foregroundStyle(needsAttention ? MTColor.warm : MTColor.inkFaint)
      .padding(.horizontal, MTSpacing.s2)
      .frame(minHeight: MTSize.hitTarget)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Pending sync, \(label)")
    .accessibilityValue(isSyncing ? "Syncing" : "")
    .accessibilityHint(
      needsAttention
        ? "Review captures MemoTrail did not accept or could not read, and sync the rest"
        : "Syncs now and lists captures waiting on this iPhone")
  }

  private var dot: some View {
    Circle()
      .fill(MTColor.warm)
      .frame(width: MTSpacing.s1_5, height: MTSpacing.s1_5)
      // One pulse fades to the low point and back, like Web's keyframes.
      .phaseAnimator(isSyncing && !reduceMotion ? [1, MTState.Muted.Opacity.pulseLow] : [1]) {
        content, opacity in
        content.opacity(opacity)
      } animation: { _ in
        MTEasing.inOut.animation(duration: MTMotion.pulse / 2)
      }
  }
}
