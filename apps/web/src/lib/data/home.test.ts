import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: vi.fn() }));
vi.mock("./inbox", () => ({ getAuthenticatedContext: vi.fn() }));
vi.mock("@/lib/media/urls", () => ({ displayImageURLs: vi.fn() }));

import { parseNowItems } from "./home";

const nowItem = {
  date_precision: "month",
  entry_id: "40000000-0000-4000-8000-000000000001",
  is_first_time: false,
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2021-03-01T12:00:00Z",
  occurred_timezone: "America/Los_Angeles",
  title: "Living in Portland",
};

describe("Dashboard Now items", () => {
  it("reads a Chapter that is going on now", () => {
    expect(parseNowItems([nowItem])).toEqual([
      {
        id: nowItem.entry_id,
        isFirstTime: false,
        occurrence: {
          datePrecision: "month",
          occurredAt: "2021-03-01T12:00:00Z",
          occurredEnd: null,
          occurredLabel: null,
          occurredTimezone: "America/Los_Angeles",
        },
        title: "Living in Portland",
      },
    ]);
    expect(parseNowItems([])).toEqual([]);
  });

  it("names an untitled Chapter by its date", () => {
    const [item] = parseNowItems([{ ...nowItem, title: "" }])!;

    expect(item?.title).toBe("March 2021");
  });

  it("rejects the retired lane and any other unexpected shape", () => {
    expect(parseNowItems([{ ...nowItem, lane: "homes" }])).toBeNull();
    expect(parseNowItems([{ ...nowItem, item_kind: "entity" }])).toBeNull();
    expect(
      parseNowItems([{ ...nowItem, is_first_time: undefined }]),
    ).toBeNull();
    expect(parseNowItems([{ ...nowItem, occurred_start: null }])).toBeNull();
    expect(parseNowItems({})).toBeNull();
  });
});
