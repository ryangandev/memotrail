import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";

vi.mock("server-only", () => ({}));
vi.mock("@/lib/media/urls", () => ({
  displayImageURLs: vi.fn(async (_client: unknown, paths: string[]) =>
    paths.length
      ? new Map([[paths[0]!, "https://example.test/photo"]])
      : new Map(),
  ),
}));

import {
  chapterEntryRows,
  chapterOverlapRows,
  chapterPage,
  loadChapterContents,
} from "./chapter-contents";

const entryRow = {
  cover_photo: null,
  date_precision: "day",
  entry_id: "40000000-0000-4000-8000-000000000001",
  excerpt: "A quiet walk.",
  is_first_time: false,
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2021-06-15T12:00:00Z",
  occurred_timezone: "UTC",
  tag_names: ["walks"],
  title: "Morning walk",
  total_count: "2",
};

const overlapRow = {
  date_precision: "year",
  entry_id: "40000000-0000-4000-8000-000000000002",
  is_first_time: true,
  occurred_end: "2022-01-01T12:00:00Z",
  occurred_label: null,
  occurred_start: "2020-01-01T12:00:00Z",
  occurred_timezone: "UTC",
  title: "",
};

function client(entries: unknown, overlaps: unknown, error = false) {
  const rpc = vi.fn((name: string) =>
    Promise.resolve(
      error
        ? { data: null, error: { message: "boom" } }
        : {
            data: name === "chapter_entries" ? entries : overlaps,
            error: null,
          },
    ),
  );
  return { rpc, client: { rpc } as unknown as SupabaseClient };
}

describe("Chapter contents", () => {
  it("asks for one page of 50 Entries and the overlapping Chapters", async () => {
    const { client: supabase, rpc } = client([entryRow], [overlapRow]);

    const contents = await loadChapterContents(supabase, "chapter-1", 3);

    expect(rpc).toHaveBeenCalledWith("chapter_entries", {
      p_chapter_id: "chapter-1",
      p_limit: 50,
      p_offset: 100,
    });
    expect(rpc).toHaveBeenCalledWith("chapter_overlaps", {
      p_chapter_id: "chapter-1",
    });
    expect(contents).toMatchObject({
      failed: false,
      totalCount: 2,
      entries: [
        { id: entryRow.entry_id, title: "Morning walk", tagNames: ["walks"] },
      ],
      overlaps: [{ id: overlapRow.entry_id, isFirstTime: true, title: "2020" }],
    });
  });

  it("signs a cover photo for display", async () => {
    const cover = {
      attachment_id: "a",
      bucket_id: "entry-media",
      byte_size: 10,
      mime_type: "image/jpeg",
      object_path: "owner/photo.jpg",
      original_filename: "photo.jpg",
      pixel_height: 10,
      pixel_width: 10,
    };
    const { client: supabase } = client(
      [{ ...entryRow, cover_photo: cover }],
      [],
    );

    const contents = await loadChapterContents(supabase, "chapter-1", 1);

    expect(contents.entries[0]?.coverPhoto).toEqual({
      alt: "photo.jpg",
      imageUrl: "https://example.test/photo",
      objectPath: "owner/photo.jpg",
    });
  });

  it("reports a failed load instead of an empty Chapter", async () => {
    const { client: supabase } = client(null, null, true);

    expect(await loadChapterContents(supabase, "chapter-1", 1)).toEqual({
      entries: [],
      failed: true,
      overlaps: [],
      totalCount: 0,
    });
  });

  it("returns nothing for a Chapter without a calendar date", async () => {
    const { client: supabase } = client([], []);

    expect(await loadChapterContents(supabase, "chapter-1", 1)).toEqual({
      entries: [],
      failed: false,
      overlaps: [],
      totalCount: 0,
    });
  });

  it("rejects malformed rows", () => {
    expect(chapterEntryRows([{ ...entryRow, is_first_time: "no" }])).toBeNull();
    expect(chapterEntryRows([{ ...entryRow, cover_photo: {} }])).toBeNull();
    expect(chapterEntryRows([{ ...entryRow, total_count: "many" }])).toBeNull();
    expect(chapterOverlapRows([{ ...overlapRow, title: null }])).toBeNull();
    expect(chapterOverlapRows("rows")).toBeNull();
  });

  it("bounds the page number", () => {
    expect(chapterPage("2")).toBe(2);
    expect(chapterPage(["3", "4"])).toBe(3);
    expect(chapterPage(undefined)).toBe(1);
    expect(chapterPage("0")).toBe(1);
    expect(chapterPage("abc")).toBe(1);
    expect(chapterPage("999999")).toBe(1);
  });
});
