import { describe, expect, it } from "vitest";
import {
  createFirstTimeObjectPath,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
  isFirstTimeEntryIdentity,
  normalizeFirstTimeImageMimeType,
  parseFirstTimeAttachmentInput,
  parseFirstTimeEntryInput,
} from "./first-time-input";

const ownerId = "10000000-0000-0000-0000-000000000001";
const entryId = "40000000-0000-4000-8000-000000000001";
const attachmentId = "60000000-0000-4000-8000-000000000001";

describe("parseFirstTimeEntryInput", () => {
  it("accepts and trims a title-only First Time", () => {
    expect(
      parseFirstTimeEntryInput({
        body: "  ",
        collectionNames: [],
        datePrecision: "unknown",
        id: null,
        occurredLabel: null,
        occurredStart: null,
        occurredTimezone: null,
        revision: null,
        tagNames: [],
        title: "  First ocean swim  ",
      }),
    ).toEqual({
      data: {
        body: "",
        collectionNames: [],
        datePrecision: "unknown",
        id: null,
        occurredLabel: null,
        occurredStart: null,
        occurredTimezone: null,
        revision: null,
        tagNames: [],
        title: "First ocean swim",
      },
      success: true,
    });
  });

  it("normalizes dated content and organization", () => {
    const parsed = parseFirstTimeEntryInput({
      body: "  A cold, clear morning. ",
      collectionNames: [" Travel ", "travel"],
      datePrecision: "day",
      id: entryId,
      occurredLabel: "  July 3, 2026 ",
      occurredStart: "2026-07-03T19:00:00-07:00",
      occurredTimezone: " America/Los_Angeles ",
      revision: 3,
      tagNames: [" snow ", "Snow"],
      title: " First time skiing ",
    });

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data).toMatchObject({
        collectionNames: ["Travel"],
        occurredLabel: "July 3, 2026",
        occurredStart: "2026-07-04T02:00:00.000Z",
        occurredTimezone: "America/Los_Angeles",
        tagNames: ["snow"],
      });
    }
  });

  it("requires a title", () => {
    const parsed = parseFirstTimeEntryInput({
      body: "A note",
      collectionNames: [],
      datePrecision: "unknown",
      id: null,
      occurredLabel: null,
      occurredStart: null,
      occurredTimezone: null,
      revision: null,
      tagNames: [],
      title: " ",
    });

    expect(parsed).toMatchObject({ success: false });
  });

  it("requires a date for exact precision", () => {
    const parsed = parseFirstTimeEntryInput({
      body: "",
      collectionNames: [],
      datePrecision: "day",
      id: null,
      occurredLabel: null,
      occurredStart: null,
      occurredTimezone: null,
      revision: null,
      tagNames: [],
      title: "First concert",
    });

    expect(parsed).toMatchObject({ success: false });
  });

  it("accepts an age label without inventing an exact date", () => {
    const parsed = parseFirstTimeEntryInput({
      body: "",
      collectionNames: [],
      datePrecision: "age",
      id: null,
      occurredLabel: "Age 7",
      occurredStart: null,
      occurredTimezone: null,
      revision: null,
      tagNames: [],
      title: "First flight",
    });

    expect(parsed).toMatchObject({ success: true });
  });

  it("rejects a stale or mismatched identity shape", () => {
    expect(isFirstTimeEntryIdentity(entryId, null)).toBe(false);
    expect(isFirstTimeEntryIdentity(null, 1)).toBe(false);
    expect(isFirstTimeEntryIdentity(entryId, 1)).toBe(true);
    expect(isFirstTimeEntryIdentity(null, null)).toBe(true);
  });
});

describe("First Time photos", () => {
  it("builds a private owner and Entry scoped object path", () => {
    expect(
      createFirstTimeObjectPath(ownerId, entryId, attachmentId, "image/jpeg"),
    ).toBe(`${ownerId}/${entryId}/${attachmentId}.jpg`);
  });

  it("normalizes supported MIME types", () => {
    expect(normalizeFirstTimeImageMimeType(" IMAGE/HEIC ")).toBe("image/heic");
    expect(normalizeFirstTimeImageMimeType("image/gif")).toBeNull();
    expect(inferFirstTimeImageMimeType("IMG_1001.HEIC", "")).toBe("image/heic");
  });

  it("rejects an unsafe object path identity", () => {
    expect(
      createFirstTimeObjectPath(
        "not-a-user",
        entryId,
        attachmentId,
        "image/png",
      ),
    ).toBeNull();
  });

  it("accepts valid attachment metadata", () => {
    const objectPath = `${ownerId}/${entryId}/${attachmentId}.webp`;

    expect(
      parseFirstTimeAttachmentInput({
        attachmentId,
        byteSize: 2048,
        entryId,
        mimeType: "image/webp",
        objectPath,
        originalFilename: "first.webp",
        pixelHeight: 1200,
        pixelWidth: 1600,
      }),
    ).toEqual({
      data: {
        attachmentId,
        byteSize: 2048,
        entryId,
        mimeType: "image/webp",
        objectPath,
        originalFilename: "first.webp",
        pixelHeight: 1200,
        pixelWidth: 1600,
      },
      success: true,
    });
  });

  it("rejects unsupported and oversized attachments", () => {
    const base = {
      attachmentId,
      byteSize: 2048,
      entryId,
      mimeType: "image/gif",
      objectPath: `${ownerId}/${entryId}/${attachmentId}.gif`,
      originalFilename: "first.gif",
      pixelHeight: null,
      pixelWidth: null,
    };

    expect(parseFirstTimeAttachmentInput(base)).toMatchObject({
      success: false,
    });
    expect(
      parseFirstTimeAttachmentInput({
        ...base,
        byteSize: firstTimePhotoSizeLimit + 1,
        mimeType: "image/jpeg",
      }),
    ).toMatchObject({ success: false });
  });
});
