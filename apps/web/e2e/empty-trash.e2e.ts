import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";

test("Empty Trash confirms an exact cross-page snapshot and preserves later changes", async ({
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
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `empty-trash-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  const photoParent = randomUUID(),
    photoID = randomUUID();
  const photoPath = `${owner}/${photoParent}/${photoID}.png`;
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
        sameSite: "Lax" as const,
      })),
    );
    const ids = Array.from({ length: 30 }, () => randomUUID()).sort();
    expect(
      (
        await client.from("entries").insert(
          ids.map((id, index) => ({
            id,
            owner_id: owner,
            title: `Removed ${index}`,
            body: "Synthetic recoverable writing",
            deleted_at: "2026-09-01T12:00:00Z",
          })),
        )
      ).error,
    ).toBeNull();
    for (const table of ["people", "collections"] as const) {
      expect(
        (
          await client.from(table).insert({
            owner_id: owner,
            name: `Removed ${table}`,
            ...(table === "collections"
              ? { archived_at: "2026-09-01T12:00:00Z" }
              : { deleted_at: "2026-09-01T12:00:00Z" }),
          })
        ).error,
      ).toBeNull();
    }
    expect(
      (
        await client.from("entries").insert({
          id: photoParent,
          owner_id: owner,
          title: "Keep active original",
          body: "Active writing stays intact.",
        })
      ).error,
    ).toBeNull();
    const photoBytes = await sharp({
      create: { width: 16, height: 16, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(photoPath, photoBytes, { contentType: "image/png" })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("register_entry_attachment", {
          p_entry_id: photoParent,
          p_attachment_id: photoID,
          p_object_path: photoPath,
          p_original_filename: "removed.png",
          p_mime_type: "image/png",
          p_byte_size: photoBytes.length,
          p_pixel_width: 16,
          p_pixel_height: 16,
        })
      ).error,
    ).toBeNull();
    expect(
      (await client.rpc("trash_entry_attachment", { p_attachment_id: photoID }))
        .error,
    ).toBeNull();
    await page.goto("/trash");
    const collection = await client.from("collections").select("id").single();
    expect(collection.error).toBeNull();
    expect(
      (
        await client.from("entry_collections").insert({
          entry_id: photoParent,
          collection_id: collection.data!.id,
          owner_id: owner,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client
          .from("entries")
          .update({ body: "A later removed revision" })
          .eq("id", ids[1])
      ).error,
    ).toBeNull();
    expect(
      (await client.from("entry_versions").select("id").eq("entry_id", ids[1]))
        .data?.length,
    ).toBeGreaterThan(0);
    await expect(
      page.getByRole("button", { name: "Empty Trash", exact: true }),
    ).toBeVisible();
    const open = page.getByRole("button", { name: "Empty Trash", exact: true });
    const dialog = page.getByRole("dialog");
    await open.click();
    await expect(dialog).toContainText("Empty 33 items from Trash?");
    await page.screenshot({
      caret: "initial",
      animations: "disabled",
      path: "/private/tmp/memotrail-empty-trash-desktop.png",
    });
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    expect((await client.rpc("prepare_empty_trash")).data).toHaveLength(33);
    await open.click();
    await expect(dialog).toBeVisible();
    // A second device restores the first confirmed target. The batch must stop,
    // not silently retarget newly trashed content or delete later targets.
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: null })
          .eq("id", ids[0])
      ).error,
    ).toBeNull();
    await dialog
      .getByRole("button", { name: "Permanently delete confirmed items" })
      .click();
    await expect(
      page.getByText(/0 of 33 items confirmed deleted/),
    ).toBeVisible();
    expect((await client.rpc("prepare_empty_trash")).data).toHaveLength(32);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await open.click();
    await expect(dialog).toContainText("Empty 32 items from Trash?");
    await page.screenshot({
      caret: "initial",
      animations: "disabled",
      path: "/private/tmp/memotrail-empty-trash-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const late = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: late,
          owner_id: owner,
          title: "Trashed after confirmation list",
          deleted_at: new Date().toISOString(),
        })
      ).error,
    ).toBeNull();
    await dialog
      .getByRole("button", { name: "Permanently delete confirmed items" })
      .click();
    await expect(
      page.locator("[data-sonner-toast]").filter({
        hasText: /32 confirmed items permanently deleted/,
      }),
    ).toBeVisible({ timeout: 45000 });
    const remaining = await client.rpc("prepare_empty_trash");
    expect(remaining.error).toBeNull();
    expect(
      remaining.data.map((item: { item_id: string }) => item.item_id),
    ).toEqual([late]);
    expect(
      (
        await client
          .from("entries")
          .select("id")
          .in("id", [ids[0], photoParent])
      ).data,
    ).toHaveLength(2);
    expect(
      (
        await client
          .from("entries")
          .select("body")
          .eq("id", photoParent)
          .single()
      ).data?.body,
    ).toBe("Active writing stays intact.");
    expect(
      (await client.from("attachments").select("id").eq("id", photoID)).data,
    ).toEqual([]);
    expect(
      (await client.from("entry_versions").select("id").eq("entry_id", ids[1]))
        .data,
    ).toEqual([]);
    expect(
      (await admin.storage.from("entry-media").download(photoPath)).error,
    ).not.toBeNull();
    for (const table of ["people", "collections"] as const) {
      expect((await client.from(table).select("id")).data).toEqual([]);
    }
  } finally {
    await page.close();
    // Clean only this test user's private fixture objects after assertions.
    async function clean(prefix: string) {
      const files = await admin.storage
        .from("entry-media")
        .list(prefix, { limit: 1000 });
      for (const file of files.data ?? []) {
        const path = `${prefix}/${file.name}`;
        if (file.id) await admin.storage.from("entry-media").remove([path]);
        else await clean(path);
      }
    }
    await clean(owner);
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
