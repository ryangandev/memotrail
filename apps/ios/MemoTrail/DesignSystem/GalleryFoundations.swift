#if DEBUG
  import SwiftUI

  struct FoundationSpecimens: View {
    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "Colors",
          description:
            "\(MTColor.catalog.count) semantic colors with matched light and dark names, generated from shared tokens."
        ) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MTSpacing.s3) { themePreviews }
            VStack(alignment: .leading, spacing: MTSpacing.s3) { themePreviews }
          }
        }
        GallerySpecimen(
          title: "Typography",
          api: "MTFont · mtTextRole(_:)",
          description:
            "\(MTTextRole.catalog.count) text roles shared with Web. Roles with a text style follow Dynamic Type; the rest keep a fixed size."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(MTTextRole.catalog, id: \.name) { role in
              VStack(alignment: .leading, spacing: MTSpacing.s1) {
                Text("A life in progress").mtTextRole(role).foregroundStyle(MTColor.ink)
                Text("\(role.name) · \(role.detail)").font(MTFont.identifier)
                  .foregroundStyle(MTColor.inkMuted)
              }
            }
          }
        }
        GallerySpecimen(title: "Spacing") {
          // A grid sizes the name column to the longest name, so names like space.0-25 never wrap.
          Grid(
            alignment: .leading, horizontalSpacing: MTSpacing.s3, verticalSpacing: MTSpacing.s2
          ) {
            ForEach(MTSpacing.catalog, id: \.name) { token in
              GridRow {
                Text("space.\(token.name)").font(MTFont.identifier).lineLimit(1)
                HStack(spacing: MTSpacing.s3) {
                  RoundedRectangle(cornerRadius: 2).fill(MTColor.accent)
                    .frame(width: token.value, height: 8)
                  Text("\(Int(token.value)) pt").font(MTFont.caption).foregroundStyle(
                    MTColor.inkMuted
                  )
                  .fixedSize()
                }
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
                Text(token.name).font(MTFont.identifier).foregroundStyle(MTColor.ink)
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
                Text(token.name).font(MTFont.identifier).foregroundStyle(MTColor.ink)
                Text(token.css).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              }
            }
          }
          .padding(.vertical, MTSpacing.s2)
        }
        GallerySpecimen(
          title: "Motion",
          api: "MTMotion · MTEasing.<curve>.animation(duration:)",
          description:
            "Durations and easing curves are shared with Web. Reduce Motion replaces movement with a fade."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            ForEach(MTMotion.catalog, id: \.name) { token in
              MotionRow(name: token.name, seconds: token.seconds, curve: MTEasing.inOut)
            }
            Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin)
            ForEach(MTEasing.catalog, id: \.name) { curve in
              MotionRow(name: curve.name, seconds: MTMotion.deliberate * 4, curve: curve)
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
                  MTFont.identifier
                ).foregroundStyle(MTColor.inkMuted)
              }
            }
          }
        }
        SizeSpecimen()
        StateSpecimen()
        ElevationSpecimen()
        MaterialSpecimen()
      }
    }

    @ViewBuilder private var themePreviews: some View {
      ThemeColorPreview(scheme: .light)
      ThemeColorPreview(scheme: .dark)
    }
  }

  extension MTTextRole {
    fileprivate var detail: String {
      let design =
        switch design {
        case .serif: "serif"
        case .monospaced: "mono"
        default: "sans"
        }
      let scaling = textStyle.map { String(describing: $0) } ?? "fixed"
      return "\(design) · \(Int(size)) pt · \(scaling)"
    }
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
                Text(value(of: token))
                  .font(MTFont.identifier).foregroundStyle(MTColor.inkMuted)
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

    private func value(of token: MTColorToken) -> String {
      let hex = scheme == .dark ? token.darkHex : token.lightHex
      let opacity = scheme == .dark ? token.darkOpacity : token.lightOpacity
      return opacity < 1 ? "\(hex) \(Int((opacity * 100).rounded()))%" : hex
    }
  }

  private struct MotionRow: View {
    let name: String
    let seconds: Double
    let curve: MTEasingCurve
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      HStack(spacing: MTSpacing.s3) {
        Text(name).font(MTFont.identifier).foregroundStyle(MTColor.ink)
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
          withAnimation(curve.animation(duration: seconds)) { moved.toggle() }
        }
        .labelStyle(.iconOnly).frame(minWidth: MTSize.hitTarget, minHeight: MTSize.hitTarget)
      }
    }
  }

  private struct SizeSpecimen: View {
    private let controls: [(name: String, value: CGFloat, isField: Bool)] = [
      ("control.small", MTSize.Control.small, false),
      ("control.medium", MTSize.Control.medium, false),
      ("control.large", MTSize.Control.large, false),
      ("field.small", MTSize.Field.small, true),
      ("field.medium", MTSize.Field.medium, true),
      ("field.large", MTSize.Field.large, true),
    ]
    private let icons: [CGFloat] = [
      MTSize.Icon.s7, MTSize.Icon.s8, MTSize.Icon.s10, MTSize.Icon.s11, MTSize.Icon.s12,
      MTSize.Icon.s13, MTSize.Icon.s14, MTSize.Icon.s15, MTSize.Icon.s16, MTSize.Icon.s17,
      MTSize.Icon.s18, MTSize.Icon.s19, MTSize.Icon.s20, MTSize.Icon.s21, MTSize.Icon.s22,
      MTSize.Icon.s23, MTSize.Icon.s24, MTSize.Icon.s25, MTSize.Icon.s30,
    ]
    private let strokes: [(name: String, value: CGFloat)] = [
      ("thin", MTSize.Stroke.thin), ("medium", MTSize.Stroke.medium),
      ("thick", MTSize.Stroke.thick), ("icon", MTSize.Stroke.icon),
    ]

    var body: some View {
      GallerySpecimen(
        title: "Size",
        api: "MTSize.Control · Field · hitTarget · Icon · Stroke",
        description:
          "Native control and field heights follow the 44 pt touch minimum, so they differ from Web."
      ) {
        VStack(alignment: .leading, spacing: MTSpacing.s5) {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: MTSpacing.s3)],
            alignment: .leading, spacing: MTSpacing.s3
          ) {
            ForEach(controls, id: \.name) { token in
              VStack(spacing: MTSpacing.s1) {
                RoundedRectangle(cornerRadius: MTRadius.small)
                  .fill(token.isField ? MTColor.surfaceRaised : MTColor.accentSubtle)
                  .overlay {
                    RoundedRectangle(cornerRadius: MTRadius.small).stroke(MTColor.borderStrong)
                  }
                  .frame(height: token.value)
                Text(token.name).font(MTFont.identifier).foregroundStyle(MTColor.ink)
                Text("\(Int(token.value)) pt").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted)
              }
              .frame(maxHeight: .infinity, alignment: .bottom)
            }
            VStack(spacing: MTSpacing.s1) {
              RoundedRectangle(cornerRadius: MTRadius.small)
                .strokeBorder(
                  MTColor.accent, style: StrokeStyle(lineWidth: MTSize.Stroke.thin, dash: [3])
                )
                .frame(width: MTSize.hitTarget, height: MTSize.hitTarget)
              Text("hitTarget").font(MTFont.identifier).foregroundStyle(MTColor.ink)
              Text("\(Int(MTSize.hitTarget)) pt").font(MTFont.caption).foregroundStyle(
                MTColor.inkMuted)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: MTSpacing.s2)],
            alignment: .leading, spacing: MTSpacing.s3
          ) {
            ForEach(icons, id: \.self) { size in
              VStack(spacing: MTSpacing.s1) {
                Image(MTIcon.star).font(.mtIcon(size)).foregroundStyle(MTColor.ink)
                  .frame(height: MTSize.Icon.s30)
                Text("s\(Int(size))").font(MTFont.identifier).foregroundStyle(
                  MTColor.inkMuted)
              }
              .accessibilityElement(children: .combine)
            }
          }
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            ForEach(strokes, id: \.name) { stroke in
              HStack(spacing: MTSpacing.s3) {
                Text("stroke.\(stroke.name)").font(MTFont.identifier)
                  .foregroundStyle(MTColor.ink).frame(width: 104, alignment: .leading)
                Capsule().fill(MTColor.ink).frame(height: stroke.value)
                Text("\(stroke.value.formatted()) pt").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted
                )
                .frame(width: 44, alignment: .trailing)
              }
            }
          }
        }
      }
    }
  }

  private struct StateSpecimen: View {
    private let colors: [(name: String, color: Color)] = [
      ("focus.ring", MTState.Focus.ring), ("focus.halo", MTState.Focus.halo),
      ("hover.surface", MTState.Hover.surface), ("hover.ink", MTState.Hover.ink),
      ("hover.accentSurface", MTState.Hover.accentSurface),
      ("hover.primary", MTState.Hover.primary), ("hover.chipBorder", MTState.Hover.chipBorder),
      ("hover.periodBar", MTState.Hover.periodBar),
      ("selected.surface", MTState.Selected.surface), ("selected.ink", MTState.Selected.ink),
      ("selected.fill", MTState.Selected.fill), ("selected.onFill", MTState.Selected.onFill),
      ("disabled.codeSurface", MTState.Disabled.codeSurface),
    ]
    private let opacities: [(name: String, value: Double)] = [
      ("button", MTState.Disabled.Opacity.button), ("field", MTState.Disabled.Opacity.field),
      ("choice", MTState.Disabled.Opacity.choice), ("quiet", MTState.Disabled.Opacity.quiet),
      ("navigation", MTState.Disabled.Opacity.navigation),
      ("soft", MTState.Disabled.Opacity.soft), ("toolbar", MTState.Disabled.Opacity.toolbar),
      ("calendarDay", MTState.Disabled.Opacity.calendarDay),
    ]

    var body: some View {
      GallerySpecimen(
        title: "State",
        api: "MTState.Focus · Hover · Selected · Disabled",
        description:
          "Focus, hover, selected, and disabled treatments shared with Web. Hover applies to pointer input on iPad."
      ) {
        VStack(alignment: .leading, spacing: MTSpacing.s5) {
          HStack(spacing: MTSpacing.s6) {
            Text("Focus ring").font(MTFont.label).foregroundStyle(MTColor.ink)
              .padding(.horizontal, MTSpacing.s4).padding(.vertical, MTSpacing.s2)
              .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.small))
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.small).stroke(MTColor.borderStrong)
              }
              .padding(MTState.Focus.ringOffset)
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.small + MTState.Focus.ringOffset)
                  .stroke(MTState.Focus.ring, lineWidth: MTState.Focus.ringWidth)
              }
            Text("Focus halo").font(MTFont.label).foregroundStyle(MTColor.ink)
              .padding(.horizontal, MTSpacing.s4).padding(.vertical, MTSpacing.s2)
              .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.small))
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.small).stroke(MTState.Focus.ring)
              }
              .padding(MTState.Focus.haloWidth)
              .background(
                MTState.Focus.halo,
                in: RoundedRectangle(cornerRadius: MTRadius.small + MTState.Focus.haloWidth))
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: MTSpacing.s2)],
            alignment: .leading, spacing: MTSpacing.s3
          ) {
            ForEach(colors, id: \.name) { token in
              HStack(spacing: MTSpacing.s2) {
                RoundedRectangle(cornerRadius: MTRadius.small).fill(token.color)
                  .overlay {
                    RoundedRectangle(cornerRadius: MTRadius.small).stroke(MTColor.border)
                  }
                  .frame(width: 32, height: 32)
                Text(token.name).font(MTFont.caption).foregroundStyle(MTColor.ink)
                  .lineLimit(1).minimumScaleFactor(0.8)
              }
            }
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: MTSpacing.s2)],
            alignment: .leading, spacing: MTSpacing.s3
          ) {
            ForEach(opacities, id: \.name) { token in
              VStack(spacing: MTSpacing.s1) {
                Text("Disabled").font(MTFont.label).foregroundStyle(MTColor.accentInk)
                  .frame(maxWidth: .infinity).padding(.vertical, MTSpacing.s2)
                  .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.small))
                  .opacity(token.value)
                Text(token.name).font(MTFont.identifier).foregroundStyle(MTColor.ink)
                Text(token.value.formatted()).font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted)
              }
              .accessibilityElement(children: .combine)
            }
          }
        }
      }
    }
  }

  private struct ElevationSpecimen: View {
    var body: some View {
      GallerySpecimen(
        title: "Elevation",
        api: "MTElevation.<level>.surface · shadow · scrim",
        description:
          "Each level pairs a surface with its shadow. Overlay adds the scrim behind it."
      ) {
        VStack(spacing: MTSpacing.s3) {
          ForEach(MTElevation.catalog, id: \.name) { level in
            Text(level.name).font(MTFont.identifier).foregroundStyle(MTColor.inkMuted)
              .frame(maxWidth: .infinity, minHeight: 56)
              .background(level.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
              .overlay {
                RoundedRectangle(cornerRadius: MTRadius.medium).stroke(MTColor.border)
              }
              .mtShadow(level.shadow)
              .padding(MTSpacing.s4)
              .background(
                level.scrim ?? MTColor.canvas,
                in: RoundedRectangle(cornerRadius: MTRadius.medium))
          }
        }
      }
    }
  }

  private struct MaterialSpecimen: View {
    var body: some View {
      GallerySpecimen(
        title: "Material",
        api: "MTMaterial.<name>.tint · border · systemMaterial",
        description:
          "Native materials layer a tint over a system material, shown over a busy backdrop. Web-only materials appear in the Web gallery."
      ) {
        VStack(spacing: MTSpacing.s3) {
          ForEach(MTMaterial.catalog, id: \.name) { material in
            VStack(alignment: .leading, spacing: MTSpacing.s1) {
              Text(material.name).font(MTFont.identifier)
              Text(
                material.systemMaterial.map { "\(String(describing: $0)) material" } ?? "tint only"
              )
              .font(MTFont.caption)
            }
            .foregroundStyle(MTColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MTSpacing.s3)
            .background {
              ZStack {
                if let system = material.systemMaterial {
                  Rectangle().fill(system.material)
                }
                Rectangle().fill(material.tint)
              }
              .clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
            }
            .overlay {
              if let border = material.border {
                RoundedRectangle(cornerRadius: MTRadius.small).stroke(border)
              }
            }
          }
        }
        .padding(MTSpacing.s4)
        .background { StripedBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
      }
    }
  }

  /// Diagonal stripes that make a material's blur and tint visible.
  private struct StripedBackdrop: View {
    private let colors = [MTColor.accent, MTColor.warmSubtle, MTColor.warm, MTColor.surface]
    private let stripe: CGFloat = 12

    var body: some View {
      Canvas { context, size in
        var x = -size.height
        var index = 0
        while x < size.width {
          var path = Path()
          path.move(to: CGPoint(x: x, y: size.height))
          path.addLine(to: CGPoint(x: x + size.height, y: 0))
          path.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
          path.addLine(to: CGPoint(x: x + stripe, y: size.height))
          path.closeSubpath()
          context.fill(path, with: .color(colors[index % colors.count]))
          x += stripe
          index += 1
        }
      }
      .accessibilityHidden(true)
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
              withAnimation(MTEasing.inOut.animation(duration: MTMotion.markTurn)) {
                markRotated.toggle()
              }
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
          title: "Icon",
          api: "MTIcon · Image(_:) · Label(_:icon:) · .mtIcon(size)",
          description:
            "The shared icon vocabulary from packages/design-system/icons.json, drawn as SF Symbols. Icons are hidden from VoiceOver and take the color of the text around them, so the label beside them names the action."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.iconSet) {
              LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: MTSpacing.s2)]) {
                ForEach(MTIcon.allCases, id: \.self) { icon in
                  VStack(spacing: MTSpacing.s2) {
                    Image(icon).font(.mtIcon(MTSize.Icon.s20)).foregroundStyle(MTColor.ink)
                      .frame(height: MTSize.Icon.s24)
                    Text(String(describing: icon)).font(MTFont.identifier)
                      .foregroundStyle(MTColor.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
                    // Every cell reserves the marker line so the grid rows stay even.
                    Text("iOS only").font(MTFont.micro).foregroundStyle(MTColor.warm)
                      .opacity(MTIcon.iosOnly.contains(icon) ? 1 : 0)
                      .accessibilityHidden(!MTIcon.iosOnly.contains(icon))
                  }
                  .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
                  .accessibilityElement(children: .combine)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.iconSizes) {
              HStack(alignment: .bottom, spacing: MTSpacing.s6) {
                ForEach(
                  [
                    ("14", MTSize.Icon.s14), ("16", MTSize.Icon.s16), ("18", MTSize.Icon.s18),
                    ("24", MTSize.Icon.s24),
                  ], id: \.0
                ) { name, size in
                  VStack(spacing: MTSpacing.s2) {
                    Image(MTIcon.calendar).font(.mtIcon(size)).foregroundStyle(MTColor.inkMuted)
                    Text(name).font(MTFont.code).foregroundStyle(MTColor.inkMuted)
                  }
                  .accessibilityElement(children: .combine)
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.iconColor) {
              MTFlowLayout(spacing: MTSpacing.s5) {
                Label("Timeline", icon: .timeline).foregroundStyle(MTColor.ink)
                Label("Library", icon: .archive).foregroundStyle(MTColor.inkMuted)
                Label("Add entry", icon: .plus).foregroundStyle(MTColor.accent)
                Label("Retry sync", icon: .refresh).foregroundStyle(MTColor.warm)
              }
              .font(MTFont.label)
            }
          }
        }
      }
    }
  }

  struct LayoutSpecimens: View {
    private let gutters: [(name: String, value: CGFloat, purpose: String)] = [
      ("regular", MTLayout.PageGutter.regular, "Wide windows"),
      ("compact", MTLayout.PageGutter.compact, "Phones and narrow windows"),
      ("narrow", MTLayout.PageGutter.narrow, "The narrowest phones"),
    ]

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "PageFrame",
          api: "MTPage · width: compact | standard | wide | canvas · spacing",
          description:
            "The canonical outer geometry. Phones use the full width with page gutters; wider screens center the page at its variant width. This gallery uses canvas."
        ) {
          GalleryCase(.pageFrameWidths) {
            VStack(spacing: 0) {
              ForEach(MTPageFrameWidth.allCases, id: \.self) { width in
                HStack(alignment: .firstTextBaseline) {
                  Text(width.rawValue).font(MTFont.label).foregroundStyle(MTColor.ink)
                  Spacer()
                  Text("\(Int(width.maxWidth)) pt · \(width.pageWidth.purpose)").font(MTFont.caption)
                    .foregroundStyle(MTColor.inkMuted).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, MTSpacing.s3)
                if width != MTPageFrameWidth.allCases.last {
                  Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin)
                }
              }
            }
          }
        }
        GallerySpecimen(
          title: "Page gutters",
          api: "MTLayout.PageGutter",
          description: "Horizontal page padding at each window class, shared with Web."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            ForEach(gutters, id: \.name) { gutter in
              HStack {
                VStack(alignment: .leading, spacing: 0) {
                  Text(gutter.name).font(MTFont.label).foregroundStyle(MTColor.ink)
                  Text(gutter.purpose).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(MTColor.warm)
                  .frame(width: gutter.value, height: 8)
                Text("\(Int(gutter.value)) pt").font(MTFont.caption).foregroundStyle(
                  MTColor.inkMuted
                )
                .frame(width: 44, alignment: .trailing)
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
                ("Section gap", MTSpacing.s8), ("Group gap", MTSpacing.s3),
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
