import Foundation
@preconcurrency import Supabase
import SwiftUI

struct ExplorationInput: Encodable, Sendable {
  let action: String
  var entryID: UUID? = nil
  var beforeSequence: Int? = nil
  var requestID: UUID? = nil
  var question: String? = nil
  var sourceRevision: Int? = nil
  var turnID: UUID? = nil
  var title: String? = nil
  var body: String? = nil
}
struct ExplorationWorkspace: Decodable, Sendable {
  struct Source: Decodable, Sendable {
    let id: UUID
    let title: String?
    let body: String
    let revision: Int
  }
  struct Link: Decodable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let relationship: String
  }
  let source: Source
  let turns: [ExplorationTurn]
  let totalCount: Int
  let links: [Link]
  let linksTruncated: Bool
  enum CodingKeys: String, CodingKey {
    case source, turns, links, linksTruncated
    case totalCount = "total_count"
  }
}
struct ExplorationTurn: Decodable, Identifiable, Sendable {
  struct Saved: Decodable, Identifiable, Sendable {
    let requestID: UUID
    let entryID: UUID?
    let title: String?
    let deleted: Bool
    var id: UUID { requestID }
    enum CodingKeys: String, CodingKey {
      case title, deleted
      case requestID = "request_id"
      case entryID = "entry_id"
    }
  }
  let id: UUID
  let sequence: Int
  let question: String
  let sourceRevision: Int
  let sourceSnapshot: [String: HistoryJSON]
  let status: String
  let answer: String?
  let savedEntries: [Saved]
  enum CodingKeys: String, CodingKey {
    case id, sequence, question, status, answer
    case sourceRevision = "source_revision"
    case sourceSnapshot = "source_snapshot"
    case savedEntries = "saved_entries"
  }
}
struct ExplorationSaveResult: Decodable, Sendable {
  let entryID: UUID?
  enum CodingKeys: String, CodingKey { case entryID = "entry_id" }
}

struct ExplorationView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  @State private var workspace: ExplorationWorkspace?
  @State private var turns: [ExplorationTurn] = []
  @State private var question = ""
  @State private var busy = false
  @State private var message: String?
  @State private var pendingRequest: ExplorationInput?
  @State private var conclusion: ConclusionDraft?
  @State private var savedID: UUID?
  private var generating: Bool { turns.contains { $0.status == "generating" } }
  private struct ConclusionDraft: Identifiable {
    let id = UUID()
    let turnID: UUID
    let body: String
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MTSpacing.s5) {
        Text("ROOM FOR A THOUGHT TO GROW").font(MTFont.caption).foregroundStyle(MTColor.warm)
        Text("Explore with AI").font(MTFont.display)
        Text("A separate conversation. Your original words stay yours.").foregroundStyle(
          MTColor.inkMuted)
        if let workspace {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("ORIGINAL ENTRY · VERSION \(workspace.source.revision)").font(MTFont.caption)
              .foregroundStyle(MTColor.warm)
            Text(workspace.source.title?.trimmed.nonEmpty ?? "Untitled Entry").font(
              MTFont.title)
            Text(workspace.source.body).textSelection(.enabled)
            NavigationLink("Open original Entry") {
              EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
            }
          }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
            MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
          ForEach(workspace.links) { link in
            NavigationLink(
              "\(link.relationship == "exploration_source" ? "Source" : "Saved conclusion"): \(link.title)"
            ) {
              EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: link.id)
            }
          }
          if workspace.linksTruncated {
            Text("Showing the first 100 links.").font(MTFont.caption)
          }
        }
        HStack {
          Button("Refresh conversation") { Task { await load() } }.disabled(busy)
          Spacer()
          NavigationLink("AI settings") { AISettingsView() }
        }
        Text(
          "Sending shares a bounded excerpt of this Entry and up to eight recent completed turns with Anthropic. No photos or other archive records are sent. AI may be wrong. Opening and refreshing are free."
        ).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        if let workspace, turns.count < workspace.totalCount {
          Button("Load earlier turns") { Task { await load(older: true) } }.disabled(busy)
        }
        if turns.isEmpty && workspace != nil {
          Text("Start with a question, a new perspective, or something you want to understand.")
            .foregroundStyle(MTColor.inkMuted)
        }
        ForEach(turns) { turn in
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("YOU").font(MTFont.caption).foregroundStyle(MTColor.warm)
            Text(turn.question).textSelection(.enabled)
            Text("AI EXPLORATION · SOURCE VERSION \(turn.sourceRevision)").font(
              MTFont.caption
            ).foregroundStyle(MTColor.warm)
            if turn.status == "completed" {
              Text(turn.answer ?? "").textSelection(.enabled)
              Button("Save as Entry") {
                conclusion = ConclusionDraft(turnID: turn.id, body: turn.answer ?? "")
              }.disabled(busy)
            } else {
              Text(
                turn.status == "generating"
                  ? "Processing. You can leave and return; do not send the same question again."
                  : "This attempt did not finish. No automatic retry was made."
              ).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
              if turn.status == "failed" {
                Button("Use question for a new attempt") {
                  pendingRequest = nil
                  question = turn.question
                  message = nil
                }.disabled(busy)
              }
            }
            DisclosureGroup("Recorded source snapshot") {
              Text(
                "The model uses a bounded excerpt of this snapshot. Its version is retained after later edits."
              ).font(MTFont.caption)
              Text(turn.sourceSnapshot["body"]?.text ?? "").textSelection(.enabled)
            }.font(MTFont.caption)
            ForEach(turn.savedEntries) { saved in
              if let id = saved.entryID, !saved.deleted {
                NavigationLink("Saved Entry: \(saved.title ?? "Untitled Entry")") {
                  EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: id)
                }
              } else {
                Text("A saved conclusion was removed. Old retries will not recreate it.").font(
                  MTFont.caption)
              }
            }
          }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
            MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
        }
        VStack(alignment: .leading, spacing: MTSpacing.s3) {
          Text("Your question").font(MTFont.label)
          TextEditor(text: $question).frame(minHeight: MTLayout.Exploration.questionHeight)
            .scrollContentBackground(.hidden)
            .padding(MTSpacing.s2)
            .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
            .accessibilityLabel("Your question").disabled(busy || pendingRequest != nil)
          Text("\(question.utf16.count) / 2,000").font(MTFont.caption).foregroundStyle(
            MTColor.inkMuted)
          Button(pendingRequest == nil ? "Send question" : "Retry the same request") {
            Task { await send() }
          }
          .buttonStyle(.borderedProminent).tint(MTColor.accent).disabled(
            busy || generating || question.trimmed.isEmpty || question.utf16.count > 2000
              || workspace == nil)
          if pendingRequest != nil {
            Text(
              "The last request is unconfirmed. Refresh to check its saved state. Retrying uses the same ID to prevent duplicate generation."
            ).font(MTFont.caption)
          }
        }
        if let savedID {
          NavigationLink("Conclusion saved to Inbox. Open saved Entry") {
            EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: savedID)
          }
        }
        if busy { ProgressView() }
        if let message { Text(message).foregroundStyle(MTColor.warm) }
      }.padding(MTSpacing.s4).padding(.bottom, MTSpacing.s12)
    }.background(MTColor.canvas).navigationTitle("Explore").task { await load() }
      .refreshable { await load() }
      .sheet(item: $conclusion) { draft in
        ExplorationConclusionSheet(
          client: client, ownerID: ownerID, turnID: draft.turnID, initialBody: draft.body
        ) { id in
          savedID = id
          conclusion = nil
          Task { await load() }
        }
      }
      .task(id: generating) {
        guard generating else { return }
        for _ in 0..<12 {
          do { try await Task.sleep(for: .seconds(5)) } catch { return }
          guard !Task.isCancelled, generating else { return }
          if !busy { await load(silent: true) }
        }
      }
  }
  @MainActor private func load(older: Bool = false, silent: Bool = false) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    if !silent { message = nil }
    do {
      let next: ExplorationWorkspace = try await AIAPI.post(
        "explore",
        body: ExplorationInput(
          action: "workspace", entryID: entryID, beforeSequence: older ? turns.first?.sequence : nil
        ), client: client, ownerID: ownerID, timeout: 60)
      workspace = next
      turns =
        older
        ? next.turns + turns.filter { item in !next.turns.contains { $0.id == item.id } }
        : next.turns
      if let id = pendingRequest?.requestID,
        next.turns.contains(where: { $0.id == id && $0.status != "generating" })
      {
        pendingRequest = nil
      }
    } catch { message = error.localizedDescription }
  }
  @MainActor private func send() async {
    guard !busy, let workspace else { return }
    busy = true
    message = nil
    defer { busy = false }
    let input =
      pendingRequest
      ?? ExplorationInput(
        action: "send", entryID: entryID, requestID: UUID(), question: question.trimmed,
        sourceRevision: workspace.source.revision)
    pendingRequest = input
    do {
      let result: ExplorationWorkspace = try await AIAPI.post(
        "explore", body: input, client: client, ownerID: ownerID, timeout: 60)
      self.workspace = result
      turns = result.turns
      pendingRequest = nil
      if result.turns.contains(where: { $0.id == input.requestID && $0.status == "completed" }) {
        question = ""
      }
    } catch {
      let failure = error as NSError
      if failure.domain == "MemoTrail.AI", let code = failure.userInfo["serverCode"] as? String,
        [
          "entry_changed", "entry_unavailable", "exploration_busy", "request_id_conflict",
          "ai_disabled", "provider_unavailable", "invalid_request",
        ].contains(code)
      {
        pendingRequest = nil
      }
      message = error.localizedDescription
    }
  }
}

private struct ExplorationConclusionSheet: View {
  let client: SupabaseClient
  let ownerID: UUID
  let turnID: UUID
  let saved: (UUID) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var bodyText: String
  @State private var requestID = UUID()
  @State private var attempted = false
  @State private var busy = false
  @State private var message: String?
  @State private var confirmClose = false
  init(
    client: SupabaseClient, ownerID: UUID, turnID: UUID, initialBody: String,
    saved: @escaping (UUID) -> Void
  ) {
    self.client = client
    self.ownerID = ownerID
    self.turnID = turnID
    self.saved = saved
    _bodyText = State(initialValue: initialBody)
  }
  var body: some View {
    NavigationStack {
      Form {
        Text(
          "Edit the wording before saving. This creates a separate Inbox Entry linked both ways to the original."
        )
        TextField("Conclusion title", text: $title).disabled(busy || attempted)
        Text("\(title.utf16.count) / 200").font(MTFont.caption)
        TextEditor(text: $bodyText).frame(minHeight: MTLayout.Exploration.conclusionHeight)
          .accessibilityLabel("Conclusion text")
          .disabled(busy || attempted)
        Text("\(bodyText.utf16.count) / 50,000").font(MTFont.caption)
        Button(attempted ? "Retry same save" : "Save conclusion") { Task { await save() } }
          .disabled(
            busy || bodyText.trimmed.isEmpty || title.utf16.count > 200
              || bodyText.utf16.count > 50000)
        if busy { ProgressView() }
        if let message { Text(message).foregroundStyle(MTColor.warm) }
      }.navigationTitle("Keep a conclusion").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { confirmClose = true }.disabled(busy)
        }
      }.confirmationDialog(
        "Close this editor?", isPresented: $confirmClose, titleVisibility: .visible
      ) {
        Button("Close editor", role: .destructive) { dismiss() }
      } message: {
        Text(
          "Unsaved edits will be lost. If a save was interrupted, refresh the conversation to check whether it was already saved."
        )
      }
    }.interactiveDismissDisabled()
  }
  @MainActor private func save() async {
    guard !busy else { return }
    busy = true
    attempted = true
    message = nil
    defer { busy = false }
    do {
      let result: ExplorationSaveResult = try await AIAPI.post(
        "explore",
        body: ExplorationInput(
          action: "save", requestID: requestID, turnID: turnID, title: title, body: bodyText),
        client: client, ownerID: ownerID, timeout: 60)
      guard let id = result.entryID else {
        message = "This save was completed but its Entry was deleted. It was not recreated."
        return
      }
      saved(id)
    } catch { message = error.localizedDescription }
  }
}
