import { describe, it, expect } from "vitest";
import { parseMediaPaths, signMediaGrant, verifyMediaGrant } from "./contracts";
const owner = "10000000-0000-4000-8000-000000000001",
  id = "20000000-0000-4000-8000-000000000002";
describe("scoped photo capabilities", () => {
  it("requires an unmodified, unexpired, purpose-bound signature", () => {
    const grant = { owner, id, expires: 10_000, trash: false };
    const token = signMediaGrant(grant, "test-secret");
    expect(verifyMediaGrant(token, "test-secret", 1000)).toEqual(grant);
    expect(verifyMediaGrant(token, "wrong-secret", 1000)).toBeNull();
    expect(verifyMediaGrant(token + "x", "test-secret", 1000)).toBeNull();
    expect(verifyMediaGrant(token, "test-secret", 10_000)).toBeNull();
    expect(
      verifyMediaGrant(
        signMediaGrant({ ...grant, expires: 4_000_000 }, "test-secret"),
        "test-secret",
        1000,
      ),
    ).toBeNull();
  });
  it("accepts original paths only, bounds batches and excludes arbitrary fetch locations", () => {
    const path = `${owner}/${id}/${id}.jpg`;
    expect(parseMediaPaths({ paths: [path, path] })).toEqual({
      paths: [path],
      trash: false,
    });
    for (const paths of [
      ["https://example.com/image.jpg"],
      [`${owner}/${id}/derived/file.webp`],
      ["../../secret"],
      Array(101).fill(path),
    ])
      expect(parseMediaPaths({ paths })).toBeNull();
    expect(parseMediaPaths({ paths: [path], trash: "true" })).toBeNull();
  });
});
