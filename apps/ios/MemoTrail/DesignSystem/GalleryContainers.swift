#if DEBUG
  import SwiftUI

  struct ContainerSpecimens: View {
    @State private var recordMessage = "Interactive state has not been activated."
    @State private var collectionMessage = "No Collection opened yet."
    @State private var chinese = false
    @State private var hasLocation = true

    private let collections: [(name: String, entries: Int, inbox: Int, updated: String?)] = [
      ("Early years", 12, 0, "Latest Sep 18"),
      ("Homes and neighborhoods", 7, 0, "Latest Aug 30"),
      ("First times", 19, 2, "Latest Sep 22"),
      (
        "Notes from my travels across three continents and many small towns", 24, 0,
        "Latest Sep 12"
      ),
      ("To revisit", 0, 0, nil),
    ]

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        GallerySpecimen(
          title: "RecordCard",
          api:
            "accessibilityLabel · action; composable MTRecordCardVisual and MTRecordCardBody · MTCardButtonStyle"
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTRecordCard(accessibilityLabel: "Open sample memory") {
              recordMessage = "RecordCard action fired."
            } content: {
              MTRecordCardVisual { GallerySampleArtwork() }
              MTRecordCardBody {
                MTEyebrow(text: "Memory")
                Text("First trip to the coast").font(MTFont.cardTitle).foregroundStyle(
                  MTColor.ink)
                Text("A production RecordCard composed with its real subparts.")
                  .font(MTFont.body).foregroundStyle(MTColor.inkMuted)
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
            "Home, Vehicle, and First Time cards prefer a photo, then a map of their Location, then a mark. Glass badges stay legible over each."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTRecordCard(accessibilityLabel: "Open sample Home with a map") {
              recordMessage = "Opened the Home with a map."
            } content: {
              MTRecordCardVisual {
                MTLocationSnapshot(latitude: 45.5231, longitude: -122.6765) {
                  MTRecordMark(icon: .home, title: "Portland")
                }
              }
              .overlay(alignment: .topLeading) {
                MTBadge(title: "Current", tone: .glassAccent, size: .micro, uppercase: true)
                  .padding(MTSpacing.s2)
              }
              MTRecordCardBody {
                Text("Maple Street flat").font(MTFont.cardTitle).foregroundStyle(MTColor.ink)
              }
            }
            MTRecordCard(accessibilityLabel: "Open sample Home without a Location") {
              recordMessage = "Opened the Home without a Location."
            } content: {
              MTRecordCardVisual(height: MTLayout.Gallery.sampleVisual) {
                MTRecordMark(icon: .home, title: "A place in your trail")
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
                Text("Harbor Road cottage").font(MTFont.cardTitle).foregroundStyle(MTColor.ink)
              }
            }
          }
        }

        GallerySpecimen(
          title: "Entity card",
          api:
            "MTRecordSection · title · detail; MTEntityCard · range · duration · isCurrent · coverURL · latitude · longitude · facts",
          description:
            "The Home and Vehicle archive: a section heading, then cards with a photo, map, or mark, the dates, facts, a short memory, and organization."
        ) {
          MTRecordSection(
            "Vehicle archive", detail: "Current first, followed by earlier vehicles"
          ) {
            MTEntityCard(
              title: "Blue hatchback", range: "Since Sep 15, 2019", duration: "7 years",
              isCurrent: true, latitude: 45.512, longitude: -122.625, markIcon: .car,
              markTitle: "2015 Honda Fit · Blue",
              facts: [
                MTEntityCard.Fact(icon: .car, text: "2015 Honda Fit · Blue"),
                MTEntityCard.Fact(icon: .map, text: "Hawthorne Boulevard, Portland, OR"),
              ],
              memory: "Road trips, groceries, and one flat tire.", tagNames: ["car"]
            ) { recordMessage = "Opened the current Vehicle." }
            MTEntityCard(
              title: "Red touring bike", range: "2012 - 2016", duration: "About 4 years",
              isCurrent: false, markIcon: .car, markTitle: "Details not recorded",
              facts: [MTEntityCard.Fact(icon: .car, text: "Details not recorded")],
              collectionNames: ["Early years"]
            ) { recordMessage = "Opened the earlier Vehicle." }
          }
        }

        GallerySpecimen(
          title: "Record detail",
          api: "MTRecordPhotos · MTFactList · MTDetailSection",
          description:
            "The focused Home, Vehicle, First Time, and Goal page: photos, labeled facts that skip empty values, then Story and Organize."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s8) {
            MTRecordPhotos(
              recordLabel: "Home",
              photos: [
                MTPhotoField.SavedPhoto(
                  id: UUID(), url: GallerySamples.artworkURL, name: "coast-memory.jpg")
              ])
            MTFactList(facts: [
              ("When", "Since Jun 1, 2021"), ("Location", "Portland, Oregon, United States"),
              ("Address", "120 Maple Street"), ("Why you moved in", "Closer to work"),
              ("Why you left", nil),
            ])
            MTDetailSection("Story") {
              Text("Sunny kitchen and a creaky staircase.")
                .font(MTFont.bodyLarge).foregroundStyle(MTColor.ink)
            }
            MTDetailSection("Organize") {
              MTFlowLayout(spacing: MTSpacing.s2) {
                MTBadge(title: "Early years", tone: .neutral)
                MTBadge(title: "#home", tone: .neutral)
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
            MTLocationPanel(message: "This Vehicle keeps its own Location.") {
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
          title: "Collection card",
          api: "name · entryCount · inboxCount · updatedLabel · action · manage",
          description:
            "Compare occupied, empty, Inbox, and long-title states. Management stays a separate action."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            LazyVGrid(
              columns: [
                GridItem(.adaptive(minimum: MTLayout.Gallery.sampleGrid), spacing: MTSpacing.s3)
              ],
              spacing: MTSpacing.s3
            ) {
              ForEach(collections, id: \.name) { collection in
                MTCollectionCard(
                  name: collection.name, entryCount: collection.entries,
                  inboxCount: collection.inbox, updatedLabel: collection.updated
                ) {
                  collectionMessage = "Opened \(collection.name)."
                } manage: {
                  Menu {
                    Button("Rename", systemImage: MTIcon.edit.systemName) {
                      collectionMessage = "Rename \(collection.name): preview only."
                    }
                    Button("Delete", systemImage: MTIcon.trash.systemName, role: .destructive) {
                      collectionMessage = "Delete \(collection.name): preview only."
                    }
                  } label: {
                    Image(.more).font(.mtIcon(MTSize.Icon.s15, weight: .medium))
                      .foregroundStyle(MTColor.inkMuted)
                      .frame(
                        width: MTLayout.InlineAction.height, height: MTLayout.InlineAction.height
                      )
                      .contentShape(Rectangle())
                  }
                  .accessibilityLabel("Manage \(collection.name)")
                }
              }
            }
            Text(collectionMessage).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
          }
        }

        GallerySpecimen(
          title: "RichTextContent",
          api: "text · richText · font · color · lineLimit · falls back to the plain body",
          description:
            "Renders Web-authored writing: emphasis, code, links, quotes, lists, and code blocks. A line limit flows it into a clamped preview."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            MTRichTextContent(
              text: GallerySamples.richText?.text ?? "", richText: GallerySamples.richText)
            MTListDivider()
            MTRichTextContent(
              text: GallerySamples.richText?.text ?? "", richText: GallerySamples.richText,
              font: MTFont.body, textStyle: .subheadline, color: MTColor.inkMuted, lineLimit: 4)
            MTListDivider()
            MTRichTextContent(
              text: "A plain body renders as one paragraph when no valid rich document is stored.")
          }
        }

        GallerySpecimen(
          title: "FlowSeparator",
          api: "MTFlowLayout { MTFlowSeparator() } · MTWordFlow(textStyle)",
          description:
            "Summary and metadata rows, like Web SeparatedList. As the frames narrow, facts wrap whole and a separator shows only between two facts on the same line."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            ForEach(
              [("Wide", nil), ("Medium", 240), ("Narrow", 150)] as [(String, CGFloat?)], id: \.0
            ) { name, width in
              VStack(alignment: .leading, spacing: MTSpacing.s3) {
                MTFlowLayout(spacing: MTSpacing.s2) {
                  Button("Manage tracks") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(MTColor.accent)
                  ForEach(["8 tracks", "12 moments", "2017 to 2026"], id: \.self) { fact in
                    MTFlowSeparator()
                    Text(fact)
                  }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name) separated facts")
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
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkFaint)
              .padding(MTSpacing.s4)
              .frame(width: width)
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

        GallerySpecimen(
          title: "RecordSummary",
          api: "kind · title · subtitle · status",
          description: "The compact record identity used in Map results."
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
                title: "The next chapter", subtitle: "No occurred date · On this iPhone",
                kind: "Entry", status: "In Inbox")
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
          api: "MTListHeader · title · detail · alignsDetailTrailing · trailing; MTListSurface",
          description:
            "The uppercase list heading and bordered row surface shared by the Inbox and Library, with pressable whole-row links."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            MTListHeader("Results", detail: "2 items")
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
            MTListHeader("All items", detail: "9 items", alignsDetailTrailing: true)
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
