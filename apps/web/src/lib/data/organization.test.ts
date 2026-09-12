import { describe, it, expect } from "vitest";
import { validOrganizationInput, type OrganizationInput } from "./organization";
describe("Organization settings", () => {
  const input: OrganizationInput = {
    kind: "collection",
    name: " 学习 ",
    id: null,
    revision: null,
    order: -1,
  };
  it("accepts bilingual Collections and alphabetic tags", () => {
    expect(validOrganizationInput(input)).toBe(true);
    expect(validOrganizationInput({ ...input, kind: "tag", order: 0 })).toBe(
      true,
    );
    expect(validOrganizationInput({ ...input, kind: "tag" })).toBe(false);
  });
  it("bounds names, order and identity", () => {
    for (const change of [
      { name: " " },
      { name: "x".repeat(81) },
      { order: NaN },
      { order: 1000001 },
      { order: 0.1 },
      { revision: 1 },
      { id: "x", revision: 1 },
    ])
      expect(validOrganizationInput({ ...input, ...change })).toBe(false);
    expect(
      validOrganizationInput({
        ...input,
        id: "96000000-0000-4000-8000-000000000002",
        revision: 2,
      }),
    ).toBe(true);
  });
});
