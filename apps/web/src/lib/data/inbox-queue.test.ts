import { describe, expect, it, vi } from "vitest";
import {
  enqueueInboxEntry,
  inboxQueueKey,
  loadInboxQueue,
  parseInboxQueue,
  type QueuedInboxEntry,
  rejectInboxQueueEntry,
  removeInboxQueueEntry,
  queuedOccurrence,
  queuedRejection,
  isQueuedInboxEntry,
  discardUnreadableCapture,
  inboxQuarantineKey,
  loadUnreadableCaptures,
  unreadableAttachmentIds,
} from "./inbox-queue";
import { occurrencePrecisions, resolveOccurrenceDraft } from "./occurrence";
import { createEntryRichText, plainTextDocument } from "./rich-text";

describe("Precision-aware offline capture", () => {
  for (const precision of occurrencePrecisions)
    it(`replays ${precision} without inventing bounds`, () => {
      const result = resolveOccurrenceDraft({
        precision,
        start: ["age", "approximate", "unknown"].includes(precision)
          ? ""
          : precision === "year"
            ? "2017"
            : precision === "month"
              ? "2017-07"
              : precision === "exact"
                ? "2017-07-08T12:34:56"
                : "2017-07-08",
        end: precision === "range" ? "2018-08-09" : "",
        label: ["age", "approximate"].includes(precision) ? "At age 17" : "",
        timezone: "Asia/Kathmandu",
      });
      expect(result.error).toBeUndefined();
      const entry: QueuedInboxEntry = {
        ...queuedEntry(),
        ...result.value!,
        version: 3,
      };
      expect(isQueuedInboxEntry(entry)).toBe(true);
      const stored = parseInboxQueue(JSON.stringify([entry])).entries;
      expect(stored).toEqual([entry]);
      expect(queuedOccurrence(stored[0])).toMatchObject(result.value!);
    });
  it("rejects inconsistent unknown dates and invalid zones at the sync boundary", () => {
    const entry = {
      ...queuedEntry(),
      version: 3,
      datePrecision: "unknown",
      occurredEnd: null,
      occurredLabel: null,
    };
    expect(isQueuedInboxEntry(entry)).toBe(false);
    expect(
      isQueuedInboxEntry({
        ...entry,
        occurredAt: null,
        occurredTimezone: "invalid/zone",
      }),
    ).toBe(false);
    expect(isQueuedInboxEntry({ ...entry, occurredAt: null })).toBe(true);
  });
});

function queuedEntry(
  overrides: Partial<Extract<QueuedInboxEntry, { version: 2 }>> = {},
): Extract<QueuedInboxEntry, { version: 2 }> {
  return {
    attachments: [],
    body: "A thought worth keeping.",
    id: "f4d2df16-a506-4be6-a63e-b7b18afe3468",
    occurredAt: "2026-09-01T15:00:00.000Z",
    occurredTimezone: "America/Los_Angeles",
    queuedAt: "2026-09-01T15:00:00.000Z",
    title: null,
    version: 2,
    ...overrides,
  };
}

function memoryStorage() {
  const values = new Map<string, string>();

  return {
    values,
    getItem: vi.fn((key: string) => values.get(key) ?? null),
    removeItem: vi.fn((key: string) => values.delete(key)),
    setItem: vi.fn((key: string, value: string) => values.set(key, value)),
  };
}

describe("Inbox synchronization queue", () => {
  it("keeps validated rich formatting beside the plaintext body", () => {
    const storage = memoryStorage();
    const bodyRich = createEntryRichText(
      plainTextDocument("A thought worth keeping."),
    );
    const entry = queuedEntry({ bodyRich });

    expect(enqueueInboxEntry(storage, "owner-a", entry)).toEqual([entry]);
    expect(loadInboxQueue(storage, "owner-a")[0].bodyRich).toEqual(bodyRich);
    expect(
      parseInboxQueue(JSON.stringify([{ ...entry, body: "A different body." }]))
        .entries,
    ).toEqual([]);
  });

  it("accepts Tiptap link attributes at the server boundary", () => {
    const entry = queuedEntry({
      bodyRich: {
        document: {
          type: "doc",
          content: [
            {
              type: "paragraph",
              content: [
                {
                  type: "text",
                  marks: [
                    {
                      type: "link",
                      attrs: {
                        href: "https://example.com/memory",
                        target: "_blank",
                        rel: "noopener noreferrer",
                        class: null,
                        title: null,
                      },
                    },
                    { type: "bold" },
                  ],
                  text: "A thought worth keeping.",
                },
              ],
            },
          ],
        },
        text: "A thought worth keeping.",
        version: 1,
      },
    });

    expect(isQueuedInboxEntry(entry)).toBe(true);
  });

  it("keeps queued Entries isolated by MemoTrail user", () => {
    const storage = memoryStorage();
    const entry = queuedEntry();

    expect(enqueueInboxEntry(storage, "owner-a", entry)).toEqual([entry]);
    expect(loadInboxQueue(storage, "owner-a")).toEqual([entry]);
    expect(loadInboxQueue(storage, "owner-b")).toEqual([]);
  });

  it("does not duplicate a retry with the same Entry ID", () => {
    const storage = memoryStorage();
    const entry = queuedEntry();

    enqueueInboxEntry(storage, "owner-a", entry);

    expect(enqueueInboxEntry(storage, "owner-a", entry)).toEqual([entry]);
  });

  it("removes only the Entry confirmed by the server", () => {
    const storage = memoryStorage();
    const first = queuedEntry();
    const second = queuedEntry({
      id: "a220e8e7-1228-4490-9a66-4e71e35879d8",
      title: "Second thought",
    });

    enqueueInboxEntry(storage, "owner-a", first);
    enqueueInboxEntry(storage, "owner-a", second);

    expect(removeInboxQueueEntry(storage, "owner-a", first.id)).toEqual([
      second,
    ]);
  });

  it("sets aside malformed, future, and conflicting stored items instead of dropping them", () => {
    expect(parseInboxQueue("not json")).toEqual({
      entries: [],
      unreadable: ["not json"],
    });
    const future = { ...queuedEntry(), version: 3 };
    expect(parseInboxQueue(JSON.stringify([future]))).toEqual({
      entries: [],
      unreadable: [future],
    });
    // An identical copy is the same capture; a different one must not be lost.
    expect(
      parseInboxQueue(JSON.stringify([queuedEntry(), queuedEntry()])),
    ).toEqual({ entries: [queuedEntry()], unreadable: [] });
    const conflicting = queuedEntry({ body: "Another version." });
    expect(
      parseInboxQueue(JSON.stringify([queuedEntry(), conflicting])),
    ).toEqual({ entries: [queuedEntry()], unreadable: [conflicting] });
  });

  it("keeps every capture of a queue past the usual size limit", () => {
    const entries = Array.from({ length: 101 }, (_, index) =>
      queuedEntry({
        id: `f4d2df16-a506-4be6-a63e-${String(index).padStart(12, "0")}`,
      }),
    );
    const parsed = parseInboxQueue(JSON.stringify(entries));

    expect(parsed.entries).toHaveLength(101);
    expect(parsed.unreadable).toEqual([]);
  });

  it("migrates the text-only version 1 queue", () => {
    const current = queuedEntry();
    const legacy = {
      body: current.body,
      id: current.id,
      occurredAt: current.occurredAt,
      occurredTimezone: current.occurredTimezone,
      queuedAt: current.queuedAt,
      title: current.title,
      version: 1,
    };

    expect(parseInboxQueue(JSON.stringify([legacy])).entries).toEqual([
      { ...legacy, attachments: [], version: 2 },
    ]);
  });

  it("accepts photo-only Entries and rejects repeated attachment IDs", () => {
    const attachment = {
      id: "1c4aa86d-0ed9-47d5-838e-1adfc1d45bbb",
      lastModified: 1_788_000_000_000,
      mimeType: "image/jpeg" as const,
      name: "memory.jpg",
      size: 2048,
    };
    const photoOnly = queuedEntry({
      attachments: [attachment],
      body: "",
      title: null,
    });

    expect(parseInboxQueue(JSON.stringify([photoOnly])).entries).toEqual([
      photoOnly,
    ]);
    expect(
      parseInboxQueue(
        JSON.stringify([
          { ...photoOnly, attachments: [attachment, attachment] },
        ]),
      ).entries,
    ).toEqual([]);
  });

  it("leaves the existing queue intact when browser storage rejects a write", () => {
    const storage = memoryStorage();
    storage.setItem.mockImplementation(() => {
      throw new Error("Quota exceeded");
    });

    expect(enqueueInboxEntry(storage, "owner-a", queuedEntry())).toBeNull();
    expect(storage.removeItem).not.toHaveBeenCalledWith(
      inboxQueueKey("owner-a"),
    );
  });
});

describe("Unreadable captures in the queue", () => {
  const unreadableId = "9b2b6c1e-8f35-4c63-8d57-4a8d1d0a3c11";
  const unreadableBody = "Something I wrote offline that I must not lose.";

  function seedMixedQueue(storage: ReturnType<typeof memoryStorage>) {
    const valid = queuedEntry();
    // Valid when it was queued; a later release tightened a rule it now breaks.
    const stale = {
      ...queuedEntry({ id: unreadableId }),
      body: unreadableBody,
      occurredAt: "not a date",
    };
    storage.setItem(inboxQueueKey("owner-a"), JSON.stringify([stale, valid]));
    return { stale, valid };
  }

  function everythingStored(storage: ReturnType<typeof memoryStorage>) {
    return [...storage.values.values()].join("\n");
  }

  it("never loses the writing of a capture that no longer validates", () => {
    const storage = memoryStorage();
    const { valid } = seedMixedQueue(storage);

    enqueueInboxEntry(
      storage,
      "owner-a",
      queuedEntry({ id: "a220e8e7-1228-4490-9a66-4e71e35879d8" }),
    );
    removeInboxQueueEntry(storage, "owner-a", valid.id);

    expect(everythingStored(storage)).toContain(unreadableBody);
  });

  it("reads past an unreadable capture without writing anything", () => {
    const storage = memoryStorage();
    const { valid } = seedMixedQueue(storage);
    storage.setItem.mockClear();

    const parsed = parseInboxQueue(storage.getItem(inboxQueueKey("owner-a")));

    expect(parsed.entries).toEqual([valid]);
    expect(parsed.unreadable).toHaveLength(1);
    expect(loadInboxQueue(storage, "owner-a")).toEqual([valid]);
    expect(storage.setItem).not.toHaveBeenCalled();
    expect(storage.removeItem).not.toHaveBeenCalled();
  });

  it("keeps a queue that is not valid JSON, and its writing, through later captures", () => {
    const storage = memoryStorage();
    const damaged = `[{"body":"${unreadableBody}"`;
    storage.setItem(inboxQueueKey("owner-a"), damaged);

    expect(loadUnreadableCaptures(storage, "owner-a")).toEqual([
      { key: JSON.stringify(damaged), text: damaged, value: damaged },
    ]);
    const entry = queuedEntry();
    expect(enqueueInboxEntry(storage, "owner-a", entry)).toEqual([entry]);

    expect(loadInboxQueue(storage, "owner-a")).toEqual([entry]);
    expect(loadUnreadableCaptures(storage, "owner-a")).toHaveLength(1);
    expect(everythingStored(storage)).toContain(unreadableBody);
  });

  it("offers the title and body of an unreadable capture to copy", () => {
    const storage = memoryStorage();
    seedMixedQueue(storage);

    const [capture] = loadUnreadableCaptures(storage, "owner-a");

    expect(capture.text).toBe(unreadableBody);
  });

  it("never writes the queue when the unreadable items cannot be set aside", () => {
    const storage = memoryStorage();
    const { stale, valid } = seedMixedQueue(storage);
    const before = storage.getItem(inboxQueueKey("owner-a"));
    storage.setItem.mockImplementation(() => {
      throw new Error("Quota exceeded");
    });

    expect(
      enqueueInboxEntry(
        storage,
        "owner-a",
        queuedEntry({ id: "a220e8e7-1228-4490-9a66-4e71e35879d8" }),
      ),
    ).toBeNull();
    expect(removeInboxQueueEntry(storage, "owner-a", valid.id)).toBeNull();
    expect(storage.getItem(inboxQueueKey("owner-a"))).toBe(before);
    expect(storage.removeItem).not.toHaveBeenCalled();
    expect(JSON.parse(before!)).toContainEqual(stale);
  });

  it("keeps an unreadable capture across later syncs and sets it aside once", () => {
    const storage = memoryStorage();
    const { valid } = seedMixedQueue(storage);

    removeInboxQueueEntry(storage, "owner-a", valid.id);
    removeInboxQueueEntry(storage, "owner-a", valid.id);

    expect(storage.getItem(inboxQueueKey("owner-a"))).toBeNull();
    expect(
      JSON.parse(storage.getItem(inboxQuarantineKey("owner-a"))!),
    ).toHaveLength(1);
    expect(loadUnreadableCaptures(storage, "owner-a")).toHaveLength(1);
  });

  it("discards only the unreadable capture the person chose", () => {
    const storage = memoryStorage();
    const { valid } = seedMixedQueue(storage);
    const other = { id: "not-a-uuid", body: "Another unreadable one." };
    storage.setItem(
      inboxQueueKey("owner-a"),
      JSON.stringify([
        ...JSON.parse(storage.getItem(inboxQueueKey("owner-a"))!),
        other,
      ]),
    );
    const [first, second] = loadUnreadableCaptures(storage, "owner-a");

    expect(discardUnreadableCapture(storage, "owner-a", first.key)).toBe(true);

    expect(loadUnreadableCaptures(storage, "owner-a")).toEqual([second]);
    expect(loadInboxQueue(storage, "owner-a")).toEqual([valid]);
    expect(discardUnreadableCapture(storage, "owner-a", second.key)).toBe(true);
    expect(loadUnreadableCaptures(storage, "owner-a")).toEqual([]);
    expect(storage.getItem(inboxQuarantineKey("owner-a"))).toBeNull();
    expect(loadInboxQueue(storage, "owner-a")).toEqual([valid]);
  });

  it("names the photos an unreadable capture holds", () => {
    expect(
      unreadableAttachmentIds({
        attachments: [{ id: "photo-1" }, { id: 4 }, null, { id: "photo-2" }],
      }),
    ).toEqual(["photo-1", "photo-2"]);
    expect(unreadableAttachmentIds("text")).toEqual([]);
    expect(unreadableAttachmentIds({ attachments: "none" })).toEqual([]);
  });
});

describe("Rejected captures in the queue", () => {
  const rejection = {
    message: "MemoTrail cannot accept this Entry, so it will not sync.",
    rejectedAt: "2026-10-03T12:00:00.000Z",
  };

  it("marks a rejected capture in place and keeps its content and order", () => {
    const storage = memoryStorage();
    const bodyRich = createEntryRichText(
      plainTextDocument("A thought worth keeping."),
    );
    const first = queuedEntry({ bodyRich });
    const second = queuedEntry({
      id: "a220e8e7-1228-4490-9a66-4e71e35879d8",
      title: "Second thought",
    });
    enqueueInboxEntry(storage, "owner-a", first);
    enqueueInboxEntry(storage, "owner-a", second);

    expect(
      rejectInboxQueueEntry(storage, "owner-a", first.id, rejection),
    ).toEqual([{ ...first, rejection }, second]);

    // The marker survives a reload, so a later page never sends it again.
    const stored = loadInboxQueue(storage, "owner-a");
    expect(stored).toEqual([{ ...first, rejection }, second]);
    expect(queuedRejection(stored[0])).toEqual(rejection);
    expect(queuedRejection(stored[1])).toBeNull();
  });

  it("does not bring back a capture another tab already removed", () => {
    const storage = memoryStorage();
    const entry = queuedEntry();

    expect(
      rejectInboxQueueEntry(storage, "owner-a", entry.id, rejection),
    ).toEqual([]);
    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it("reports a rejection browser storage cannot keep", () => {
    const storage = memoryStorage();
    const entry = queuedEntry();
    enqueueInboxEntry(storage, "owner-a", entry);
    storage.setItem.mockImplementationOnce(() => {
      throw new Error("Quota exceeded");
    });

    expect(
      rejectInboxQueueEntry(storage, "owner-a", entry.id, rejection),
    ).toBeNull();
    expect(loadInboxQueue(storage, "owner-a")).toEqual([entry]);
  });

  it("keeps a capture whose rejection marker is malformed, so it can sync again", () => {
    for (const malformed of [
      null,
      "rejected",
      { message: "", rejectedAt: rejection.rejectedAt },
      { message: "x".repeat(501), rejectedAt: rejection.rejectedAt },
      { message: rejection.message, rejectedAt: "yesterday" },
      { message: rejection.message },
    ]) {
      const [stored] = parseInboxQueue(
        JSON.stringify([{ ...queuedEntry(), rejection: malformed }]),
      ).entries;
      expect(stored.id).toBe(queuedEntry().id);
      expect(queuedRejection(stored)).toBeNull();
    }
  });
});
