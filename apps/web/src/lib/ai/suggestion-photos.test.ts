import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/media/server", () => ({ mediaImage: vi.fn() }));
import { mediaImage } from "@/lib/media/server";
import { suggestionPhotos } from "./suggestion-photos";
const render = vi.mocked(mediaImage);
const query = {
  select: vi.fn(),
  eq: vi.fn(),
  is: vi.fn(),
  order: vi.fn(),
  limit: vi.fn(),
};
const client = { from: vi.fn(() => query) } as unknown as SupabaseClient;
beforeEach(() => {
  vi.clearAllMocks();
  for (const key of ["select", "eq", "is", "order"] as const)
    query[key].mockReturnValue(query);
  query.limit.mockResolvedValue({ data: [{ id: "photo" }], error: null });
  render.mockResolvedValue(
    new Blob(["RIFF0000WEBPpreview"], { type: "image/webp" }),
  );
});
afterEach(() => vi.useRealTimers());
it("uses only active owned original attachments and private metadata-free thumbnails", async () => {
  const result = await suggestionPhotos(client, "owner", "entry");
  expect(query.eq.mock.calls).toEqual([
    ["entry_id", "entry"],
    ["owner_id", "owner"],
    ["bucket_id", "entry-media"],
    ["variant", "original"],
  ]);
  expect(query.is).toHaveBeenCalledWith("deleted_at", null);
  expect(render).toHaveBeenCalledWith(
    expect.objectContaining({ owner: "owner", id: "photo", trash: false }),
    "thumbnail",
  );
  expect(result.images[0].mediaType).toBe("image/webp");
  expect(result.fingerprint).toMatch(/^[a-f0-9]{64}$/);
});
it("fingerprints both preview bytes and membership, but not temporary grant expiry", async () => {
  const first = await suggestionPhotos(client, "owner", "entry");
  expect((await suggestionPhotos(client, "owner", "entry")).fingerprint).toBe(
    first.fingerprint,
  );
  render.mockResolvedValue(new Blob(["RIFF0000WEBPchanged"]));
  expect(
    (await suggestionPhotos(client, "owner", "entry")).fingerprint,
  ).not.toBe(first.fingerprint);
  render.mockResolvedValue(new Blob(["RIFF0000WEBPpreview"]));
  query.limit.mockResolvedValue({ data: [{ id: "replacement" }], error: null });
  expect(
    (await suggestionPhotos(client, "owner", "entry")).fingerprint,
  ).not.toBe(first.fingerprint);
});
it("keeps text-only context when there are no photos", async () => {
  query.limit.mockResolvedValue({ data: [], error: null });
  expect(await suggestionPhotos(client, "owner", "entry")).toEqual({
    images: [],
    fingerprint: null,
  });
  expect(render).not.toHaveBeenCalled();
});
it.each([
  { data: null, error: {} },
  { data: Array(13).fill({ id: "photo" }), error: null },
])(
  "fails closed on incomplete or oversized attachment lists",
  async (result) => {
    query.limit.mockResolvedValue(result);
    await expect(suggestionPhotos(client, "owner", "entry")).rejects.toThrow();
    expect(render).not.toHaveBeenCalled();
  },
);
it("does not silently omit unavailable photos", async () => {
  render.mockRejectedValue(Error("unavailable"));
  await expect(suggestionPhotos(client, "owner", "entry")).rejects.toThrow();
});
it("bounds total preparation and stops processing additional photos after timeout", async () => {
  vi.useFakeTimers();
  query.limit.mockResolvedValue({
    data: [{ id: "first" }, { id: "second" }],
    error: null,
  });
  let complete!: (blob: Blob) => void;
  render.mockImplementation(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  const result = expect(
    suggestionPhotos(client, "owner", "entry"),
  ).rejects.toThrow("timed out");
  await vi.advanceTimersByTimeAsync(20_001);
  await result;
  complete(new Blob(["RIFF0000WEBPpreview"]));
  await vi.advanceTimersByTimeAsync(1);
  expect(render).toHaveBeenCalledTimes(1);
});
