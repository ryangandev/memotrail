import SwiftUI

struct EntryCard: View {
  let entry: InboxEntry
  let review: () -> Void

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

      if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(entry.collectionNames, id: \.self) { name in
              organizationBadge(name)
            }

            ForEach(entry.tagNames.prefix(3), id: \.self) { name in
              organizationBadge("#\(name)")
            }

            if entry.tagNames.count > 3 {
              organizationBadge("+\(entry.tagNames.count - 3)")
            }
          }
        }
      }

      HStack {
        HStack(spacing: 6) {
          Text("Unreviewed")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkMuted)
            .padding(.horizontal, MTSpacing.s2)
            .padding(.vertical, 4)
            .background(MTColor.surfaceSubtle, in: Capsule())

          if entry.entryType == .firstTime {
            Text("First Time")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(MTColor.inkMuted)
              .padding(.horizontal, MTSpacing.s2)
              .padding(.vertical, 4)
              .background(MTColor.surfaceSubtle, in: Capsule())
          }
        }

        Spacer()

        Button("Review", systemImage: "chevron.right") {
          review()
        }
        .labelStyle(.titleAndIcon)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.accent)
        .accessibilityIdentifier("review-entry-\(entry.id.uuidString.lowercased())")
      }
      .padding(.top, MTSpacing.s1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
  }

  private func organizationBadge(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, 4)
      .background(MTColor.surfaceSubtle, in: Capsule())
  }
}

struct PendingEntryCard: View {
  let entry: QueuedInboxEntry

  var body: some View {
    let presentedEntry = entry.presentedEntry

    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack(alignment: .firstTextBaseline) {
        Text(presentedEntry.displayDate)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        Text("On this iPhone")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .padding(.horizontal, MTSpacing.s2)
          .padding(.vertical, 4)
          .background(MTColor.accentSubtle, in: Capsule())
      }

      Text(presentedEntry.displayTitle)
        .font(.system(size: 18, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)

      if let excerpt = presentedEntry.displayExcerpt {
        Text(excerpt)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
          .lineLimit(3)
      }

      if !entry.attachments.isEmpty {
        Label(
          "\(entry.attachments.count) \(entry.attachments.count == 1 ? "photo" : "photos")",
          systemImage: "photo"
        )
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkMuted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
  }
}
