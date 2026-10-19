import Foundation
@preconcurrency import Supabase
import XCTest

@testable import MemoTrail

// The Entry editor (P3) against the local stack, through `EntryEditorController`, so each
// contract covers what the editor sends and how it reads the answer.
extension NativeContractTests {
  func testEditorSavesAChapterWithASpanAndAFirstTime() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let created = try await savedEntry(
      "Moved into the flat \(marker)", client: client, ownerID: ownerID)
    let opened = try await XCTUnwrapAsync(try await api.editable(created.entryID))

    // Checking Chapter and First Time with a Month span, as the editor's controls would.
    let editor = EntryEditorController(
      client: client, ownerID: ownerID, mode: .edit(opened), timezone: "Europe/Lisbon")
    await editor.loadTagOptions()
    editor.draft.title = "  Lisbon years \(marker)  "
    editor.draft.changeMarks(EntryMarks(isChapter: true, isFirstTime: false))
    editor.draft.changeMarks(EntryMarks(isChapter: true, isFirstTime: true))
    editor.draft.occurrence.changeSegment(to: .month, span: true, unsurePrecision: .approximate)
    editor.draft.occurrence.edit { $0.start = "2022-02" }
    editor.draft.occurrence.setPresent(false)
    editor.draft.occurrence.edit { $0.end = "2024-11" }
    editor.draft.tagNames = ["moves \(marker)"]
    let outcome = await editor.save()
    XCTAssertEqual(outcome, .saved(SavedEntry(entryID: created.entryID, revision: 2)))
    XCTAssertNil(editor.errorMessage)

    let chapter = try await XCTUnwrapAsync(try await api.editable(created.entryID))
    XCTAssertEqual(chapter.title, "Lisbon years \(marker)")
    XCTAssertEqual(chapter.marks, EntryMarks(isChapter: true, isFirstTime: true))
    XCTAssertEqual(chapter.datePrecision, .month)
    XCTAssertEqual(chapter.occurredTimezone, "Europe/Lisbon")
    let reopened = OccurrenceDraft.editing(chapter.occurrence(fallbackTimezone: "UTC"))
    XCTAssertEqual([reopened.start, reopened.end], ["2022-02", "2024-11"])
    XCTAssertEqual(reopened.endMode, .date)
    XCTAssertEqual(chapter.tagNames, ["moves \(marker)"])
    let detail = try await XCTUnwrapAsync(try await api.detail(created.entryID))
    XCTAssertEqual(detail.marks.identityLabel, "Chapter · First Time")

    // A new Chapter still going on saves without an end, under its drafted id.
    let ongoing = EntryEditorController(
      client: client, ownerID: ownerID, mode: .new(.chapter), timezone: "UTC")
    ongoing.draft.occurrence.edit { $0.start = "2025-09-01" }
    XCTAssertEqual(ongoing.draft.occurrence.endMode, .present)
    let untitled = await ongoing.save()
    XCTAssertEqual(untitled, .failed)
    XCTAssertEqual(ongoing.errorMessage, "Give this Chapter a title.")
    ongoing.draft.title = "Grad school \(marker)"
    let added = await ongoing.save()
    XCTAssertEqual(added, .saved(SavedEntry(entryID: ongoing.draft.entryID, revision: 1)))
    let open = try await XCTUnwrapAsync(try await api.editable(ongoing.draft.entryID))
    XCTAssertEqual(open.subtype, .chapter)
    XCTAssertFalse(open.isFirstTime)
    XCTAssertEqual(open.datePrecision, .day)
    XCTAssertNotNil(open.occurredStart)
    XCTAssertNil(open.occurredEnd)
  }

  func testEditorKeepsUntouchedRichTextAndLocation() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let node = try JSONDecoder().decode(
      EntryRichText.Node.self,
      from: Data(
        #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Pack:"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Tent"}]}]},{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Stove","marks":[{"type":"link","attrs":{"href":"https://example.com/stove","target":"_blank","rel":null}}]}]}]}]}]}"#
          .utf8))
    let rich = EntryRichText(version: 1, text: EntryRichText.plainText(node), document: node)
    let id = UUID()
    var created = try parameters(
      SaveEntryParameters(
        entryID: id, expectedRevision: nil, title: "Packing \(marker)", body: rich.text.trimmed,
        richText: rich, occurrence: EntryOccurrence(precision: .unknown, timezone: "UTC"),
        tagNames: [], location: nil, marks: .none))
    created["p_primary_location"] = .object([
      "kind": .string("manual"), "address": .string("Rua Augusta 1"), "city": .string("Lisbon"),
      "region": .null, "country": .string("Portugal"),
    ])
    let createdRows: [SavedEntry] =
      try await client.rpc("save_entry", params: created).execute().value
    XCTAssertEqual(createdRows, [SavedEntry(entryID: id, revision: 1)])
    let opened = try await XCTUnwrapAsync(try await api.editable(id))
    let savedRich = try XCTUnwrap(opened.richText)
    let location = try XCTUnwrap(opened.primaryLocation)

    // The note opens read-only behind the Web formatting notice; a title edit resends the
    // document and the Location untouched.
    let editor = EntryEditorController(client: client, ownerID: ownerID, mode: .edit(opened))
    XCTAssertTrue(editor.hasWebOnlyFormatting)
    XCTAssertFalse(editor.isNoteEditable)
    editor.draft.title = "Packing list \(marker)"
    let saved = await editor.save()
    XCTAssertEqual(saved, .saved(SavedEntry(entryID: id, revision: 2)))
    let kept = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertEqual(kept.title, "Packing list \(marker)")
    XCTAssertEqual(kept.body, opened.body)
    XCTAssertEqual(kept.richText, savedRich)
    XCTAssertEqual(kept.primaryLocation?.id, location.id)

    // Choosing to edit the note here without changing it still keeps the document.
    let second = EntryEditorController(client: client, ownerID: ownerID, mode: .edit(kept))
    second.isEditingWebNote = true
    second.draft.tagNames = ["packing \(marker)"]
    let tagged = await second.save()
    XCTAssertEqual(tagged, .saved(SavedEntry(entryID: id, revision: 3)))
    let stillKept = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertEqual(stillKept.richText, savedRich)
    XCTAssertEqual(stillKept.primaryLocation?.id, location.id)

    // Remove clears the Location on save, and only then.
    let third = EntryEditorController(client: client, ownerID: ownerID, mode: .edit(stillKept))
    third.draft.location = nil
    let removed = await third.save()
    XCTAssertEqual(removed, .saved(SavedEntry(entryID: id, revision: 4)))
    let cleared = try await XCTUnwrapAsync(try await api.editable(id))
    XCTAssertNil(cleared.primaryLocation)
    XCTAssertEqual(cleared.richText, savedRich)
  }

  func testPhotoRetryUpdatesTheSameEntry() async throws {
    let (client, ownerID) = try await client(session: HeldResponseProtocol.session)
    defer { HeldResponseProtocol.gate.answerNextUpload(nil) }
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let title = "Harbor day \(marker)"
    let editor = EntryEditorController(
      client: client, ownerID: ownerID, mode: .new(.none), timezone: "UTC")
    editor.draft.title = title
    editor.add([try photoDraft(), try photoDraft(color: .systemBlue)])
    XCTAssertEqual(editor.newPhotos.count, 2)
    XCTAssertNil(editor.errorMessage)
    let id = editor.draft.entryID

    // Storage refuses the first photo: the Entry is saved, the other photo attached, and the
    // refused one waits for Save again in an editor that stays open.
    HeldResponseProtocol.gate.answerNextUpload(.refuse(statusCode: "500"))
    let first = await editor.save()
    XCTAssertEqual(first, .savedWithUnattachedPhotos(SavedEntry(entryID: id, revision: 1)))
    XCTAssertEqual(
      editor.errorMessage,
      "The Entry was saved, but 1 photo could not be attached. Select Save again to retry.")
    XCTAssertEqual(editor.newPhotos.count, 1)
    XCTAssertEqual(editor.draft.revision, 1)
    let attachedFirst = try await livePhotoCount(entryID: id, client: client)
    XCTAssertEqual(attachedFirst, 1)

    // Save again updates that same Entry rather than adding another one.
    let retry = await editor.save()
    XCTAssertEqual(retry, .saved(SavedEntry(entryID: id, revision: 2)))
    XCTAssertNil(editor.errorMessage)
    XCTAssertTrue(editor.newPhotos.isEmpty)
    let attachedAfterRetry = try await livePhotoCount(entryID: id, client: client)
    XCTAssertEqual(attachedAfterRetry, 2)
    let rows: [ExistingRow] =
      try await client.from("entries").select("id").eq("title", value: title).execute().value
    XCTAssertEqual(rows.map(\.id), [id])
  }

  func testStaleRevisionReportsAConflict() async throws {
    let (client, ownerID) = try await client()
    let api = EntryAPI(client: client, ownerID: ownerID)
    let marker = String(UUID().uuidString.prefix(8)).lowercased()
    let created = try await savedEntry("Two devices \(marker)", client: client, ownerID: ownerID)
    let opened = try await XCTUnwrapAsync(try await api.editable(created.entryID))
    let editor = EntryEditorController(client: client, ownerID: ownerID, mode: .edit(opened))

    // Another device saves first.
    let elsewhere = try await api.save(
      SaveEntryParameters(
        entryID: opened.id, expectedRevision: opened.revision, title: "Edited elsewhere",
        body: opened.body, richText: nil,
        occurrence: opened.occurrence(fallbackTimezone: "UTC"), tagNames: [], location: nil,
        marks: .none))
    XCTAssertEqual(elsewhere.revision, 2)

    editor.draft.title = "Edited here \(marker)"
    let outcome = await editor.save()
    XCTAssertEqual(outcome, .failed)
    XCTAssertEqual(
      editor.errorMessage,
      "This Entry changed on another device. Close it, refresh, and edit the latest version.")
    XCTAssertEqual(editor.draft.revision, 1)
    let current = try await XCTUnwrapAsync(try await api.editable(opened.id))
    XCTAssertEqual(current.title, "Edited elsewhere")
    XCTAssertEqual(current.revision, 2)

    // Move to Trash from the stale editor is refused too, and the Entry stays.
    let trashed = await editor.moveToTrash()
    XCTAssertFalse(trashed)
    XCTAssertNotNil(editor.errorMessage)
    let stillThere = try await api.editable(opened.id)
    XCTAssertNotNil(stillThere)
  }
}
