import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { createServerClient } from "@supabase/ssr";

test("native bearer and Web cookie media/export work while AI remains paused", async ({
  baseURL,
  request,
  context,
}) => {
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
  const email = `native-api-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  const entry = randomUUID(),
    attachment = randomUUID();
  const path = `${owner}/${entry}/${attachment}.png`;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(...values.map(({ name, value }) => ({ name, value })));
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
    const headers = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          body: "Synthetic native API record.",
        })
      ).error,
    ).toBeNull();
    const original = await sharp({
      create: { width: 1, height: 1, channels: 3, background: "white" },
    })
      .png()
      .toBuffer();
    expect(
      (
        await client.storage.from("entry-media").upload(path, original, {
          contentType: "image/png",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("register_entry_attachment", {
          p_entry_id: entry,
          p_attachment_id: attachment,
          p_object_path: path,
          p_original_filename: "native.png",
          p_mime_type: "image/png",
          p_byte_size: original.length,
          p_pixel_width: 1,
          p_pixel_height: 1,
        })
      ).error,
    ).toBeNull();

    const photos = await request.post(`/api/media/photos?entryId=${entry}`, {
      headers,
    });
    expect(photos.status()).toBe(200);
    expect((await photos.json()).photos).toEqual([
      expect.objectContaining({ id: attachment }),
    ]);
    const urls = await request.post("/api/media/urls", {
      headers,
      data: { paths: [path] },
    });
    expect(urls.status()).toBe(200);
    expect(new URL((await urls.json()).urls[path]).pathname).toBe(
      "/api/media/image",
    );
    const metadata = await request.post(
      `/api/media/metadata?attachmentId=${attachment}`,
      { headers },
    );
    expect(metadata.status()).toBe(200);
    expect((await metadata.json()).attachmentId).toBe(attachment);
    const exports = await request.post("/api/export", {
      headers,
      data: { action: "list" },
    });
    expect(exports.status()).toBe(200);
    expect((await exports.json()).snapshots).toEqual([]);
    expect(
      (await request.post("/api/media/place-options", { headers })).status(),
    ).toBe(410);
    expect(
      (
        await request.post(`/api/media/photos?entryId=${randomUUID()}`, {
          headers,
        })
      ).status(),
    ).toBe(404);
    expect(
      (
        await request.post("/api/export", {
          headers: { Authorization: "Bearer invalid-native-session" },
          data: { action: "list" },
        })
      ).status(),
    ).toBe(401);
    for (const route of ["connection", "suggestions", "search", "explore"]) {
      const paused = await request.post(`/api/ai/${route}`, {
        headers,
        data: {},
      });
      expect(paused.status()).toBe(503);
      expect((await paused.json()).code).toBe("ai_paused");
    }

    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    expect(
      (
        await context.request.post("/api/export", { data: { action: "list" } })
      ).status(),
    ).toBe(403);
    expect(
      (
        await context.request.post("/api/export", {
          headers: { Origin: "https://untrusted.example" },
          data: { action: "list" },
        })
      ).status(),
    ).toBe(403);
    expect(
      (
        await context.request.post("/api/export", {
          headers: { Origin: baseURL! },
          data: { action: "list" },
        })
      ).status(),
    ).toBe(200);
  } finally {
    await admin.storage.from("entry-media").remove([path]);
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
