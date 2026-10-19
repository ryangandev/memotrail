import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: vi.fn() }));

import { chapterReviewListings, loadChapterReviews } from "./reviews";

const chapter = (overrides: Record<string, unknown> = {}) => ({
  id: "50000000-0000-4000-8000-000000000001",
  title: "  Moving out  ",
  item_subtype: "chapter",
  deleted_at: null,
  occurred_start: "2026-03-01T12:00:00Z",
  occurred_end: "2026-06-30T12:00:00Z",
  occurred_label: null,
  occurred_timezone: "UTC",
  date_precision: "day",
  ...overrides,
});

describe("Chapter review listings", () => {
  it("reads a made review with its Chapter's dates", () => {
    expect(
      chapterReviewListings([
        {
          generated_at: "2026-10-19T08:00:00Z",
          ongoing: false,
          chapter: chapter(),
        },
      ]),
    ).toEqual([
      {
        chapter: {
          id: "50000000-0000-4000-8000-000000000001",
          title: "Moving out",
          occurredStart: "2026-03-01T12:00:00Z",
          occurredEnd: "2026-06-30T12:00:00Z",
          occurredLabel: null,
          occurredTimezone: "UTC",
          datePrecision: "day",
        },
        generatedAt: "2026-10-19T08:00:00Z",
        ongoing: false,
      },
    ]);
  });

  it("orders the newest Chapter first and an undated one last", () => {
    const listings = chapterReviewListings([
      {
        generated_at: "2026-10-01T08:00:00Z",
        chapter: chapter({ id: "undated", date_precision: "unknown" }),
      },
      {
        generated_at: "2026-10-02T08:00:00Z",
        chapter: chapter({
          id: "older",
          occurred_start: "2019-01-01T12:00:00Z",
        }),
      },
      {
        generated_at: "2026-10-03T08:00:00Z",
        ongoing: true,
        chapter: chapter({ id: "newer", occurred_end: null }),
      },
    ]);
    expect(listings.map((listing) => listing.chapter.id)).toEqual([
      "newer",
      "older",
      "undated",
    ]);
    expect(listings[0].ongoing).toBe(true);
  });

  it("leaves out a Chapter in Trash, an Entry that is no longer a Chapter, and malformed rows", () => {
    expect(
      chapterReviewListings([
        {
          generated_at: "2026-10-01T08:00:00Z",
          chapter: chapter({ deleted_at: "2026-10-05T00:00:00Z" }),
        },
        {
          generated_at: "2026-10-01T08:00:00Z",
          chapter: chapter({ item_subtype: "entry" }),
        },
        { generated_at: null, chapter: chapter() },
        { generated_at: "2026-10-01T08:00:00Z", chapter: null },
        "nonsense",
      ]),
    ).toEqual([]);
    expect(chapterReviewListings(null)).toEqual([]);
  });

  it("asks only for made Chapter reviews and reports a failed read", async () => {
    const calls: unknown[][] = [];
    const query = (result: { data: unknown; error: unknown }) => {
      const builder = {
        select: (...args: unknown[]) => (
          calls.push(["select", ...args]),
          builder
        ),
        eq: (...args: unknown[]) => (calls.push(["eq", ...args]), builder),
        not: (...args: unknown[]) => (
          calls.push(["not", ...args]),
          Promise.resolve(result)
        ),
      };
      return builder;
    };
    const ok = {
      from: (table: string) => (
        calls.push(["from", table]),
        query({
          data: [{ generated_at: "2026-10-19T08:00:00Z", chapter: chapter() }],
          error: null,
        })
      ),
    } as unknown as SupabaseClient;
    const result = await loadChapterReviews(ok);
    expect(result.failed).toBe(false);
    expect(result.chapters).toHaveLength(1);
    expect(calls).toContainEqual(["from", "entry_reviews"]);
    expect(calls).toContainEqual(["eq", "scope", "chapter"]);
    expect(calls).toContainEqual(["not", "content", "is", null]);

    const failing = {
      from: () => query({ data: null, error: { message: "boom" } }),
    } as unknown as SupabaseClient;
    expect(await loadChapterReviews(failing)).toEqual({
      chapters: [],
      failed: true,
    });
  });
});
