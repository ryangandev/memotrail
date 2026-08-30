import SwiftUI

struct EntryCard: View {
  let entry: PreviewEntry

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack {
        Text(entry.date)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        Button("More", systemImage: "ellipsis") {}
          .labelStyle(.iconOnly)
          .foregroundStyle(MTColor.inkFaint)
      }

      Text(entry.title)
        .font(.system(size: 18, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)

      Text(entry.excerpt)
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)

      HStack(alignment: .bottom) {
        FlowLayout(spacing: 6) {
          ForEach(entry.tags, id: \.self) { tag in
            Text(tag)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(MTColor.inkMuted)
              .padding(.horizontal, MTSpacing.s2)
              .padding(.vertical, 4)
              .background(MTColor.surfaceSubtle, in: Capsule())
          }
        }

        Spacer(minLength: MTSpacing.s2)

        if entry.isAISuggested {
          Label("AI suggested", systemImage: "sparkles")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.accent)
        }
      }
      .padding(.top, MTSpacing.s1)
    }
    .padding(MTSpacing.s4)
  }
}

private struct FlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    layout(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    let result = layout(proposal: proposal, subviews: subviews)

    for (index, point) in result.points.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
        proposal: .unspecified
      )
    }
  }

  private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
    let maxWidth = proposal.width ?? .infinity
    var points: [CGPoint] = []
    var cursor = CGPoint.zero
    var lineHeight: CGFloat = 0
    var measuredWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)

      if cursor.x + size.width > maxWidth, cursor.x > 0 {
        cursor.x = 0
        cursor.y += lineHeight + spacing
        lineHeight = 0
      }

      points.append(cursor)
      cursor.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
      measuredWidth = max(measuredWidth, cursor.x - spacing)
    }

    return LayoutResult(
      points: points,
      size: CGSize(width: measuredWidth, height: cursor.y + lineHeight)
    )
  }
}

private struct LayoutResult {
  let points: [CGPoint]
  let size: CGSize
}
