import { describe, expect, it } from "vitest";
import {
  createEntryObjectPath,
  entryPhotoSizeLimit,
  inferEntryImageMimeType,
  isEntryUuid,
  normalizeEntryImageMimeType,
  parseEntryAttachmentInput,
} from "./entry-photo-input";

const ownerId = "10000000-0000-0000-0000-000000000001";
const entryId = "40000000-0000-4000-8000-000000000001";
const attachmentId = "60000000-0000-4000-8000-000000000001";

describe("Entry photos", () => {
  it("builds a private owner and Entry scoped object path", () => {
    expect(
      createEntryObjectPath(ownerId, entryId, attachmentId, "image/jpeg"),
    ).toBe(`${ownerId}/${entryId}/${attachmentId}.jpg`);
  });

  it("normalizes supported MIME types", () => {
    expect(normalizeEntryImageMimeType(" IMAGE/HEIC ")).toBe("image/heic");
    expect(normalizeEntryImageMimeType("image/gif")).toBeNull();
    expect(inferEntryImageMimeType("IMG_1001.HEIC", "")).toBe("image/heic");
  });

  it("rejects an unsafe object path identity", () => {
    expect(
      createEntryObjectPath("not-a-user", entryId, attachmentId, "image/png"),
    ).toBeNull();
  });

  it("accepts valid attachment metadata", () => {
    const objectPath = `${ownerId}/${entryId}/${attachmentId}.webp`;

    expect(
      parseEntryAttachmentInput({
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

    expect(parseEntryAttachmentInput(base)).toMatchObject({
      success: false,
    });
    expect(
      parseEntryAttachmentInput({
        ...base,
        byteSize: entryPhotoSizeLimit + 1,
        mimeType: "image/jpeg",
      }),
    ).toMatchObject({ success: false });
  });

  it("recognizes record IDs", () => {
    expect(isEntryUuid(entryId)).toBe(true);
    expect(isEntryUuid("first-time")).toBe(false);
  });
});
