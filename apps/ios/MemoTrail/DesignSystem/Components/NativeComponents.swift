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

struct MTSearchField: View {
  let prompt: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      Image(systemName: "magnifyingglass").foregroundStyle(MTColor.inkMuted)
      TextField(prompt, text: $text)
        .font(MTFont.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .accessibilityLabel(prompt)
      if !text.isEmpty {
        Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
          .labelStyle(.iconOnly)
          .frame(minWidth: 44, minHeight: 44)
          .foregroundStyle(MTColor.inkMuted)
      }
    }
    .padding(.leading, MTSpacing.s3)
    .padding(.trailing, text.isEmpty ? MTSpacing.s3 : 0)
    .frame(minHeight: 48)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.medium).stroke(MTColor.border) }
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
