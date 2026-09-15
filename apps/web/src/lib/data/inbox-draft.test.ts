import { describe, expect, it } from "vitest";
import {
  clearInboxDraft,
  inboxDraftKey,
  loadInboxDraft,
  parseInboxDraft,
  persistInboxDraft,
  type DraftStorage,
} from "./inbox-draft";
import { createEntryRichText, plainTextDocument } from "./rich-text";

class MemoryStorage implements DraftStorage {
  private values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  removeItem(key: string) {
    this.values.delete(key);
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

describe("Inbox draft persistence", () => {
  it("keeps an unfinished date and photo-only date draft without guessing an instant", () => {
    const storage = new MemoryStorage();
    const occurrence = {
      precision: "year" as const,
      start: "20",
      end: "",
      label: "",
      timezone: "Asia/Kathmandu",
    };
    expect(
      persistInboxDraft(storage, "owner", {
        body: "",
        title: "",
        occurredAt: null,
        occurrence,
      }),
    ).toBe(true);
    expect(loadInboxDraft(storage, "owner")).toMatchObject({
      version: 3,
      occurredAt: null,
      occurrence,
    });
    expect(loadInboxDraft(storage, "another-owner")).toBeNull();
    persistInboxDraft(storage, "owner", {
      body: "Text remains",
      title: "",
      occurredAt: null,
      occurrence: null,
    });
    expect(loadInboxDraft(storage, "owner")).toMatchObject({
      occurrence: null,
      body: "Text remains",
    });
  });

  it("rejects malformed v3 date shapes rather than silently dropping uncertainty", () => {
    const storage = new MemoryStorage();
    const data = {
      version: 3,
      body: "Original",
      title: "",
      occurredAt: null,
      updatedAt: new Date().toISOString(),
    };
    for (const occurrence of [
      { precision: "invalid" },
      { precision: "age", start: "", end: "", label: 17, timezone: "UTC" },
    ]) {
      storage.setItem(
        inboxDraftKey("owner"),
        JSON.stringify({ ...data, occurrence }),
      );
      expect(loadInboxDraft(storage, "owner")).toBeNull();
    }
  });
  it("keeps drafts isolated by MemoTrail owner", () => {
    const storage = new MemoryStorage();

    persistInboxDraft(storage, "owner-a", {
      body: "A private thought",
      occurredAt: null,
      title: "",
    });

    expect(loadInboxDraft(storage, "owner-a")?.body).toBe("A private thought");
    expect(loadInboxDraft(storage, "owner-b")).toBeNull();
    expect(inboxDraftKey("owner/a")).not.toBe(inboxDraftKey("owner-a"));
  });

  it("restores rich formatting only while it matches the draft text", () => {
    const storage = new MemoryStorage();
    const bodyRich = createEntryRichText(plainTextDocument("Formatted draft"));

    persistInboxDraft(storage, "owner", {
      body: "Formatted draft",
      bodyRich,
      occurredAt: null,
      title: "",
    });
    expect(loadInboxDraft(storage, "owner")?.bodyRich).toEqual(bodyRich);

    const stored = JSON.parse(storage.getItem(inboxDraftKey("owner"))!);
    storage.setItem(
      inboxDraftKey("owner"),
      JSON.stringify({ ...stored, body: "Changed elsewhere" }),
    );
    expect(loadInboxDraft(storage, "owner")).toBeNull();
  });

  it("preserves whitespace and clears empty drafts", () => {
    const storage = new MemoryStorage();

    expect(
      persistInboxDraft(storage, "owner-a", {
        body: "  Keep my spacing.\n",
        occurredAt: "2026-07-03T09:30",
        title: " Draft title ",
      }),
    ).toBe(true);
    expect(loadInboxDraft(storage, "owner-a")).toMatchObject({
      body: "  Keep my spacing.\n",
      occurredAt: "2026-07-03T09:30",
      title: " Draft title ",
      version: 2,
    });

    expect(
      persistInboxDraft(storage, "owner-a", {
        body: "",
        occurredAt: null,
        title: "",
      }),
    ).toBe(false);
    expect(loadInboxDraft(storage, "owner-a")).toBeNull();
  });

  it("clears a saved draft after the Entry is accepted", () => {
    const storage = new MemoryStorage();
    persistInboxDraft(storage, "owner-a", {
      body: "Keep me",
      occurredAt: null,
      title: "",
    });

    clearInboxDraft(storage, "owner-a");

    expect(loadInboxDraft(storage, "owner-a")).toBeNull();
  });

  it("ignores malformed, obsolete, and oversized stored data", () => {
    expect(parseInboxDraft("not json")).toBeNull();
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "content",
          title: "",
          updatedAt: new Date().toISOString(),
          version: 3,
        }),
      ),
    ).toBeNull();
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "content",
          title: "t".repeat(201),
          updatedAt: new Date().toISOString(),
          version: 1,
        }),
      ),
    ).toBeNull();
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "content",
          occurredAt: "not-a-date",
          title: "",
          updatedAt: new Date().toISOString(),
          version: 2,
        }),
      ),
    ).toBeNull();
  });

  it("migrates a version one text draft without inventing a date", () => {
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "An earlier draft",
          title: "",
          updatedAt: "2026-09-01T15:00:00.000Z",
          version: 1,
        }),
      ),
    ).toEqual({
      body: "An earlier draft",
      occurredAt: null,
      title: "",
      updatedAt: "2026-09-01T15:00:00.000Z",
      version: 2,
    });
  });
});
