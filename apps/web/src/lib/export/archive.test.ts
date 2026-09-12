import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createExportArchive, getExportSnapshot } from "./archive";
import { hasCompleteExport, type ExportSnapshot } from "./contracts";
const owner = "00000000-0000-0000-0000-000000000001";
const id = "00000000-0000-0000-0000-000000000002";
const fixture = (media?: Record<string, unknown>) => {
  const snapshot: ExportSnapshot = {
    id,
    schema_version: 1,
    captured_at: "2026-09-12T00:00:00Z",
    expires_at: "2026-09-13T00:00:00Z",
    row_count: media ? 2 : 1,
    json_bytes: 100,
    datasets: { entries: 1, media_objects: media ? 1 : 0 },
  };
  const rows = [
    { position: 1, dataset: "entries", value: { id, body: "my writing" } },
    ...(media ? [{ position: 2, dataset: "media_objects", value: media }] : []),
  ];
  const rpc = vi.fn((_name, args) => ({
    abortSignal: async () => ({
      data: {
        snapshot,
        rows: rows.filter((row) => row.position > args.p_after),
        has_more: false,
      },
      error: null,
    }),
  }));
  const storage = {
    from: vi.fn(() => ({
      createSignedUrl: vi.fn(async () => ({
        data: { signedUrl: "https://synthetic-storage.test/original" },
        error: null,
      })),
    })),
  };
  return {
    snapshot,
    rows,
    rpc,
    client: { rpc, storage } as unknown as SupabaseClient,
  };
};
const media = {
  attachment_id: id,
  variant: "original",
  bucket_id: "entry-media",
  object_path: `${owner}/photo.png`,
  available: true,
  etag: "original-etag",
  byte_size: "3",
};
afterEach(() => vi.unstubAllGlobals());
describe("complete ZIP streaming", () => {
  it("ends an owner-scoped archive with the completion record only after all files", async () => {
    const f = fixture(media);
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(new Uint8Array([1, 2, 3]), {
            headers: { etag: '"original-etag"' },
          }),
      ),
    );
    const data = new Uint8Array(
      await new Response(
        createExportArchive(
          f.client,
          owner,
          f.snapshot,
          new AbortController().signal,
        ),
      ).arrayBuffer(),
    );
    expect(hasCompleteExport(data)).toBe(true);
    expect(f.rpc.mock.calls.at(-1)?.[1].p_after).toBe(2);
  });
  it.each([
    { ...media, available: false },
    { ...media, object_path: "other-owner/photo.png" },
    { ...media, bucket_id: "other-bucket" },
    { ...media, byte_size: null },
    { ...media, etag: null },
  ])(
    "refuses missing or unverifiable media without foreign storage requests",
    async (record) => {
      const f = fixture(record);
      const fetch = vi.fn();
      vi.stubGlobal("fetch", fetch);
      await expect(
        new Response(
          createExportArchive(
            f.client,
            owner,
            f.snapshot,
            new AbortController().signal,
          ),
        ).arrayBuffer(),
      ).rejects.toThrow("Export interrupted");
      expect(fetch).not.toHaveBeenCalled();
    },
  );
  it.each([
    { etag: "replaced", bytes: 3 },
    { etag: "original-etag", bytes: 2 },
    { etag: "original-etag", bytes: 4 },
  ])(
    "fails closed on changed original identity or truncated/oversized media",
    async ({ etag, bytes }) => {
      const f = fixture(media);
      vi.stubGlobal(
        "fetch",
        vi.fn(
          async () =>
            new Response(new Uint8Array(bytes), { headers: { etag } }),
        ),
      );
      await expect(
        new Response(
          createExportArchive(
            f.client,
            owner,
            f.snapshot,
            new AbortController().signal,
          ),
        ).arrayBuffer(),
      ).rejects.toThrow();
    },
  );
  it("does not hang when the request is already cancelled", async () => {
    const f = fixture();
    await expect(
      new Response(
        createExportArchive(f.client, owner, f.snapshot, AbortSignal.abort()),
      ).arrayBuffer(),
    ).rejects.toThrow();
    expect(f.rpc).not.toHaveBeenCalled();
  });
  it("stops pagination when the consumer cancels", async () => {
    const f = fixture();
    const controller = new AbortController();
    const reader = createExportArchive(
      f.client,
      owner,
      f.snapshot,
      controller.signal,
    ).getReader();
    await reader.read();
    await reader.cancel();
    await new Promise((resolve) => setTimeout(resolve, 10));
    const calls = f.rpc.mock.calls.length;
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(f.rpc).toHaveBeenCalledTimes(calls);
  });
  it("refuses incomplete pagination instead of silently dropping rows", async () => {
    const f = fixture();
    f.rows[0].position = 2;
    await expect(
      new Response(
        createExportArchive(
          f.client,
          owner,
          f.snapshot,
          new AbortController().signal,
        ),
      ).arrayBuffer(),
    ).rejects.toThrow();
  });
  it("validates snapshot counts and owner-scoped availability before sending headers", async () => {
    const f = fixture();
    f.snapshot.row_count = 9;
    await expect(
      getExportSnapshot(f.client, id, new AbortController().signal),
    ).rejects.toThrow("compatible server");
    f.rpc.mockImplementation(
      () =>
        ({ abortSignal: async () => ({ data: null, error: null }) }) as never,
    );
    await expect(
      getExportSnapshot(f.client, id, new AbortController().signal),
    ).rejects.toThrow("not available to this account");
  });
});
