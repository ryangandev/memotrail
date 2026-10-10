import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Entry photos are added, retried, and moved to Trash in the editor", async ({
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
  const email = `media-management-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id,
    entry = randomUUID();
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
    await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "Organized photo memory",
          body: "Original thoughts",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const bytes = await sharp({
      create: { width: 320, height: 200, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    await page.goto(`/items/${entry}`);
    const itemPhotos = page.getByRole("region", {
      name: "Photos",
      exact: true,
    });
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "Organized photo memory",
    );
    await expect(itemPhotos).toHaveCount(0);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    const editor = page.getByRole("dialog", { name: "Edit Entry" });
    const field = editor.getByRole("group", { name: "Photos", exact: true });
    const picker = field.getByLabel("Add photos", { exact: true });
    await picker.setInputFiles({
      name: "not-a-photo.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("text"),
    });
    await expect(editor.getByRole("alert")).toContainText("Use JPEG");
    await picker.setInputFiles({
      name: "New memory.png",
      mimeType: "image/png",
      buffer: bytes,
    });
    await expect(editor.getByRole("alert")).toHaveCount(0);
    await field
      .getByRole("button", {
        name: "Remove selected New memory.png",
        exact: true,
      })
      .click();
    await editor.getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(editor).toHaveCount(0);
    expect(
      (await client.from("attachments").select("id").eq("entry_id", entry))
        .data,
    ).toEqual([]);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await picker.setInputFiles({
      name: "New memory.png",
      mimeType: "image/png",
      buffer: bytes,
    });
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: test
        .info()
        .outputPath("memotrail-photo-management-editor-light.png"),
    });
    // The first registration reaches the server but its answer is lost.
    let dropped = false;
    await page.route(`**/items/${entry}`, async (route) => {
      if (
        !dropped &&
        route.request().method() === "POST" &&
        route.request().postData()?.includes('"attachmentId"')
      ) {
        await route.fetch();
        dropped = true;
        await route.abort("failed");
      } else await route.continue();
    });
    await editor
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect.poll(() => dropped).toBe(true);
    await expect(editor.getByRole("alert")).toContainText(
      "The Entry was saved, but 1 photo could not be attached.",
    );
    await editor
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(editor).toHaveCount(0);
    await expect(
      itemPhotos.getByRole("button", {
        name: "Open New memory.png",
        exact: true,
      }),
    ).toBeVisible();
    const rows = await client
      .from("attachments")
      .select("id,object_path")
      .eq("entry_id", entry)
      .eq("variant", "original");
    expect(rows.error).toBeNull();
    expect(rows.data).toHaveLength(1);
    const photo = rows.data![0];
    const revision = (
      await client.from("entries").select("revision").eq("id", entry).single()
    ).data?.revision;
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await field
      .getByRole("button", { name: "Remove New memory.png", exact: true })
      .click();
    await page
      .getByRole("dialog", { name: "Move this photo to Trash?" })
      .getByRole("button", { name: "Cancel", exact: true })
      .click();
    await expect(
      field.getByRole("button", {
        name: "Preview New memory.png",
        exact: true,
      }),
    ).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: test
        .info()
        .outputPath("memotrail-photo-management-editor-mobile-dark.png"),
    });
    await field
      .getByRole("button", { name: "Remove New memory.png", exact: true })
      .click();
    await page
      .getByRole("dialog", { name: "Move this photo to Trash?" })
      .getByRole("button", { name: "Move photo to Trash", exact: true })
      .click();
    await expect(
      field.getByRole("button", { name: "Preview New memory.png" }),
    ).toHaveCount(0);
    const removed = (
      await client
        .from("attachments")
        .select("deleted_at")
        .eq("id", photo.id)
        .single()
    ).data!;
    expect(removed.deleted_at).not.toBeNull();
    // Photo changes leave the Entry's revision alone, so the open editor stays current.
    expect(
      (await client.from("entries").select("revision").eq("id", entry).single())
        .data?.revision,
    ).toBe(revision);
    await editor.getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(itemPhotos).toHaveCount(0);
    const original = await admin.storage
      .from("entry-media")
      .download(photo.object_path);
    expect(Buffer.from(await original.data!.arrayBuffer())).toEqual(bytes);
    expect(
      (
        await client.rpc("restore_trash_item", {
          p_item_id: photo.id,
          p_item_kind: "attachment",
          p_expected_revision: null,
          p_expected_deleted_at: removed.deleted_at,
        })
      ).error,
    ).toBeNull();
    await page.reload();
    await expect(
      itemPhotos.getByRole("button", {
        name: "Open New memory.png",
        exact: true,
      }),
    ).toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("body,date_precision")
          .eq("id", entry)
          .single()
      ).data,
    ).toEqual({
      body: "Original thoughts",
      date_precision: "unknown",
    });
    await page.unroute(`**/items/${entry}`);

    // A new Entry takes its photos when it is first saved.
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.emulateMedia({ colorScheme: "light" });
    await page.goto("/first-times");
    await page
      .getByRole("button", { name: "Add First Time", exact: true })
      .first()
      .click();
    const creator = page.getByRole("dialog", { name: "Add a First Time" });
    await creator.getByRole("textbox", { name: "Title" }).fill("First kayak");
    await creator
      .getByRole("group", { name: "Photos", exact: true })
      .getByLabel("Add photos", { exact: true })
      .setInputFiles({
        name: "Kayak.png",
        mimeType: "image/png",
        buffer: bytes,
      });
    await creator.getByRole("button", { name: "Add", exact: true }).click();
    await expect(creator).toHaveCount(0);
    const kayak = await client
      .from("entries")
      .select("id")
      .eq("title", "First kayak")
      .single();
    expect(kayak.error).toBeNull();
    expect(
      (
        await client
          .from("attachments")
          .select("original_filename")
          .eq("entry_id", kayak.data!.id)
          .eq("variant", "original")
      ).data,
    ).toEqual([{ original_filename: "Kayak.png" }]);
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
