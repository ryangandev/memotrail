import { describe, expect, it } from "vitest";
import {
  importErrorMessage,
  parseImportAction,
  parseImportOptions,
} from "./contracts";

const jobId = "22222222-2222-4222-8222-222222222222";
const options = {
  notionDateProperty: null,
  tags: { folders: false, marker: true, properties: true, source: true },
  timezone: "America/New_York",
  undated: "leave",
};

describe("parseImportAction", () => {
  it("accepts the actions the page sends", () => {
    expect(parseImportAction({ action: "state" })).toEqual({ action: "state" });
    expect(parseImportAction({ action: "run", jobId })).toEqual({
      action: "run",
      jobId,
    });
    expect(
      parseImportAction({
        action: "create",
        fileBytes: 10,
        fileName: "a.zip",
        source: "notion",
      }),
    ).toMatchObject({ action: "create", source: "notion" });
    expect(
      parseImportAction({
        action: "confirm",
        excludedFolders: [["A", "B"]],
        jobId,
        options,
      }),
    ).toMatchObject({ action: "confirm", excludedFolders: [["A", "B"]] });
    expect(parseImportAction({ action: "preview", jobId })).toEqual({
      action: "preview",
      jobId,
      timezone: null,
      warningsOnly: false,
    });
  });

  it("rejects anything malformed", () => {
    expect(parseImportAction(null)).toBeNull();
    expect(parseImportAction({ action: "nope" })).toBeNull();
    expect(
      parseImportAction({ action: "run", jobId: "not-a-uuid" }),
    ).toBeNull();
    expect(parseImportAction({ action: "run" })).toBeNull();
    expect(
      parseImportAction({
        action: "create",
        fileBytes: 0,
        fileName: "a.zip",
        source: "notion",
      }),
    ).toBeNull();
    expect(
      parseImportAction({
        action: "create",
        fileBytes: 5,
        fileName: "a.zip",
        source: "evernote",
      }),
    ).toBeNull();
    expect(
      parseImportAction({
        action: "confirm",
        excludedFolders: [[]],
        jobId,
        options,
      }),
    ).toBeNull();
    expect(
      parseImportAction({
        action: "confirm",
        excludedFolders: [[1]],
        jobId,
        options,
      }),
    ).toBeNull();
  });

  it("ignores a time zone it does not know", () => {
    expect(
      parseImportAction({ action: "preview", jobId, timezone: "Mars/Olympus" }),
    ).toMatchObject({ timezone: null });
  });
});

describe("parseImportOptions", () => {
  it("accepts good options and rejects bad ones", () => {
    expect(parseImportOptions(options)).toEqual(options);
    expect(
      parseImportOptions({ ...options, timezone: "Nowhere/City" }),
    ).toBeNull();
    expect(parseImportOptions({ ...options, undated: "today" })).toBeNull();
    expect(
      parseImportOptions({ ...options, tags: { folders: true } }),
    ).toBeNull();
    expect(
      parseImportOptions({ ...options, notionDateProperty: 5 }),
    ).toBeNull();
  });
});

describe("importErrorMessage", () => {
  it("gives a plain sentence for known and unknown codes", () => {
    expect(importErrorMessage("empty_import")).toContain("No notes");
    expect(importErrorMessage("something_else")).toContain(
      "stopped unexpectedly",
    );
    expect(importErrorMessage(null)).toContain("stopped unexpectedly");
  });
});
