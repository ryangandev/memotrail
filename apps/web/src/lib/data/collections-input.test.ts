import { describe, expect, it } from "vitest";
import {
  collectionPageHref,
  parseCollectionId,
  parseCollectionPage,
} from "./collections-input";

const collectionId = "21000000-0000-4000-8000-000000000001";

describe("Collections route input", () => {
  it("accepts UUID collection identifiers", () => {
    expect(parseCollectionId(collectionId)).toBe(collectionId);
    expect(parseCollectionId(collectionId.toUpperCase())).toBe(
      collectionId.toUpperCase(),
    );
  });

  it("rejects invalid collection identifiers", () => {
    expect(parseCollectionId("collection-test")).toBeNull();
    expect(parseCollectionId(null)).toBeNull();
  });

  it("defaults an absent page to one", () => {
    expect(parseCollectionPage(undefined)).toBe(1);
    expect(parseCollectionPage("")).toBe(1);
  });

  it("accepts safe page numbers and the first repeated value", () => {
    expect(parseCollectionPage("2")).toBe(2);
    expect(parseCollectionPage(["3", "4"])).toBe(3);
  });

  it("rejects invalid and out-of-contract pages", () => {
    expect(parseCollectionPage("0")).toBeNull();
    expect(parseCollectionPage("1.5")).toBeNull();
    expect(parseCollectionPage("402")).toBeNull();
    expect(parseCollectionPage("anything")).toBeNull();
  });

  it("builds stable first and subsequent page links", () => {
    expect(collectionPageHref(collectionId, 1)).toBe(
      `/collections/${collectionId}`,
    );
    expect(collectionPageHref(collectionId, 3)).toBe(
      `/collections/${collectionId}?page=3`,
    );
    expect(collectionPageHref("invalid", 1)).toBe("/collections");
  });
});
