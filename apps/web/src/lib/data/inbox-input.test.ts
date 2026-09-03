import { describe, expect, it } from "vitest";
import {
  entryBodyLimit,
  entryTitleLimit,
  parseInboxEntryInput,
  parseInboxEntryValues,
} from "./inbox-input";

describe("parseInboxEntryInput", () => {
  it("accepts a body-only quick capture", () => {
    const formData = new FormData();
    formData.set("body", "  A thought worth keeping.  ");

    expect(parseInboxEntryInput(formData)).toEqual({
      data: {
        body: "A thought worth keeping.",
        title: null,
      },
      success: true,
    });
  });

  it("accepts a title-only capture", () => {
    const formData = new FormData();
    formData.set("title", "  First time skiing  ");

    expect(parseInboxEntryInput(formData)).toEqual({
      data: {
        body: "",
        title: "First time skiing",
      },
      success: true,
    });
  });

  it("rejects an empty capture", () => {
    const formData = new FormData();

    expect(parseInboxEntryInput(formData)).toEqual({
      message: "Write a title, a note, or add a photo before saving.",
      success: false,
    });
  });

  it("accepts a photo-only local capture", () => {
    expect(
      parseInboxEntryValues({ body: "", hasAttachments: true, title: "" }),
    ).toEqual({
      data: { body: "", title: null },
      success: true,
    });
  });

  it("rejects an oversized title", () => {
    const formData = new FormData();
    formData.set("title", "t".repeat(entryTitleLimit + 1));

    expect(parseInboxEntryInput(formData).success).toBe(false);
  });

  it("rejects an oversized body", () => {
    const formData = new FormData();
    formData.set("body", "b".repeat(entryBodyLimit + 1));

    expect(parseInboxEntryInput(formData).success).toBe(false);
  });

  it("shares validation with local queued capture", () => {
    expect(
      parseInboxEntryValues({
        body: "  Saved before the network request.  ",
        title: " ",
      }),
    ).toEqual({
      data: {
        body: "Saved before the network request.",
        title: null,
      },
      success: true,
    });
  });
});
