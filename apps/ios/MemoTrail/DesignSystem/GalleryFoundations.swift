#if DEBUG
  import SwiftUI

  struct FoundationSpecimens: View {
    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "Colors",
          description:
            "\(MTColor.catalog.count) semantic colors with matched light and dark names, generated from tokens.json."
        ) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MTSpacing.s3) { themePreviews }
            VStack(alignment: .leading, spacing: MTSpacing.s3) { themePreviews }
          }
        }
        GallerySpecimen(
          title: "Typography",
          description:
            "Text roles use the Web token names and the iOS text style of the same default size, so they follow Dynamic Type."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(TypeRole.all, id: \.name) { role in
              VStack(alignment: .leading, spacing: MTSpacing.s1) {
                Text("A life in progress").font(role.font).foregroundStyle(MTColor.ink)
                Text("\(role.name) · \(role.detail)").font(MTFont.caption.monospaced())
                  .foregroundStyle(MTColor.inkMuted)
              }
            }
          }
        }
        GallerySpecimen(title: "Spacing") {
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            ForEach(MTSpacing.catalog, id: \.name) { token in
              HStack(spacing: MTSpacing.s3) {
                Text("space.\(token.name)").font(MTFont.caption.monospaced())
                  .frame(width: 72, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(MTColor.accent)
                  .frame(width: token.value, height: 8)
                Text("\(Int(token.value)) pt").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted)
              }
            }
          }
          .foregroundStyle(MTColor.ink)
        }
        GallerySpecimen(title: "Radius") {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: MTSpacing.s3)]) {
            ForEach(MTRadius.catalog, id: \.name) { token in
              VStack(spacing: MTSpacing.s1) {
                RoundedRectangle(cornerRadius: token.value).fill(MTColor.accentSubtle)
                  .overlay { RoundedRectangle(cornerRadius: token.value).stroke(MTColor.accent) }
                  .frame(width: 64, height: 48)
                Text(token.name).font(MTFont.caption.monospaced()).foregroundStyle(MTColor.ink)
                Text("\(Int(token.value)) pt").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted)
              }
            }
          }
        }
        GallerySpecimen(
          title: "Shadow",
          description:
            "Generated from the CSS token layers; a CSS blur becomes a native radius of half its size."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s6) {
            ForEach(MTShadow.catalog, id: \.name) { token in
              VStack(alignment: .leading, spacing: MTSpacing.s3) {
                RoundedRectangle(cornerRadius: MTRadius.medium).fill(MTColor.surfaceRaised)
                  .frame(height: 64)
                  .mtShadow(token.layers)
                Text(token.name).font(MTFont.caption.monospaced()).foregroundStyle(MTColor.ink)
                Text(token.css).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              }
            }
          }
          .padding(.vertical, MTSpacing.s2)
        }
        GallerySpecimen(
          title: "Motion",
          description: "Durations are shared with Web. Reduce Motion replaces movement with a fade."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            ForEach(MTMotion.catalog, id: \.name) { token in
              MotionRow(name: token.name, seconds: token.seconds)
            }
          }
        }
        GallerySpecimen(title: "Line height", api: "tight · body · relaxed") {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(
              [
                ("tight", MTLineHeight.tight), ("body", MTLineHeight.body),
                ("relaxed", MTLineHeight.relaxed),
              ], id: \.0
            ) { name, multiplier in
              VStack(alignment: .leading, spacing: MTSpacing.s1) {
                Text(
                  "Small details give a memory its shape: the place, the people, and what we noticed."
                )
                .font(MTFont.body).foregroundStyle(MTColor.ink)
                .mtLineSpacing(multiplier)
                Text("\(name) · \(String(format: "%.2f", multiplier))").font(
                  MTFont.caption.monospaced()
                ).foregroundStyle(MTColor.inkMuted)
              }
            }
          }
        }
      }
    }

    @ViewBuilder private var themePreviews: some View {
      ThemeColorPreview(scheme: .light)
      ThemeColorPreview(scheme: .dark)
    }
  }

  private struct TypeRole {
    let name: String
    let detail: String
    let font: Font

    static let all = [
      TypeRole(name: "display", detail: "serif · Large Title · Web 42", font: MTFont.display),
      TypeRole(name: "title", detail: "serif · Title · Web 28", font: MTFont.title),
      TypeRole(name: "titleSmall", detail: "sans · Title 3 · Web 20", font: MTFont.titleSmall),
      TypeRole(
        name: "cardTitle", detail: "serif · Title 3 · record titles", font: MTFont.cardTitle),
      TypeRole(name: "bodyLarge", detail: "sans · Body · Web 17", font: MTFont.bodyLarge),
      TypeRole(name: "heading", detail: "sans · Headline · list titles", font: MTFont.heading),
      TypeRole(name: "body", detail: "sans · Subheadline · Web 15", font: MTFont.body),
      TypeRole(name: "label", detail: "sans · Footnote · Web 13", font: MTFont.label),
      TypeRole(name: "caption", detail: "sans · Caption · Web 12", font: MTFont.caption),
      TypeRole(name: "micro", detail: "sans · Caption 2 · eyebrows", font: MTFont.micro),
    ]
  }

  private struct ThemeColorPreview: View {
    let scheme: ColorScheme

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        Text(scheme == .dark ? "Dark" : "Light").font(MTFont.heading).foregroundStyle(MTColor.ink)
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 128), spacing: MTSpacing.s2)], alignment: .leading,
          spacing: MTSpacing.s3
        ) {
          ForEach(MTColor.catalog, id: \.name) { token in
            HStack(spacing: MTSpacing.s2) {
              RoundedRectangle(cornerRadius: MTRadius.small).fill(token.color)
                .overlay { RoundedRectangle(cornerRadius: MTRadius.small).stroke(MTColor.border) }
                .frame(width: 32, height: 32)
              VStack(alignment: .leading, spacing: 0) {
                Text(token.name).font(MTFont.caption).foregroundStyle(MTColor.ink)
                Text(scheme == .dark ? token.darkHex : token.lightHex)
                  .font(MTFont.caption.monospaced()).foregroundStyle(MTColor.inkMuted)
              }
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            }
          }
        }
      }
      .padding(MTSpacing.s3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.canvas, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .environment(\.colorScheme, scheme)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(scheme == .dark ? "Dark colors" : "Light colors")
    }
  }

  private struct MotionRow: View {
    let name: String
    let seconds: Double
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      HStack(spacing: MTSpacing.s3) {
        Text(name).font(MTFont.caption.monospaced()).foregroundStyle(MTColor.ink)
          .frame(width: 80, alignment: .leading)
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(MTColor.surfaceSubtle).frame(height: 6)
            Circle().fill(MTColor.accent).frame(width: 14, height: 14)
              .offset(x: reduceMotion ? 0 : (moved ? proxy.size.width - 14 : 0))
              .opacity(reduceMotion && moved ? 0.4 : 1)
          }
          .frame(maxHeight: .infinity)
        }
        .frame(height: 20)
        Text("\(Int(seconds * 1_000)) ms").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        Button("Play \(name) motion", systemImage: "play.fill") {
          withAnimation(.easeInOut(duration: seconds)) { moved.toggle() }
        }
        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
      }
    }
  }

  struct IdentitySpecimens: View {
    @State private var markRotated = false
    @State private var revealID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "MemoTrailMark", api: "animated · reveal · follows Reduce Motion",
          description: "The shared mark used by the splash screen, sign-in, and navigation."
        ) {
          HStack(spacing: MTSpacing.s6) {
            MemoTrailMark(animated: true).id(revealID).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: MTSpacing.s2) {
              Button("Replay reveal", systemImage: "arrow.clockwise") { revealID += 1 }
                .mtButtonStyle(.secondary)
              Text("MemoTrail").font(MTFont.title).foregroundStyle(MTColor.ink)
            }
          }
        }
        GallerySpecimen(
          title: "Brand motion",
          description:
            "The outer ring and accent turn a quarter while the inner ring counter-rotates, matching the Web sidebar brand."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MemoTrailMark(turn: markRotated ? 90 : 0).frame(width: 64, height: 64)
            Button("Preview motion") {
              guard !reduceMotion else { return }
              // 320 ms matches the Web sidebar collapse.
              withAnimation(.easeInOut(duration: 0.32)) { markRotated.toggle() }
            }.mtButtonStyle(.secondary)
            Text(
              reduceMotion
                ? "Reduce Motion is on. The mark stays still."
                : "Motion follows the system Reduce Motion preference."
            )
            .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }
        GallerySpecimen(
          title: "Icons",
          api: "MTIcon · Image(_:) · Label(_:icon:)",
          description:
            "The Web icon vocabulary mapped to SF Symbols so both clients name concepts the same way."
        ) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: MTSpacing.s2)]) {
            ForEach(MTIcon.allCases, id: \.self) { icon in
              VStack(spacing: MTSpacing.s2) {
                Image(icon).font(.system(size: 20)).foregroundStyle(MTColor.ink)
                  .frame(height: 24)
                Text(String(describing: icon)).font(MTFont.caption.monospaced())
                  .foregroundStyle(MTColor.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
              }
              .frame(maxWidth: .infinity, minHeight: 64)
              .accessibilityElement(children: .combine)
            }
          }
        }
      }
    }
  }

  struct LayoutSpecimens: View {
    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "MTPage",
          api: "width: compact | standard | wide | canvas · spacing",
          description:
            "The canonical outer geometry. Phones use the full width with 16 pt gutters; wider screens center the page at its variant width. This gallery uses canvas."
        ) {
          VStack(spacing: 0) {
            ForEach(MTPageWidth.allCases, id: \.self) { width in
              HStack(alignment: .firstTextBaseline) {
                Text(width.title.lowercased()).font(MTFont.label).foregroundStyle(MTColor.ink)
                Spacer()
                Text("\(Int(width.rawValue)) pt · \(width.purpose)").font(MTFont.caption)
                  .foregroundStyle(MTColor.inkMuted).multilineTextAlignment(.trailing)
              }
              .padding(.vertical, MTSpacing.s3)
              if width != MTPageWidth.allCases.last {
                Rectangle().fill(MTColor.border).frame(height: 1)
              }
            }
          }
        }
        GallerySpecimen(
          title: "Rhythm",
          description:
            "Pages stack sections 32 pt apart; related content inside a section uses 12 to 16 pt."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            ForEach(
              [
                ("Page gutter", MTSpacing.s4), ("Section gap", MTSpacing.s8),
                ("Group gap", MTSpacing.s3),
              ],
              id: \.0
            ) { name, value in
              HStack {
                Text(name).font(MTFont.label).foregroundStyle(MTColor.ink)
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(MTColor.warm).frame(width: value, height: 8)
                Text("\(Int(value)) pt").font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
                  .frame(width: 44, alignment: .trailing)
              }
            }
          }
        }
      }
    }
  }
#endif
