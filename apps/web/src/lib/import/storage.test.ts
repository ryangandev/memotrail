import { describe, expect, it } from "vitest";
import {
  httpRangeSource,
  openStagedArchive,
  removeStagedFiles,
} from "./storage";
import { buildZip } from "./test-zip";

/** A server that honors Range, like Supabase Storage. */
function rangeFetch(bytes: Buffer, log: string[] = []): typeof fetch {
  return (async (_url: string | URL | Request, init?: RequestInit) => {
    const range = new Headers(init?.headers).get("range") ?? "";
    log.push(range);
    const match = /bytes=(\d+)-(\d+)/.exec(range);
    if (!match) return new Response(new Uint8Array(bytes), { status: 200 });
    const start = Number(match[1]);
    const end = Math.min(Number(match[2]), bytes.length - 1);
    return new Response(new Uint8Array(bytes.subarray(start, end + 1)), {
      headers: { "content-range": `bytes ${start}-${end}/${bytes.length}` },
      status: 206,
    });
  }) as typeof fetch;
}

function clientFor(signedUrl: string | null) {
  return {
    storage: {
      from: () => ({
        createSignedUrl: async () =>
          signedUrl
            ? { data: { signedUrl }, error: null }
            : { data: null, error: new Error("missing") },
        remove: async () => ({ data: [], error: null }),
      }),
    },
  } as never;
}

describe("httpRangeSource", () => {
  it("learns the size from Content-Range and reads exact ranges", async () => {
    const bytes = Buffer.from("0123456789abcdef");
    const log: string[] = [];
    const source = await httpRangeSource(
      "https://x.test/f",
      rangeFetch(bytes, log),
    );
    expect(source.size).toBe(16);
    expect((await source.read(4, 8)).toString()).toBe("4567");
    expect(log).toEqual(["bytes=0-0", "bytes=4-7"]);
  });

  it("slices the body when a server ignores the range", async () => {
    const bytes = Buffer.from("0123456789");
    const fetchImpl = (async (_url: string, init?: RequestInit) => {
      const probe = new Headers(init?.headers).get("range") === "bytes=0-0";
      return probe
        ? new Response(new Uint8Array([48]), {
            headers: { "content-range": "bytes 0-0/10" },
            status: 206,
          })
        : new Response(new Uint8Array(bytes), { status: 200 });
    }) as unknown as typeof fetch;
    const source = await httpRangeSource("https://x.test/f", fetchImpl);
    expect((await source.read(2, 5)).toString()).toBe("234");
  });

  it("reports a missing object as unavailable without retrying forever", async () => {
    const fetchImpl = (async () =>
      new Response("", { status: 404 })) as unknown as typeof fetch;
    await expect(
      httpRangeSource("https://x.test/f", fetchImpl),
    ).rejects.toMatchObject({
      code: "storage_unavailable",
    });
  });
});

describe("openStagedArchive", () => {
  it("opens a ZIP over ranges", async () => {
    const zip = await buildZip({ "a.md": "Hello" });
    const { archive, size } = await openStagedArchive(
      clientFor("https://x.test/f"),
      "owner/job.zip",
      { fetchImpl: rangeFetch(zip) },
    );
    expect(size).toBe(zip.length);
    expect(archive.members.length).toBeGreaterThan(0);
    archive.close();
  });

  it("refuses a file over the size cap", async () => {
    const zip = await buildZip({ "a.md": "Hello" });
    await expect(
      openStagedArchive(clientFor("https://x.test/f"), "p", {
        fetchImpl: rangeFetch(zip),
        maxBytes: 10,
      }),
    ).rejects.toMatchObject({ code: "too_large" });
  });

  it("refuses a file that is not a ZIP", async () => {
    await expect(
      openStagedArchive(clientFor("https://x.test/f"), "p", {
        fetchImpl: rangeFetch(Buffer.from("this is plain text, not a zip")),
      }),
    ).rejects.toMatchObject({ code: "unsupported_archive" });
  });

  it("reports an object it cannot sign", async () => {
    await expect(openStagedArchive(clientFor(null), "p")).rejects.toMatchObject(
      {
        code: "storage_unavailable",
      },
    );
  });
});

describe("removeStagedFiles", () => {
  it("does nothing for no paths and reports removed paths", async () => {
    expect(await removeStagedFiles(clientFor(null), [])).toEqual([]);
    expect(await removeStagedFiles(clientFor(null), ["a", "b"])).toEqual([
      "a",
      "b",
    ]);
  });
});
