import { describe, expect, it } from "vitest";
import {
  candidateContentHash,
  importAttachmentId,
  importEntryId,
  uuidV5,
} from "./identity";
import {
  defaultImportOptions,
  entryTagNames,
  normalizeTagName,
  uniqueTagNames,
} from "./tags";

const owner = "10000000-0000-4000-8000-000000000001";

describe("deterministic identity", () => {
  it("matches the RFC 4122 version 5 test vector", () => {
    expect(uuidV5("python.org", "6ba7b810-9dad-11d1-80b4-00c04fd430c8")).toBe(
      "886313e1-3b8a-5372-9b90-0c9aee199e5d",
    );
  });

  it("gives the same Entry the same ID every time", () => {
    const id = importEntryId(owner, "markdown", "Notes/a.md");
    expect(importEntryId(owner, "markdown", "Notes/a.md")).toBe(id);
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });

  it("differs by owner, source, and key", () => {
    const id = importEntryId(owner, "markdown", "a");
    expect(
      importEntryId("20000000-0000-4000-8000-000000000002", "markdown", "a"),
    ).not.toBe(id);
    expect(importEntryId(owner, "notion", "a")).not.toBe(id);
    expect(importEntryId(owner, "markdown", "b")).not.toBe(id);
  });

  it("derives a photo's ID from its Entry and file", () => {
    const entry = importEntryId(owner, "markdown", "a");
    expect(importAttachmentId(entry, "|p.png")).toBe(
      importAttachmentId(entry, "|p.png"),
    );
    expect(importAttachmentId(entry, "|p.png")).not.toBe(
      importAttachmentId(entry, "|q.png"),
    );
  });
});

describe("content hash", () => {
  const base = {
    date: { local: "2024-05-12", precision: "day" as const },
    locationLabel: null,
    photoNames: ["b.png", "a.png"],
    plainText: "Hello   world\n",
    propertyTagNames: [],
    tagNames: ["Trip", "food"],
    title: "Title",
  };

  it("ignores whitespace noise, tag order and case, and photo order", () => {
    const hash = candidateContentHash(base);
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
    expect(
      candidateContentHash({
        ...base,
        photoNames: ["a.png", "b.png"],
        plainText: "Hello world",
        tagNames: ["FOOD", "trip"],
      }),
    ).toBe(hash);
  });

  it("changes when the writing, date, or title does", () => {
    const hash = candidateContentHash(base);
    expect(
      candidateContentHash({ ...base, plainText: "Hello there" }),
    ).not.toBe(hash);
    expect(candidateContentHash({ ...base, title: "Other" })).not.toBe(hash);
    expect(
      candidateContentHash({
        ...base,
        date: { local: "2024-05-13", precision: "day" },
      }),
    ).not.toBe(hash);
  });
});

describe("tags", () => {
  it("normalizes names", () => {
    expect(normalizeTagName("  #Trip   to  Rome ")).toBe("Trip to Rome");
    expect(normalizeTagName("###")).toBeNull();
    expect(normalizeTagName("x".repeat(120))).toHaveLength(80);
  });

  it("removes repeats ignoring case and limits the count", () => {
    expect(uniqueTagNames(["Trip", "trip", " TRIP "]).names).toEqual(["Trip"]);
    const many = uniqueTagNames(
      Array.from({ length: 90 }, (_, i) => `tag ${i}`),
    );
    expect(many.names).toHaveLength(70);
    expect(many.trimmed).toBe(true);
  });

  it("applies the person's choices", () => {
    const candidate = {
      folderPath: ["Travel", "Rome"],
      propertyTagNames: ["Status"],
      source: "notion" as const,
      tagNames: ["Trip"],
    };
    const options = defaultImportOptions("UTC", {
      distinctParentFolders: 3,
      notionDateProperty: null,
    });
    expect(entryTagNames(candidate, options).names).toEqual([
      "Trip",
      "Status",
      "Rome",
      "Imported from Notion",
    ]);
    expect(
      entryTagNames(candidate, {
        tags: {
          folders: false,
          marker: false,
          properties: false,
          source: true,
        },
      }).names,
    ).toEqual(["Trip"]);
  });

  it("turns folder tags off by default when there are too many folders", () => {
    expect(
      defaultImportOptions("UTC", {
        distinctParentFolders: 31,
        notionDateProperty: null,
      }).tags.folders,
    ).toBe(false);
  });
});
