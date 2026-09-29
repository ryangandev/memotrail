import SwiftUI

struct MTMediaPlaceholder: View {
  enum State { case empty, loading, failed }
  let state: State
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MTRadius.medium).fill(MTColor.surfaceSubtle)
      switch state {
      case .empty: Label("No photo", systemImage: "photo")
      case .loading: ProgressView("Loading photo...")
      case .failed: Label("Photo unavailable", systemImage: "photo.badge.exclamationmark")
      }
    }
    .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
    .accessibilityElement(children: .combine)
  }
}
