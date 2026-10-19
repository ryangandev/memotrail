#if DEBUG
  import SwiftUI

  struct ContainerSpecimens: View {
    @State private var recordMessage = "Interactive state has not been activated."
    @State private var chinese = false
    @State private var hasLocation = true
    @State private var captureNote = NSAttributedString(string: "")
    @State private var captureOccurrence: OccurrenceDraft?
    @State private var capturePhotos: [PhotoDraft] = []
    @State private var captureMessage = "Nothing captured yet."

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "RecordCard",
          api:
            "accessibilityLabel · action; composable MTRecordCardVisual and MTRecordCardBody · MTCardButtonStyle"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.recordCardPhoto) {
              MTRecordCard(accessibilityLabel: "First sourdough loaf, September 18, 2026") {
                recordMessage = "Opened the first sourdough loaf."
              } content: {
                MTRecordCardVisual {
                  MTRemoteImage(url: GallerySamples.artworkURL)
                }
                .overlay(alignment: .bottomTrailing) {
                  MTBadge(title: "3 photos", tone: .inverse, size: .micro, uppercase: true)
                    .padding(MTSpacing.s3)
                }
                MTRecordCardBody {
                  Text("September 18, 2026".uppercased())
                    .mtTextRole(.firstTimeDate)
                    .foregroundStyle(MTColor.warm)
                  Text("First sourdough loaf")
                    .mtTextRole(.recordCardTitle)
                    .foregroundStyle(MTColor.ink)
                    .padding(.top, MTSpacing.s1)
                  Label("Portland, Oregon", icon: .map)
                    .labelStyle(MTInlineIconLabelStyle())
                    .font(MTFont.supporting)
                    .foregroundStyle(MTColor.inkMuted)
                    .padding(.top, MTSpacing.s2)
                  Text("The crust cracked as it cooled, and the kitchen smelled like a bakery.")
                    .font(MTFont.supporting)
                    .foregroundStyle(MTColor.inkMuted)
                    .mtLineSpacing(MTLineHeight.body)
                    .lineLimit(2)
                    .padding(.top, MTSpacing.s2)
                  MTRecordCardFooter(tagNames: ["baking", "home"])
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.recordCardMark) {
              MTRecordCard(accessibilityLabel: "First solo trip, Summer 2016") {
                recordMessage = "Opened the first solo trip."
              } content: {
                MTRecordCardVisual {
                  MTRecordMark(icon: .timeline, title: "Summer 2016")
                }
                MTRecordCardBody {
                  Text("Summer 2016".uppercased())
                    .mtTextRole(.firstTimeDate)
                    .foregroundStyle(MTColor.warm)
                  Text("First solo trip")
                    .mtTextRole(.recordCardTitle)
                    .foregroundStyle(MTColor.ink)
                    .padding(.top, MTSpacing.s1)
                  MTRecordCardFooter(tagNames: ["travel"])
                }
              }
            }
            Text(recordMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              .accessibilityIdentifier("design-record-status")
          }
        }

        GallerySpecimen(
          title: "Record card visuals",
          api:
            "MTLocationSnapshot · latitude · longitude · fallback; MTRecordMark · icon · title; glass badges",
          description:
            "First Time cards prefer a photo, then a map of their Location, then a mark. Glass badges stay legible over each."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTRecordCard(accessibilityLabel: "Open sample First Time with a map") {
              recordMessage = "Opened the First Time with a map."
            } content: {
              MTRecordCardVisual {
                MTLocationSnapshot(latitude: 45.5231, longitude: -122.6765) {
                  MTRecordMark(icon: .map, title: "Portland")
                }
              }
              .overlay(alignment: .topLeading) {
                MTBadge(title: "Current", tone: .glassAccent, size: .micro, uppercase: true)
                  .padding(MTSpacing.s2)
              }
              MTRecordCardBody {
                Text("First swim in the ocean").font(MTFont.cardTitle).foregroundStyle(MTColor.ink)
              }
            }
            MTRecordCard(accessibilityLabel: "Open sample First Time without a Location") {
              recordMessage = "Opened the First Time without a Location."
            } content: {
              MTRecordCardVisual(height: MTLayout.Gallery.sampleVisual) {
                MTRecordMark(icon: .star, title: "A First Time without a photo")
              }
              .overlay(alignment: .topLeading) {
                MTBadge(title: "Earlier", tone: .glassNeutral, size: .micro, uppercase: true)
                  .padding(MTSpacing.s2)
              }
              .overlay(alignment: .bottomTrailing) {
                MTBadge(title: "3 photos", tone: .inverse, size: .micro, uppercase: true)
                  .padding(MTSpacing.s3)
              }
              MTRecordCardBody {
                Text("First day of school").font(MTFont.cardTitle).foregroundStyle(MTColor.ink)
              }
            }
          }
        }

        GallerySpecimen(
          title: "LocationPreview",
          api: "label · latitude · longitude · remove; MTLocationPanel · message",
          description:
            "A saved Location in an editor, alone or in the Location panel. Remove clears it; editing the address by hand clears the coordinates."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTLocationPanel(message: "This Entry keeps its own Location.") {
              if hasLocation {
                MTLocationPreview(
                  label: "120 Maple Street, Portland, Oregon, United States", latitude: 45.5231,
                  longitude: -122.6765
                ) { hasLocation = false }
              } else {
                Button("Restore sample Location") { hasLocation = true }
                  .mtButtonStyle(.secondary, size: .small)
              }
            }
            MTLocationPreview(label: "Portland, Oregon", latitude: nil, longitude: nil)
          }
        }

        GallerySpecimen(
          title: "SeparatedList",
          api:
            "MTFlowLayout · align: start | end · rowAlignment: center | firstTextBaseline { MTFlowSeparator() } · MTWordFlow(textStyle, align:)",
          description:
            "Summary and metadata rows, like Web SeparatedList. As the frames narrow, facts wrap whole and a separator shows only between two facts on the same line."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.separatedListDefault) {
              separatedFrames { name in
                MTFlowLayout(spacing: MTSpacing.s2) {
                  Button("Open Timeline") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(MTColor.accent)
                  ForEach(["4 Chapters", "3 First Times", "2017 to 2026"], id: \.self) { fact in
                    MTFlowSeparator()
                    Text(fact)
                  }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name) separated facts")
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.separatedListWord) {
              separatedFrames { name in
                MTWordFlow(.caption1) {
                  Text("First Time")
                  MTFlowSeparator()
                  Text("3 earlier versions")
                  MTFlowSeparator()
                  Text("In Trash")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name) word-spaced facts")
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.separatedListEndAligned) {
              separatedFrames { name in
                MTFlowLayout(spacing: MTSpacing.s2, align: .end) {
                  Text("Powered by Geoapify")
                  MTFlowSeparator()
                  Text("© OpenStreetMap contributors")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name) attribution")
              }
            }
          }
        }

        GallerySpecimen(
          title: "SectionHeader",
          api:
            "title · variant: section | list · detail · detailAlign: start | end · description · trailing"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.sectionHeaderSection) {
              VStack(alignment: .leading, spacing: MTSpacing.s4) {
                MTSectionHeader("Recent Entries", detail: "12 entries")
                MTSectionHeader("Favorites", description: "Pinned to the top of your Library.") {
                  Button("Edit") { recordMessage = "Section action activated." }
                    .mtButtonStyle(.secondary, size: .small)
                }
                MTSectionHeader("A memory for today") {
                  MTSectionLink(title: "View all") { recordMessage = "Section link activated." }
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.sectionHeaderList) {
              VStack(alignment: .leading, spacing: MTSpacing.s4) {
                MTSectionHeader("All Entries", variant: .list, detail: "12 Entries")
                MTSectionHeader(
                  "All Entries", variant: .list, detail: "12 Entries", detailAlign: .end
                ) {
                  MTSectionLink(title: "3 need organizing") {
                    recordMessage = "List link activated."
                  }
                }
              }
            }
            GalleryCaseSeparator()
            GalleryCase(.sectionHeaderLong) {
              MTSectionHeader("Letters, photos, and notes from the summer at the coast house") {
                MTSectionLink(title: "View all") { recordMessage = "Section link activated." }
              }
              .frame(width: MTLayout.Gallery.photoSampleWidth)
            }
          }
        }

        GallerySpecimen(
          title: "RecordSummary",
          api: "kind · title · subtitle · status",
          description: "The compact record identity, where a full record card is too large."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Toggle("Preview Chinese & long content", isOn: $chinese)
              .font(MTFont.label).tint(MTColor.accent)
            MTCard {
              MTRecordSummary(
                title: chinese
                  ? "第一次沿着海岸慢慢走，记住了风、灯塔，以及那天没有说完的故事。" : "A quiet afternoon by the coast",
                subtitle: chinese
                  ? "旧金山，加利福尼亚 · 2026年9月" : "San Francisco, California · September 2026",
                kind: "First Time")
            }
            MTCard {
              MTRecordSummary(
                title: "The next chapter", subtitle: "Undated entry · On this iPhone",
                kind: "Chapter", status: "Not accepted")
            }
          }
        }

        GallerySpecimen(
          title: "Card", api: "content",
          description: "A plain raised surface for grouped content that is not itself interactive."
        ) {
          MTCard {
            Text("Grouped context, such as a saved preview or a short explanation.")
              .font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
        }

        GallerySpecimen(
          title: "List",
          api: "MTSectionHeader · variant: .list · detail · detailAlign; MTListSurface",
          description:
            "The uppercase list heading and bordered row surface shared by Library and Trash, with pressable whole-row links."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTSectionHeader("Results", variant: .list, detail: "2 items")
            MTListSurface {
              ForEach(["Letters from the coast house", "Hike the coast trail"], id: \.self) {
                title in
                Button {
                  recordMessage = "Opened \(title)."
                } label: {
                  VStack(alignment: .leading, spacing: MTSpacing.s1) {
                    Text(title).font(MTFont.cardTitle).foregroundStyle(MTColor.ink)
                    Text("Matched in Title").font(MTFont.caption).foregroundStyle(MTColor.accent)
                  }
                  .padding(MTSpacing.s4)
                }
                .buttonStyle(MTListRowButtonStyle())
                if title == "Letters from the coast house" { MTListDivider() }
              }
            }
            MTSectionHeader("All Entries", variant: .list, detail: "9 Entries", detailAlign: .end)
          }
        }

        GallerySpecimen(
          title: "CaptureComposer",
          api:
            "CaptureCard · note · occurrence · photos · style: page | dialog · isSaving · hasLocalDraft · error · save",
          description:
            "The Dashboard composer and the Quick Capture body. Both share this gallery's draft, and nothing is saved."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s5) {
            GalleryCase(.captureComposerPage) { captureCard(.page) }
            GalleryCaseSeparator()
            GalleryCase(.captureComposerDialog) { captureCard(.dialog) }
            Text(captureMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }
      }
    }

    private func captureCard(_ style: MTCaptureComposerStyle) -> some View {
      CaptureCard(
        note: $captureNote, occurrence: $captureOccurrence, photos: $capturePhotos, style: style,
        isSaving: false, hasLocalDraft: false, error: nil,
        addPhoto: { capturePhotos.append($0) },
        removePhoto: { id in capturePhotos.removeAll { $0.id == id } },
        save: { captureMessage = "Capture saved in the gallery only. Nothing was uploaded." })
    }

    /// The same list in a wide, a medium, and a narrow frame, outlined so its wrapping shows.
    private func separatedFrames(@ViewBuilder _ list: @escaping (String) -> some View) -> some View
    {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        ForEach(
          [("Wide", nil), ("Medium", 240), ("Narrow", 150)]
            as [(String, CGFloat?)], id: \.0
        ) { name, width in
          list(name)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkFaint)
            .padding(MTSpacing.s4)
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .overlay {
              RoundedRectangle(cornerRadius: MTRadius.medium)
                .strokeBorder(
                  MTColor.borderStrong,
                  style: StrokeStyle(
                    lineWidth: MTSize.Stroke.thin,
                    dash: [MTLayout.DashedBorder.dot, MTLayout.DashedBorder.gap]))
            }
        }
      }
    }
  }

  enum GallerySamples {
    /// A Web-shaped `body_rich` document covering every supported node and mark.
    static let richText: EntryRichText? = {
      let json = """
        {"type":"doc","content":[
          {"type":"paragraph","content":[
            {"type":"text","text":"Formatted memory","marks":[{"type":"bold"}]},
            {"type":"text","text":" with durable, validated structure."}]},
          {"type":"paragraph","content":[
            {"type":"text","text":"We walked to the "},
            {"type":"text","text":"old lighthouse","marks":[{"type":"italic"}]},
            {"type":"text","text":", checked the "},
            {"type":"text","text":"tide table","marks":[{"type":"code"}]},
            {"type":"text","text":", and "},
            {"type":"text","text":"saved the map","marks":[
              {"type":"link","attrs":{"href":"https://example.com/lighthouse"}}]},
            {"type":"text","text":"."}]},
          {"type":"blockquote","content":[
            {"type":"paragraph","content":[
              {"type":"text","text":"The wind was louder than the waves."}]}]},
          {"type":"bulletList","content":[
            {"type":"listItem","content":[{"type":"paragraph","content":[
              {"type":"text","text":"One remembered detail"}]}]},
            {"type":"listItem","content":[{"type":"paragraph","content":[
              {"type":"text","text":"Another","marks":[{"type":"underline"}]},
              {"type":"text","text":" worth keeping"}]}]}]},
          {"type":"orderedList","attrs":{"start":3},"content":[
            {"type":"listItem","content":[{"type":"paragraph","content":[
              {"type":"text","text":"Pack the thermos"}]}]},
            {"type":"listItem","content":[{"type":"paragraph","content":[
              {"type":"text","text":"Leave early","marks":[{"type":"strike"}]},
              {"type":"text","text":" Leave when ready"}]}]}]},
          {"type":"codeBlock","content":[{"type":"text","text":"sunrise 06:42\\nsunset  19:08"}]},
          {"type":"paragraph","content":[{"type":"text","text":"第一次沿着海岸慢慢走。"}]}]}
        """
      guard let document = try? JSONDecoder().decode(EntryRichText.Node.self, from: Data(json.utf8))
      else { return nil }
      return EntryRichText(version: 1, text: EntryRichText.plainText(document), document: document)
    }()
  }

  /// The Web gallery's sample landscape, drawn natively so specimens need no bundled image.
  struct GallerySampleArtwork: View {
    var body: some View {
      Canvas { context, size in
        let scale = max(size.width / 640, size.height / 360)
        let origin = CGPoint(
          x: (size.width - 640 * scale) / 2, y: (size.height - 360 * scale) / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
          CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xDDE8E1)))
        var hills = Path()
        hills.move(to: point(0, 285))
        for (x, y) in [(190, 115), (302, 210), (392, 138), (640, 285), (640, 360), (0, 360)] {
          hills.addLine(to: point(CGFloat(x), CGFloat(y)))
        }
        hills.closeSubpath()
        context.fill(hills, with: .color(Color(hex: 0x82AD98)))
        let sun = CGRect(
          origin: point(492 - 38, 92 - 38), size: CGSize(width: 76 * scale, height: 76 * scale))
        context.fill(Path(ellipseIn: sun), with: .color(Color(hex: 0xA76346)))
      }
      .accessibilityHidden(true)
    }
  }

  extension Color {
    fileprivate init(hex: UInt32) {
      self.init(
        red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255)
    }
  }
#endif
