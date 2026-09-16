import { execFileSync } from "node:child_process";
import { randomUUID, createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Private photo previews preserve originals across Web, native bearer access, caching, and Trash", async ({
  page,
  context,
}) => {
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
  const email = `media-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  const entry = randomUUID();
  const objects: string[] = [];
  try {
    expect(
      (
        await page.request.post("/api/media/urls", {
          headers: { Origin: "http://127.0.0.1:3100" },
          data: { paths: [] },
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
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );
    const headers = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "Photo archive",
          body: "Original writing",
          item_kind: "event",
          item_subtype: "first_time",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const jpeg = await sharp({
      create: { width: 2400, height: 1200, channels: 3, background: "#316652" },
    })
      .jpeg()
      .withMetadata({ orientation: 6 })
      .toBuffer();
    const heic = Buffer.from(
      readFileSync(
        "src/lib/media/fixtures/synthetic.heic.base64",
        "utf8",
      ).trim(),
      "base64",
    );
    const photos: { id: string; path: string; bytes: Buffer }[] = [];
    for (const [bytes, ext, mime] of [
      [jpeg, "jpg", "image/jpeg"],
      [heic, "heic", "image/heic"],
    ] as const) {
      const id = randomUUID(),
        path = `${owner}/${entry}/${id}.${ext}`;
      objects.push(path);
      expect(
        (
          await client.storage
            .from("entry-media")
            .upload(path, bytes, { contentType: mime })
        ).error,
      ).toBeNull();
      expect(
        (
          await client.rpc("register_entry_attachment", {
            p_entry_id: entry,
            p_attachment_id: id,
            p_object_path: path,
            p_original_filename: `synthetic.${ext}`,
            p_mime_type: mime,
            p_byte_size: bytes.length,
            p_pixel_width: null,
            p_pixel_height: null,
          })
        ).error,
      ).toBeNull();
      photos.push({ id, path, bytes });
    }
    expect(
      (
        await page.request.post("/api/media/urls", {
          headers: { Origin: "https://untrusted.example" },
          data: { paths: photos.map((p) => p.path) },
        })
      ).status(),
    ).toBe(403);
    const urls = await page.request.post("/api/media/urls", {
      headers,
      data: { paths: photos.map((p) => p.path) },
    });
    expect(urls.status()).toBe(200);
    const mapping = (await urls.json()).urls;
    const previews = await Promise.all(
      photos.map((p) => page.request.get(mapping[p.path])),
    );
    for (let i = 0; i < photos.length; i++) {
      expect(previews[i].status()).toBe(200);
      expect(previews[i].headers()["content-type"]).toBe("image/webp");
      expect(previews[i].headers()["cache-control"]).toContain("private");
      const metadata = await sharp(await previews[i].body()).metadata();
      expect([metadata.width, metadata.height]).toEqual(
        i === 0 ? [800, 1600] : [120, 80],
      );
      expect(metadata.exif).toBeUndefined();
      const original = await client.storage
        .from("entry-media")
        .download(photos[i].path);
      expect(
        Buffer.from(await original.data!.arrayBuffer()).equals(photos[i].bytes),
      ).toBe(true);
    }
    const thumbnail = await page.request.get(
      mapping[photos[0].path] + "&variant=thumbnail",
    );
    expect(thumbnail.status()).toBe(200);
    expect((await sharp(await thumbnail.body()).metadata()).height).toBe(400);
    await page.goto("/first-times");
    await expect(
      page.getByRole("heading", { name: "First Times", exact: true }),
    ).toBeVisible();
    const cover = page.locator('img[src*="/api/media/image"]').first();
    await expect(cover).toBeVisible();
    await expect
      .poll(() => cover.evaluate((img: HTMLImageElement) => img.naturalHeight))
      .toBe(1600);
    await page.screenshot({
      path: "/private/tmp/memotrail-media-desktop.png",
      fullPage: true,
    });
    const variants = await client
      .from("attachments")
      .select("id,object_path,parent_attachment_id,variant,metadata")
      .eq("entry_id", entry)
      .neq("variant", "original");
    expect(variants.error).toBeNull();
    expect(variants.data).toHaveLength(4);
    objects.push(...variants.data!.map((v) => v.object_path));
    const repeated = await page.request.get(mapping[photos[0].path]);
    expect(repeated.status()).toBe(200);
    expect(
      createHash("sha256")
        .update(await repeated.body())
        .digest("hex"),
    ).toBe(
      createHash("sha256")
        .update(await previews[0].body())
        .digest("hex"),
    );
    expect(
      (await client.from("attachments").select("id").eq("entry_id", entry))
        .data,
    ).toHaveLength(6);
    const workspace = await client.rpc("first_times_workspace_with_occurrence");
    expect(workspace.error).toBeNull();
    expect(workspace.data[0].attachments).toHaveLength(2);
    const display = variants.data!.find(
      (v) => v.parent_attachment_id === photos[0].id && v.variant === "display",
    )!;
    expect(
      (await admin.storage.from("entry-media").remove([display.object_path]))
        .error,
    ).toBeNull();
    expect((await page.request.get(mapping[photos[0].path])).status()).toBe(
      200,
    );
    expect(
      (await client.from("attachments").select("id").eq("entry_id", entry))
        .data,
    ).toHaveLength(6);
    const overwritten = await sharp({
      create: { width: 300, height: 200, channels: 3, background: "#886644" },
    })
      .jpeg()
      .toBuffer();
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(photos[0].path, overwritten, {
            contentType: "image/jpeg",
            upsert: true,
          })
      ).error,
    ).toBeNull();
    const refreshed = await page.request.get(mapping[photos[0].path]);
    expect(refreshed.status()).toBe(200);
    expect((await sharp(await refreshed.body()).metadata()).width).toBe(300);
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(variants.data![0].object_path, Buffer.from("corrupt"), {
            contentType: "image/webp",
            upsert: true,
          })
      ).error,
    ).not.toBeNull();
    expect(
      (
        await client.rpc("media_source", {
          p_owner_id: owner,
          p_attachment_id: photos[0].id,
        })
      ).error,
    ).not.toBeNull();
    const tampered = new URL(mapping[photos[0].path]);
    tampered.searchParams.set(
      "token",
      tampered.searchParams.get("token") + "x",
    );
    expect((await page.request.get(tampered.toString())).status()).toBe(401);
    const otherPath = `${randomUUID()}/${entry}/${randomUUID()}.jpg`;
    expect(
      (
        await (
          await page.request.post("/api/media/urls", {
            headers,
            data: { paths: [otherPath] },
          })
        ).json()
      ).urls,
    ).toEqual({});
    expect(
      (
        await client.rpc("trash_entry_attachment", {
          p_attachment_id: photos[0].id,
        })
      ).error,
    ).toBeNull();
    expect((await page.request.get(mapping[photos[0].path])).status()).toBe(
      404,
    );
    const trashURLs = (
      await (
        await page.request.post("/api/media/urls", {
          headers,
          data: { paths: [photos[0].path], trash: true },
        })
      ).json()
    ).urls;
    expect((await page.request.get(trashURLs[photos[0].path])).status()).toBe(
      200,
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.goto("/trash");
    await expect(
      page.locator('img[src*="/api/media/image"]').first(),
    ).toBeVisible();
    await page.screenshot({
      path: "/private/tmp/memotrail-media-mobile.png",
      fullPage: true,
    });
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
