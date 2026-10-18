import { describe, expect, it } from "vitest";
import {
  clearInboxDraft,
  inboxDraftKey,
  inboxDraftQuarantineKey,
  inspectInboxDraft,
  loadInboxDraft,
  parseInboxDraft,
  persistInboxDraft,
  type DraftStorage,
} from "./inbox-draft";
import { createEntryRichText, plainTextDocument } from "./rich-text";

class MemoryStorage implements DraftStorage {
  values = new Map<string, string>();

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

describe("A draft that no longer validates", () => {
  const longBody = "Words I wrote offline. ".repeat(3000);

  function seedOverlongDraft(storage: MemoryStorage) {
    storage.setItem(
      inboxDraftKey("owner"),
      JSON.stringify({
        body: longBody,
        occurredAt: null,
        title: "Kept title",
        updatedAt: "2026-09-01T15:00:00.000Z",
        version: 2,
      }),
    );
  }

  it("still shows the writing it can read", () => {
    const storage = new MemoryStorage();
    seedOverlongDraft(storage);

    const draft = loadInboxDraft(storage, "owner");

    expect(draft?.title).toBe("Kept title");
    expect(draft?.body.length).toBeGreaterThan(0);
    expect(longBody.startsWith(draft!.body)).toBe(true);
  });

  it("is kept aside before the next keystroke replaces it", () => {
    const storage = new MemoryStorage();
    seedOverlongDraft(storage);

    persistInboxDraft(storage, "owner", {
      body: "A",
      occurredAt: null,
      title: "",
    });

    expect([...storage.values.values()].join("\n")).toContain(longBody);
  });

  it("is kept aside before the draft is cleared", () => {
    const storage = new MemoryStorage();
    seedOverlongDraft(storage);

    clearInboxDraft(storage, "owner");

    expect(storage.getItem(inboxDraftKey("owner"))).toBeNull();
    expect([...storage.values.values()].join("\n")).toContain(longBody);
  });

  it("is never replaced when it cannot be kept aside", () => {
    const storage = new MemoryStorage();
    seedOverlongDraft(storage);
    const original = storage.getItem(inboxDraftKey("owner"));
    const setItem = storage.setItem.bind(storage);
    storage.setItem = (key, value) => {
      if (key !== inboxDraftKey("owner")) throw new Error("Quota exceeded");
      setItem(key, value);
    };

    expect(
      persistInboxDraft(storage, "owner", {
        body: "A",
        occurredAt: null,
        title: "",
      }),
    ).toBe(false);
    clearInboxDraft(storage, "owner");

    expect(storage.getItem(inboxDraftKey("owner"))).toBe(original);
  });

  it("does not keep a draft aside that this device wrote itself", () => {
    const storage = new MemoryStorage();

    persistInboxDraft(storage, "owner", {
      body: "First",
      occurredAt: null,
      title: "",
    });
    persistInboxDraft(storage, "owner", {
      body: "Second",
      occurredAt: null,
      title: "",
    });
    clearInboxDraft(storage, "owner");

    expect(storage.getItem(inboxDraftQuarantineKey("owner"))).toBeNull();
  });

  it("keeps what can be read of each kind of damage", () => {
    const base = {
      body: "Body",
      occurredAt: null,
      title: "Title",
      updatedAt: "2026-09-01T15:00:00.000Z",
      version: 2,
    };
    const parsed = (changes: object) =>
      inspectInboxDraft(JSON.stringify({ ...base, ...changes }));

    expect(parsed({ version: 9 })).toMatchObject({
      draft: { body: "Body", title: "Title" },
      isComplete: false,
    });
    expect(parsed({ title: "t".repeat(201) }).draft?.title).toHaveLength(200);
    expect(parsed({ occurredAt: "not-a-date" })).toMatchObject({
      draft: { body: "Body", occurredAt: null },
      isComplete: false,
    });
    expect(parsed({ updatedAt: "yesterday" })).toMatchObject({
      draft: { body: "Body" },
      isComplete: false,
    });
    const mismatched = parsed({
      bodyRich: { document: { type: "doc" }, text: "Other", version: 1 },
    });
    expect(mismatched).toMatchObject({
      draft: { body: "Body" },
      isComplete: false,
    });
    expect(mismatched.draft).not.toHaveProperty("bodyRich");
    expect(
      parsed({ version: 3, occurrence: { precision: "invalid" } }),
    ).toMatchObject({
      draft: { body: "Body", version: 2 },
      isComplete: false,
    });
    expect(inspectInboxDraft("not json")).toEqual({
      draft: null,
      isComplete: false,
    });
    expect(inspectInboxDraft(JSON.stringify({ body: 4 }))).toEqual({
      draft: null,
      isComplete: false,
    });
    expect(inspectInboxDraft(JSON.stringify(base))).toMatchObject({
      isComplete: true,
    });
  });
});

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

  it("restores the writing of a draft whose v3 date shape is malformed, without inventing a date", () => {
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
      expect(loadInboxDraft(storage, "owner")).toMatchObject({
        body: "Original",
        occurredAt: null,
        version: 2,
      });
      expect(loadInboxDraft(storage, "owner")?.occurrence).toBeUndefined();
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
    expect(loadInboxDraft(storage, "owner")).toMatchObject({
      body: "Changed elsewhere",
    });
    expect(loadInboxDraft(storage, "owner")?.bodyRich).toBeUndefined();
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

  it("reads nothing from unusable stored data and keeps what is usable from the rest", () => {
    expect(parseInboxDraft("not json")).toBeNull();
    expect(parseInboxDraft("[]")).toBeNull();
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "content",
          title: "",
          updatedAt: new Date().toISOString(),
          version: 3,
        }),
      ),
    ).toMatchObject({ body: "content", version: 2 });
    expect(
      parseInboxDraft(
        JSON.stringify({
          body: "content",
          title: "t".repeat(201),
          updatedAt: new Date().toISOString(),
          version: 1,
        }),
      ),
    ).toMatchObject({ body: "content", title: "t".repeat(200) });
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
    ).toMatchObject({ body: "content", occurredAt: null });
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
