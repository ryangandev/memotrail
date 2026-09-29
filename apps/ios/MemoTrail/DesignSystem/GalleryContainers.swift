#if DEBUG
  import SwiftUI

  struct ContainerSpecimens: View {
    @State private var recordMessage = "Interactive state has not been activated."
    @State private var collectionMessage = "No Collection opened yet."
    @State private var chinese = false

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
          title: "Collection card",
          api: "name · entryCount · inboxCount · updatedLabel · action · manage",
          description:
            "Compare occupied, empty, Inbox, and long-title states. Management stays a separate action."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 220), spacing: MTSpacing.s3)],
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
                    Image(.more).font(.system(size: 15, weight: .medium))
                      .foregroundStyle(MTColor.inkMuted)
                      .frame(width: 32, height: 32)
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
          api: "text · richText · font · falls back to the plain body",
          description:
            "Renders Web-authored writing: emphasis, code, links, quotes, lists, and code blocks."
        ) {
          VStack(alignment: .leading, spacing: MTSpacing.s4) {
            MTRichTextContent(
              text: GallerySamples.richText?.text ?? "", richText: GallerySamples.richText)
            Rectangle().fill(MTColor.border).frame(height: 1)
            MTRichTextContent(
              text: "A plain body renders as one paragraph when no valid rich document is stored.")
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
