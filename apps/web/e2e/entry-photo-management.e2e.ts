import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Organized Entry photos can be staged, uploaded, trashed, and restored", async ({
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
          inbox_status: "organized",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const bytes = await sharp({
      create: { width: 320, height: 200, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    await page.goto(`/history?entry=${entry}`);
    const gallery = page.getByRole("region", {
      name: "Current photos",
      exact: true,
    });
    await gallery
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    const picker = gallery.getByLabel("Add photos", { exact: true });
    await expect(picker).toBeVisible();
    await picker.setInputFiles({
      name: "not-a-photo.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("text"),
    });
    await expect(gallery.getByRole("alert")).toContainText("Use JPEG");
    await expect(
      gallery.getByRole("button", { name: "Upload photos", exact: true }),
    ).toHaveCount(0);
    await picker.setInputFiles({
      name: "New memory.png",
      mimeType: "image/png",
      buffer: bytes,
    });
    await gallery
      .getByRole("button", {
        name: "Discard selected New memory.png",
        exact: true,
      })
      .click();
    expect(
      (await client.from("attachments").select("id").eq("entry_id", entry))
        .data,
    ).toEqual([]);
    await picker.setInputFiles({
      name: "New memory.png",
      mimeType: "image/png",
      buffer: bytes,
    });
    await page.screenshot({
      path: "/private/tmp/memotrail-photo-management-desktop.png",
      fullPage: true,
    });
    await gallery.screenshot({
      path: "/private/tmp/memotrail-photo-management-panel-light.png",
    });
    let dropped = false;
    await page.route("**/history?*", async (route) => {
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
    await gallery
      .getByRole("button", { name: "Upload photos", exact: true })
      .click();
    await expect.poll(() => dropped).toBe(true);
    await expect(gallery.getByRole("alert")).toContainText("not confirmed");
    await gallery
      .getByRole("button", { name: "Upload photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: "Upload photos", exact: true }),
    ).toHaveCount(0);
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toBeVisible();
    const row = await client
      .from("attachments")
      .select("id,object_path")
      .eq("entry_id", entry)
      .eq("variant", "original")
      .single();
    expect(row.error).toBeNull();
    const photo = row.data!;
    expect(
      (await client.rpc("entry_history", { p_entry_id: entry })).data.current
        .revision,
    ).toBe(2);
    page.once("dialog", (dialog) => dialog.dismiss());
    await gallery
      .getByRole("button", {
        name: "Move New memory.png to Trash",
        exact: true,
      })
      .click();
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-photo-management-mobile.png",
      fullPage: true,
    });
    await gallery.screenshot({
      path: "/private/tmp/memotrail-photo-management-panel-dark.png",
    });
    page.once("dialog", (dialog) => dialog.accept());
    await gallery
      .getByRole("button", {
        name: "Move New memory.png to Trash",
        exact: true,
      })
      .click();
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toHaveCount(0);
    const removed = (
      await client
        .from("attachments")
        .select("deleted_at")
        .eq("id", photo.id)
        .single()
    ).data!;
    expect(removed.deleted_at).not.toBeNull();
    expect(
      (await client.rpc("entry_history", { p_entry_id: entry })).data.current
        .revision,
    ).toBe(3);
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
    await gallery
      .getByRole("button", { name: "Refresh photos", exact: true })
      .click();
    const history = (await client.rpc("entry_history", { p_entry_id: entry }))
      .data;
    expect(history.current.revision).toBe(4);
    expect(
      history.versions.map((version: { version: number }) => version.version),
    ).toEqual([3, 2, 1]);
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("body,inbox_status,date_precision")
          .eq("id", entry)
          .single()
      ).data,
    ).toEqual({
      body: "Original thoughts",
      inbox_status: "organized",
      date_precision: "unknown",
    });
    await page.reload();
    await gallery
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toBeVisible();
    await page
      .getByRole("combobox", { name: /Earlier version/ })
      .selectOption("1");
    page.once("dialog", (dialog) => dialog.accept());
    await page
      .getByRole("button", { name: "Restore selected version", exact: true })
      .click();
    await expect(
      page.getByRole("region", { name: "Current version", exact: true }),
    ).toContainText("version 5");
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toHaveCount(0);
    await expect(
      gallery.getByText("No saved photos on this Entry."),
    ).toBeVisible();
    page.once("dialog", (dialog) => dialog.accept());
    await page
      .getByRole("button", { name: "Restore selected version", exact: true })
      .click();
    await expect(
      page.getByRole("region", { name: "Current version", exact: true }),
    ).toContainText("version 6");
    await expect(
      gallery.getByRole("button", { name: "Open New memory.png", exact: true }),
    ).toBeVisible();
    const retained = await admin.storage
      .from("entry-media")
      .download(photo.object_path);
    expect(Buffer.from(await retained.data!.arrayBuffer())).toEqual(bytes);
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
