import { describe, expect, it } from "vitest";
import {
  clearInboxDraft,
  inboxDraftKey,
  loadInboxDraft,
  parseInboxDraft,
  persistInboxDraft,
  type DraftStorage,
} from "./inbox-draft";

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
  it("keeps drafts isolated by MemoTrail owner", () => {
    const storage = new MemoryStorage();

    persistInboxDraft(storage, "owner-a", {
      body: "A private thought",
      title: "",
    });

    expect(loadInboxDraft(storage, "owner-a")?.body).toBe("A private thought");
    expect(loadInboxDraft(storage, "owner-b")).toBeNull();
    expect(inboxDraftKey("owner/a")).not.toBe(inboxDraftKey("owner-a"));
  });

  it("preserves whitespace and clears empty drafts", () => {
    const storage = new MemoryStorage();

    expect(
      persistInboxDraft(storage, "owner-a", {
        body: "  Keep my spacing.\n",
        title: " Draft title ",
      }),
    ).toBe(true);
    expect(loadInboxDraft(storage, "owner-a")).toMatchObject({
      body: "  Keep my spacing.\n",
      title: " Draft title ",
      version: 1,
    });

    expect(persistInboxDraft(storage, "owner-a", { body: "", title: "" })).toBe(
      false,
    );
    expect(loadInboxDraft(storage, "owner-a")).toBeNull();
  });

  it("clears a saved draft after the Entry is accepted", () => {
    const storage = new MemoryStorage();
    persistInboxDraft(storage, "owner-a", { body: "Keep me", title: "" });

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
          version: 2,
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
  });
});
