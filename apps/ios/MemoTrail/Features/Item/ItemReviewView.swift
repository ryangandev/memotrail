import SwiftUI

/// A Chapter's saved review, read-only, like Web `ReviewPanel` once a review exists. Three kinds
/// of text stay apart: facts from the person's records (plain), Claude's interpretation (a
/// tinted surface with a warm edge and an "Interpretation" badge), and the person's own words
/// (set as quotes). Every cited Entry and every quote opens its Item page. Making, deleting, and
/// turning on reviews are Web-only.
struct ItemReviewView: View {
  let review: StoredReview
  let facts: ReviewFacts?
  /// The Chapter's dates, such as "Mar 2026 - May 2026", for the records block.
  let spanLabel: String?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let display = ReviewDisplay(review)
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      header
      VStack(alignment: .leading, spacing: MTSpacing.s5) {
        ForEach(review.notices, id: \.self) { notice in
          Text(notice)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MTSpacing.s4)
            .padding(.vertical, MTSpacing.s3)
            .background(
              MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium)
            )
            .overlay {
              RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
                MTColor.border, lineWidth: MTSize.Stroke.thin)
            }
        }
        if let facts {
          records(facts)
        }
        interpretation(display)
        if !display.themes.isEmpty {
          themes(display.themes)
        }
        if !display.quotes.isEmpty || display.hiddenQuoteCount > 0 {
          words(display)
        }
        Text(ReviewCopy.footer)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkFaint)
          .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("item-review")
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s1) {
      MTSectionHeader(review.title) {
        MTBadge(title: "Written by AI", tone: .outline)
      }
      Text(
        [review.madeLabel(), review.readLabel].compactMap(\.self).joined(separator: " · ")
      )
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
    }
  }

  // MARK: From your Entries

  private func records(_ facts: ReviewFacts) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader("From your Entries", variant: .list)
      Text(facts.stats(spanLabel: spanLabel).joined(separator: " · "))
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
      if !facts.topTags.isEmpty {
        MTFlowLayout(spacing: MTSpacing.s2) {
          ForEach(facts.topTags, id: \.name) { tag in
            MTBadge(title: "\(tag.name) \(tag.count)", tone: .neutral)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Most used tags")
      }
      if !facts.firstTimes.isEmpty {
        VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
          Text("First Times")
            .font(MTFont.caption)
            .foregroundStyle(MTColor.inkFaint)
          ForEach(facts.firstTimes) { entry in
            ReviewEntryLink(entry: entry)
          }
        }
      }
      if let line = facts.busiestMonthLine {
        Text(line)
          .font(MTFont.body)
          .foregroundStyle(MTColor.ink)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, MTSpacing.s4)
    .overlay(alignment: .top) { MTListDivider() }
  }

  // MARK: Interpretation

  private func interpretation(_ display: ReviewDisplay) -> some View {
    ReviewInterpretation(title: "How it felt") {
      if !display.overview.isEmpty {
        ReviewParagraph(text: display.overview)
      }
      ForEach(display.phases) { phase in
        VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
          if !phase.range.isEmpty {
            Text(phase.range)
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
          }
          Text(phase.feeling)
            .font(MTFont.heading)
            .foregroundStyle(MTColor.ink)
            .fixedSize(horizontal: false, vertical: true)
          ReviewParagraph(text: phase.description)
          ReviewCitations(entries: phase.cited)
        }
      }
    }
  }

  private func themes(_ themes: [ReviewDisplay.Theme]) -> some View {
    ReviewInterpretation(title: "What kept coming back") {
      ForEach(themes) { theme in
        VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
          Text(theme.name)
            .font(MTFont.heading)
            .foregroundStyle(MTColor.ink)
            .fixedSize(horizontal: false, vertical: true)
          ReviewParagraph(text: theme.description)
          ReviewCitations(entries: theme.cited)
        }
      }
    }
  }

  // MARK: In your words

  private func words(_ display: ReviewDisplay) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("In your words")
        .font(MTFont.cardTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      ForEach(display.quotes) { quote in
        HStack(alignment: .top, spacing: MTSpacing.s4) {
          Rectangle()
            .fill(MTColor.accentStripe)
            .frame(width: MTSize.Stroke.thick)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            Text(quote.text)
              .font(MTFont.itemTitle)
              .foregroundStyle(MTColor.ink)
              .mtLineSpacing(MTLineHeight.relaxed)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
            ReviewEntryLink(entry: quote.source)
            Text("Why it stands out: \(quote.why)")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
              .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("item-review-quote-\(quote.id)")
      }
      if let note = display.hiddenQuotesNote {
        Text(note)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// A block of Claude's interpretation: a tinted surface with a warm edge, titled and labeled so
/// it is never mistaken for the person's own words.
private struct ReviewInterpretation<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.large)
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      HStack(alignment: .center, spacing: MTSpacing.s2) {
        Text(title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        MTBadge(title: "Interpretation", tone: .warm)
      }
      VStack(alignment: .leading, spacing: MTSpacing.s5) { content }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s5)
    .background(MTColor.warmWash, in: shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
    .overlay(alignment: .leading) {
      // Web's thick warm start edge, clipped to the surface's corners.
      Rectangle().fill(MTColor.warm).frame(width: MTSize.Stroke.thick)
        .accessibilityHidden(true)
    }
    .clipShape(shape)
    .accessibilityElement(children: .contain)
  }
}

private struct ReviewParagraph: View {
  let text: String

  var body: some View {
    Text(text)
      .font(MTFont.body)
      .foregroundStyle(MTColor.ink)
      .mtLineSpacing(MTLineHeight.relaxed)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A cited Entry: its date, then its title when it has one. It opens the Entry's Item page.
private struct ReviewEntryLink: View {
  let entry: ReviewEntryRef

  var body: some View {
    NavigationLink(value: ItemLink(entryID: entry.id)) {
      MTFlowLayout(spacing: MTSpacing.s2) {
        Text(entry.dateLabel)
          .foregroundStyle(MTColor.inkFaint)
        if !entry.title.isEmpty {
          Text(entry.displayTitle)
            .foregroundStyle(MTColor.accent)
        }
      }
      .font(MTFont.detail)
      .frame(maxWidth: .infinity, minHeight: MTSize.hitTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [entry.dateLabel, entry.title.isEmpty ? nil : entry.displayTitle].compactMap(\.self)
        .joined(separator: ", ")
    )
    .accessibilityHint("Opens this Entry")
    .accessibilityAddTraits(.isLink)
    .accessibilityIdentifier("item-review-entry-\(entry.id.uuidString.lowercased())")
  }
}

/// Web's "From N Entries" disclosure, listing the Entries a statement rests on.
private struct ReviewCitations: View {
  let entries: [ReviewEntryRef]
  @State private var isOpen = false

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s1) {
      Button {
        withAnimation(MTEasing.enter.animation(duration: MTMotion.quick)) { isOpen.toggle() }
      } label: {
        HStack(spacing: MTSpacing.s1_5) {
          Image(systemName: "arrowtriangle.right.fill")
            .font(.mtIcon(MTSize.Icon.s7))
            .rotationEffect(.degrees(isOpen ? 90 : 0))
          Text("From \(countLabel(entries.count, "Entry"))")
        }
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .frame(minHeight: MTLayout.InlineAction.height)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
      if isOpen {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(entries) { entry in
            ReviewEntryLink(entry: entry)
          }
        }
      }
    }
  }
}
