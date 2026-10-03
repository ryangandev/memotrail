import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { finishMediaPurges, MEDIA_PURGE_BATCH_SIZE } from "./media-purge";

const owner = "10000000-0000-4000-8000-000000000001";
const original = `${owner}/20000000-0000-4000-8000-000000000001/photo.jpg`;
const preview = `${owner}/20000000-0000-4000-8000-000000000001/derived/a/v1/b/display.webp`;

type Reply = { data: unknown; error: unknown };

function fakeClient(
  pending: Reply[],
  completed: Reply[],
  removal: Reply = { data: [], error: null },
) {
  const calls: string[] = [];
  const remove = vi.fn(async (paths: string[]) => {
    calls.push(`remove ${paths.join(",")}`);
    return removal;
  });
  const rpc = vi.fn(async (name: string, args?: unknown) => {
    calls.push(name);
    if (name === "pending_media_purge_paths") {
      expect(args).toEqual({ p_limit: MEDIA_PURGE_BATCH_SIZE });
      return pending.shift() ?? { data: [], error: null };
    }
    return completed.shift() ?? { data: 0, error: null };
  });
  const client = {
    rpc,
    storage: { from: vi.fn(() => ({ remove })) },
  } as unknown as SupabaseClient;
  return { calls, client, remove };
}

const rows = (...paths: string[]) => ({
  data: paths.map((object_path) => ({ object_path })),
  error: null,
});

describe("removing permanently deleted photo files", () => {
  it("removes only recorded files, then confirms with the server", async () => {
    const { calls, client } = fakeClient(
      [rows(original, preview, original)],
      [{ data: 0, error: null }],
    );
    expect(await finishMediaPurges(client, owner)).toBe(true);
    expect(calls).toEqual([
      "pending_media_purge_paths",
      `remove ${original},${preview}`,
      "complete_media_purges",
    ]);
  });

  it("confirms without a Storage call when nothing is recorded", async () => {
    const { calls, client, remove } = fakeClient(
      [rows()],
      [{ data: 0, error: null }],
    );
    expect(await finishMediaPurges(client, owner)).toBe(true);
    expect(remove).not.toHaveBeenCalled();
    expect(calls).toEqual([
      "pending_media_purge_paths",
      "complete_media_purges",
    ]);
  });

  it("continues in batches until the server confirms nothing remains", async () => {
    const { calls, client } = fakeClient(
      [rows(original), rows(preview)],
      [
        { data: 1, error: null },
        { data: 0, error: null },
      ],
    );
    expect(await finishMediaPurges(client, owner)).toBe(true);
    expect(calls).toHaveLength(6);
  });

  it("stays unfinished when Storage removal fails, so the files remain recorded", async () => {
    const { calls, client } = fakeClient([rows(original)], [], {
      data: null,
      error: { message: "network" },
    });
    expect(await finishMediaPurges(client, owner)).toBe(false);
    expect(calls).not.toContain("complete_media_purges");
  });

  it.each([
    { data: null, error: { message: "unavailable" } },
    { data: [{ path: original }], error: null },
    { data: "paths", error: null },
  ])("stays unfinished on an unusable path list", async (reply) => {
    const { client, remove } = fakeClient([reply], []);
    expect(await finishMediaPurges(client, owner)).toBe(false);
    expect(remove).not.toHaveBeenCalled();
  });

  it.each([
    "20000000-0000-4000-8000-000000000009/other/photo.jpg",
    `${owner}/`,
    `${owner}/../other/photo.jpg`,
  ])(
    "never removes a path outside the signed-in owner's media: %s",
    async (path) => {
      const { client, remove } = fakeClient([rows(path)], []);
      expect(await finishMediaPurges(client, owner)).toBe(false);
      expect(remove).not.toHaveBeenCalled();
    },
  );

  it("stays unfinished when the confirmation fails or recorded files cannot be listed", async () => {
    expect(
      await finishMediaPurges(
        fakeClient([rows(original)], [{ data: null, error: { message: "x" } }])
          .client,
        owner,
      ),
    ).toBe(false);
    expect(
      await finishMediaPurges(
        fakeClient([rows()], [{ data: 2, error: null }]).client,
        owner,
      ),
    ).toBe(false);
  });

  it("stops after its round limit and on a thrown network error", async () => {
    const { client, calls } = fakeClient(
      [rows(original), rows(original)],
      [
        { data: 1, error: null },
        { data: 1, error: null },
      ],
    );
    expect(await finishMediaPurges(client, owner, 2)).toBe(false);
    expect(calls).toHaveLength(6);
    const throwing = {
      rpc: vi.fn().mockRejectedValue(new Error("offline")),
    } as unknown as SupabaseClient;
    expect(await finishMediaPurges(throwing, owner)).toBe(false);
  });
});
