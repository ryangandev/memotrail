import { describe, expect, it } from "vitest";
import { validTrackInput, type TrackInput } from "./tracks";
describe("Timeline track input", () => {
  const input: TrackInput = {
    id: null,
    revision: null,
    name: "  学习  ",
    order: 0,
    hidden: false,
  };
  it("accepts a bilingual custom track", () =>
    expect(validTrackInput(input)).toBe(true));
  it("bounds name and order", () => {
    for (const change of [
      { name: " " },
      { name: "x".repeat(101) },
      { order: NaN },
      { order: 1.5 },
      { order: 1000001 },
    ])
      expect(validTrackInput({ ...input, ...change })).toBe(false);
  });
  it("requires a coherent identity and revision", () => {
    expect(validTrackInput({ ...input, revision: 1 })).toBe(false);
    expect(validTrackInput({ ...input, id: "invalid", revision: 1 })).toBe(
      false,
    );
    const id = "95000000-0000-4000-8000-000000000001";
    expect(validTrackInput({ ...input, id })).toBe(false);
    expect(
      validTrackInput({ ...input, id, revision: 2, hidden: true, order: -1 }),
    ).toBe(true);
  });
});
