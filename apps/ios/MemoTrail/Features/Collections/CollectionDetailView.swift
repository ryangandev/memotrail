@preconcurrency import Supabase
import SwiftUI

/// Web `/collections/<id>`: one Collection's Entries, newest first, with its counts and editor.
/// Each Entry opens where it lives, and its Collections and tags open Library filtered to them.
struct CollectionDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  /// Runs after the Collection changes here, so the overview shows it.
  let changed: @MainActor () async -> Void

  @State private var collection: MemoCollection
  @State private var controller: CollectionDetailController
  @State private var item: OrganizationItem?
  @State private var isEditing = false
  /// The Collection moved to Trash, so its page closes once the editor has.
  @State private var isGone = false
  @State private var opened: WikiItemLink?
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.dismiss) private var dismiss

  init(
    client: SupabaseClient, ownerID: UUID, collection: MemoCollection,
    changed: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.ownerID = ownerID
    self.changed = changed
    _collection = State(initialValue: collection)
    _controller = State(
      initialValue: CollectionDetailController(
        client: client, ownerID: ownerID, collectionID: collection.id))
  }

  private var actions: OrganizationActions { OrganizationActions(client: client, ownerID: ownerID) }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Collection archive", title: collection.name,
        description:
          "Entries can belong to more than one Collection without being copied or separated."
      ) {
        Button {
          navigator.startCapture()
        } label: {
          Label("New entry", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("collection-new-entry")
      }
      toolbar
      content
    }
    .refreshable { await reload() }
    .navigationTitle(collection.name)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      // Leaving while the editor closes would cancel the dismissal.
      if isGone { dismiss() }
    } content: {
      if let item {
        OrganizationEditorSheet(
          actions: actions, kind: .collection, item: item,
          changed: {
            await changed()
            await reload()
          })
      }
    }
    .wikiItemDestination($opened, client: client, ownerID: ownerID)
    .task {
      if !controller.hasLoaded { await reload() }
    }
  }

  /// Web's detail toolbar: the counts, then the Collection's editor.
  private var toolbar: some View {
    HStack(spacing: MTSpacing.s4) {
      MTFlowLayout(spacing: MTSpacing.s2) {
        Text(countLabel(collection.entryCount, "Entry"))
        if collection.unreviewedCount > 0 {
          MTFlowSeparator()
          Text("\(collection.unreviewedCount) still in Inbox")
        }
      }
      .font(MTFont.caption.weight(.regular))
      .foregroundStyle(MTColor.inkFaint)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Collection summary")
      if item != nil {
        MTIconButton(label: "Edit \(collection.name)", icon: .more) { isEditing = true }
      }
    }
    .padding(.vertical, MTSpacing.s3)
    .overlay(alignment: .top) { MTListDivider() }
    .overlay(alignment: .bottom) { MTListDivider() }
  }

  @ViewBuilder private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading \(collection.name)...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage, controller.entries.isEmpty {
      MTEmptyState(title: "Collection unavailable", message: message, icon: .archive) {
        Button("Try again") { Task { await reload() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.entries.isEmpty {
      MTEmptyState(
        title: "This Collection is empty",
        message: "Assign “\(collection.name)” while organizing an Entry and it will appear here.",
        icon: .archive
      ) {
        OpenInboxButton()
      }
    } else {
      VStack(spacing: MTSpacing.s4) {
        ForEach(controller.entries) { entry in
          CollectionEntryCard(
            entry: entry, open: { navigator.open(WikiItemLink(entry)) { opened = $0 } },
            openCollection: { navigator.openLibrary(collection: $0) },
            openTag: { navigator.openLibrary(tag: $0) })
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(collection.name) Entries")
      if controller.entries.count < controller.totalCount
        || (controller.loadErrorMessage != nil && !controller.entries.isEmpty)
      {
        MTLoadMore(
          isLoading: controller.isLoading,
          message: controller.entries.isEmpty ? nil : controller.loadErrorMessage
        ) { await controller.loadMore() }
      }
    }
  }

  /// Reloads the Entries and the Collection's own counts and editor identity, like Web
  /// `router.refresh()`. A Collection moved to Trash elsewhere closes its page.
  private func reload() async {
    async let entries: Void = controller.load()
    async let identity = actions.load(.collection, limit: 100)
    async let summary = CollectionsController.summary(client: client, ownerID: ownerID)
    await entries
    item = (try? await identity)?.first { $0.id == collection.id }
    if let summary = try? await summary {
      if let current = summary.first(where: { $0.id == collection.id }) {
        collection = current
      } else if isEditing {
        isGone = true
      } else {
        dismiss()
      }
    }
  }
}

/// Web `CollectionEntryCard`: a cover photo, the Kind, Inbox state, and date, the title that
/// opens the Entry, its writing with Read full note, and Collection and tag links.
private struct CollectionEntryCard: View {
  let entry: CollectionEntry
  let open: () -> Void
  let openCollection: (String) -> Void
  let openTag: (String) -> Void
  @State private var showsFullNote = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let cover = entry.coverAttachment {
        Group {
          if cover.signedURL != nil {
            MTRemoteImage(
              url: cover.signedURL, accessibilityLabel: cover.originalFilename ?? "Entry photo")
          } else {
            Label("Private photo", icon: .photo)
              .font(MTFont.caption)
              .foregroundStyle(MTColor.inkMuted)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(MTColor.surfaceSubtle)
          }
        }
        .frame(height: 210)
        .clipped()
      }
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 6) {
          MTBadge(title: entry.displayType, tone: .neutral)
          if entry.isInInbox { MTBadge(title: "In Inbox", tone: .warm) }
          Spacer(minLength: MTSpacing.s2)
          Text(entry.displayDate)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(MTColor.inkFaint)
            .multilineTextAlignment(.trailing)
        }
        Button(action: open) {
          Text(entry.displayTitle)
            .font(.system(.title3, design: .serif).weight(.medium))
            .foregroundStyle(MTColor.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(entry.isInInbox ? "Opens its Inbox review" : "Opens this record")
        .padding(.top, MTSpacing.s3)
        let body = entry.body.trimmed
        if !body.isEmpty {
          MTRichTextContent(
            text: body, richText: entry.bodyRich, font: MTFont.body, textStyle: .subheadline,
            color: MTColor.inkMuted, lineLimit: 4
          )
          .padding(.top, MTSpacing.s2)
        }
        if body.utf16.count > 320 {
          fullNote(body)
        }
        if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
          MTFlowLayout(spacing: 6) {
            ForEach(entry.collectionNames, id: \.self) { name in
              chip(Label(name, icon: .archive), label: "Collection \(name)") {
                openCollection(name)
              }
            }
            ForEach(entry.tagNames, id: \.self) { name in
              chip(Text("#\(name)"), label: "Tag \(name)") { openTag(name) }
            }
          }
          .padding(.top, MTSpacing.s3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .top) {
            Rectangle().fill(MTColor.border.opacity(0.7)).frame(height: 1)
          }
          .padding(.top, MTSpacing.s4)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Entry organization")
        }
      }
      .padding(MTSpacing.s5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
  }

  /// Web's `details` below the clamped writing.
  @ViewBuilder private func fullNote(_ body: String) -> some View {
    Button {
      withAnimation(.easeOut(duration: MTMotion.quick)) { showsFullNote.toggle() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "arrowtriangle.right.fill")
          .font(.system(size: 7))
          .rotationEffect(.degrees(showsFullNote ? 90 : 0))
        Text("Read full note")
      }
      .font(MTFont.caption.weight(.regular))
      .foregroundStyle(MTColor.accent)
      .frame(minHeight: 32)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(showsFullNote ? "Expanded" : "Collapsed")
    .padding(.top, MTSpacing.s1)
    if showsFullNote {
      MTRichTextContent(
        text: body, richText: entry.bodyRich, font: MTFont.body, textStyle: .subheadline,
        color: MTColor.inkMuted
      )
      .padding(MTSpacing.s4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .padding(.top, MTSpacing.s3)
    }
  }

  /// Web's organization link: a small pill that opens Library filtered to it.
  private func chip(_ content: some View, label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      content
        .labelStyle(MTInlineIconLabelStyle())
        .font(.system(size: 10))
        .foregroundStyle(MTColor.inkMuted)
        .padding(.horizontal, MTSpacing.s2)
        .padding(.vertical, 3)
        .background(MTColor.surfaceSubtle, in: Capsule())
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityHint("Opens Library filtered to it")
  }
}
