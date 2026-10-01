import SwiftUI

/// Renders Entry writing like the Web EntryRichTextContent: validated `body_rich` writing with
/// its structure and emphasis, or the plain body when no valid rich document is present.
/// With a `lineLimit`, the writing flows into one clamped preview that keeps its emphasis,
/// list markers, and line breaks, like the Web search result excerpt.
struct MTRichTextContent: View {
  /// The plain Entry body, which a valid rich document must match exactly.
  let text: String
  var richText: EntryRichText?
  var font: Font = MTFont.bodyLarge
  var textStyle: UIFont.TextStyle = .body
  var color: Color = MTColor.ink
  var lineLimit: Int?
  @ScaledMetric(relativeTo: .body) private var blockSpacing = 11

  var body: some View {
    Group {
      let document = richText.flatMap { $0.isValid(expectedText: text) ? $0.document : nil }
      if let lineLimit {
        paragraph(
          Text(document.map { flowing($0.content ?? []) } ?? AttributedString(text)), color: color
        )
        .lineLimit(lineLimit)
      } else if let document {
        blocks(document.content ?? [], color: color)
      } else {
        paragraph(Text(text), color: color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The blocks as one run of text, one block per line.
  private func flowing(_ nodes: [EntryRichText.Node]) -> AttributedString {
    var lines: [AttributedString] = []
    for node in nodes {
      switch node.type {
      case "paragraph": lines.append(inline(node.content ?? []))
      case "blockquote": lines.append(flowing(node.content ?? []))
      case "bulletList", "orderedList":
        let start = node.attrs?["start"]?.integer ?? 1
        for (index, item) in (node.content ?? []).enumerated() {
          let marker = node.type == "orderedList" ? "\(start + index). " : "• "
          lines.append(AttributedString(marker) + flowing(item.content ?? []))
        }
      case "codeBlock":
        var code = AttributedString((node.content ?? []).map { $0.text ?? "" }.joined())
        code.font = font.monospaced()
        lines.append(code)
      default: break
      }
    }
    return lines.enumerated().reduce(into: AttributedString()) { result, line in
      if line.offset > 0 { result += AttributedString("\n") }
      result += line.element
    }
  }

  private func blocks(_ nodes: [EntryRichText.Node], color: Color) -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: blockSpacing) {
        ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in block(node, color: color) }
      })
  }

  @ViewBuilder private func block(_ node: EntryRichText.Node, color: Color) -> some View {
    switch node.type {
    case "paragraph":
      paragraph(Text(inline(node.content ?? [])), color: color)
    case "blockquote":
      HStack(alignment: .top, spacing: MTSpacing.s3) {
        Rectangle().fill(MTColor.accent).frame(width: 2)
        blocks(node.content ?? [], color: MTColor.inkMuted)
      }
      .fixedSize(horizontal: false, vertical: true)
    case "bulletList", "orderedList":
      let start = node.attrs?["start"]?.integer ?? 1
      VStack(alignment: .leading, spacing: blockSpacing / 2) {
        ForEach(Array((node.content ?? []).enumerated()), id: \.offset) { index, item in
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
            Text(node.type == "orderedList" ? "\(start + index)." : "•")
              .font(font)
              .monospacedDigit()
              .foregroundStyle(MTColor.inkMuted)
              .frame(minWidth: 18, alignment: .trailing)
              .accessibilityHidden(true)
            blocks(item.content ?? [], color: color)
          }
        }
      }
    case "codeBlock":
      ScrollView(.horizontal) {
        Text((node.content ?? []).map { $0.text ?? "" }.joined())
          .font(font.monospaced())
          .foregroundStyle(MTColor.ink)
          .fixedSize()
          .padding(.vertical, MTSpacing.s3)
          .padding(.horizontal, MTSpacing.s4)
      }
      .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.small))
    default:
      EmptyView()
    }
  }

  private func paragraph(_ text: Text, color: Color) -> some View {
    text
      .font(font)
      .foregroundStyle(color)
      .mtLineSpacing(MTLineHeight.body, textStyle: textStyle)
      .tint(MTColor.accent)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func inline(_ nodes: [EntryRichText.Node]) -> AttributedString {
    nodes.reduce(into: AttributedString()) { result, node in
      guard node.type == "text", let text = node.text else {
        if node.type == "hardBreak" { result += AttributedString("\n") }
        return
      }
      var run = AttributedString(text)
      var runFont = font
      for mark in node.marks ?? [] {
        switch mark.type {
        case "bold": runFont = runFont.bold()
        case "italic": runFont = runFont.italic()
        case "underline": run.underlineStyle = .single
        case "strike": run.strikethroughStyle = .single
        case "code":
          runFont = runFont.monospaced()
          run.backgroundColor = MTColor.surfaceSubtle
        case "link":
          if let href = mark.attrs?["href"]?.string, EntryRichText.safeLink(href),
            let url = URL(string: href)
          {
            run.link = url
            run.underlineStyle = .single
            run.foregroundColor = MTColor.accent
          }
        default: break
        }
      }
      run.font = runFont
      result += run
    }
  }
}
