import { execFileSync } from "node:child_process";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { hasCompleteExport } from "../src/lib/export/contracts";

test("Complete ZIP is portable, byte-identical, shared with native auth, and recoverable after missing media", async ({
  baseURL,
  page,
  context,
}, testInfo) => {
  test.setTimeout(120_000);
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `export-zip-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user?.id;
  if (!owner) throw new Error("Synthetic export fixture unavailable.");
  const entryID = randomUUID(),
    attachmentID = randomUUID();
  const path = `${owner}/${entryID}/${attachmentID}.png`;
  // Valid tiny PNG followed by opaque fixture bytes tests unbuffered >4.5 MB transport.
  const original = Buffer.concat([
    Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=",
      "base64",
    ),
    randomBytes(5 * 1024 * 1024),
  ]);
  const sha = (bytes: Buffer) =>
    createHash("sha256").update(bytes).digest("hex");
  try {
    expect(
      (
        await page.request.post("/api/export", {
          headers: { Origin: baseURL! },
          data: { action: "list" },
        })
      ).status(),
    ).toBe(401);
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    const signed = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    expect(signed.error).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );
    const nativeHeaders = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    expect(
      (
        await page.request.post("/api/export", {
          headers: nativeHeaders,
          data: { action: "download", id: randomUUID() },
        })
      ).status(),
    ).toBe(404);
    expect(
      (
        await page.request.post("/api/export", {
          headers: nativeHeaders,
          data: { action: "list", ownerID: owner },
        })
      ).status(),
    ).toBe(400);
    const originalBody = "第一次导出我的人生记录\n\n每一句都应该完整保存。";
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: owner,
          title: "../安全的标题",
          body: originalBody,
          date_precision: "age",
          occurred_label: "17岁",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(path, original, { contentType: "image/png" })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("register_entry_attachment", {
          p_entry_id: entryID,
          p_attachment_id: attachmentID,
          p_object_path: path,
          p_original_filename: "照片.png",
          p_mime_type: "image/png",
          p_byte_size: original.length,
          p_pixel_width: 1,
          p_pixel_height: 1,
        })
      ).error,
    ).toBeNull();
    await page.addInitScript(() => {
      Object.defineProperty(window, "showSaveFilePicker", {
        value: undefined,
        configurable: true,
      });
    });
    await page.goto("/settings");
    await page.getByRole("link", { name: /Export archive/ }).click();
    await expect(
      page.getByRole("heading", { name: "Export archive" }),
    ).toBeVisible();
    expect(
      (
        await page.request.post("/api/export", {
          headers: { Origin: "https://evil.test" },
          data: { action: "create", id: randomUUID() },
        })
      ).status(),
    ).toBe(403);
    await page.getByRole("button", { name: "Prepare snapshot" }).click();
    await expect(
      page.locator("[data-sonner-toast]").filter({
        hasText: "Snapshot prepared",
      }),
    ).toBeVisible();
    const nativeList = await page.request.post("/api/export", {
      headers: nativeHeaders,
      data: { action: "list" },
    });
    expect(nativeList.status()).toBe(200);
    const snapshot = (await nativeList.json()).snapshots[0];
    expect(snapshot.datasets.entries).toBe(1);
    const reused = await page.request.post("/api/export", {
      headers: nativeHeaders,
      data: { action: "create", id: snapshot.id },
    });
    expect((await reused.json()).snapshot.captured_at).toBe(
      snapshot.captured_at,
    );
    const revision = (
      await client.from("entries").select("revision").eq("id", entryID).single()
    ).data!.revision;
    expect(
      (
        await client
          .from("entries")
          .update({
            body: "Edited later on another device",
            revision: revision + 1,
          })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    const downloading = page.waitForEvent("download");
    await page.getByRole("button", { name: "Download ZIP" }).click();
    const download = await downloading;
    const zipPath = testInfo.outputPath("synthetic-export.zip");
    await download.saveAs(zipPath);
    expect(await download.failure()).toBeNull();
    const archive = await readFile(zipPath);
    expect(archive.length).toBeGreaterThan(4.5 * 1024 * 1024);
    expect(hasCompleteExport(archive)).toBe(true);
    execFileSync("unzip", ["-tq", zipPath]);
    const read = (name: string) =>
      execFileSync("unzip", ["-p", zipPath, name], {
        maxBuffer: 10 * 1024 * 1024,
      });
    const manifest = JSON.parse(read("manifest.json").toString());
    expect(Object.keys(manifest.datasets).sort()).toEqual(
      Object.keys(snapshot.datasets).sort(),
    );
    for (const [name, value] of Object.entries(snapshot.datasets))
      expect(JSON.parse(read(`data/${name}.json`).toString())).toHaveLength(
        value as number,
      );
    expect(JSON.parse(read("data/entries.json").toString())[0].body).toBe(
      originalBody,
    );
    expect(read(`entries/${entryID}.md`).toString()).toContain(originalBody);
    expect(read(`entries/${entryID}.md`).toString()).toContain(
      'occurred_label: "17岁"',
    );
    for (const name of ["homes", "vehicles"])
      expect(read(`tables/${name}.csv`).toString()).toContain('"id"');
    const checksum = JSON.parse(read("checksums.json").toString()).media[0];
    expect(checksum.sha256).toBe(sha(original));
    expect(sha(read(checksum.archive_path))).toBe(sha(original));
    const nativeZip = await page.request.post("/api/export", {
      headers: nativeHeaders,
      data: { action: "download", id: snapshot.id },
    });
    expect(nativeZip.status()).toBe(200);
    expect(hasCompleteExport(await nativeZip.body())).toBe(true);
    // Exercise direct-to-disk orchestration without a headless OS file chooser.
    await page.evaluate(() => {
      const state = { bytes: 0, closed: false, aborted: false };
      Object.assign(window, { exportSinkState: state });
      Object.defineProperty(window, "showSaveFilePicker", {
        configurable: true,
        value: async () => ({
          createWritable: async () => ({
            write: async (chunk: Uint8Array) => {
              state.bytes += chunk.length;
            },
            close: async () => {
              state.closed = true;
            },
            abort: async () => {
              state.aborted = true;
            },
          }),
        }),
      });
    });
    await page.getByRole("button", { name: "Download ZIP" }).click();
    await expect(
      page.locator("[data-sonner-toast]").filter({
        hasText: "Complete ZIP saved",
      }),
    ).toBeVisible();
    const sink = await page.evaluate(
      () =>
        (
          window as unknown as {
            exportSinkState: {
              bytes: number;
              closed: boolean;
              aborted: boolean;
            };
          }
        ).exportSinkState,
    );
    expect(sink.bytes).toBeGreaterThan(original.length);
    expect(sink.closed).toBe(true);
    expect(sink.aborted).toBe(false);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-export-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-export-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    // Storage refuses a signed-in removal of a registered original.
    expect(
      (await admin.storage.from("entry-media").remove([path])).error,
    ).toBeNull();
    await page.evaluate(() => {
      Object.assign(
        (window as unknown as { exportSinkState: object }).exportSinkState,
        { bytes: 0, closed: false, aborted: false },
      );
    });
    await page.getByRole("button", { name: "Download ZIP" }).click();
    await expect(page.getByRole("status")).toContainText(
      "Download did not complete",
      { timeout: 30_000 },
    );
    expect(
      await page.evaluate(
        () =>
          (window as unknown as { exportSinkState: object }).exportSinkState,
      ),
    ).toMatchObject({ closed: false, aborted: true });
    await page
      .getByRole("button", { name: "Discard snapshot", exact: true })
      .click();
    await page.getByRole("button", { name: "Confirm discard" }).click();
    await expect(
      page.locator("[data-sonner-toast]").filter({
        hasText: "Temporary copy discarded",
      }),
    ).toBeVisible();
    expect(
      (
        await page.request.post("/api/export", {
          headers: nativeHeaders,
          data: { action: "download", id: snapshot.id },
        })
      ).status(),
    ).toBe(410);
    expect(
      (await client.from("entries").select("body").eq("id", entryID).single())
        .data?.body,
    ).toBe("Edited later on another device");
  } finally {
    await admin.storage.from("entry-media").remove([path]);
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
