import { describe, expect, it, vi } from "vitest";
import {
  enqueueInboxEntry,
  inboxQueueKey,
  loadInboxQueue,
  parseInboxQueue,
  type QueuedInboxEntry,
  removeInboxQueueEntry,
  queuedOccurrence,
  isQueuedInboxEntry,
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
      const stored = parseInboxQueue(JSON.stringify([entry]));
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
      parseInboxQueue(
        JSON.stringify([{ ...entry, body: "A different body." }]),
      ),
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

  it("fails closed for malformed, oversized, and duplicate stored queues", () => {
    expect(parseInboxQueue("not json")).toEqual([]);
    expect(
      parseInboxQueue(JSON.stringify([{ ...queuedEntry(), version: 3 }])),
    ).toEqual([]);
    expect(
      parseInboxQueue(JSON.stringify([queuedEntry(), queuedEntry()])),
    ).toEqual([]);
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

    expect(parseInboxQueue(JSON.stringify([legacy]))).toEqual([
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

    expect(parseInboxQueue(JSON.stringify([photoOnly]))).toEqual([photoOnly]);
    expect(
      parseInboxQueue(
        JSON.stringify([
          { ...photoOnly, attachments: [attachment, attachment] },
        ]),
      ),
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
