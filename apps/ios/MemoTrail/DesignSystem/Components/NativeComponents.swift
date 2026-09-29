import SwiftUI

struct MTCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MTSpacing.s4)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border, lineWidth: 1)
      }
  }
}

struct MTRecordSummary: View {
  let title: String
  let subtitle: String
  let kind: String
  var status: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      ViewThatFits(in: .horizontal) {
        badges
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          MTBadge(title: kind, tone: .accent)
          if let status { MTBadge(title: status, tone: .warm) }
        }
      }
      Text(title).font(MTFont.heading).foregroundStyle(MTColor.ink)
      Text(subtitle).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var badges: some View {
    HStack(spacing: MTSpacing.s2) {
      MTBadge(title: kind, tone: .accent)
      if let status { MTBadge(title: status, tone: .warm) }
    }
  }
}

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
