import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";

test("Permanent photo removal includes interrupted unregistered previews", async ({
  page,
  context,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `media-cleanup-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id,
    entry = randomUUID(),
    original = randomUUID();
  const path = `${owner}/${entry}/${original}.png`;
  const prefix = `${owner}/${entry}/derived/${original}/v1/${"a".repeat(64)}`;
  const interrupted = `${prefix}/display.webp`;
  try {
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
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "Private photo cleanup",
        })
      ).error,
    ).toBeNull();
    const bytes = await sharp({
      create: { width: 20, height: 20, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(path, bytes, { contentType: "image/png" })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("register_entry_attachment", {
          p_entry_id: entry,
          p_attachment_id: original,
          p_object_path: path,
          p_original_filename: "private.png",
          p_mime_type: "image/png",
          p_byte_size: bytes.length,
          p_pixel_width: 20,
          p_pixel_height: 20,
        })
      ).error,
    ).toBeNull();
    // Reproduce a worker stopped after Storage upload but before attachment registration.
    expect(
      (
        await admin.storage
          .from("entry-media")
          .upload(interrupted, await sharp(bytes).webp().toBuffer(), {
            contentType: "image/webp",
          })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("trash_entry_attachment", {
          p_attachment_id: original,
        })
      ).error,
    ).toBeNull();
    await page.goto("/trash");
    const image = page.locator('img[src*="/api/media/image"]').first();
    await expect
      .poll(() =>
        image.evaluate(
          (img: HTMLImageElement) => img.complete && img.naturalWidth > 0,
        ),
      )
      .toBe(true);
    await page
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await expect(
      page.getByText("Item permanently deleted.", { exact: true }),
    ).toBeVisible();
    expect(
      (await client.from("attachments").select("id").eq("entry_id", entry))
        .data,
    ).toEqual([]);
    expect((await admin.storage.from("entry-media").list(prefix)).data).toEqual(
      [],
    );
    // A late worker must not re-create a derived object after permanent removal.
    expect(
      (
        await admin.storage
          .from("entry-media")
          .upload(interrupted, await sharp(bytes).webp().toBuffer(), {
            contentType: "image/webp",
            upsert: true,
          })
      ).error,
    ).not.toBeNull();
  } finally {
    const paths = execFileSync(
      "docker",
      [
        "exec",
        "supabase_db_memotrail",
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-Atc",
        `select name from storage.objects where bucket_id='entry-media' and split_part(name,'/',1)='${owner}'`,
      ],
      { encoding: "utf8" },
    )
      .trim()
      .split("\n")
      .filter(Boolean);
    if (paths.length)
      expect(
        (await admin.storage.from("entry-media").remove(paths)).error,
      ).toBeNull();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
