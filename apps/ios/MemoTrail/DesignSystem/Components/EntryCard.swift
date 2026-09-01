import SwiftUI

struct EntryCard: View {
  let entry: InboxEntry

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text(entry.displayDate)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkFaint)

      Text(entry.displayTitle)
        .font(.system(size: 18, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)

      if let excerpt = entry.displayExcerpt {
        Text(excerpt)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
      }

      Text("Unreviewed")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(MTColor.inkMuted)
        .padding(.horizontal, MTSpacing.s2)
        .padding(.vertical, 4)
        .background(MTColor.surfaceSubtle, in: Capsule())
        .padding(.top, MTSpacing.s1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
  }
}
