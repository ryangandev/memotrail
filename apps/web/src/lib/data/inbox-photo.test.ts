import { describe, expect, it, vi } from "vitest";
import {
  inboxPhotoLimit,
  inboxPhotoSizeLimit,
  isQueuedInboxAttachment,
  queuedInboxAttachment,
  validateInboxPhotoFiles,
} from "./inbox-photo";

describe("Inbox photos", () => {
  it("accepts supported photos and preserves queue metadata", () => {
    vi.spyOn(crypto, "randomUUID").mockReturnValue(
      "1c4aa86d-0ed9-47d5-838e-1adfc1d45bbb",
    );
    const file = new File(["photo"], "first-snow.webp", {
      lastModified: 1_788_000_000_000,
      type: "image/webp",
    });
    const result = validateInboxPhotoFiles([file], 0);

    expect(result.message).toBeNull();
    expect(result.accepted).toHaveLength(1);
    expect(queuedInboxAttachment(result.accepted[0])).toEqual({
      id: "1c4aa86d-0ed9-47d5-838e-1adfc1d45bbb",
      lastModified: 1_788_000_000_000,
      mimeType: "image/webp",
      name: "first-snow.webp",
      size: 5,
    });
  });

  it("infers camera formats and rejects unsupported or oversized files", () => {
    const heic = new File(["photo"], "IMG_0101.HEIC");
    const invalid = new File(["photo"], "notes.txt", {
      type: "text/plain",
    });
    const oversized = new File(["x"], "huge.jpg", { type: "image/jpeg" });
    Object.defineProperty(oversized, "size", {
      value: inboxPhotoSizeLimit + 1,
    });

    expect(validateInboxPhotoFiles([heic], 0).accepted[0].mimeType).toBe(
      "image/heic",
    );
    expect(validateInboxPhotoFiles([invalid], 0).accepted).toEqual([]);
    expect(validateInboxPhotoFiles([oversized], 0).accepted).toEqual([]);
  });

  it("enforces the Entry photo limit", () => {
    const file = new File(["photo"], "memory.jpg", { type: "image/jpeg" });
    const result = validateInboxPhotoFiles([file], inboxPhotoLimit);

    expect(result.accepted).toEqual([]);
    expect(result.message).toContain(`${inboxPhotoLimit}`);
  });

  it("fails closed for invalid queued metadata", () => {
    const valid = {
      id: "1c4aa86d-0ed9-47d5-838e-1adfc1d45bbb",
      lastModified: 1_788_000_000_000,
      mimeType: "image/png",
      name: "memory.png",
      size: 2048,
    };

    expect(isQueuedInboxAttachment(valid)).toBe(true);
    expect(isQueuedInboxAttachment({ ...valid, mimeType: "image/gif" })).toBe(
      false,
    );
    expect(isQueuedInboxAttachment({ ...valid, size: 0 })).toBe(false);
  });
});
