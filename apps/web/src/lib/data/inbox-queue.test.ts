import { describe, expect, it, vi } from "vitest";
import {
  enqueueInboxEntry,
  inboxQueueKey,
  loadInboxQueue,
  parseInboxQueue,
  type QueuedInboxEntry,
  removeInboxQueueEntry,
} from "./inbox-queue";

function queuedEntry(
  overrides: Partial<QueuedInboxEntry> = {},
): QueuedInboxEntry {
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
